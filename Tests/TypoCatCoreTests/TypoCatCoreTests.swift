import XCTest
@testable import TypoCatCore

/// Core logic against tiny synthetic layouts and word lists, so these run on any
/// Mac (and CI) without real keyboard layouts or downloaded word lists.
final class TypoCatCoreTests: XCTestCase {
    static let ru = Language(rawValue: "ru")

    /// Keys 0...5 type h e l o w r on "en" and р у д щ ц к on "ru" (ЙЦУКЕН positions).
    func layouts() -> [Language: LayoutMap] {
        let en = ["h", "e", "l", "o", "w", "r"], ru = ["р", "у", "д", "щ", "ц", "к"]
        func map(_ letters: [String], _ language: Language) -> LayoutMap {
            var forward: [KeyStroke: String] = [:]
            for (i, s) in letters.enumerated() { forward[KeyStroke(keyCode: UInt16(i), shift: false)] = s }
            return LayoutMap(language: language, inputSourceID: "test.\(language)", forward: forward)
        }
        return [.english: map(en, .english), Self.ru: map(ru, Self.ru)]
    }

    func strokes(_ keys: [UInt16]) -> [KeyStroke] { keys.map { KeyStroke(keyCode: $0, shift: false) } }

    func detector() -> Detector {
        Detector(dictionaries: [
            .english: FrequencyDictionary(contents: "hello 5000\nworld 3000\nhell 900\nlower 400\nrow 300\n"),
            Self.ru: FrequencyDictionary(contents: "друг 4000\nрука 2000\nдом 1500\n"),
        ])
    }

    func testFixesWordTypedOnWrongLayout() {
        let keys = strokes([0, 1, 2, 2, 3]) // h e l l o
        let fix = detector().decide(strokes: keys, typed: "руддщ", current: Self.ru, layouts: layouts())
        XCTAssertEqual(fix?.replacement, "hello")
        XCTAssertEqual(fix?.to, .english)
    }

    func testLeavesCorrectWordAlone() {
        let keys = strokes([0, 1, 2, 2, 3])
        XCTAssertNil(detector().decide(strokes: keys, typed: "hello", current: .english, layouts: layouts()))
    }

    func testProtectedCommandsInTerminal() {
        // Shell commands are protected only where commands get typed; tech names everywhere.
        XCTAssertTrue(ProtectedWords.contains("chmod", in: .terminal))
        XCTAssertFalse(ProtectedWords.contains("chmod", in: .general))
        XCTAssertTrue(ProtectedWords.contains("git", in: .general))
        XCTAssertEqual(AppCategory(bundleID: "com.apple.Terminal"), .terminal)
        XCTAssertEqual(AppCategory(bundleID: "com.jetbrains.intellij"), .code)
    }

    func testDeadKeysCompose() {
        let acute = KeyStroke(keyCode: 9, shift: false), a = KeyStroke(keyCode: 0, shift: false)
        let map = LayoutMap(language: Language(rawValue: "el"), inputSourceID: "test.el",
                            forward: [a: "α", acute: "΄"], deadKeys: [acute: [a: "ά"]])
        XCTAssertEqual(map.render([acute, a, a]), "άα")
        XCTAssertEqual(map.inverse()["ά"], [acute, a])
    }

    func testLanguageCodesNormalize() {
        XCTAssertEqual(Language(rawValue: "en-US"), .english)
        XCTAssertEqual(Language(rawValue: "zh_Hant").rawValue, "zh")
        XCTAssertTrue(Language.thai.writesWithoutSpaces)
        XCTAssertFalse(Self.ru.writesWithoutSpaces)
    }

    func testCommonnessFollowsRank() {
        let dict = FrequencyDictionary(contents: "a 100\nb 10\nc 1\n")
        XCTAssertEqual(dict.commonness(of: "a"), 1)
        XCTAssertGreaterThan(dict.commonness(of: "b"), dict.commonness(of: "c"))
        XCTAssertEqual(dict.commonness(of: "zzz"), 0)
    }

    func testLookupIgnoresCaseAndNormalization() {
        let dict = FrequencyDictionary(contents: "caf\u{E9} 5\nzebra 3\napple 9\n")
        XCTAssertEqual(dict.count(of: "cafe\u{301}"), 5) // e + combining accent
        XCTAssertEqual(dict.count(of: "Apple"), 9)
        XCTAssertEqual(dict.count(of: "zebr"), 0)
        XCTAssertEqual(dict.count(of: "zebras"), 0)
        XCTAssertEqual(dict.count(of: ""), 0)
        XCTAssertEqual(dict.segmentCoverage("applezebra"), 1)
    }

    func testCompiledFileMatchesInMemoryList() throws {
        let contents = "hello 50\nสวัสดี 40\nworld 30\nhell 20\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).tcdict")
        defer { try? FileManager.default.removeItem(at: url) }
        try FrequencyDictionary.compile(contents: contents).write(to: url)
        let mapped = try FrequencyDictionary(compiledURL: url)
        let memory = FrequencyDictionary(contents: contents)
        for word in ["hello", "สวัสดี", "world", "hell", "he", "zzz"] {
            XCTAssertEqual(mapped.count(of: word), memory.count(of: word), word)
            XCTAssertEqual(mapped.commonness(of: word), memory.commonness(of: word), word)
        }
        XCTAssertEqual(mapped.alphabet, memory.alphabet)
        XCTAssertEqual(mapped.maxScalarLength, 6)
        XCTAssertEqual(mapped.segmentCoverage("helloworld"), 1)
    }

    func testCorruptCompiledFileIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).tcdict")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = FrequencyDictionary.compile(contents: "a 1\n")
        data.removeLast()
        try data.write(to: url)
        XCTAssertThrowsError(try FrequencyDictionary(compiledURL: url))
    }

    func testCompoundsCreditTheirParts() {
        // "ทำ" alone is rare, but it appears inside a common phrase.
        let contents = "ทำอะไร 500\nอะไร 300\nทำ 2\n"
        let plain = FrequencyDictionary(contents: contents)
        let split = FrequencyDictionary(contents: contents, splitCompounds: true)
        XCTAssertEqual(plain.count(of: "ทำ"), 2)
        XCTAssertEqual(split.count(of: "ทำ"), 502)
    }

    func testUnusualPunctuation() {
        XCTAssertTrue(Detector.hasUnusualPunctuation("[kp")) // บาย on Thai
        XCTAssertTrue(Detector.hasUnusualPunctuation("=kp"))
        XCTAssertTrue(Detector.hasUnusualPunctuation(";hk;"))
        XCTAssertFalse(Detector.hasUnusualPunctuation("look,"))
        XCTAssertFalse(Detector.hasUnusualPunctuation("(word)"))
        XCTAssertFalse(Detector.hasUnusualPunctuation("\"quoted\""))
        XCTAssertFalse(Detector.hasUnusualPunctuation("plain"))
    }

    func testQuotedWordsScoreAsWords() {
        let detector = Detector(dictionaries: [.english: FrequencyDictionary(contents: "to 900\n'em 5\n")])
        // Known words score 0.6 or more; 'em is the rarest here, so exactly 0.6.
        XCTAssertGreaterThan(detector.score("'to'", as: .english), 0.6)
        XCTAssertGreaterThan(detector.score("'em", as: .english), 0.5)
        XCTAssertTrue(Detector.hasUnpairedQuote("'nj")) // это on Russian
        XCTAssertFalse(Detector.hasUnpairedQuote("'to'"))
    }

    func testThaiOrthographyRejectsNoise() {
        XCTAssertTrue(ThaiOrthography.isPlausible("สวัสดี"))
        XCTAssertFalse(ThaiOrthography.isPlausible("้ำสสน")) // starts with a tone mark
    }

    func testSerbianTransliteration() {
        XCTAssertEqual(SerbianScript.cyrillic("zdravo"), "здраво")
        XCTAssertEqual(SerbianScript.cyrillic("ljubav"), "љубав")
        XCTAssertEqual(SerbianScript.cyrillic("džep"), "џеп")
        XCTAssertNil(SerbianScript.cyrillic("xyz"))
    }

    func testSerbianListLeavesOutEnglishQuotes() {
        // "out" is 4th here but 1st in English: a quote, not Serbian.
        let contents = SerbianScript.addingCyrillic(to: "da 10\nne 9\nje 8\nout 5\n", english: "out 100\nda 1\n",
                                                    englishBias: 2)
        XCTAssertTrue(contents.contains("да 10"))
        XCTAssertFalse(contents.contains("оут"))
    }

    func testPrefixLookup() {
        let d = FrequencyDictionary(contents: "hello 5\nhelp 4\nworld 3\n")
        XCTAssertTrue(d.hasPrefix("hel"))
        XCTAssertTrue(d.hasPrefix("Hello"))
        XCTAssertFalse(d.hasPrefix("hellos"))
        XCTAssertFalse(d.hasPrefix("wx"))
        XCTAssertFalse(d.hasPrefix("zz"))
    }

    func testThaiRunFixedBeforeSpace() {
        // Keys 0...2 type a b c on "en" and ก า ร on "th".
        func map(_ letters: [String], _ language: Language) -> LayoutMap {
            var forward: [KeyStroke: String] = [:]
            for (i, s) in letters.enumerated() { forward[KeyStroke(keyCode: UInt16(i), shift: false)] = s }
            return LayoutMap(language: language, inputSourceID: "test.\(language)", forward: forward)
        }
        let layouts = [Language.english: map(["a", "b", "c"], .english), .thai: map(["ก", "า", "ร"], .thai)]
        let d = Detector(dictionaries: [.english: FrequencyDictionary(contents: "abba 5\n"),
                                        .thai: FrequencyDictionary(contents: "การ 50\n")])
        d.midWordMinimumStrokes = 3
        XCTAssertEqual(d.decideMidWord(strokes: strokes([0, 1, 2]), typed: "abc", current: .english, layouts: layouts)?.replacement, "การ")
        XCTAssertNil(d.decideMidWord(strokes: strokes([0, 1, 2]), typed: "abc", current: .english, layouts: layouts,
                                     category: .terminal))
        // "ab" may still become "abba".
        d.midWordMinimumStrokes = 2
        XCTAssertNil(d.decideMidWord(strokes: strokes([0, 1]), typed: "ab", current: .english, layouts: layouts))
    }

    func testRereadKeepScorePerLanguage() {
        let d = detector()
        XCTAssertNil(d.rereadKeepScore(.english))
        XCTAssertEqual(d.rereadKeepScore(Self.ru), 0.8)
        XCTAssertEqual(d.rereadKeepScore(Language(rawValue: "he")), 0.65)
    }

    func testLayoutVariantsShareTheirLanguagesWordList() {
        let dvorak = Language(rawValue: "en+dvorak")
        XCTAssertEqual(dvorak.base, .english)
        XCTAssertEqual(dvorak.variant, "dvorak")
        XCTAssertEqual(dvorak.shortName, "DV")
        XCTAssertEqual(Language(.english, variant: "Colemak").rawValue, "en+colemak")
        XCTAssertNil(Language.english.variant)

        // Keys 0...2 type h e y on QWERTY and d . f on Dvorak; "hey" typed on Dvorak keys reads "d.f".
        func map(_ letters: [String], _ language: Language) -> LayoutMap {
            var forward: [KeyStroke: String] = [:]
            for (i, s) in letters.enumerated() { forward[KeyStroke(keyCode: UInt16(i), shift: false)] = s }
            return LayoutMap(language: language, inputSourceID: "test.\(language)", forward: forward)
        }
        let qwerty = map(["h", "e", "y"], .english), dv = map(["d", ".", "f"], dvorak)
        XCTAssertTrue(dv.movesLetters(comparedTo: qwerty))
        XCTAssertFalse(qwerty.movesLetters(comparedTo: map(["h", "e", "y"], dvorak)))
        let d = Detector(dictionaries: [.english: FrequencyDictionary(contents: "hey 50\n")])
        let fix = d.decide(strokes: strokes([0, 1, 2]), typed: "d.f", current: dvorak, layouts: [.english: qwerty, dvorak: dv])
        XCTAssertEqual(fix?.replacement, "hey")
        XCTAssertEqual(fix?.to, .english)
    }

    func testTypoFixPicksClearWinner() {
        let d = detector()
        XCTAssertNil(d.typoFix("helo", in: .english))                 // hello 5000 vs hell 900: not 10x apart
        XCTAssertEqual(d.typoFix("wrold,", in: .english), "world,")   // keeps punctuation
        XCTAssertNil(d.typoFix("Wrold", in: .english))                // capitalized: maybe a name
        XCTAssertNil(d.typoFix("wrold", in: .english, category: .terminal))
        XCTAssertNil(d.typoFix("hello", in: .english))                // already a word
    }

    func testAppLanguageProfileNeedsClearMajority() {
        var profile = AppLanguageProfile()
        for _ in 0..<19 { profile.record(.english, in: "app") }
        XCTAssertNil(profile.dominant(in: "app"))
        profile.record(.english, in: "app")
        XCTAssertEqual(profile.dominant(in: "app"), .english)
        profile.reassign(from: .english, to: .thai, in: "app")
        XCTAssertEqual(profile.counts["app"]?["th"], 1)
    }
}
