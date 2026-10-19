import AppKit
import Carbon
import TypoCatCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let inputSources = InputSources()
    private let store = UserStore()
    private var interceptor: Interceptor!
    private var statusItem: NSStatusItem!
    private var lastCorrectionItem = NSMenuItem(title: L("No corrections yet"), action: nil, keyEquivalent: "")
    private var permissionItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private var enabledItem = NSMenuItem(title: L("Enabled"), action: #selector(toggleEnabled), keyEquivalent: "")
    private var excludeItem = NSMenuItem(title: "", action: #selector(toggleExcludeFrontApp), keyEquivalent: "")
    private var matchLayoutItem = NSMenuItem(title: L("Match layout to each app"), action: #selector(toggleMatchLayout),
                                             keyEquivalent: "")
    private var matchSiteItem = NSMenuItem(title: L("Match layout to each website"), action: #selector(toggleMatchSite),
                                           keyEquivalent: "")
    private var typoItem = NSMenuItem(title: L("Fix typos (beta)"), action: #selector(toggleFixTypos), keyEquivalent: "")
    private var loginItem = NSMenuItem(title: L("Open at login"), action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    private var learnItem = NSMenuItem(title: L("Learn words I convert by hand"), action: #selector(toggleLearnWords),
                                       keyEquivalent: "")
    private var forgetItem = NSMenuItem(title: "", action: #selector(forgetLearnedWords), keyEquivalent: "")
    private var showFixesItem = NSMenuItem(title: L("Show each fix"), action: #selector(toggleShowFixes), keyEquivalent: "")
    private var countItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var hintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var shortcutItems: [NSMenuItem] = []
    /// The last app that wasn't us; opening our menu doesn't change it.
    private var frontApp: NSRunningApplication?
    private var permissionTimer: Timer?
    private var siteTimer: Timer?
    private let siteQueue = DispatchQueue(label: "TypoCat.site")
    private var siteLookupRunning = false
    private var currentHost: String?
    /// Languages of the enabled layouts the current detector was built for.
    private var loadedLanguages: Set<Language> = []
    private let setup = SetupModel()
    private lazy var setupWindow = SetupWindowController(model: setup)
    private let exceptions = ExceptionsModel()
    private lazy var exceptionsWindow = ExceptionsWindowController(model: exceptions)

    func applicationDidFinishLaunching(_ notification: Notification) {
        inputSources.reload()
        // Word lists load in the background (Thai alone takes ~1s); until then nothing is fixed.
        interceptor = Interceptor(detector: Detector(dictionaries: [:]),
                                  inputSources: inputSources, store: store)
        interceptor.onCorrection = { [weak self] c in
            guard let self else { return }
            self.lastCorrectionItem.title = String(format: L("Last: %@ → %@"), c.original, c.replacement)
            self.setup.lastFix = "\(c.original) → \(c.replacement)"
            // Spelling fixes stay in their language; count words that changed layout.
            if c.from != c.to { self.store.countFix(into: c.to) }
            self.refreshCount()
            self.showFix(c)
        }
        interceptor.onUndo = { [weak self] c in
            if c.from != c.to { self?.store.countFix(into: c.to, by: -1) }
            self?.refreshCount()
            self?.refreshExceptions()
        }
        interceptor.onNothingToConvert = { NSSound.beep() }
        interceptor.onManualConversion = { [weak self] c in
            guard let self, self.store.learn(c.replacement, in: c.to) else { return }
            self.interceptor.detector.learnedWords = self.store.learnedWords
            self.refreshLearnItems()
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
        setup.learnWords = store.learnWords
        setup.matchSite = store.matchLayoutPerSite
        setup.setMatchSite = { [weak self] on in
            if self?.store.matchLayoutPerSite != on { self?.toggleMatchSite() }
        }
        setup.setLearnWords = { [weak self] on in
            if self?.store.learnWords != on { self?.toggleLearnWords() }
        }
        setup.setOpenAtLogin = { [weak self] on in
            if (SMAppService.mainApp.status == .enabled) != on { self?.toggleOpenAtLogin() }
        }
        setup.setFixTypos = { [weak self] on in
            if self?.store.fixTypos != on { self?.toggleFixTypos() }
        }
        setup.setMatchLayout = { [weak self] on in
            if self?.store.matchLayoutPerApp != on { self?.toggleMatchLayout() }
        }
        setup.shortcut = store.shortcut
        setup.setShortcut = { [weak self] in self?.setShortcut($0) }
        setup.done = { [weak self] in
            if self?.setup.trusted == true { UserDefaults.standard.set(true, forKey: "setupDone") }
            self?.setupWindow.close()
        }
    }

    @objc private func showSetup() { setupWindow.show() }

    @objc private func checkForUpdates() { UpdateCheck.run() }

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
        permissionItem.title = L("Grant Accessibility access…")
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
        matchSiteItem.target = self
        matchSiteItem.state = store.matchLayoutPerSite ? .on : .off
        loginItem.target = self
        typoItem.target = self
        typoItem.state = store.fixTypos ? .on : .off
        learnItem.target = self
        forgetItem.target = self
        refreshLearnItems()
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(enabledItem)
        menu.addItem(excludeItem)
        menu.addItem(matchLayoutItem)
        menu.addItem(matchSiteItem)
        menu.addItem(typoItem)
        menu.addItem(learnItem)
        menu.addItem(forgetItem)
        menu.addItem(loginItem)
        menu.addItem(permissionItem)
        showFixesItem.target = self
        showFixesItem.state = store.showFixes ? .on : .off
        menu.addItem(showFixesItem)
        let shortcutMenu = NSMenu()
        for shortcut in UserStore.Shortcut.allCases {
            let item = NSMenuItem(title: Self.title(of: shortcut), action: #selector(chooseShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shortcut.rawValue
            shortcutMenu.addItem(item)
            shortcutItems.append(item)
        }
        let shortcutItem = NSMenuItem(title: L("Convert shortcut"), action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)
        let exceptionsItem = NSMenuItem(title: L("Exceptions…"), action: #selector(showExceptions), keyEquivalent: "")
        exceptionsItem.target = self
        menu.addItem(exceptionsItem)
        menu.addItem(.separator())
        menu.addItem(lastCorrectionItem)
        hintItem.isEnabled = false
        menu.addItem(hintItem)
        countItem.isEnabled = false
        menu.addItem(countItem)
        refreshShortcut()
        refreshCount()
        menu.addItem(.separator())
        let setupItem = NSMenuItem(title: L("Setup…"), action: #selector(showSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        let updates = NSMenuItem(title: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        let about = NSMenuItem(title: L("About TypoCat"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: L("Quit TypoCat"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshTitle()
    }

    private func refreshTitle() {
        let lang = inputSources.currentLanguage()?.shortName ?? "—"
        let active = interceptor.enabled && !store.isExcluded(frontApp?.bundleIdentifier)
        statusItem.button?.title = active ? lang : "\(lang)·off"
        statusItem.button?.appearsDisabled = !active
        let name = frontApp?.localizedName ?? L("this app")
        excludeItem.title = String(format: L("Disable in %@"), name)
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
        watchSite()
    }

    /// Switches to the language the user usually types in `app`.
    private func matchLayout(to app: NSRunningApplication) {
        guard store.matchLayoutPerApp, interceptor.enabled, let id = app.bundleIdentifier, !store.isExcluded(id),
              let language = store.appLanguages.dominant(in: id), language != inputSources.currentLanguage() else { return }
        inputSources.select(language)
        NSLog("TypoCat: \(app.localizedName ?? id) matched layout to its dominant language (\(language.rawValue))")
    }

    // MARK: - Websites

    /// While a browser is in front and per-site matching is on, checks the site once a second.
    private func watchSite() {
        siteTimer?.invalidate()
        siteTimer = nil
        currentHost = nil
        interceptor.siteKey = nil
        guard store.matchLayoutPerSite, let app = frontApp, BrowserSite.isBrowser(app.bundleIdentifier) else { return }
        checkSite(app)
        siteTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkSite(app) }
    }

    /// Reads the host off the main thread: Accessibility calls can take up to their timeout.
    private func checkSite(_ app: NSRunningApplication) {
        guard !siteLookupRunning else { return }
        siteLookupRunning = true
        siteQueue.async {
            let host = BrowserSite.currentHost(of: app)
            DispatchQueue.main.async {
                self.siteLookupRunning = false
                guard self.frontApp == app, self.store.matchLayoutPerSite, host != self.currentHost else { return }
                self.currentHost = host
                self.interceptor.siteKey = host.map(BrowserSite.profileKey)
                self.matchLayout(toSite: host)
            }
        }
    }

    /// Switches to the language the user usually types on this site.
    private func matchLayout(toSite host: String?) {
        guard let host, interceptor.enabled, !store.isExcluded(frontApp?.bundleIdentifier),
              let language = store.appLanguages.dominant(in: BrowserSite.profileKey(host)),
              inputSources.layouts[language] != nil, language != inputSources.currentLanguage() else { return }
        interceptor.reset()
        inputSources.select(language)
        NSLog("TypoCat: matched layout to this website's dominant language (\(language.rawValue))")
    }

    @objc private func toggleMatchSite() {
        store.matchLayoutPerSite.toggle()
        matchSiteItem.state = store.matchLayoutPerSite ? .on : .off
        setup.matchSite = store.matchLayoutPerSite
        watchSite()
    }

    @objc private func toggleMatchLayout() {
        store.matchLayoutPerApp.toggle()
        matchLayoutItem.state = store.matchLayoutPerApp ? .on : .off
        setup.matchLayout = store.matchLayoutPerApp
    }

    /// Credits include the word lists' CC BY-SA attribution, which redistribution requires.
    @objc private func showAbout() {
        let text = [
            L("Fixes words typed on the wrong keyboard layout."),
            L("Open source under the MIT license: github.com/hx-natthawat/typocat"),
            "",
            L("Word lists: FrequencyWords by Hermit Dave (github.com/hermitdave/FrequencyWords), licensed CC BY-SA 4.0, built from OpenSubtitles."),
        ].joined(separator: "\n")
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
        ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "TypoCat"])
    }

    @objc private func toggleLearnWords() {
        store.learnWords.toggle()
        interceptor.detector.learnedWords = store.learnedWords
        setup.learnWords = store.learnWords
        setup.matchSite = store.matchLayoutPerSite
        setup.setMatchSite = { [weak self] on in
            if self?.store.matchLayoutPerSite != on { self?.toggleMatchSite() }
        }
        refreshLearnItems()
    }

    @objc private func forgetLearnedWords() {
        store.forgetLearnedWords()
        interceptor.detector.learnedWords = [:]
        refreshLearnItems()
    }

    private func refreshLearnItems() {
        learnItem.state = store.learnWords ? .on : .off
        let n = store.learnedWordCount
        forgetItem.title = n == 1 ? L("Forget 1 learned word") : String(format: L("Forget %d learned words"), n)
        forgetItem.isHidden = !store.learnWords || n == 0
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
        refreshExceptions()
    }

    // MARK: - Exceptions

    @objc private func showExceptions() {
        refreshExceptions()
        exceptions.addWord = { [weak self] word in
            self?.store.ignore(Detector.learnable(word))
            self?.refreshExceptions()
        }
        exceptions.removeWord = { [weak self] word in
            self?.store.unignore(word)
            self?.refreshExceptions()
        }
        exceptions.removeApp = { [weak self] id in
            self?.store.setExcluded(id, false)
            self?.refreshTitle()
            self?.refreshExceptions()
        }
        exceptionsWindow.show()
    }

    private func refreshExceptions() {
        exceptions.words = store.ignoredWords.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        exceptions.apps = store.excludedApps.map { id in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
            return ExceptionsModel.App(id: id, name: name, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) })
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Shortcut and feedback

    private static func title(of shortcut: UserStore.Shortcut) -> String {
        switch shortcut {
        case .controlOptionSpace: return "⌃⌥Space"
        case .shiftTwice: return L("Press Shift twice")
        case .both: return L("Both")
        }
    }

    @objc private func chooseShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let shortcut = UserStore.Shortcut(rawValue: raw) else { return }
        setShortcut(shortcut)
    }

    private func setShortcut(_ shortcut: UserStore.Shortcut) {
        store.shortcut = shortcut
        setup.shortcut = shortcut
        refreshShortcut()
    }

    private func refreshShortcut() {
        for item in shortcutItems { item.state = item.representedObject as? String == store.shortcut.rawValue ? .on : .off }
        hintItem.title = String(format: L("%@ converts the current word or the selection"), Self.title(of: store.shortcut))
    }

    private func refreshCount() {
        let counts = store.fixCounts.filter { $0.value > 0 }
        let total = counts.values.reduce(0, +)
        countItem.isHidden = total == 0
        let parts = counts.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key.shortName) \($0.value)" }
        let list = parts.joined(separator: " · ")
        countItem.title = total == 1 ? String(format: L("1 word fixed: %@"), list) : String(format: L("%d words fixed: %@"), total, list)
    }

    @objc private func toggleShowFixes() {
        store.showFixes.toggle()
        showFixesItem.state = store.showFixes ? .on : .off
    }

    /// A short flash of the menu bar icon, and with VoiceOver on, the fix read aloud.
    private func showFix(_ c: Correction) {
        if store.showFixes, let button = statusItem.button {
            button.highlight(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { button.highlight(false) }
        }
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: String(format: L("Fixed: %@"), c.replacement),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
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
            DispatchQueue.main.async {
                detector.learnedWords = self.store.learnedWords
                self.interceptor.detector = detector
                self.interceptor.reset()
            }
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

/// A user-facing string in the user's language: Resources/<language>.lproj/Localizable.strings.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum Dictionaries {
    /// Looks in the app bundle first (compiled by build-app.sh), then ./Data for `swift run` during development.
    static func url(for language: Language) -> URL? {
        let name = "\(language.base.rawValue)_50k"
        if let url = Bundle.main.url(forResource: name, withExtension: "tcdict") { return url }
        if let url = Bundle.main.url(forResource: name, withExtension: "txt") { return url }
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Data/\(name).txt")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    /// A word list as text, with the per-language preparation the detector expects.
    static func compile(_ language: Language, from url: URL) throws -> Data {
        var contents = try String(contentsOf: url, encoding: .utf8)
        if language.rawValue == "sr" {
            let english = Dictionaries.url(for: .english).flatMap { $0.pathExtension == "txt" ? try? String(contentsOf: $0, encoding: .utf8) : nil }
            contents = SerbianScript.addingCyrillic(to: contents, english: english)
        }
        if let extra = extraWords(for: language) {
            // Ranked like the list's 5000th word: everyday, but below the most common ones.
            let lines = contents.split(whereSeparator: \.isNewline)
            let count = lines.count >= 5000 ? lines[4999].split(separator: " ").last.flatMap { Int($0) } ?? 1 : 1
            contents += "\n" + extra.map { "\($0) \(count)" }.joined(separator: "\n")
        }
        return FrequencyDictionary.compile(contents: contents, splitCompounds: language.writesWithoutSpaces)
    }

    /// Everyday words the subtitle lists lack (ลาย, ภาษี, скриншот): Data/extra/<language>.txt,
    /// one per line. Part of this repository, unlike the downloaded lists.
    static func extraWords(for language: Language) -> [String]? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Data/extra/\(language.rawValue).txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func load(_ language: Language) -> FrequencyDictionary? {
        guard let url = url(for: language) else {
            NSLog("TypoCat: no word list for \(language.rawValue); its layout can't be detected")
            return nil
        }
        if url.pathExtension == "tcdict" { return try? FrequencyDictionary(compiledURL: url) }
        return autoreleasepool {
            guard let data = try? compile(language, from: url) else { return nil }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: tmp) }
            // Map it like a bundled list, so development builds measure the same footprint.
            guard (try? data.write(to: tmp)) != nil else { return nil }
            return try? FrequencyDictionary(compiledURL: tmp)
        }
    }

    /// Loads word lists only for `languages` (the enabled layouts). Compiled lists are mapped
    /// from disk, so this takes milliseconds; text lists (`swift run`) are parsed first.
    static func makeDetector(for languages: some Sequence<Language>) -> Detector {
        var dicts: [Language: FrequencyDictionary] = [:]
        for language in Set(languages.map(\.base)) { dicts[language] = load(language) }
        // Hand the freed parsing buffers back to the system, or they stay in the footprint.
        malloc_zone_pressure_relief(nil, 0)
        return Detector(dictionaries: dicts)
    }
}
