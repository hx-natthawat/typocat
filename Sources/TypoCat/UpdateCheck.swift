import AppKit

/// "Check for Updates…": asks GitHub for the latest release, only when the user picks it.
/// TypoCat makes no other network requests.
enum UpdateCheck {
    static let releases = URL(string: "https://github.com/hx-natthawat/typocat/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/hx-natthawat/typocat/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func run() {
        var request = URLRequest(url: api, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            let tag = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["tag_name"] as? String
            DispatchQueue.main.async { show(latest: tag.map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }, failed: error != nil) }
        }.resume()
    }

    /// Compares dotted versions numerically: 0.10.0 is newer than 0.9.1.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
            return (i < x.count ? x[i] : 0) > (i < y.count ? y[i] : 0)
        }
        return false
    }

    private static func show(latest: String?, failed: Bool) {
        let alert = NSAlert()
        let newer = latest.map { isNewer($0, than: currentVersion) } ?? false
        if let latest, newer {
            alert.messageText = String(format: L("TypoCat %@ is available"), latest)
            alert.informativeText = String(format: L("You have %@. Download the new TypoCat.dmg and drag it into Applications. Afterwards, turn TypoCat off and on again in Accessibility settings if it stops fixing words."), currentVersion)
            alert.addButton(withTitle: L("Download"))
            alert.addButton(withTitle: L("Later"))
        } else if latest != nil {
            alert.messageText = L("TypoCat is up to date")
            alert.informativeText = String(format: L("You have the latest version, %@."), currentVersion)
        } else {
            alert.messageText = L("Couldn't check for updates")
            alert.informativeText = failed ? L("Check your internet connection and try again.") : L("No release was found on GitHub.")
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: L("Open Releases Page"))
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if (newer && response == .alertFirstButtonReturn) || (latest == nil && response == .alertSecondButtonReturn) {
            NSWorkspace.shared.open(releases)
        }
    }
}
