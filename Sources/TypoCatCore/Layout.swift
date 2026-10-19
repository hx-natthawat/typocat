import Foundation

/// A language identified by its ISO 639-1 code ("en", "ru", "he"), taken from
/// the keyboard layout macOS reports. Any layout works; detection needs a word
/// list for its language.
///
/// A second layout for the same language with letters in other places (Dvorak or Colemak
/// next to QWERTY) is a variant, "en+dvorak": its own layout, sharing the base's word list.
public struct Language: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        // "en-US", "zh_Hant" → "en", "zh"; a variant keeps its name.
        let parts = rawValue.lowercased().split(separator: "+", maxSplits: 1)
        let code = String((parts.first ?? "").prefix { $0.isLetter })
        self.rawValue = parts.count == 2 && !code.isEmpty ? "\(code)+\(parts[1])" : code
    }

    public init(_ base: Language, variant: String) {
        self.init(rawValue: "\(base.base.rawValue)+\(variant.lowercased().filter { $0.isLetter || $0.isNumber })")
    }

    /// The language without its layout variant: what word lists and spell checkers are keyed by.
    public var base: Language { Language(rawValue: String(rawValue.prefix { $0 != "+" })) }
    public var variant: String? { rawValue.firstIndex(of: "+").map { String(rawValue[rawValue.index(after: $0)...]) } }

    public static let english = Language(rawValue: "en")
    public static let thai = Language(rawValue: "th")

    /// Languages scripts.sh downloads word lists for: English, languages whose macOS layouts use
    /// a non-Latin script, where wrong-layout typing turns into gibberish, and Latin layouts that
    /// move letters (AZERTY, QWERTZ, ä ö ü on punctuation keys).
    public static let bundled: [Language] = ["en", "ru", "uk", "bg", "sr", "mk", "kk", "el", "he", "ar", "fa",
                                             "ur", "hy", "ka", "hi", "th", "ko",
                                             "fr", "de", "es", "it", "tr", "cs", "sv", "hu", "da", "fi"].map { Language(rawValue: $0) }

    /// Written without spaces between words (Thai, Lao, Khmer, Burmese): scored by
    /// segmentation, and short words are reread after a later fix.
    public var writesWithoutSpaces: Bool { ["th", "lo", "km", "my"].contains(base.rawValue) }

    /// "EN"; a variant shows its own name: "DV" for Dvorak.
    public var shortName: String { variant.map { String($0.prefix(2)).uppercased() } ?? rawValue.uppercased() }
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
    /// Keys type Hangul letters that join into syllables (Korean 2-Set): see `Hangul`.
    public let joinsHangul: Bool

    public init(language: Language, inputSourceID: String, forward: [KeyStroke: String],
                deadKeys: [KeyStroke: [KeyStroke: String]] = [:], joinsHangul: Bool = false) {
        self.language = language
        self.inputSourceID = inputSourceID
        self.forward = forward
        self.deadKeys = deadKeys
        self.joinsHangul = joinsHangul
    }

    /// What each key types on its own.
    public var keyMap: [KeyStroke: String] { forward }

    public func produces(_ stroke: KeyStroke) -> Bool { forward[stroke] != nil }

    /// The same key map under another name, for a layout variant.
    public func named(_ language: Language) -> LayoutMap {
        LayoutMap(language: language, inputSourceID: inputSourceID, forward: forward, deadKeys: deadKeys, joinsHangul: joinsHangul)
    }

    /// Whether some key types a different letter here than on `other`: Dvorak against
    /// QWERTY, but not ABC against U.S., which differ in a few symbols at most.
    public func movesLetters(comparedTo other: LayoutMap) -> Bool {
        forward.contains { stroke, s in
            guard let o = other.forward[stroke], o != s else { return false }
            return s.unicodeScalars.contains { $0.properties.isAlphabetic } || o.unicodeScalars.contains { $0.properties.isAlphabetic }
        }
    }

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

    /// The keys that type `text` here, or nil when some character can't be typed.
    public func strokes(typing text: String, inverse: [String: [KeyStroke]]? = nil) -> [KeyStroke]? {
        let inverse = inverse ?? self.inverse()
        var out: [KeyStroke] = []
        for scalar in (joinsHangul ? Hangul.keyLetters(text) : text).unicodeScalars {
            guard let keys = inverse[String(scalar)] else { return nil }
            out += keys
        }
        return out
    }

    /// Re-types the strokes on this layout; nil when a stroke has no output here.
    public func render(_ strokes: [KeyStroke]) -> String? {
        guard joinsHangul else { return renderKeys(strokes) }
        return renderKeys(strokes).map(Hangul.compose)
    }

    private func renderKeys(_ strokes: [KeyStroke]) -> String? {
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
