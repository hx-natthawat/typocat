import AppKit
import TypoCatCore

/// The website open in the front browser window, read through the Accessibility API, so the
/// layout can follow the site (Thai on a Thai news site, English on GitHub) when the user
/// turns that on. Only the host name is used; it is kept with the per-app language counts.
enum BrowserSite {
    static let browsers: Set<String> = [
        "com.apple.safari", "com.apple.safaritechnologypreview", "com.google.chrome", "com.google.chrome.beta",
        "com.google.chrome.canary", "company.thebrowser.browser", "com.microsoft.edgemac", "com.brave.browser",
        "com.vivaldi.vivaldi", "com.operasoftware.opera", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.kagi.kagimacos", "app.zen-browser.zen", "org.chromium.chromium",
    ]

    static func isBrowser(_ bundleID: String?) -> Bool { bundleID.map { browsers.contains($0.lowercased()) } ?? false }

    /// The key site counts are kept under in AppLanguageProfile.
    static func profileKey(_ host: String) -> String { "site:\(host)" }

    static func host(of text: String) -> String? { WebsiteHost.from(text) }

    /// The host of the page in the front window of `app`, or nil when it can't be read.
    /// Safari exposes the page's URL on its web area; Chromium browsers show it in the address bar.
    static func currentHost(of app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        if let focused = child(element, kAXFocusedUIElementAttribute),
           let host = webAreaHost(above: focused) {
            return host
        }
        guard let window = child(element, kAXFocusedWindowAttribute) else { return nil }
        return addressBarHost(in: window)
    }

    /// Walks up from the focused element to the web area holding it.
    private static func webAreaHost(above start: AXUIElement) -> String? {
        var element = start
        for _ in 0..<40 {
            if (attribute(element, kAXRoleAttribute) as String?) == "AXWebArea" {
                if let url: URL = attribute(element, kAXURLAttribute) { return host(of: url.absoluteString) }
                if let text: String = attribute(element, kAXURLAttribute) { return host(of: text) }
                return nil
            }
            guard let parent = child(element, kAXParentAttribute) else { return nil }
            element = parent
        }
        return nil
    }

    /// Searches the window's toolbar area for a text field holding a URL, breadth first and
    /// bounded, so a page with a huge accessibility tree can't stall the lookup.
    private static func addressBarHost(in window: AXUIElement) -> String? {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 300 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role: String? = attribute(element, kAXRoleAttribute)
            // Page content can hold text fields too; the address bar is never inside it.
            if role == "AXWebArea" { continue }
            if role == "AXTextField" || role == "AXComboBox", let value: String = attribute(element, kAXValueAttribute),
               let host = host(of: value) {
                return host
            }
            guard depth < 12, let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { continue }
            queue += children.map { ($0, depth + 1) }
        }
        return nil
    }

    /// An element-valued attribute. `as? AXUIElement` can't check the type: CF casts always succeed.
    private static func child(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
