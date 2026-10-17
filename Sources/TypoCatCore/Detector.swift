import Foundation

public struct Correction: Sendable, Equatable {
    public let original: String
    public let replacement: String
    public let from: Language
    public let to: Language

    public init(original: String, replacement: String, from: Language, to: Language) {
        self.original = original
        self.replacement = replacement
        self.from = from
        self.to = to
    }
}

/// Decides whether a word was typed on the wrong layout by re-rendering its
/// keystrokes on every other layout and comparing dictionary plausibility.
public final class Detector: @unchecked Sendable {
    private let dictionaries: [Language: FrequencyDictionary]

    /// Minimum confidence for the alternative rendering.
    public var acceptThreshold = 0.6
    /// Maximum confidence the typed text may have and still be replaced.
    public var rejectThreshold = 0.3
    public var minimumStrokes = 2
    /// The typed text may be a real but rare word ("mew" for ทำไม). Replace it
    /// anyway when the other rendering scores this much higher.
    public var dominanceMargin = 0.2
    /// Words reread after a later fix are kept when they score at least this in
    /// their own language (about the top 200 words).
    public var rereadKeepScore = 0.8
    /// Whether earlier words may be reread into a language. On the top 5000 words, rereading
    /// into Thai recovers ~80% of missed short words with 0.5% false changes; into English it
    /// recovers few words and changes ~3% of correct short Thai words. Languages written with
    /// spaces rarely leave short words behind, so only spaceless scripts get rereading.
    public var rereadsInto: @Sendable (Language) -> Bool = { $0.writesWithoutSpaces }

    public init(dictionaries: [Language: FrequencyDictionary]) {
        self.dictionaries = dictionaries
    }

    /// 0...1 confidence that `text` is real text in `language`.
    public func score(_ text: String, as language: Language) -> Double {
        guard let dict = dictionaries[language] else { return 0 }
        if language.writesWithoutSpaces {
            if language == .thai && !ThaiOrthography.isPlausible(text) { return 0 }
            if dict.count(of: text) > 0 { return 0.6 + 0.4 * dict.commonness(of: text) }
            guard text.unicodeScalars.allSatisfy(Self.isWordScalar) else { return 0 }
            let coverage = dict.segmentCoverage(text)
            return coverage >= 0.999 ? 0.8 : coverage * coverage * 0.75
        }
        let word = text.trimmingCharacters(in: Self.edgePunctuation).lowercased()
        guard !word.isEmpty, word.unicodeScalars.allSatisfy(Self.isWordScalar),
              dict.count(of: word) > 0 else { return 0 }
        return 0.6 + 0.4 * dict.commonness(of: word)
    }

    /// Languages with a loaded word list.
    public var languages: Set<Language> { Set(dictionaries.keys) }

    /// - Parameter force: the user explicitly asked to convert; take the best
    ///   alternative even when neither rendering is a known word.
    public func decide(strokes: [KeyStroke], typed: String, current: Language,
                       layouts: [Language: LayoutMap], ignoring ignored: Set<String> = [],
                       category: AppCategory = .general, force: Bool = false) -> Correction? {
        guard force || strokes.count >= minimumStrokes, !ignored.contains(typed) else { return nil }
        if !force && ProtectedWords.contains(typed, in: category) { return nil }
        let typedScore = score(typed, as: current)
        // Beyond the reject threshold only a clearly more common alternative can win.
        let required = typedScore > rejectThreshold ? typedScore + dominanceMargin : 0
        if !force && required > 1 { return nil }

        var best: (Correction, Double)?
        for (language, layout) in layouts where language != current {
            guard let alt = layout.render(strokes), alt != typed else { continue }
            let s = score(alt, as: language)
            if best == nil || s > best!.1 {
                best = (Correction(original: typed, replacement: alt, from: current, to: language), s)
            }
        }
        guard let (correction, altScore) = best else { return nil }
        if force { return correction }
        return altScore >= acceptThreshold && altScore > typedScore && altScore >= required ? correction : nil
    }

    /// After a later word was fixed to `target`, decides whether an earlier word
    /// left alone (short words like `z,` for ผม are ambiguous on their own) should
    /// be fixed too. Returns its `target` rendering, or nil to keep it.
    public func reread(strokes: [KeyStroke], typed: String, current: Language, as target: Language,
                       layouts: [Language: LayoutMap], ignoring ignored: Set<String> = [],
                       category: AppCategory = .general) -> String? {
        guard target != current, rereadsInto(target), !ignored.contains(typed), !ProtectedWords.contains(typed, in: category),
              let alt = layouts[target]?.render(strokes), alt != typed else { return nil }
        let altScore = score(alt, as: target), typedScore = score(typed, as: current)
        // Common words (นา, ทำ, go) stay: mixed-language text is normal. Rare ones (fu, z) may go.
        guard typedScore < rereadKeepScore else { return nil }
        return altScore >= acceptThreshold && altScore > typedScore ? alt : nil
    }

    private static let edgePunctuation = CharacterSet.punctuationCharacters.union(.symbols)
        .subtracting(CharacterSet(charactersIn: "'’-"))
    /// Letters and combining marks of any script, plus in-word apostrophes and hyphens.
    private static func isWordScalar(_ s: Unicode.Scalar) -> Bool {
        s.properties.isAlphabetic || s.properties.generalCategory == .nonspacingMark
            || s.properties.generalCategory == .spacingMark || s == "'" || s == "’" || s == "-"
    }
}

public enum ThaiOrthography {
    /// Above/below vowels and tone marks that must follow a consonant.
    static func isCombining(_ v: UInt32) -> Bool {
        v == 0x0E31 || (0x0E34...0x0E3A).contains(v) || (0x0E47...0x0E4E).contains(v)
    }

    /// Cheap structural check that rejects keyboard noise like "้ำสสน".
    public static func isPlausible(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.first?.value else { return false }
        // Must be Thai script throughout.
        guard scalars.allSatisfy({ (0x0E01...0x0E5B).contains($0.value) }) else { return false }
        // Cannot start with a combining mark or a following vowel (ะ า ำ ๅ).
        if isCombining(first) || [0x0E30, 0x0E32, 0x0E33, 0x0E45].contains(first) { return false }
        for (a, b) in zip(scalars, scalars.dropFirst()) {
            let tones: ClosedRange<UInt32> = 0x0E48...0x0E4B
            if tones.contains(a.value) && tones.contains(b.value) { return false }
            if isCombining(a.value) && a == b { return false }
        }
        return true
    }
}
