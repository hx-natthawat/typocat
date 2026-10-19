import Foundation

extension Detector {
    /// Converts selected text typed on the wrong layout: a sentence or paragraph at once.
    /// The user asked for it, so some conversion is returned whenever another layout reads
    /// better word for word. Spaces and line breaks are kept; words another layout can't
    /// type stay as they are.
    ///
    /// Tries every pair of layouts and keeps the one that improves the words most,
    /// preferring text typed on `current` when that ties.
    public func convertText(_ text: String, current: Language?, layouts: [Language: LayoutMap]) -> Correction? {
        let tokens = Self.splitKeepingWhitespace(text)
        let words = tokens.filter { !$0.isWhitespace }
        guard !words.isEmpty else { return nil }
        var best: (correction: Correction, gain: Double)?
        // Sorted so a tie goes the same way every time.
        let order = layouts.keys.sorted { ($0 == current ? 0 : 1, $0.rawValue) < ($1 == current ? 0 : 1, $1.rawValue) }
        for from in order {
            let source = layouts[from]!, inverse = source.inverse()
            let keys = words.map { source.strokes(typing: $0.text, inverse: inverse) }
            // Typed on `from`: at least half the words must be typeable there.
            guard keys.filter({ $0 != nil }).count * 2 >= words.count else { continue }
            let before = zip(words, keys).reduce(0.0) { $0 + ($1.1 == nil ? 0 : score($1.0.text, as: from)) }
            for to in order where to != from {
                let target = layouts[to]!
                var out = "", after = 0.0, changed = false, i = 0
                for token in tokens {
                    if token.isWhitespace { out += token.text; continue }
                    defer { i += 1 }
                    guard let k = keys[i], let alt = target.render(k) else { out += token.text; continue }
                    out += alt
                    changed = changed || alt != token.text
                    after += score(alt, as: to)
                }
                guard changed else { continue }
                let gain = after - before
                if best == nil || gain > best!.gain + 1e-9 {
                    best = (Correction(original: text, replacement: out, from: from, to: to), gain)
                }
            }
        }
        // Text that reads worse converted (English selected by mistake) stays; gibberish both ways
        // still converts, as the shortcut does for one word.
        guard let best, best.gain >= 0 else { return nil }
        return best.correction
    }

    struct Token { let text: String; let isWhitespace: Bool }

    static func splitKeepingWhitespace(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = "", inSpace = false
        for c in text {
            let space = c.isWhitespace
            if !current.isEmpty && space != inSpace {
                tokens.append(Token(text: current, isWhitespace: inSpace))
                current = ""
            }
            current.append(c)
            inSpace = space
        }
        if !current.isEmpty { tokens.append(Token(text: current, isWhitespace: inSpace)) }
        return tokens
    }
}
