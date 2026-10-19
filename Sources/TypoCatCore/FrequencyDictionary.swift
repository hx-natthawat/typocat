import Foundation

/// Ranked word list in FrequencyWords format: one "word count" pair per line.
///
/// Stored in one flat buffer, the same layout as a compiled `.tcdict` file, so the app can
/// map a compiled list straight from disk instead of parsing text at launch:
///
///     "TCD1", wordCount, byteCount, maxScalarLength, alphabetBytes   (UInt32 each, little-endian)
///     alphabet: its letters as UTF-8 separated by "\n", padded to 4 bytes
///     offsets: Int32 × (wordCount + 1)   word i is bytes[offsets[i]..<offsets[i + 1]]
///     counts:  Int32 × wordCount
///     ranks:   Int32 × wordCount         1 = most frequent
///     bytes:   the words as lowercase NFC UTF-8, sorted bytewise
///
/// Ranks are comparable across languages, unlike raw counts: the Thai corpus is far smaller
/// than English. A [String: Entry] table took about 4x the memory, mostly for the separate
/// heap allocation behind every non-ASCII String.
public final class FrequencyDictionary: @unchecked Sendable {
    private let storage: Storage
    private let wordCount: Int
    private let offsets: UnsafePointer<Int32>
    private let counts: UnsafePointer<Int32>
    private let ranks: UnsafePointer<Int32>
    private let bytes: UnsafeRawPointer
    /// Longest entry measured in Unicode scalars, bounds the segmentation search.
    public let maxScalarLength: Int
    /// Letters seen in the list, most frequent first; candidate edits draw from these.
    public let alphabet: [Character]

    private static let magic: UInt32 = 0x3144_4354 // "TCD1"
    private static let headerSize = 20

    /// Owns the buffer: either a file mapped read-only or memory built from a word list.
    private final class Storage {
        let base: UnsafeRawPointer
        let size: Int
        private let release: () -> Void
        init(base: UnsafeRawPointer, size: Int, release: @escaping () -> Void) {
            self.base = base; self.size = size; self.release = release
        }
        deinit { release() }
    }

    /// - Parameter splitCompounds: for lists built from unsegmented text (Thai subtitles hold
    ///   entries like "คุณมาทำอะไรที่นี่"), also credit each entry's count to the words it splits into,
    ///   so short everyday words like ทำ rank as high as they are common.
    public convenience init(contents: String, splitCompounds: Bool = false) {
        let data = Self.compile(contents: contents, splitCompounds: splitCompounds)
        let memory = UnsafeMutableRawPointer.allocate(byteCount: max(data.count, 1), alignment: 8)
        data.copyBytes(to: memory.assumingMemoryBound(to: UInt8.self), count: data.count)
        try! self.init(storage: Storage(base: memory, size: data.count) { memory.deallocate() })
    }

    public convenience init(url: URL, splitCompounds: Bool = false) throws {
        self.init(contents: try String(contentsOf: url, encoding: .utf8), splitCompounds: splitCompounds)
    }

    /// Maps a file written by `compile`. Its pages are read from disk as lookups touch them
    /// and, being clean, don't count toward the app's memory footprint.
    public convenience init(compiledURL url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= Self.headerSize,
              let map = mmap(nil, Int(info.st_size), PROT_READ, MAP_PRIVATE, fd, 0), map != MAP_FAILED else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let size = Int(info.st_size)
        try self.init(storage: Storage(base: UnsafeRawPointer(map), size: size) { munmap(map, size) })
    }

    private init(storage: Storage) throws {
        let base = storage.base
        func header(_ i: Int) -> Int { Int(UInt32(littleEndian: base.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))) }
        guard storage.size >= Self.headerSize, header(0) == Self.magic else { throw CocoaError(.fileReadCorruptFile) }
        let n = header(1), byteCount = header(2), alphabetBytes = header(4)
        let alphabetStart = Self.headerSize
        let offsetsStart = alphabetStart + Self.padded(alphabetBytes)
        let countsStart = offsetsStart + (n + 1) * 4
        let ranksStart = countsStart + n * 4
        let bytesStart = ranksStart + n * 4
        guard bytesStart + byteCount == storage.size else { throw CocoaError(.fileReadCorruptFile) }
        self.storage = storage
        wordCount = n
        offsets = (base + offsetsStart).assumingMemoryBound(to: Int32.self)
        counts = (base + countsStart).assumingMemoryBound(to: Int32.self)
        ranks = (base + ranksStart).assumingMemoryBound(to: Int32.self)
        bytes = base + bytesStart
        maxScalarLength = header(3)
        let letters = String(decoding: UnsafeRawBufferPointer(start: base + alphabetStart, count: alphabetBytes), as: UTF8.self)
        alphabet = letters.split(separator: "\n").compactMap(\.first)
    }

    private static func padded(_ n: Int) -> Int { (n + 3) & ~3 }

    /// Parses a word list into the flat layout described above, ready to write to a `.tcdict` file.
    public static func compile(contents: String, splitCompounds: Bool = false) -> Data {
        var counts: [String: Int] = [:]
        var maxLen = 0
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let n = Int(parts[parts.count - 1]) else { continue }
            let word = normalized(parts[0..<(parts.count - 1)].joined(separator: " "))
            // Keep the highest count when case-folding merges two entries.
            if n > counts[word, default: 0] { counts[word] = n }
            maxLen = max(maxLen, word.unicodeScalars.count)
        }
        if splitCompounds { counts = creditingParts(of: counts, maxLength: min(maxLen, 24)) }
        var letterCounts: [Character: Int] = [:]
        for (word, n) in counts { for ch in word where ch.isLetter { letterCounts[ch, default: 0] += n } }
        // Drop stray letters from other scripts (names, loanwords) that would only add noise.
        let total = letterCounts.values.reduce(0, +)
        let alphabet = letterCounts.filter { Double($0.value) / Double(max(1, total)) > 0.0005 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : String($0.key) < String($1.key) }.map(\.key)
        // Ties broken by spelling so ranks, and every score, are the same on each run.
        let byCount = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var words = byCount.enumerated().map { (utf8: Array($0.element.key.utf8), count: $0.element.value, rank: $0.offset + 1) }
        words.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }

        var out = Data()
        func append(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func append(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        let letters = Array(alphabet.map(String.init).joined(separator: "\n").utf8)
        let byteCount = words.reduce(0) { $0 + $1.utf8.count }
        out.reserveCapacity(headerSize + padded(letters.count) + (words.count * 3 + 1) * 4 + byteCount)
        for v in [magic, UInt32(words.count), UInt32(byteCount), UInt32(min(maxLen, 24)), UInt32(letters.count)] { append(v) }
        out.append(contentsOf: letters)
        out.append(contentsOf: [UInt8](repeating: 0, count: padded(letters.count) - letters.count))
        var offset: Int32 = 0
        append(offset)
        for word in words { offset += Int32(word.utf8.count); append(offset) }
        for word in words { append(Int32(clamping: word.count)) }
        for word in words { append(Int32(word.rank)) }
        for word in words { out.append(contentsOf: word.utf8) }
        return out
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

    public var isEmpty: Bool { wordCount == 0 }

    public func count(of word: String) -> Int { index(of: word).map { Int(Int32(littleEndian: counts[$0])) } ?? 0 }

    /// 0...1: 1 for the top word, falling with log rank to 0 at the end of the list; 0 if absent.
    public func commonness(of word: String) -> Double {
        guard let i = index(of: word), wordCount > 1 else { return 0 }
        return 1 - log(Double(Int32(littleEndian: ranks[i]))) / log(Double(wordCount))
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

    /// Whether some entry starts with `prefix`: a word still being typed may become it.
    public func hasPrefix(_ prefix: String) -> Bool {
        var key = Self.normalized(prefix)
        return key.withUTF8 { key in
            // Entries are sorted bytewise, so those starting with the key follow its insertion point.
            var low = 0, high = wordCount
            while low < high {
                let mid = (low + high) / 2
                let start = Int(Int32(littleEndian: offsets[mid])), length = Int(Int32(littleEndian: offsets[mid + 1])) - start
                let shared = min(length, key.count)
                var order = shared == 0 ? 0 : memcmp(bytes + start, key.baseAddress!, shared)
                if order == 0 && length < key.count { order = -1 }
                if order < 0 { low = mid + 1 } else { high = mid }
            }
            guard low < wordCount else { return false }
            let start = Int(Int32(littleEndian: offsets[low])), length = Int(Int32(littleEndian: offsets[low + 1])) - start
            return length >= key.count && (key.isEmpty || memcmp(bytes + start, key.baseAddress!, key.count) == 0)
        }
    }

    /// Binary search over the packed words.
    private func index(of key: UnsafeRawBufferPointer) -> Int? {
        var low = 0, high = wordCount
        while low < high {
            let mid = (low + high) / 2
            let start = Int(Int32(littleEndian: offsets[mid])), length = Int(Int32(littleEndian: offsets[mid + 1])) - start
            let shared = min(length, key.count)
            var order = shared == 0 ? 0 : memcmp(bytes + start, key.baseAddress!, shared)
            if order == 0 { order = length < key.count ? -1 : (length > key.count ? 1 : 0) }
            if order == 0 { return mid }
            if order < 0 { low = mid + 1 } else { high = mid }
        }
        return nil
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
    ///
    /// Subtitles quote English ("out", "but", "got"), and their Cyrillic copies (оут, бут, гот)
    /// would make English typed on the Serbian layout read as Serbian. With `english` (the English
    /// list's contents), a word is skipped when its English rank is over `englishBias` times better
    /// than its Serbian one: "we" is 15th in English and 6461st here. Words common in both (то, но)
    /// stay. 30 instead of 10 keeps но ("but", 646th; "no" is 27th in English).
    public static func addingCyrillic(to contents: String, english: String? = nil, englishBias: Int = 30) -> String {
        let englishRanks = english.map(ranks) ?? [:]
        var out = ""
        out.reserveCapacity(contents.utf8.count * 2)
        var rank = 0
        for line in contents.split(whereSeparator: \.isNewline) {
            out += line + "\n"
            rank += 1
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            let latin = parts[0].lowercased()
            if let en = englishRanks[latin], en * englishBias < rank { continue }
            if let cyr = cyrillic(latin) { out += "\(cyr) \(parts[1])\n" }
        }
        return out
    }

    /// Line number of each word's first appearance, 1 = most frequent.
    private static func ranks(_ contents: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for (i, line) in contents.split(whereSeparator: \.isNewline).enumerated() {
            guard let word = line.split(separator: " ").first else { continue }
            let key = word.lowercased()
            if out[key] == nil { out[key] = i + 1 }
        }
        return out
    }
}
