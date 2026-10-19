import Foundation

extension Detector {
    /// A correction for a misspelled word one edit away from a common word
    /// (`teh` → `the` is too short; `becuase` → `because`, `recieve` → `receive`).
    /// Conservative on purpose: only lowercase words of `typoMinimumLength` letters or more
    /// that are absent from the word list, and only when one candidate clearly wins.
    /// The app also asks the system spell checker before applying it.
    public func typoFix(_ typed: String, in language: Language, ignoring ignored: Set<String> = [],
                        category: AppCategory = .general) -> String? {
        guard !language.writesWithoutSpaces, category != .terminal, category != .code,
              !Self.isIgnored(typed, in: ignored), !ProtectedWords.contains(typed, in: category),
              let dict = dictionary(for: language) else { return nil }
        // Keep edge punctuation ("becuase," → "because,") and fix only the word inside.
        let scalars = typed.unicodeScalars
        guard let start = scalars.firstIndex(where: { $0.properties.isAlphabetic }),
              let end = scalars.lastIndex(where: { $0.properties.isAlphabetic }) else { return nil }
        let word = String(scalars[start...end])
        guard word.count >= typoMinimumLength, word == word.lowercased(),
              word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }), dict.count(of: word) == 0 else { return nil }

        var best: (word: String, count: Int)?
        var runnerUp = 0
        for candidate in Self.edits(of: word, alphabet: dict.alphabet) {
            let n = dict.count(of: candidate)
            guard n > 0, candidate != best?.word else { continue }
            if n > (best?.count ?? 0) {
                runnerUp = best?.count ?? 0
                best = (candidate, n)
            } else if n > runnerUp {
                runnerUp = n
            }
        }
        guard let best, dict.commonness(of: best.word) >= typoMinimumCommonness,
              Double(best.count) >= Double(runnerUp) * typoDominance else { return nil }
        return String(scalars[..<start]) + best.word + String(scalars[scalars.index(after: end)...])
    }

    /// Every string one deletion, transposition, substitution or insertion away.
    static func edits(of word: String, alphabet: [Character]) -> Set<String> {
        let chars = Array(word)
        var out = Set<String>()
        for i in 0..<chars.count {
            var d = chars; d.remove(at: i); out.insert(String(d))
            if i + 1 < chars.count { var t = chars; t.swapAt(i, i + 1); out.insert(String(t)) }
            for c in alphabet where c != chars[i] { var s = chars; s[i] = c; out.insert(String(s)) }
        }
        for i in 0...chars.count {
            for c in alphabet { var ins = chars; ins.insert(c, at: i); out.insert(String(ins)) }
        }
        out.remove(word)
        return out
    }
}
