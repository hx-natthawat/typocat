import Foundation

/// Automatic fixes from the last moments, so a fix taken back late (selected and converted back,
/// or deleted and typed again) still counts as undone, and one left in place counts as kept.
/// Also undone spelling fixes, to see which word the user meant instead.
public struct RecentFixes: Sendable {
    public struct Entry: Sendable, Equatable {
        public let id: Int
        public let correction: Correction
        /// The last word as typed, which an undo adds to the exceptions.
        public let word: String
        /// Whether a delimiter followed the replacement (it was typed after it, so it's in the field).
        public let delimited: Bool
        public let at: TimeInterval
        /// A spelling fix the user undid: the field holds `word` again, not the replacement.
        public let undone: Bool
        /// Words finished since, for deciding the fix was kept.
        public fileprivate(set) var wordsSince = 0
        /// Scalars typed after the fix still in the field, and the fix's own still there.
        /// Backspace takes from the first, then the second.
        public fileprivate(set) var typedAfter = 0
        public fileprivate(set) var remaining: Int
        /// False once the caret may have moved (a click, an arrow key): erasing no longer means erasing it.
        public fileprivate(set) var caretTracked = true
        /// False once a later rewrite made the counts unreliable; the caret is still where it was.
        public fileprivate(set) var counted = true
        var following: Bool { caretTracked && counted }
        public fileprivate(set) var credited = false

        /// Every scalar of the replacement (and its delimiter) was erased. Stays true while the
        /// user types the word again.
        public var erased: Bool { remaining <= 0 }

        init(id: Int, correction: Correction, word: String, delimited: Bool, at: TimeInterval, undone: Bool) {
            self.id = id
            self.correction = correction
            self.word = word
            self.delimited = delimited
            self.at = at
            self.undone = undone
            remaining = (undone ? correction.original : correction.replacement).unicodeScalars.count + (delimited ? 1 : 0)
        }

        /// The text this entry put in the field: the replacement, or for an undone fix the original.
        var inField: String { undone ? correction.original : correction.replacement }
    }

    /// How long a fix can still be taken back by converting it or typing it again.
    public var maximumAge: TimeInterval = 30
    /// Words typed after a fix before it counts as kept.
    public var wordsToKeep = 3
    public var capacity = 5
    public private(set) var entries: [Entry] = []
    private var nextID = 0

    public init() {}

    /// `undone`: a spelling fix just taken back, so its original is in the field again.
    public mutating func add(_ correction: Correction, word: String, delimited: Bool, at now: TimeInterval,
                             undone: Bool = false) {
        // A rewrite erases and retypes, so earlier fixes can't be followed through it.
        for i in entries.indices where !entries[i].erased { entries[i].counted = false }
        entries.append(Entry(id: nextID, correction: correction, word: word, delimited: delimited, at: now, undone: undone))
        nextID += 1
        if entries.count > capacity { entries.removeFirst() }
    }

    public mutating func remove(_ entry: Entry) { entries.removeAll { $0.id == entry.id } }

    public mutating func removeAll() { entries.removeAll() }

    /// The most recent fix the user is taking back by converting `selection`: its whole replacement,
    /// or its last word.
    public func converted(_ selection: String, at now: TimeInterval) -> Entry? {
        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return entries.last { entry in
            !entry.undone && now - entry.at <= maximumAge
                && (entry.correction.replacement == text || entry.correction.replacement.split(separator: " ").last.map(String.init) == text)
        }
    }

    /// The most recent fix the user erased and typed again as it was, in the language it came from.
    public func retyped(_ typed: String, in language: Language, at now: TimeInterval) -> Entry? {
        entries.last {
            !$0.undone && now - $0.at <= maximumAge && $0.erased && $0.following && $0.word == typed
                && $0.correction.from == language
        }
    }

    /// An undone spelling fix whose word the user erased and typed differently: maybe the word
    /// they meant. The caller checks it's a real word close to the typo.
    public func replacedAfterUndo(with typed: String, in language: Language, at now: TimeInterval) -> Entry? {
        entries.last {
            $0.undone && now - $0.at <= maximumAge && $0.erased && $0.following && $0.word != typed
                && $0.correction.from == language
        }
    }

    /// One key typed (`scalars` > 0) or one Backspace.
    public mutating func typed(scalars: Int) {
        for i in entries.indices where entries[i].following { entries[i].typedAfter += scalars }
    }

    public mutating func deleted() {
        for i in entries.indices where entries[i].following && !entries[i].erased {
            if entries[i].typedAfter > 0 { entries[i].typedAfter -= 1 } else { entries[i].remaining -= 1 }
        }
    }

    /// ⌥⌫ right after a fix erases its last word and delimiter. After anything else typed it
    /// isn't followed: the caller loses the caret.
    public mutating func deletedWord() {
        for i in entries.indices where entries[i].following && !entries[i].erased && entries[i].typedAfter == 0 {
            let last = entries[i].inField.split(separator: " ").last?.unicodeScalars.count ?? 0
            entries[i].remaining -= last + (entries[i].delimited ? 1 : 0)
        }
    }

    /// The caret may be elsewhere now; only converting a selection can still take a fix back.
    public mutating func lostCaret() {
        for i in entries.indices where !entries[i].erased { entries[i].caretTracked = false }
    }

    /// A word was finished. Returns the fixes that now count as kept, once each.
    public mutating func finishedWord(at now: TimeInterval) -> [Entry] {
        var kept: [Entry] = []
        for i in entries.indices {
            entries[i].wordsSince += 1
            // Only while followed: a click away and back may have been to fix it by hand.
            if !entries[i].undone, !entries[i].credited, entries[i].wordsSince >= wordsToKeep,
               entries[i].caretTracked, !entries[i].erased {
                entries[i].credited = true
                kept.append(entries[i])
            }
        }
        entries.removeAll { now - $0.at > maximumAge }
        return kept
    }
}

/// Undone and kept fixes, as counts per app and language pair, so an app where fixes keep being
/// undone gets more careful ones. Stored as `{"com.apple.mail|en>ru": 2.3}`: no words.
public struct FixFeedback: Codable, Sendable, Equatable {
    public private(set) var strikes: [String: Double] = [:]

    /// An undone fix adds a strike; a kept one takes this much off, so ten kept fixes forgive one.
    public var keptCredit = 0.1
    /// Strikes before fixes get more careful: one undo is already handled by the exceptions.
    public var strikesBeforeCaution = 2.0
    /// Extra confidence a fix needs per strike from then on, and at most.
    public var cautionPerStrike = 0.1
    public var maximumCaution = 0.3

    public init() {}

    static func key(_ app: String?, _ from: Language, _ to: Language) -> String {
        "\(app ?? "*")|\(from.base.rawValue)>\(to.base.rawValue)"
    }

    public mutating func recordUndo(in app: String?, from: Language, to: Language) {
        strikes[Self.key(app, from, to), default: 0] += 1
    }

    public mutating func recordKept(in app: String?, from: Language, to: Language) {
        let key = Self.key(app, from, to)
        guard let s = strikes[key] else { return }
        strikes[key] = s - keptCredit > 0.001 ? s - keptCredit : nil
    }

    /// How much more confident than usual a fix from `from` to `to` must be in `app` (0 when it's never undone).
    public func caution(in app: String?, from: Language, to: Language) -> Double {
        let s = strikes[Self.key(app, from, to)] ?? 0
        guard s >= strikesBeforeCaution else { return 0 }
        return min(maximumCaution, cautionPerStrike * (s - strikesBeforeCaution + 1))
    }

    /// Caution for fixes from `current` into each of `languages`, as the detector takes it.
    public func caution(in app: String?, from current: Language, into languages: some Sequence<Language>) -> [Language: Double] {
        var out: [Language: Double] = [:]
        for language in languages {
            let c = caution(in: app, from: current, to: language)
            if c > 0 { out[language] = c }
        }
        return out
    }

    public mutating func removeAll() { strikes = [:] }

    // Only the strikes are persisted; the rest is policy, not data.
    private enum CodingKeys: String, CodingKey { case strikes }
}
