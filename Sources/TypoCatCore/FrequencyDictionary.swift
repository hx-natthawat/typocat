import Foundation

/// Ranked word list in FrequencyWords format: one "word count" pair per line.
public final class FrequencyDictionary: @unchecked Sendable {
    private let counts: [String: Int]
    /// 1 for the most frequent word. Comparable across languages, unlike raw counts:
    /// the Thai corpus is hundreds of times smaller than the English one.
    private let ranks: [String: Int]
    /// Longest entry measured in Unicode scalars, bounds the segmentation search.
    public let maxScalarLength: Int
    /// Letters seen in the list, most frequent first; candidate edits draw from these.
    public let alphabet: [Character]

    /// - Parameter splitCompounds: for lists built from unsegmented text (Thai subtitles hold
    ///   entries like "คุณมาทำอะไรที่นี่"), also credit each entry's count to the words it splits into,
    ///   so short everyday words like ทำ rank as high as they are common.
    public init(contents: String, splitCompounds: Bool = false) {
        var counts: [String: Int] = [:]
        var maxLen = 0
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let n = Int(parts[parts.count - 1]) else { continue }
            let word = parts[0..<(parts.count - 1)].joined(separator: " ").lowercased()
            // Keep the highest count when case-folding merges two entries.
            if n > counts[word, default: 0] { counts[word] = n }
            maxLen = max(maxLen, word.unicodeScalars.count)
        }
        if splitCompounds { counts = Self.creditingParts(of: counts, maxLength: min(maxLen, 24)) }
        var letterCounts: [Character: Int] = [:]
        for (word, n) in counts { for ch in word where ch.isLetter { letterCounts[ch, default: 0] += n } }
        // Drop stray letters from other scripts (names, loanwords) that would only add noise.
        let total = letterCounts.values.reduce(0, +)
        self.alphabet = letterCounts.filter { Double($0.value) / Double(max(1, total)) > 0.0005 }
            .sorted { $0.value > $1.value }.map(\.key)
        self.counts = counts
        var ranks: [String: Int] = [:]
        for (i, word) in counts.keys.sorted(by: { counts[$0]! > counts[$1]! }).enumerated() { ranks[word] = i + 1 }
        self.ranks = ranks
        self.maxScalarLength = min(maxLen, 24)
    }

    public convenience init(url: URL, splitCompounds: Bool = false) throws {
        self.init(contents: try String(contentsOf: url, encoding: .utf8), splitCompounds: splitCompounds)
    }

    /// Splits each entry into the fewest other entries (two scalars or more) that cover it
    /// exactly, and adds the entry's count to each of them.
    private static func creditingParts(of counts: [String: Int], maxLength: Int) -> [String: Int] {
        var result = counts
        for (entry, n) in counts {
            let scalars = Array(entry.unicodeScalars)
            let len = scalars.count
            guard len >= 4 else { continue }
            // pieces[i]: fewest words covering scalars[0..<i]; from[i]: where the last one starts.
            var pieces = [Int](repeating: .max, count: len + 1)
            var from = [Int](repeating: -1, count: len + 1)
            pieces[0] = 0
            for i in 2...len {
                for j in max(0, i - maxLength)...(i - 2) where pieces[j] != .max && !(j == 0 && i == len) {
                    var view = String.UnicodeScalarView()
                    view.append(contentsOf: scalars[j..<i])
                    if counts[String(view)] != nil, pieces[j] + 1 < pieces[i] {
                        pieces[i] = pieces[j] + 1
                        from[i] = j
                    }
                }
            }
            guard pieces[len] != .max else { continue }
            var end = len
            while end > 0 {
                let start = from[end]
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[start..<end])
                result[String(view), default: 0] += n
                end = start
            }
        }
        return result
    }

    public var isEmpty: Bool { counts.isEmpty }

    public func count(of word: String) -> Int { counts[word.lowercased()] ?? 0 }

    /// 0...1: 1 for the top word, falling with log rank to 0 at the end of the list; 0 if absent.
    public func commonness(of word: String) -> Double {
        guard let rank = ranks[word.lowercased()], ranks.count > 1 else { return 0 }
        return 1 - log(Double(rank)) / log(Double(ranks.count))
    }

    /// Fraction of scalars covered by dictionary words (each at least two scalars long)
    /// in the best segmentation. Used for scripts written without spaces, such as Thai.
    public func segmentCoverage(_ text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        let n = scalars.count
        guard n > 0 else { return 0 }
        var best = [Int](repeating: 0, count: n + 1)
        for i in 1...n {
            best[i] = best[i - 1] // leave scalar i-1 uncovered
            let lower = max(0, i - maxScalarLength)
            var j = i - 2
            while j >= lower {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[j..<i])
                if counts[String(view)] != nil {
                    best[i] = max(best[i], best[j] + (i - j))
                }
                j -= 1
            }
        }
        return Double(best[n]) / Double(n)
    }
}

/// Serbian is written in both Latin and Cyrillic and maps one to one. Subtitle
/// corpora are mostly Latin while the macOS Serbian layout types Cyrillic.
public enum SerbianScript {
    private static let digraphs: [(String, String)] = [("lj", "љ"), ("nj", "њ"), ("dž", "џ")]
    private static let letters: [Character: String] = [
        "a": "а", "b": "б", "c": "ц", "č": "ч", "ć": "ћ", "d": "д", "đ": "ђ", "e": "е", "f": "ф", "g": "г",
        "h": "х", "i": "и", "j": "ј", "k": "к", "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "r": "р",
        "s": "с", "š": "ш", "t": "т", "u": "у", "v": "в", "z": "з", "ž": "ж",
    ]

    /// Cyrillic spelling of a lowercase Latin Serbian word, or nil if it has other letters.
    public static func cyrillic(_ latin: String) -> String? {
        var rest = Substring(latin)
        var out = ""
        outer: while !rest.isEmpty {
            for (pair, cyr) in digraphs where rest.hasPrefix(pair) {
                out += cyr
                rest = rest.dropFirst(pair.count)
                continue outer
            }
            guard let cyr = letters[rest.first!] else { return nil }
            out += cyr
            rest = rest.dropFirst()
        }
        return out
    }

    /// Word list contents with a Cyrillic line added after every Latin one.
    public static func addingCyrillic(to contents: String) -> String {
        var out = ""
        out.reserveCapacity(contents.utf8.count * 2)
        for line in contents.split(whereSeparator: \.isNewline) {
            out += line + "\n"
            let parts = line.split(separator: " ")
            if parts.count == 2, let cyr = cyrillic(parts[0].lowercased()) { out += "\(cyr) \(parts[1])\n" }
        }
        return out
    }
}
