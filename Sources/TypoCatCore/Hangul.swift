import Foundation

/// Korean is typed through an input method, not a keyboard layout: each key types a letter
/// (jamo) and the input method joins letters into syllable blocks as you type (ㅇ ㅏ ㄴ → 안).
/// macOS has no key map to read for it, so the 2-Set (Dubeolsik) layout is built here, and
/// rendering keys on it joins the letters the way the input method does.
public enum Hangul {
    /// Input source IDs of the 2-Set Korean input mode; other Korean layouts (3-Set, Romaja)
    /// put letters elsewhere and aren't supported.
    public static func isTwoSet(_ inputSourceID: String) -> Bool {
        inputSourceID.hasPrefix("com.apple.inputmethod.Korean.2SetKorean")
    }

    public static let language = Language(rawValue: "ko")

    /// 2-Set Korean on the ANSI key positions; keys it leaves alone type what U.S. types.
    public static func twoSetLayout(over us: LayoutMap?, inputSourceID: String = "com.apple.inputmethod.Korean.2SetKorean") -> LayoutMap {
        var forward: [KeyStroke: String] = us?.keyMap ?? [:]
        for (code, plain, shifted) in twoSetKeys {
            forward[KeyStroke(keyCode: code, shift: false)] = plain
            forward[KeyStroke(keyCode: code, shift: true)] = shifted
        }
        return LayoutMap(language: language, inputSourceID: inputSourceID, forward: forward, joinsHangul: true)
    }

    /// (ANSI key code, jamo, jamo with Shift). Shift doubles ㅂㅈㄷㄱㅅ and turns ㅐㅔ into ㅒㅖ.
    private static let twoSetKeys: [(UInt16, String, String)] = [
        (12, "ㅂ", "ㅃ"), (13, "ㅈ", "ㅉ"), (14, "ㄷ", "ㄸ"), (15, "ㄱ", "ㄲ"), (17, "ㅅ", "ㅆ"),
        (16, "ㅛ", "ㅛ"), (32, "ㅕ", "ㅕ"), (34, "ㅑ", "ㅑ"), (31, "ㅐ", "ㅒ"), (35, "ㅔ", "ㅖ"),
        (0, "ㅁ", "ㅁ"), (1, "ㄴ", "ㄴ"), (2, "ㅇ", "ㅇ"), (3, "ㄹ", "ㄹ"), (5, "ㅎ", "ㅎ"),
        (4, "ㅗ", "ㅗ"), (38, "ㅓ", "ㅓ"), (40, "ㅏ", "ㅏ"), (37, "ㅣ", "ㅣ"),
        (6, "ㅋ", "ㅋ"), (7, "ㅌ", "ㅌ"), (8, "ㅊ", "ㅊ"), (9, "ㅍ", "ㅍ"), (11, "ㅠ", "ㅠ"),
        (45, "ㅜ", "ㅜ"), (46, "ㅡ", "ㅡ"),
    ]

    // Compatibility jamo in syllable-index order.
    private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// Index 0 is "no final consonant".
    private static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    private static let compoundVowels: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    private static let compoundFinals: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
        "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]
    private static let splitVowels = Dictionary(uniqueKeysWithValues: compoundVowels.map { ($0.value, $0.key) })
    private static let splitFinals = Dictionary(uniqueKeysWithValues: compoundFinals.map { ($0.value, $0.key) })

    private static func isConsonant(_ c: Character) -> Bool { initials.contains(c) || splitFinals[c] != nil }
    private static func isVowel(_ c: Character) -> Bool { vowels.contains(c) }

    /// Joins typed letters into syllables as the 2-Set input method does: ㅇㅏㄴㄴㅕㅇ → 안녕,
    /// ㄷㅏㄹㄱ → 닭, and a final consonant moves on when a vowel follows (ㄱㅏㄴㅏ → 가나).
    public static func compose(_ text: String) -> String {
        var out = ""
        var initial: Character?, vowel: Character?, final: Character?

        func flush() {
            if let i = initial, let v = vowel, let li = initials.firstIndex(of: i), let vi = vowels.firstIndex(of: v) {
                let ti = final.flatMap { f in finals.firstIndex(of: f) } ?? 0
                out.unicodeScalars.append(Unicode.Scalar(0xAC00 + (li * 21 + vi) * 28 + ti)!)
            } else {
                if let i = initial { out.append(i) }
                if let v = vowel { out.append(v) }
            }
            initial = nil; vowel = nil; final = nil
        }

        for c in text {
            if isVowel(c) {
                if let v = vowel, final == nil, let joined = compoundVowels["\(v)\(c)"] {
                    vowel = joined
                } else if let f = final {
                    // The final consonant starts the next syllable; a compound one gives up its second half.
                    if let parts = splitFinals[f] {
                        final = parts.first
                        flush()
                        initial = parts.last
                    } else {
                        final = nil
                        flush()
                        initial = f
                    }
                    vowel = c
                } else if initial != nil && vowel == nil {
                    vowel = c
                } else {
                    flush()
                    vowel = c
                }
            } else if isConsonant(c) {
                if initial != nil, vowel != nil {
                    if final == nil, finals.contains(c) {
                        final = c
                    } else if let f = final, let joined = compoundFinals["\(f)\(c)"] {
                        final = joined
                    } else {
                        flush()
                        initial = c
                    }
                } else {
                    flush()
                    initial = c
                }
            } else {
                flush()
                out.append(c)
            }
        }
        flush()
        return out
    }

    /// The letters, one per key, that type `text`: 닭 → ㄷㅏㄹㄱ, ㅘ → ㅗㅏ. Text that isn't
    /// Hangul passes through.
    public static func keyLetters(_ text: String) -> String {
        var out = ""
        func letter(_ c: Character) {
            if let parts = splitVowels[c] ?? splitFinals[c] { out += parts } else { out.append(c) }
        }
        for scalar in text.unicodeScalars {
            let v = Int(scalar.value)
            guard (0xAC00...0xD7A3).contains(v) else { letter(Character(scalar)); continue }
            let index = v - 0xAC00
            letter(initials[index / (21 * 28)])
            letter(vowels[(index / 28) % 21])
            if let f = finals[index % 28] { letter(f) }
        }
        return out
    }
}
