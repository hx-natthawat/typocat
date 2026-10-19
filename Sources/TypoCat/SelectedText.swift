import AppKit

/// The selected text in the front app, for converting a whole sentence or paragraph.
/// Read through Accessibility when the app exposes it, else by copying; the clipboard is put
/// back afterwards and our copy is marked so clipboard managers skip it.
enum SelectedText {
    /// Longer selections are more likely a mistake than a sentence typed on the wrong layout.
    static let maximumLength = 4000

    /// Calls back on the main thread with the selection, or nil when nothing is selected.
    static func read(post: @escaping (CGEvent) -> Void, completion: @escaping (String?) -> Void) {
        if let text = accessibilitySelection() {
            completion(text.isEmpty || text.count > maximumLength ? nil : text)
            return
        }
        // Browsers and Electron apps rarely expose the selection: copy it instead.
        let pasteboard = NSPasteboard.general
        let saved = Snapshot(pasteboard)
        let before = pasteboard.changeCount
        postCommand(keyCode: 8, post: post) // ⌘C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let copied = pasteboard.changeCount != before ? pasteboard.string(forType: .string) : nil
            if pasteboard.changeCount != before { saved.restore(to: pasteboard) }
            guard let copied, !copied.isEmpty, copied.count <= maximumLength else { return completion(nil) }
            completion(copied)
        }
    }

    /// Types `text` over the selection. Line breaks would be Return presses (sending a chat
    /// message), so text with them is pasted, and the clipboard restored.
    static func replace(with text: String, type: (String) -> Void, post: @escaping (CGEvent) -> Void,
                        completion: @escaping () -> Void) {
        guard text.contains(where: \.isNewline) else {
            type(text)
            return completion()
        }
        let pasteboard = NSPasteboard.general
        let saved = Snapshot(pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // nspasteboard.org: clipboard managers leave transient and concealed items out of their history.
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([item])
        postCommand(keyCode: 9, post: post) // ⌘V
        // Give the app time to read the paste before the clipboard changes back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            saved.restore(to: pasteboard)
            completion()
        }
    }

    private static func accessibilitySelection() -> String? {
        if NSApp.isActive, let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            return (editor.string as NSString).substring(with: editor.selectedRange())
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?, value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        // An empty string here can also mean "can't tell": fall back to copying.
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func postCommand(keyCode: CGKeyCode, post: (CGEvent) -> Void) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            e.flags = .maskCommand
            post(e)
        }
    }

    /// Everything on the clipboard, every type of every item, so it can be put back exactly.
    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        init(_ pasteboard: NSPasteboard) {
            items = (pasteboard.pasteboardItems ?? []).map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
            }
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }
            pasteboard.writeObjects(items.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
    }
}
