import AppKit
import Carbon
import TypoCatCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let inputSources = InputSources()
    private let store = UserStore()
    private var interceptor: Interceptor!
    private var statusItem: NSStatusItem!
    private var lastCorrectionItem = NSMenuItem(title: "No corrections yet", action: nil, keyEquivalent: "")
    private var permissionItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private var enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private var excludeItem = NSMenuItem(title: "", action: #selector(toggleExcludeFrontApp), keyEquivalent: "")
    private var matchLayoutItem = NSMenuItem(title: "Match layout to each app", action: #selector(toggleMatchLayout),
                                             keyEquivalent: "")
    private var typoItem = NSMenuItem(title: "Fix typos (beta)", action: #selector(toggleFixTypos), keyEquivalent: "")
    private var loginItem = NSMenuItem(title: "Open at login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    /// The last app that wasn't us; opening our menu doesn't change it.
    private var frontApp: NSRunningApplication?
    private var permissionTimer: Timer?
    /// Languages of the enabled layouts the current detector was built for.
    private var loadedLanguages: Set<Language> = []
    private let setup = SetupModel()
    private lazy var setupWindow = SetupWindowController(model: setup)

    func applicationDidFinishLaunching(_ notification: Notification) {
        inputSources.reload()
        // Word lists load in the background (Thai alone takes ~1s); until then nothing is fixed.
        interceptor = Interceptor(detector: Detector(dictionaries: [:]),
                                  inputSources: inputSources, store: store)
        interceptor.onCorrection = { [weak self] c in
            self?.lastCorrectionItem.title = "Last: \(c.original) → \(c.replacement)"
            self?.setup.lastFix = "\(c.original) → \(c.replacement)"
        }
        buildMenu()
        configureSetup()
        reloadLayouts()
        observeSystem()
        setFrontApp(NSWorkspace.shared.frontmostApplication)
        startWhenTrusted()
        if !UserDefaults.standard.bool(forKey: "setupDone") || !setup.trusted { setupWindow.show() }
    }

    // MARK: - Setup window

    private func configureSetup() {
        setup.openAtLogin = SMAppService.mainApp.status == .enabled
        setup.fixTypos = store.fixTypos
        setup.matchLayout = store.matchLayoutPerApp
        setup.setOpenAtLogin = { [weak self] on in
            if (SMAppService.mainApp.status == .enabled) != on { self?.toggleOpenAtLogin() }
        }
        setup.setFixTypos = { [weak self] on in
            if self?.store.fixTypos != on { self?.toggleFixTypos() }
        }
        setup.setMatchLayout = { [weak self] on in
            if self?.store.matchLayoutPerApp != on { self?.toggleMatchLayout() }
        }
        setup.done = { [weak self] in
            if self?.setup.trusted == true { UserDefaults.standard.set(true, forKey: "setupDone") }
            self?.setupWindow.close()
        }
    }

    @objc private func showSetup() { setupWindow.show() }

    /// The enabled layouts, and "hello" as it comes out on one that isn't English.
    private func refreshSetupLayouts() {
        let layouts = inputSources.layouts
        setup.layouts = layouts.keys.sorted { ($0 == .english ? 0 : 1, $0.rawValue) < ($1 == .english ? 0 : 1, $1.rawValue) }.map {
            SetupModel.Layout(language: $0, name: inputSources.names[$0] ?? $0.shortName,
                              hasWordList: Dictionaries.url(for: $0) != nil)
        }
        let others = setup.layouts.filter { $0.language != .english && $0.hasWordList }
        let other = others.first { $0.language == inputSources.currentLanguage() } ?? others.first
        guard let other, let english = layouts[.english], let target = layouts[other.language] else {
            setup.example = nil
            return
        }
        let keys = english.inverse()
        let word = "hello"
        let strokes = word.compactMap { keys[String($0)] }.flatMap { $0 }
        guard strokes.count == word.count, let typed = target.render(strokes) else { setup.example = nil; return }
        setup.example = (word, typed, other.name)
    }

    // MARK: - Permissions

    private func startWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), interceptor.start() {
            permissionItem.isHidden = true
            setup.trusted = true
            return
        }
        permissionItem.title = "Grant Accessibility access…"
        permissionItem.isHidden = false
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.interceptor.start() else { return }
            timer.invalidate()
            self.permissionItem.isHidden = true
            self.setup.trusted = true
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.image
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        enabledItem.target = self
        enabledItem.state = .on
        permissionItem.target = self
        lastCorrectionItem.isEnabled = false
        excludeItem.target = self
        matchLayoutItem.target = self
        matchLayoutItem.state = store.matchLayoutPerApp ? .on : .off
        loginItem.target = self
        typoItem.target = self
        typoItem.state = store.fixTypos ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(enabledItem)
        menu.addItem(excludeItem)
        menu.addItem(matchLayoutItem)
        menu.addItem(typoItem)
        menu.addItem(loginItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(lastCorrectionItem)
        let hint = NSMenuItem(title: "⌃⌥Space converts the current word", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let setupItem = NSMenuItem(title: "Setup…", action: #selector(showSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        let about = NSMenuItem(title: "About TypoCat", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit TypoCat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshTitle()
    }

    private func refreshTitle() {
        let lang = inputSources.currentLanguage()?.shortName ?? "—"
        let active = interceptor.enabled && !store.isExcluded(frontApp?.bundleIdentifier)
        statusItem.button?.title = active ? lang : "\(lang)·off"
        statusItem.button?.appearsDisabled = !active
        let name = frontApp?.localizedName ?? "this app"
        excludeItem.title = "Disable in \(name)"
        excludeItem.state = store.isExcluded(frontApp?.bundleIdentifier) ? .on : .off
        excludeItem.isHidden = frontApp?.bundleIdentifier == nil
    }

    private func setFrontApp(_ app: NSRunningApplication?) {
        guard let app else { return }
        // Our setup window: typing there counts for us, but the menu keeps naming the last other app.
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            interceptor.frontBundleID = app.bundleIdentifier
            return
        }
        frontApp = app
        interceptor.frontBundleID = app.bundleIdentifier
        ElectronAccessibility.enableIfElectron(app)
        matchLayout(to: app)
        refreshTitle()
    }

    /// Switches to the language the user usually types in `app`.
    private func matchLayout(to app: NSRunningApplication) {
        guard store.matchLayoutPerApp, interceptor.enabled, let id = app.bundleIdentifier, !store.isExcluded(id),
              let language = store.appLanguages.dominant(in: id), language != inputSources.currentLanguage() else { return }
        inputSources.select(language)
        NSLog("TypoCat: \(app.localizedName ?? id) matched layout to its dominant language (\(language.rawValue))")
    }

    @objc private func toggleMatchLayout() {
        store.matchLayoutPerApp.toggle()
        matchLayoutItem.state = store.matchLayoutPerApp ? .on : .off
        setup.matchLayout = store.matchLayoutPerApp
    }

    /// Credits include the word lists' CC BY-SA attribution, which redistribution requires.
    @objc private func showAbout() {
        let text = [
            "Fixes words typed on the wrong keyboard layout.",
            "Open source under the MIT license: github.com/hx-natthawat/typocat",
            "",
            "Word lists: FrequencyWords by Hermit Dave (github.com/hermitdave/FrequencyWords),",
            "licensed CC BY-SA 4.0, built from OpenSubtitles.",
        ].joined(separator: "\n")
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
        ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "TypoCat"])
    }

    @objc private func toggleFixTypos() {
        store.fixTypos.toggle()
        typoItem.state = store.fixTypos ? .on : .off
        setup.fixTypos = store.fixTypos
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("TypoCat: open at login failed: \(error.localizedDescription)")
        }
        loginItem.state = service.status == .enabled ? .on : .off
        setup.openAtLogin = service.status == .enabled
    }

    @objc private func toggleExcludeFrontApp() {
        guard let id = frontApp?.bundleIdentifier else { return }
        store.setExcluded(id, !store.isExcluded(id))
        interceptor.reset()
        refreshTitle()
    }

    @objc private func toggleEnabled() {
        interceptor.enabled.toggle()
        interceptor.reset()
        enabledItem.state = interceptor.enabled ? .on : .off
        refreshTitle()
    }

    /// Picks up layouts the user enabled or removed, loading word lists off the main thread.
    private func reloadLayouts() {
        inputSources.reload()
        refreshSetupLayouts()
        let languages = Set(inputSources.layouts.keys)
        guard languages != loadedLanguages else { return }
        loadedLanguages = languages
        DispatchQueue.global(qos: .userInitiated).async {
            let detector = Dictionaries.makeDetector(for: languages)
            DispatchQueue.main.async { self.interceptor.detector = detector; self.interceptor.reset() }
        }
    }

    // MARK: - Context changes that end the current word

    private func observeSystem() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                object: nil, queue: .main) { [weak self] _ in
            self?.refreshTitle()
            self?.refreshSetupLayouts()
        }
        distributed.addObserver(forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                                object: nil, queue: .main) { [weak self] _ in
            self?.reloadLayouts()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.interceptor.reset()
            self?.setFrontApp(app)
        }
    }
}

enum Dictionaries {
    /// Looks in the app bundle first, then ./Data for `swift run` during development.
    static func url(for language: Language) -> URL? {
        let name = "\(language.rawValue)_50k"
        if let url = Bundle.main.url(forResource: name, withExtension: "txt") { return url }
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Data/\(name).txt")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    /// Loads word lists only for `languages` (the enabled layouts): each list costs a few MB.
    /// Loads one list at a time. Loading in parallel was 3x faster with 7 languages but left
    /// the app at 100 MB instead of 59 MB (`--bench`), and loading runs in the background anyway.
    static func makeDetector(for languages: some Sequence<Language>) -> Detector {
        var dicts: [Language: FrequencyDictionary] = [:]
        for language in Set(languages) {
            autoreleasepool {
                guard let url = url(for: language), var contents = try? String(contentsOf: url, encoding: .utf8) else {
                    NSLog("TypoCat: no word list for \(language.rawValue); its layout can't be detected")
                    return
                }
                if language.rawValue == "sr" { contents = SerbianScript.addingCyrillic(to: contents) }
                dicts[language] = FrequencyDictionary(contents: contents, splitCompounds: language.writesWithoutSpaces)
            }
        }
        // Hand the freed parsing buffers back to the system, or they stay in the footprint.
        malloc_zone_pressure_relief(nil, 0)
        return Detector(dictionaries: dicts)
    }
}
