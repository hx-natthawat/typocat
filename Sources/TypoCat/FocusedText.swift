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
        return prefix.hasSuffix(word) ? .matches : .mismatch
    }

    /// Text from the start of the field up to the caret, or nil when the
    /// field is unreadable or has a non-empty selection.
    static func textBeforeCaret() -> String? {
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
