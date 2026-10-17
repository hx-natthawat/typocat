import Foundation
import TypoCatCore

/// Checks the detector against every keyboard layout installed on this Mac,
/// enabled or not, so languages can be tested without turning them on.
/// Usage: `swift run TypoCat --selftest` and `swift run TypoCat --eval [N]`
enum SelfTest {
    static func run() -> Bool {
        let layouts = InputSources.installedLayouts()
        guard let en = layouts[.english] else {
            print("FAIL: no English layout installed")
            return false
        }
        // (word as the user meant it, its language, should typing it on the other layout get fixed?)
        // Each word is checked against English; English words are checked against `other`.
        let cases: [(word: String, language: String, other: String, fix: Bool)] = [
            ("hello", "en", "th", true), ("world", "en", "th", true), ("meeting", "en", "th", true),
            ("the", "en", "th", true), ("people", "en", "th", true),
            ("สวัสดี", "th", "en", true), ("ครับ", "th", "en", true), ("ภาษาไทย", "th", "en", true),
            ("ขอบคุณครับ", "th", "en", true), ("ไม่", "th", "en", true), ("เป็น", "th", "en", true),
            // Ambiguous: "ok" on the Thai layout is "นา", a real Thai word. Leave it.
            ("ok", "en", "th", false),
            ("привет", "ru", "en", true), ("спасибо", "ru", "en", true), ("hello", "en", "ru", true),
            ("привіт", "uk", "en", true), ("дякую", "uk", "en", true),
            ("שלום", "he", "en", true), ("תודה", "he", "en", true), ("hello", "en", "he", true),
            ("مرحبا", "ar", "en", true), ("شكرا", "ar", "en", true),
            // Greek accents are dead keys: ΄ then a vowel.
            ("ευχαριστώ", "el", "en", true), ("καλημέρα", "el", "en", true), ("και", "el", "en", true),
            ("سلام", "fa", "en", true), ("здраво", "sr", "en", true), ("здравей", "bg", "en", true),
            ("გამარჯობა", "ka", "en", true), ("շնորհակալություն", "hy", "en", true),
        ]
        let languages = Set(cases.flatMap { [Language(rawValue: $0.language), Language(rawValue: $0.other)] })
        let detector = Dictionaries.makeDetector(for: languages)
        var ok = true
        for c in cases {
            let language = Language(rawValue: c.language), other = Language(rawValue: c.other)
            guard let intended = layouts[language], let wrong = layouts[other] else {
                print("SKIP \(c.word): no \(language) or \(other) layout installed")
                continue
            }
            guard detector.languages.contains(language) else {
                print("SKIP \(c.word): no \(language) word list in Data/ (run scripts/build-app.sh)")
                continue
            }
            guard let strokes = strokes(for: c.word, in: intended), let typed = wrong.render(strokes) else {
                print("SKIP \(c.word): cannot be typed on \(intended.inputSourceID)")
                continue
            }
            let pair = [language: intended, other: wrong]
            let fix = detector.decide(strokes: strokes, typed: typed, current: other, layouts: pair)
            let fixed = fix?.replacement == c.word
            let leftAlone = detector.decide(strokes: strokes, typed: c.word, current: language, layouts: pair) == nil
            let pass = fixed == c.fix && leftAlone
            ok = ok && pass
            print("\(pass ? "PASS" : "FAIL") [\(other)→\(language)] \(typed) → \(fix?.replacement ?? "nil")  (expected \(c.fix ? c.word : "nil"); untouched-when-correct: \(leftAlone))")
        }

        // Commands typed correctly in a terminal must be left alone even if not dictionary words.
        if let th = layouts[.thai] {
            for command in ["git", "kubectl", "pnpm", "chmod"] {
                guard let strokes = strokes(for: command, in: en) else { continue }
                let fix = detector.decide(strokes: strokes, typed: command, current: .english,
                                          layouts: [.english: en, .thai: th],
                                          category: AppCategory(bundleID: "com.apple.Terminal"))
                ok = ok && fix == nil
                print("\(fix == nil ? "PASS" : "FAIL") \(command) in Terminal → \(fix?.replacement ?? "untouched")")
            }
        }

        // Per-app language memory: needs enough words and a clear majority.
        var profile = AppLanguageProfile()
        for _ in 0..<19 { profile.record(.english, in: "code") }
        let tooFew = profile.dominant(in: "code") == nil
        profile.record(.english, in: "code")
        let english = profile.dominant(in: "code") == .english
        for _ in 0..<12 { profile.record(.english, in: "line") }
        for _ in 0..<11 { profile.record(.thai, in: "line") }
        let mixed = profile.dominant(in: "line") == nil
        let profilePass = tooFew && english && mixed
        ok = ok && profilePass
        print("\(profilePass ? "PASS" : "FAIL") app language profile (few: \(tooFew), dominant: \(english), mixed: \(mixed))")
        return ok
    }

    /// Measures the detector on the most frequent words of each bundled language,
    /// paired with English: both directions, plus how often correct text gets changed.
    static func evaluate(top n: Int) {
        let layouts = InputSources.installedLayouts()
        guard let en = layouts[.english] else { print("no English layout installed"); return }
        let languages = Language.bundled.filter { layouts[$0] != nil && Dictionaries.url(for: $0) != nil }
        let detector = Dictionaries.makeDetector(for: languages)
        print("lang  layout                               | fixed on EN layout | EN fixed on it | correct text changed")
        for language in languages where language != .english {
            let other = layouts[language]!
            let pair = [Language.english: en, language: other]
            let a = measure(ranked(language, n), intended: other, wrong: en, detector: detector, layouts: pair)
            let b = measure(ranked(.english, n), intended: en, wrong: other, detector: detector, layouts: pair)
            let changed = 100 * Double(a.changed + b.changed) / Double(max(1, a.words + b.words))
            print(String(format: "%@  %@ |  %5.1f%% of %5d   |  %5.1f%% of %5d | %5.2f%%",
                         language.rawValue.padding(toLength: 4, withPad: " ", startingAt: 0),
                         other.inputSourceID.padding(toLength: 36, withPad: " ", startingAt: 0),
                         a.rate, a.words, b.rate, b.words, changed))
            if !a.misses.isEmpty { print("      missed:", a.misses.joined(separator: " ")) }

            // Spaceless scripts: short words left alone, recovered once a later word is fixed.
            guard detector.rereadsInto(language) else { continue }
            let missedShort = ranked(language, n).filter { w in
                guard let st = strokes(for: w, in: other), (2...3).contains(st.count), let typed = en.render(st) else { return false }
                return detector.decide(strokes: st, typed: typed, current: .english, layouts: pair)?.replacement != w
            }
            let recovered = missedShort.filter { w in
                guard let st = strokes(for: w, in: other), let typed = en.render(st) else { return false }
                return detector.reread(strokes: st, typed: typed, current: .english, as: language, layouts: pair) == w
            }
            let englishShort = ranked(.english, n).filter { (strokes(for: $0, in: en)?.count).map { (2...3).contains($0) } ?? false }
            let converted = englishShort.filter { w in
                detector.reread(strokes: strokes(for: w, in: en)!, typed: w, current: .english, as: language, layouts: pair) != nil
            }
            print(String(format: "      reread: recovered %.1f%% of %d missed short words; changed %.1f%% of %d correct short English words",
                         100 * Double(recovered.count) / Double(max(1, missedShort.count)), missedShort.count,
                         100 * Double(converted.count) / Double(max(1, englishShort.count)), englishShort.count))
        }
    }

    private static func measure(_ words: [String], intended: LayoutMap, wrong: LayoutMap, detector: Detector,
                                layouts: [Language: LayoutMap]) -> (words: Int, rate: Double, changed: Int, misses: [String]) {
        var total = 0, fixed = 0, changed = 0
        var misses: [String] = []
        for word in words {
            guard let st = strokes(for: word, in: intended), st.count >= 2, let typed = wrong.render(st) else { continue }
            total += 1
            if detector.decide(strokes: st, typed: typed, current: wrong.language, layouts: layouts)?.replacement == word {
                fixed += 1
            } else if misses.count < 10 {
                misses.append("\(word)(\(typed))")
            }
            if detector.decide(strokes: st, typed: word, current: intended.language, layouts: layouts) != nil { changed += 1 }
        }
        return (total, 100 * Double(fixed) / Double(max(1, total)), changed, misses)
    }

    private static func ranked(_ language: Language, _ n: Int) -> [String] {
        guard let url = Dictionaries.url(for: language), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let words = text.split(separator: "\n").prefix(n).compactMap { $0.split(separator: " ").first.map(String.init) }
        return language.rawValue == "sr" ? words.map { SerbianScript.cyrillic($0) ?? $0 } : words
    }

    /// Inverts a layout to find the keystrokes that type `text`.
    private static var inverses: [String: [String: [KeyStroke]]] = [:]
    private static func strokes(for text: String, in layout: LayoutMap) -> [KeyStroke]? {
        let inverse = inverses[layout.inputSourceID] ?? layout.inverse()
        inverses[layout.inputSourceID] = inverse
        var out: [KeyStroke] = []
        for scalar in text.unicodeScalars {
            guard let k = inverse[String(scalar)] else { return nil }
            out += k
        }
        return out
    }
}
