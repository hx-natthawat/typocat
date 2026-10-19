import Foundation
import TypoCatCore

/// Settings and learned state that survive restarts.
/// Settings and fix counts live in UserDefaults; learned state lives in ~/Library/Application Support/TypoCat/
/// (ignoredWords.json, appLanguageCounts.json, and learnedWords.json when learning is on).
final class UserStore {
    private let defaults = UserDefaults.standard
    private let excludedKey = "excludedApps"
    private let matchLayoutKey = "matchLayoutPerApp"
    private let fileURL: URL
    private let appLanguagesURL: URL
    private var appLanguagesDirty = false
    private(set) var ignoredWords: Set<String> = []
    private(set) var excludedApps: Set<String>
    private(set) var appLanguages = AppLanguageProfile()
    private let learnedURL: URL
    /// Words converted by hand with ⌃⌥Space, by language. Only kept while `learnWords` is on.
    private(set) var learnedWords: [Language: Set<String>] = [:]

    /// Off by default: it saves words the user typed, which nothing else does.
    var learnWords: Bool {
        get { defaults.bool(forKey: "learnWords") }
        set {
            defaults.set(newValue, forKey: "learnWords")
            if !newValue { forgetLearnedWords() }
        }
    }

    var learnedWordCount: Int { learnedWords.values.reduce(0) { $0 + $1.count } }

    /// Off by default: a wrong autocorrection costs more than a missed one.
    var fixTypos: Bool {
        get { defaults.bool(forKey: "fixTypos") }
        set { defaults.set(newValue, forKey: "fixTypos") }
    }

    /// Off by default: it keeps the host names of sites typed in (only those, with counts).
    var matchLayoutPerSite: Bool {
        get { defaults.bool(forKey: "matchLayoutPerSite") }
        set {
            defaults.set(newValue, forKey: "matchLayoutPerSite")
            if !newValue { appLanguages.removeAll { $0.hasPrefix("site:") }; saveAppLanguagesSoon() }
        }
    }

    /// What converts the current word or the selection by hand.
    enum Shortcut: String, CaseIterable {
        case controlOptionSpace, shiftTwice, both
        var usesControlOptionSpace: Bool { self != .shiftTwice }
        var usesShiftTwice: Bool { self != .controlOptionSpace }
    }

    var shortcut: Shortcut {
        get { defaults.string(forKey: "shortcut").flatMap(Shortcut.init) ?? .controlOptionSpace }
        set { defaults.set(newValue.rawValue, forKey: "shortcut") }
    }

    /// Flash the menu bar icon on each fix.
    var showFixes: Bool {
        get { defaults.object(forKey: "showFixes") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showFixes") }
    }

    var matchLayoutPerApp: Bool {
        get { defaults.object(forKey: matchLayoutKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: matchLayoutKey) }
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypoCat", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("ignoredWords.json")
        appLanguagesURL = support.appendingPathComponent("appLanguageCounts.json")
        learnedURL = support.appendingPathComponent("learnedWords.json")
        if defaults.bool(forKey: "learnWords"), let data = try? Data(contentsOf: learnedURL),
           let words = try? JSONDecoder().decode([String: [String]].self, from: data) {
            learnedWords = Dictionary(uniqueKeysWithValues: words.map { (Language(rawValue: $0.key), Set($0.value)) })
        }
        if let data = try? Data(contentsOf: appLanguagesURL),
           let profile = try? JSONDecoder().decode(AppLanguageProfile.self, from: data) {
            appLanguages = profile
        }
        excludedApps = Set(defaults.stringArray(forKey: excludedKey) ?? [])
        if let data = try? Data(contentsOf: fileURL), let words = try? JSONDecoder().decode([String].self, from: data) {
            ignoredWords = Set(words)
        }
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        bundleID.map(excludedApps.contains) ?? false
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        if excluded { excludedApps.insert(bundleID) } else { excludedApps.remove(bundleID) }
        defaults.set(excludedApps.sorted(), forKey: excludedKey)
    }

    /// `bundleID` is an app's bundle ID or a website's `BrowserSite.profileKey`.
    func recordLanguage(_ language: Language, in bundleID: String?) {
        guard let bundleID else { return }
        appLanguages.record(language, in: bundleID)
        saveAppLanguagesSoon()
    }

    func correctLanguage(from wrong: Language, to right: Language, in bundleID: String?) {
        guard let bundleID else { return }
        appLanguages.reassign(from: wrong, to: right, in: bundleID)
        saveAppLanguagesSoon()
    }

    private func saveAppLanguagesSoon() {
        // Coalesce: one write per few seconds of typing, not one per word.
        guard !appLanguagesDirty else { return }
        appLanguagesDirty = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
            appLanguagesDirty = false
            let snapshot = appLanguages
            let url = appLanguagesURL
            DispatchQueue.global(qos: .utility).async {
                try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            }
        }
    }

    /// Keeps a word converted by hand, if learning is on. Returns whether it was new.
    @discardableResult
    func learn(_ word: String, in language: Language) -> Bool {
        let word = Detector.learnable(word)
        guard learnWords, !word.isEmpty, learnedWords[language.base, default: []].insert(word).inserted else { return false }
        saveLearnedWords()
        return true
    }

    /// Undoing a fix to a learned word forgets it. Returns whether it was learned.
    @discardableResult
    func unlearn(_ word: String, in language: Language) -> Bool {
        guard learnedWords[language.base]?.remove(Detector.learnable(word)) != nil else { return false }
        saveLearnedWords()
        return true
    }

    /// Deletes the file too: turning learning off leaves nothing behind.
    func forgetLearnedWords() {
        learnedWords = [:]
        try? FileManager.default.removeItem(at: learnedURL)
    }

    private func saveLearnedWords() {
        let snapshot = Dictionary(uniqueKeysWithValues: learnedWords.map { ($0.key.rawValue, $0.value.sorted()) })
        let url = learnedURL
        DispatchQueue.global(qos: .utility).async {
            try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }

    /// Words left alone: undone fixes, plus any added by hand in the Exceptions window.
    func ignore(_ word: String) {
        guard ignoredWords.insert(word).inserted else { return }
        saveIgnoredWords()
    }

    func unignore(_ word: String) {
        guard ignoredWords.remove(word) != nil else { return }
        saveIgnoredWords()
    }

    private func saveIgnoredWords() {
        let snapshot = ignoredWords.sorted()
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }

    // MARK: - Fix counts

    /// How many words were fixed into each language: numbers only, never the words.
    private(set) var fixCounts: [Language: Int] {
        get {
            let raw = defaults.dictionary(forKey: "fixCounts") as? [String: Int] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.map { (Language(rawValue: $0.key), $0.value) })
        }
        set { defaults.set(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) }), forKey: "fixCounts") }
    }

    /// Counts by base language: Dvorak fixes count as English.
    func countFix(into language: Language, by delta: Int = 1) {
        var counts = fixCounts
        counts[language.base] = max(0, counts[language.base, default: 0] + delta)
        if counts[language.base] == 0 { counts[language.base] = nil }
        fixCounts = counts
    }

    func resetFixCounts() { defaults.removeObject(forKey: "fixCounts") }
}
