import AppKit
import TypoCatCore

/// The macOS spell checker knows far more words than our 50k lists, plus words
/// the user taught it, so it gets a veto over every typo fix.
enum SystemSpelling {
    /// nil when macOS has no spelling dictionary for the language.
    static func isKnown(_ word: String, in language: Language) -> Bool? {
        let checker = NSSpellChecker.shared
        guard let code = checker.availableLanguages.first(where: { Language(rawValue: $0) == language.base }) else { return nil }
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: code, wrap: false,
                                         inSpellDocumentWithTag: 0, wordCount: nil)
        return miss.location == NSNotFound
    }

    /// Applies only when the system spell checker agrees the word is misspelled.
    static func confirmsTypo(_ word: String, in language: Language) -> Bool {
        let letters = word.trimmingCharacters(in: .letters.inverted)
        return isKnown(letters, in: language) == false
    }

    /// True when macOS also flags `typo` and its first guess is `fix`. Languages listed by
    /// macOS without a working dictionary (Ukrainian, Greek, Hebrew on this Mac) never agree.
    static func agrees(typo: String, fix: String, in language: Language) -> Bool {
        let checker = NSSpellChecker.shared
        guard let code = checker.availableLanguages.first(where: { Language(rawValue: $0) == language.base }) else { return false }
        let word = typo.trimmingCharacters(in: .letters.inverted)
        let target = fix.trimmingCharacters(in: .letters.inverted)
        guard isKnown(word, in: language) == false else { return false }
        let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
                                      language: code, inSpellDocumentWithTag: 0) ?? []
        // Only its first guess: accepting any of the top 3 lets ~3x more wrong fixes through (--eval-typos).
        return guesses.first == target
    }
}
