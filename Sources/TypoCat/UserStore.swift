import Foundation
import TypoCatCore

/// Settings and learned state that survive restarts.
/// Settings live in UserDefaults; learned state lives in
/// ~/Library/Application Support/TypoCat/ (ignoredWords.json, appLanguageCounts.json).
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

    func ignore(_ word: String) {
        guard ignoredWords.insert(word).inserted else { return }
        let snapshot = ignoredWords.sorted()
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }
}
