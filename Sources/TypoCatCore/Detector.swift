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
    let dictionaries: [Language: FrequencyDictionary]

    /// Minimum confidence for the alternative rendering.
    public var acceptThreshold = 0.6
    /// Maximum confidence the typed text may have and still be replaced.
    public var rejectThreshold = 0.3
    public var minimumStrokes = 2
    /// The typed text may be a real but rare word ("mew" for ทำไม). Replace it
    /// anyway when the other rendering scores this much higher.
    public var dominanceMargin = 0.2
    // Typo correction (see TypoCorrector.swift); tuned with `--eval-typos`.
    public var typoMinimumLength = 4
    /// The winning candidate must be at least this common in its language (0...1 by rank).
    public var typoMinimumCommonness = 0.3
    /// ...and at least this many times as frequent as the next candidate. 10 instead of 3
    /// cuts English wrong-word fixes from 4.8% to 1.9% of typos for 3 points of fix rate.
    public var typoDominance = 10.0
    /// After a later fix into a language, an earlier word left alone is reread into it unless it
    /// scores at least this in its own language: 0.8 is about the top 200 words, 0.65 the top
    /// 13000. nil: only one-key words are reread (below). `LS_REREAD_ALL=1 LS_KEEP=0.65 --eval 5000`
    /// measures it: missed short words recovered against correct short English words changed.
    /// 0.8 where that changes 0.5% of short English words or fewer: Thai and other spaceless
    /// scripts (79% recovered), Russian (85%), Kazakh (79%). Elsewhere 0.8 changes 1-9%;
    /// 0.65 changes none of the top 5000 and at most 0.04% of short English as used, for
    /// 35-56% recovered. Into English it isn't measured (~3% of Thai at 0.8), so it stays off.
    public var rereadKeepScore: @Sendable (Language) -> Double? = {
        if $0 == .english { return nil }
        return $0.writesWithoutSpaces || ["ru", "kk"].contains($0.rawValue) ? 0.8 : 0.65
    }
    /// Any language takes back a one-key word left alone before a fix ("ณ love" → "I love")
    /// when that letter is a word this common in it: about the top 10 words.
    public var singleKeyRereadScore = 0.95
    /// Keys that type punctuation on one layout type letters on another (`[kp` is บาย on Thai).
    /// When the typed text is only a word once that punctuation is stripped ("kp") and the
    /// other rendering is all letters, the typed score counts this much.
    public var strippedPunctuationWeight = 0.5

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
        var word = text.trimmingCharacters(in: Self.edgePunctuation).lowercased()
        // Apostrophes belong inside words (don't, 'em) but are also quotes: 'to' is to.
        if dict.count(of: word) == 0 { word = word.trimmingCharacters(in: Self.quotes) }
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
        // Words spelled with an edge apostrophe ('em, goin') are words, not stray keys.
        let punctuated = Self.hasUnusualPunctuation(typed) || (Self.hasUnpairedQuote(typed)
            && dictionaries[current]?.count(of: typed.trimmingCharacters(in: Self.edgePunctuation)) ?? 0 == 0)
        /// Beyond the reject threshold only a clearly more common alternative can win.
        func beats(_ altScore: Double, typed typedScore: Double) -> Bool {
            let required = typedScore > rejectThreshold ? typedScore + dominanceMargin : 0
            return altScore >= acceptThreshold && altScore > typedScore && altScore >= required
        }

        var best: (Correction, Double, wins: Bool)?
        for (language, layout) in layouts where language != current {
            guard let alt = layout.render(strokes), alt != typed else { continue }
            let s = score(alt, as: language)
            let lettersOnly = punctuated && alt.unicodeScalars.allSatisfy(Self.isWordScalar)
            let wins = beats(s, typed: lettersOnly ? typedScore * strippedPunctuationWeight : typedScore)
            if best == nil || s > best!.1 {
                best = (Correction(original: typed, replacement: alt, from: current, to: language), s, wins)
            }
        }
        guard let best else { return nil }
        return force || best.wins ? best.0 : nil
    }

    /// After a later word was fixed to `target`, decides whether an earlier word
    /// left alone (short words like `z,` for ผม are ambiguous on their own) should
    /// be fixed too. Returns its `target` rendering, or nil to keep it.
    public func reread(strokes: [KeyStroke], typed: String, current: Language, as target: Language,
                       layouts: [Language: LayoutMap], ignoring ignored: Set<String> = [],
                       category: AppCategory = .general) -> String? {
        let keepScore = rereadKeepScore(target)
        guard target != current, keepScore != nil || strokes.count == 1, !ignored.contains(typed),
              !ProtectedWords.contains(typed, in: category),
              let alt = layouts[target]?.render(strokes), alt != typed else { return nil }
        let altScore = score(alt, as: target), typedScore = score(typed, as: current)
        if keepScore == nil, altScore < singleKeyRereadScore { return nil }
        // Common words (นา, ทำ, go) stay: mixed-language text is normal. Rare ones (fu, z) may go.
        guard typedScore < keepScore ?? 0.8 else { return nil }
        return altScore >= acceptThreshold && altScore > typedScore ? alt : nil
    }

    /// Punctuation people put around words: "(word", "word,". Anything else at a word's edge
    /// (`[kp`, `=kp`, `;hk;`) is more likely letters typed on the wrong layout.
    private static let usualLeading = CharacterSet(charactersIn: "(\"'“‘«¿¡")
    private static let usualTrailing = CharacterSet(charactersIn: ",.;:!?)\"'”’»…")

    static func hasUnusualPunctuation(_ typed: String) -> Bool {
        let scalars = Array(typed.unicodeScalars)
        guard let first = scalars.firstIndex(where: { !edgePunctuation.contains($0) }),
              let last = scalars.lastIndex(where: { !edgePunctuation.contains($0) }) else { return false }
        return scalars[..<first].contains { !usualLeading.contains($0) }
            || scalars[(last + 1)...].contains { !usualTrailing.contains($0) }
    }

    /// A quote with no partner ('nj is это on Russian) is more likely a letter key.
    static func hasUnpairedQuote(_ typed: String) -> Bool {
        let core = typed.trimmingCharacters(in: edgePunctuation).unicodeScalars
        let opens = core.first.map(quotes.contains) ?? false, closes = core.last.map(quotes.contains) ?? false
        return core.count > 1 && opens != closes
    }

    private static let quotes = CharacterSet(charactersIn: "'’")
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
