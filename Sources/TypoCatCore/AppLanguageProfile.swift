import Foundation

/// Counts which language the user ends up writing in each app, so focusing an
/// app can switch to the layout they usually type there.
/// Stored as `{"com.microsoft.vscode": {"en": 362, "th": 19}}`.
public struct AppLanguageProfile: Codable, Sendable, Equatable {
    public private(set) var counts: [String: [String: Int]] = [:]

    /// Words an app needs before it gets a dominant language.
    public var minimumWords = 20
    /// Share of those words one language needs to count as dominant.
    public var minimumShare = 0.75

    public init() {}

    public mutating func record(_ language: Language, in bundleID: String) {
        counts[bundleID, default: [:]][language.rawValue, default: 0] += 1
    }

    /// Moves one count from `wrong` to `right`, e.g. when the user undoes a fix.
    public mutating func reassign(from wrong: Language, to right: Language, in bundleID: String) {
        if let n = counts[bundleID]?[wrong.rawValue], n > 0 { counts[bundleID]![wrong.rawValue] = n - 1 }
        record(right, in: bundleID)
    }

    public func dominant(in bundleID: String) -> Language? {
        guard let langs = counts[bundleID] else { return nil }
        let total = langs.values.reduce(0, +)
        guard total >= minimumWords, let top = langs.max(by: { $0.value < $1.value }),
              Double(top.value) / Double(total) >= minimumShare else { return nil }
        return Language(rawValue: top.key)
    }

    // Only the counts are persisted; thresholds are policy, not data.
    private enum CodingKeys: String, CodingKey { case counts }
}
