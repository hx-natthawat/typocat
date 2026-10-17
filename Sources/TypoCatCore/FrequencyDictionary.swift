import Foundation

/// Ranked word list in FrequencyWords format: one "word count" pair per line.
public final class FrequencyDictionary: @unchecked Sendable {
    /// Words as NFC UTF-8, sorted bytewise and packed into one buffer; word i is
    /// bytes[offsets[i]..<offsets[i + 1]]. A [String: Entry] table took about 4x the memory,
    /// mostly for the separate heap allocation behind every non-ASCII String.
    private let bytes: [UInt8]
    private let offsets: [Int32]
    private let counts: [Int32]
    /// 1 = most frequent. Ranks are comparable across languages, unlike raw counts:
    /// the Thai corpus is far smaller than English.
    private let ranks: [Int32]
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
            let word = Self.normalized(parts[0..<(parts.count - 1)].joined(separator: " "))
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
        // Ties broken by spelling so ranks, and every score, are the same on each run.
        let byCount = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var words = byCount.enumerated().map { (utf8: Array($0.element.key.utf8), count: $0.element.value, rank: $0.offset + 1) }
        words.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(words.reduce(0) { $0 + $1.utf8.count })
        var offsets: [Int32] = [0]
        offsets.reserveCapacity(words.count + 1)
        for word in words {
            bytes.append(contentsOf: word.utf8)
            offsets.append(Int32(bytes.count))
        }
        self.bytes = bytes
        self.offsets = offsets
        self.counts = words.map { Int32(clamping: $0.count) }
        self.ranks = words.map { Int32($0.rank) }
        self.maxScalarLength = min(maxLen, 24)
    }

    public convenience init(url: URL, splitCompounds: Bool = false) throws {
        self.init(contents: try String(contentsOf: url, encoding: .utf8), splitCompounds: splitCompounds)
    }

    /// Splits each entry into the fewest other entries (two scalars or more) that cover it
    /// exactly, and adds the entry's count to each of them.
    private static func creditingParts(of counts: [String: Int], maxLength: Int) -> [String: Int] {
        // A trie over the entries lets the segmentation walk forward scalar by scalar
        // instead of building a String for every candidate piece (about 10x faster on Thai).
        var children: [[UInt32: Int32]] = [[:]]
        var terminal: [Bool] = [false]
        for entry in counts.keys {
            let scalars = entry.unicodeScalars
            guard scalars.count <= maxLength else { continue }
            var node = 0
            for scalar in scalars {
                if let next = children[node][scalar.value] {
                    node = Int(next)
                } else {
                    children.append([:]); terminal.append(false)
                    children[node][scalar.value] = Int32(children.count - 1)
                    node = children.count - 1
                }
            }
            terminal[node] = true
        }

        var result = counts
        for (entry, n) in counts {
            let scalars = Array(entry.unicodeScalars)
            let len = scalars.count
            guard len >= 4 else { continue }
            // pieces[i]: fewest words covering scalars[0..<i]; from[i]: where the last one starts.
            var pieces = [Int](repeating: .max, count: len + 1)
            var from = [Int](repeating: -1, count: len + 1)
            pieces[0] = 0
            for j in 0..<len where pieces[j] != .max {
                var node = 0
                for i in j..<min(len, j + maxLength) {
                    guard let next = children[node][scalars[i].value] else { break }
                    node = Int(next)
                    let end = i + 1
                    // Pieces are two scalars or more, and never the whole entry itself.
                    guard end - j >= 2, terminal[node], !(j == 0 && end == len), pieces[j] + 1 < pieces[end] else { continue }
                    pieces[end] = pieces[j] + 1
                    from[end] = j
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

    public func count(of word: String) -> Int { index(of: word).map { Int(counts[$0]) } ?? 0 }

    /// 0...1: 1 for the top word, falling with log rank to 0 at the end of the list; 0 if absent.
    public func commonness(of word: String) -> Double {
        guard let i = index(of: word), counts.count > 1 else { return 0 }
        return 1 - log(Double(ranks[i])) / log(Double(counts.count))
    }

    /// Lowercase NFC, the form entries are stored in. Typed text and word lists can differ
    /// in normalization (é as one scalar or e + accent), which String == hides but bytes don't.
    private static func normalized(_ word: String) -> String {
        let lower = word.lowercased()
        return lower.utf8.allSatisfy({ $0 < 0x80 }) ? lower : lower.precomposedStringWithCanonicalMapping
    }

    private func index(of word: String) -> Int? {
        var key = Self.normalized(word)
        return key.withUTF8 { index(of: UnsafeRawBufferPointer($0)) }
    }

    /// Binary search over the packed words.
    private func index(of key: UnsafeRawBufferPointer) -> Int? {
        bytes.withUnsafeBytes { buffer in
            var low = 0, high = counts.count
            while low < high {
                let mid = (low + high) / 2
                let start = Int(offsets[mid]), length = Int(offsets[mid + 1]) - start
                let shared = min(length, key.count)
                var order = shared == 0 ? 0 : memcmp(buffer.baseAddress! + start, key.baseAddress!, shared)
                if order == 0 { order = length < key.count ? -1 : (length > key.count ? 1 : 0) }
                if order == 0 { return mid }
                if order < 0 { low = mid + 1 } else { high = mid }
            }
            return nil
        }
    }

    /// Fraction of scalars covered by dictionary words (each at least two scalars long)
    /// in the best segmentation. Used for scripts written without spaces, such as Thai.
    public func segmentCoverage(_ text: String) -> Double {
        let key = Self.normalized(text)
        let utf8 = Array(key.utf8)
        // starts[k]: byte offset of scalar k, so candidate pieces are byte slices, not new Strings.
        var starts: [Int] = []
        var offset = 0
        for scalar in key.unicodeScalars {
            starts.append(offset)
            offset += UTF8.width(scalar)
        }
        starts.append(offset)
        let n = starts.count - 1
        guard n > 0 else { return 0 }
        var best = [Int](repeating: 0, count: n + 1)
        utf8.withUnsafeBytes { text in
            for i in 1...n {
                best[i] = best[i - 1] // leave scalar i-1 uncovered
                let lower = max(0, i - maxScalarLength)
                var j = i - 2
                while j >= lower {
                    let piece = UnsafeRawBufferPointer(rebasing: text[starts[j]..<starts[i]])
                    if index(of: piece) != nil {
                        best[i] = max(best[i], best[j] + (i - j))
                    }
                    j -= 1
                }
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
