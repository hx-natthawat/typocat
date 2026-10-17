import Foundation

/// A language identified by its ISO 639-1 code ("en", "ru", "he"), taken from
/// the keyboard layout macOS reports. Any layout works; detection needs a word
/// list for its language.
public struct Language: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        // "en-US", "zh_Hant" → "en", "zh"
        self.rawValue = String(rawValue.lowercased().prefix { $0.isLetter })
    }

    public static let english = Language(rawValue: "en")
    public static let thai = Language(rawValue: "th")

    /// Languages scripts.sh downloads word lists for: English plus languages whose
    /// macOS layouts use a non-Latin script, where wrong-layout typing turns into gibberish.
    public static let bundled: [Language] = ["en", "ru", "uk", "bg", "sr", "mk", "kk", "el", "he", "ar", "fa",
                                             "ur", "hy", "ka", "hi", "th"].map { Language(rawValue: $0) }

    /// Written without spaces between words (Thai, Lao, Khmer, Burmese): scored by
    /// segmentation, and short words are reread after a later fix.
    public var writesWithoutSpaces: Bool { ["th", "lo", "km", "my"].contains(rawValue) }

    public var shortName: String { rawValue.uppercased() }
    public var description: String { rawValue }
}

/// A physical key press, independent of which layout is active.
public struct KeyStroke: Hashable, Sendable {
    public let keyCode: UInt16
    public let shift: Bool

    public init(keyCode: UInt16, shift: Bool) {
        self.keyCode = keyCode
        self.shift = shift
    }
}

/// What each physical key produces under one keyboard layout.
public struct LayoutMap: Sendable {
    public let language: Language
    public let inputSourceID: String
    private let forward: [KeyStroke: String]
    /// Dead keys: what each following key produces after them (Greek ΄ then α → ά).
    public let deadKeys: [KeyStroke: [KeyStroke: String]]

    public init(language: Language, inputSourceID: String, forward: [KeyStroke: String],
                deadKeys: [KeyStroke: [KeyStroke: String]] = [:]) {
        self.language = language
        self.inputSourceID = inputSourceID
        self.forward = forward
        self.deadKeys = deadKeys
    }

    public func produces(_ stroke: KeyStroke) -> Bool { forward[stroke] != nil }

    /// Single keys and dead-key pairs that type `text`, for tests and evaluation.
    public func inverse() -> [String: [KeyStroke]] {
        var out: [String: [KeyStroke]] = [:]
        // Sorted so the same text always maps to the same keys (dictionary order varies per run).
        let order: (KeyStroke, KeyStroke) -> Bool = { ($0.keyCode, $0.shift ? 1 : 0) < ($1.keyCode, $1.shift ? 1 : 0) }
        for stroke in forward.keys.sorted(by: order) where out[forward[stroke]!] == nil { out[forward[stroke]!] = [stroke] }
        for dead in deadKeys.keys.sorted(by: order) {
            let follow = deadKeys[dead]!
            for next in follow.keys.sorted(by: order) where out[follow[next]!] == nil { out[follow[next]!] = [dead, next] }
        }
        return out
    }

    /// Re-types the strokes on this layout; nil when a stroke has no output here.
    public func render(_ strokes: [KeyStroke]) -> String? {
        var out = ""
        var i = 0
        while i < strokes.count {
            if i + 1 < strokes.count, let composed = deadKeys[strokes[i]]?[strokes[i + 1]] {
                out += composed
                i += 2
                continue
            }
            guard let s = forward[strokes[i]] else { return nil }
            out += s
            i += 1
        }
        return out
    }

    public var count: Int { forward.count }
}
