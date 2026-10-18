import AppKit

/// Reads the text just before the caret in the focused field through the
/// Accessibility API, so a rewrite only happens when the field really holds
/// the word we are about to replace.
enum FocusedText {
    enum Check {
        /// The field confirms the word sits right before the caret.
        case matches
        /// The field says something else is there (autocomplete, cursor moved…): leave it alone.
        case mismatch
        /// The app doesn't expose its text (many browsers, Electron, games): no evidence either way.
        case unreadable
    }

    private static let systemWide: AXUIElement = {
        let e = AXUIElementCreateSystemWide()
        // Never stall typing on a slow app.
        AXUIElementSetMessagingTimeout(e, 0.15)
        return e
    }()

    static func check(endsWith word: String) -> Check {
        guard let prefix = textBeforeCaret() else { return .unreadable }
        return endsWith(prefix, word) ? .matches : .mismatch
    }

    /// Compares Unicode scalars, not Characters: gibberish such as "้ำสสน" typed after a space
    /// starts with a tone mark that joins the space into one Character, so String.hasSuffix fails.
    static func endsWith(_ text: String, _ word: String, ignoringLast trailing: Int = 0) -> Bool {
        let scalars = Array(text.unicodeScalars.dropLast(trailing))
        if scalars.count >= word.unicodeScalars.count && scalars.suffix(word.unicodeScalars.count).elementsEqual(word.unicodeScalars) {
            return true
        }
        // zsh shows a combining mark with no letter before it as its code: ้ำสสน reads "<0e49>ำสสน".
        let decoded = decodingShellEscapes(text)
        return decoded != text && endsWith(decoded, word, ignoringLast: trailing)
    }

    private static let shellEscape = try! NSRegularExpression(pattern: "<([0-9a-fA-F]{4,6})>")

    /// Turns zsh's "<0e49>" placeholders back into the characters they stand for.
    static func decodingShellEscapes(_ text: String) -> String {
        guard text.contains("<") else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in shellEscape.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let value = UInt32(ns.substring(with: match.range(at: 1)), radix: 16),
                  let scalar = Unicode.Scalar(value) else { continue }
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out.unicodeScalars.append(scalar)
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }

    /// Text from the start of the field up to the caret, or nil when the
    /// field is unreadable or has a non-empty selection.
    static func textBeforeCaret() -> String? {
        // Our own setup window: asking ourselves through AX from the main thread would stall.
        if NSApp.isActive {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                  editor.selectedRange().length == 0 else { return nil }
            return (editor.string as NSString).substring(to: editor.selectedRange().location)
        }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)

        var value: CFTypeRef?
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length == 0 else { return nil }
        // We only ask right after a word was typed, so a caret at the very start is wrong:
        // Ghostty always reports 0. Treat it as unreadable rather than as a mismatch.
        guard range.location > 0 else { return nil }

        // AX ranges count UTF-16 units.
        let utf16 = text.utf16
        guard range.location >= 0, range.location <= utf16.count,
              let end = utf16.index(utf16.startIndex, offsetBy: range.location, limitedBy: utf16.endIndex),
              let caret = end.samePosition(in: text) else { return nil }
        return String(text[..<caret])
    }
}

/// Electron apps (VS Code, Slack, Discord…) build their accessibility tree only for
/// screen readers. Setting AXManualAccessibility asks them to build it anyway, so the
/// field check above can read their text fields. Chromium browsers have a similar
/// switch (AXEnhancedUserInterface), but it breaks window animations and window
/// managers, so it is left alone.
enum ElectronAccessibility {
    private static var enabled: Set<pid_t> = []

    static func enableIfElectron(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard !enabled.contains(pid), let url = app.bundleURL,
              FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        else { return }
        enabled.insert(pid)
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.2)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
