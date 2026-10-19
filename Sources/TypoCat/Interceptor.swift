import AppKit
import Carbon
import TypoCatCore

/// Watches keystrokes through a CGEventTap, keeps the current word as physical
/// keystrokes, and rewrites it when the Detector says the layout was wrong.
final class Interceptor {
    /// Marks events we post so the tap lets them through untouched.
    static let syntheticTag: Int64 = 0x5459_5043 // "TYPC"
    /// Marks the last event of a rewrite; seeing it come back through the tap means the rewrite is done.
    static let fenceTag: Int64 = syntheticTag + 1

    var enabled = true
    var onCorrection: ((Correction) -> Void)?
    /// A fix the user took back, with Backspace or ⌘Z.
    var onUndo: ((Correction) -> Void)?
    /// The shortcut found nothing to convert.
    var onNothingToConvert: (() -> Void)?
    /// A word converted by hand with ⌃⌥Space, for learning.
    var onManualConversion: ((Correction) -> Void)?
    /// Set from the app delegate when the front app changes.
    var frontBundleID: String? {
        didSet { category = AppCategory(bundleID: frontBundleID); reset() }
    }

    /// The website in front, as `BrowserSite.profileKey`, when per-site matching is on.
    var siteKey: String?

    /// Replaced when the enabled layouts change.
    var detector: Detector
    private let inputSources: InputSources
    private let store: UserStore
    private var category = AppCategory.general
    private var tap: CFMachPort?
    private let eventSource = CGEventSource(stateID: .privateState)

    private var strokes: [KeyStroke] = []
    /// Up from swallowing a word's delimiter until the rewrite's last event passes the tap.
    /// Keys typed meanwhile are held and replayed afterwards, so a fast typist's next
    /// letters can't land inside the word being erased.
    private var fenceUp = false
    private var fenceGeneration = 0
    private var heldEvents: [CGEvent] = []
    /// The rewrite switched layouts, so held keys are rebuilt to type on the new one.
    private var switchedDuringFence = false
    /// `delimiter` is nil for a fix made before Space (Thai typed in one run).
    private var lastCorrection: (correction: Correction, delimiter: CGEvent?, word: String)?
    /// Words just typed and left alone, each followed by one space, oldest first.
    /// A later fix may reread them (short words like `z,` for ผม are ambiguous alone).
    private var recentWords: [(strokes: [KeyStroke], typed: String, language: Language)] = []
    /// When Shift was last tapped on its own, for the Shift-twice shortcut.
    private var lastShiftTap: TimeInterval?
    private var shiftDown: (at: TimeInterval, clean: Bool)?

    private enum Key {
        static let space: UInt16 = 49, returnKey: UInt16 = 36, tab: UInt16 = 48, enter: UInt16 = 76
        static let delete: UInt16 = 51, escape: UInt16 = 53, z: UInt16 = 6
        static let navigation: Set<UInt16> = [115, 116, 117, 119, 121, 123, 124, 125, 126]
    }

    init(detector: Detector, inputSources: InputSources, store: UserStore) {
        self.detector = detector
        self.inputSources = inputSources
        self.store = store
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<Interceptor>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reset() {
        strokes.removeAll()
        recentWords.removeAll()
        lastCorrection = nil
    }

    // MARK: - Event handling (runs on the main run loop; keep it fast)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        switch event.getIntegerValueField(.eventSourceUserData) {
        case Self.syntheticTag: return pass
        case Self.fenceTag:
            DispatchQueue.main.async { self.lowerFence() }
            return pass
        default: break
        }
        if fenceUp && (type == .keyDown || type == .keyUp), let copy = event.copy() {
            heldEvents.append(copy)
            return nil
        }
        if type == .keyUp { return pass }
        if type == .flagsChanged {
            // Modifiers alone don't end a word: Shift is pressed for capitals mid-word.
            if enabled, !IsSecureEventInputEnabled(), !store.isExcluded(frontBundleID), shiftTappedTwice(event) { convert() }
            return pass
        }
        shiftDown = nil
        lastShiftTap = nil
        guard type == .keyDown else { reset(); return pass }
        guard enabled, !IsSecureEventInputEnabled(), !store.isExcluded(frontBundleID) else { reset(); return pass }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // ⌃⌥Space: convert the current word, or the selection, whatever the detector thinks.
        if store.shortcut.usesControlOptionSpace, flags.contains(.maskControl) && flags.contains(.maskAlternate),
           keyCode == Key.space {
            convert()
            return nil
        }
        // ⌘Z right after a fix undoes the fix, not the app's last edit.
        if keyCode == Key.z, flags.contains(.maskCommand), !flags.contains(.maskShift),
           strokes.isEmpty, let last = lastCorrection {
            raiseFence()
            undo(last.correction, delimiter: last.delimiter, word: last.word)
            return nil
        }
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            reset()
            return pass
        }

        if keyCode == Key.delete {
            if strokes.isEmpty, let last = lastCorrection {
                raiseFence()
                undo(last.correction, delimiter: last.delimiter, word: last.word)
                return nil
            }
            // Deleting a space joins words; the earlier ones no longer match the field.
            if strokes.isEmpty { recentWords.removeAll() }
            lastCorrection = nil
            if !strokes.isEmpty { strokes.removeLast() }
            return pass
        }

        if [Key.space, Key.returnKey, Key.tab, Key.enter].contains(keyCode) {
            defer { strokes.removeAll() }
            guard let current = inputSources.currentLanguage(),
                  let typed = inputSources.layouts[current]?.render(strokes) else {
                lastCorrection = nil
                return pass
            }
            guard let wordFix = detector.decide(strokes: strokes, typed: typed, current: current,
                                                layouts: inputSources.layouts, ignoring: store.ignoredWords,
                                                category: category),
                  let delimiter = event.copy() else {
                lastCorrection = nil
                if let typoFix = typoCorrection(typed, language: current), let delimiter = event.copy() {
                    recentWords.removeAll()
                    raiseFence()
                    DispatchQueue.main.async { self.apply(typoFix, delimiter: delimiter, word: typed) }
                    return nil
                }
                if keyCode == Key.space && !strokes.isEmpty {
                    recentWords.append((strokes, typed, current))
                    if recentWords.count > 3 { recentWords.removeFirst() }
                } else {
                    recentWords.removeAll()
                }
                // Count only words that read as real text, not passwords or noise.
                if strokes.count >= detector.minimumStrokes, detector.score(typed, as: current) > detector.rejectThreshold {
                    record(current)
                }
                return pass
            }
            let correction = extendBackwards(wordFix)
            recentWords.removeAll()
            // Swallow the delimiter now; replay it after the rewrite so ordering holds.
            raiseFence()
            DispatchQueue.main.async { self.apply(correction, delimiter: delimiter, word: typed) }
            return nil
        }

        if keyCode == Key.escape || Key.navigation.contains(keyCode) {
            reset()
            return pass
        }

        let stroke = KeyStroke(keyCode: keyCode, shift: flags.contains(.maskShift))
        guard let current = inputSources.currentLanguage(),
              inputSources.layouts[current]?.produces(stroke) == true else {
            reset()
            return pass
        }
        lastCorrection = nil
        strokes.append(stroke)
        if strokes.count > 48 { reset(); return pass }
        // Thai is typed without spaces: fix a long run now rather than at the end of the phrase.
        if let typed = inputSources.layouts[current]?.render(strokes),
           let fix = detector.decideMidWord(strokes: strokes, typed: typed, current: current,
                                            layouts: inputSources.layouts, ignoring: store.ignoredWords, category: category) {
            strokes.removeAll()
            recentWords.removeAll()
            // This key goes through first; the rewrite waits for the field to show it.
            raiseFence()
            DispatchQueue.main.async { self.apply(fix, delimiter: nil, word: typed) }
        }
        return pass
    }

    /// Shift pressed and released on its own twice within a moment, with no other key between.
    private func shiftTappedTwice(_ event: CGEvent) -> Bool {
        guard store.shortcut.usesShiftTwice else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let now = ProcessInfo.processInfo.systemUptime
        let others: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]
        guard keyCode == 56 || keyCode == 60, event.flags.intersection(others).isEmpty else {
            shiftDown = nil; lastShiftTap = nil
            return false
        }
        if event.flags.contains(.maskShift) {
            shiftDown = (now, true)
            return false
        }
        // Released: a tap only if it was quick.
        guard let down = shiftDown, down.clean, now - down.at < 0.3 else { shiftDown = nil; lastShiftTap = nil; return false }
        shiftDown = nil
        if let last = lastShiftTap, now - last < 0.4 {
            lastShiftTap = nil
            return true
        }
        lastShiftTap = now
        return false
    }

    // MARK: - Rewriting

    /// The shortcut: the word being typed if there is one, else the selected text.
    private func convert() {
        if strokes.isEmpty { convertSelection() } else { convertCurrentWord() }
    }

    private func convertSelection() {
        reset()
        SelectedText.read(post: { self.post($0) }) { text in
            guard let text, let fix = self.detector.convertText(text, current: self.inputSources.currentLanguage(),
                                                                layouts: self.inputSources.layouts) else {
                self.onNothingToConvert?()
                return
            }
            SelectedText.replace(with: fix.replacement, type: { self.replace(scalarCount: 0, with: $0) },
                                 post: { self.post($0) }) {
                self.inputSources.select(fix.to)
                self.onCorrection?(fix)
            }
        }
    }

    private func convertCurrentWord() {
        guard !strokes.isEmpty, let current = inputSources.currentLanguage(),
              let typed = inputSources.layouts[current]?.render(strokes),
              let correction = detector.decide(strokes: strokes, typed: typed, current: current,
                                               layouts: inputSources.layouts, force: true) else {
            onNothingToConvert?()
            return
        }
        strokes.removeAll()
        DispatchQueue.main.async {
            guard FocusedText.check(endsWith: correction.original) != .mismatch else { return }
            self.committingComposition(from: correction) {
                self.replace(scalarCount: correction.original.unicodeScalars.count, with: correction.replacement)
                self.inputSources.select(correction.to)
                self.onCorrection?(correction)
                self.onManualConversion?(correction)
            }
        }
    }

    /// Korean's input method still holds the last syllable while it may grow (녀 → 녕), and
    /// Backspace there removes one letter, not the syllable. Switching layouts first makes it
    /// commit the syllable, so the Backspaces that follow erase whole ones.
    private func committingComposition(from correction: Correction, then work: @escaping () -> Void) {
        guard inputSources.composes(correction.from), correction.from != correction.to else { return work() }
        select(correction.to)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// A same-language spelling fix, when enabled and macOS agrees with it.
    private func typoCorrection(_ typed: String, language: Language) -> Correction? {
        guard store.fixTypos,
              let fix = detector.typoFix(typed, in: language, ignoring: store.ignoredWords, category: category),
              SystemSpelling.agrees(typo: typed, fix: fix, in: language) else { return nil }
        return Correction(original: typed, replacement: fix, from: language, to: language)
    }

    /// Folds immediately preceding words that read better in the fix's language into one rewrite.
    private func extendBackwards(_ fix: Correction) -> Correction {
        var original = fix.original, replacement = fix.replacement
        for word in recentWords.reversed() {
            guard word.language == fix.from,
                  let alt = detector.reread(strokes: word.strokes, typed: word.typed, current: word.language,
                                            as: fix.to, layouts: inputSources.layouts,
                                            ignoring: store.ignoredWords, category: category) else { break }
            original = word.typed + " " + original
            replacement = alt + " " + replacement
        }
        return Correction(original: original, replacement: replacement, from: fix.from, to: fix.to)
    }

    private func apply(_ correction: Correction, delimiter: CGEvent?, word: String, attempt: Int = 0) {
        // Backspacing blind is only safe if the field holds what we think it does.
        // Unreadable fields fall back to trusting our keystroke buffer.
        if FocusedText.check(endsWith: correction.original) == .mismatch {
            // When typing fast the app may not have drawn the last keys yet; give it a moment.
            // The fence is up, so nothing typed meanwhile gets ahead of the rewrite.
            if attempt < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    self.apply(correction, delimiter: delimiter, word: word, attempt: attempt + 1)
                }
                return
            }
            NSLog("TypoCat: field text doesn't end with the typed word; skipping fix")
            if let delimiter { post(delimiter, last: true) } else { lowerFence() }
            lastCorrection = nil
            return
        }
        record(correction.to)
        lastCorrection = (correction, delimiter, word)
        committingComposition(from: correction) {
            self.replace(scalarCount: correction.original.unicodeScalars.count, with: correction.replacement,
                         fenceAtEnd: delimiter == nil)
            self.select(correction.to)
            if let delimiter { self.post(delimiter, last: true) }
            self.onCorrection?(correction)
        }
    }

    private func undo(_ correction: Correction, delimiter: CGEvent?, word: String) {
        lastCorrection = nil
        onUndo?(correction)
        store.ignore(word)
        if store.unlearn(correction.replacement, in: correction.to) { detector.learnedWords = store.learnedWords }
        store.correctLanguage(from: correction.to, to: correction.from, in: frontBundleID)
        if let siteKey { store.correctLanguage(from: correction.to, to: correction.from, in: siteKey) }
        DispatchQueue.main.async {
            // The field should end with our replacement plus the replayed delimiter, if any.
            let trailing = delimiter == nil ? 0 : 1
            if let prefix = FocusedText.textBeforeCaret(),
               !FocusedText.endsWith(prefix, correction.replacement, ignoringLast: trailing) {
                self.lowerFence()
                return
            }
            // Removes the replayed delimiter too, which we type again after the original.
            self.replace(scalarCount: correction.replacement.unicodeScalars.count + trailing, with: correction.original,
                         fenceAtEnd: delimiter == nil)
            self.select(correction.from)
            if let delimiter { self.post(delimiter, last: true) }
        }
    }

    /// Counts a word's language for the front app and, when known, the website.
    private func record(_ language: Language) {
        store.recordLanguage(language, in: frontBundleID)
        if let siteKey { store.recordLanguage(language, in: siteKey) }
    }

    private func select(_ language: Language) {
        if fenceUp && language != inputSources.currentLanguage() { switchedDuringFence = true }
        inputSources.select(language)
    }

    /// Deletes by Backspace (one per typed scalar; each keystroke produced one) and types `text`.
    /// `fenceAtEnd` marks its last event as the end of the rewrite, when no delimiter follows.
    private func replace(scalarCount: Int, with text: String, fenceAtEnd: Bool = false) {
        for _ in 0..<scalarCount {
            postKey(Key.delete, down: true)
            postKey(Key.delete, down: false)
        }
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: 16) {
            let chunk = Array(units[start..<min(start + 16, units.count)])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e.flags = []
                post(e, last: fenceAtEnd && !down && start + 16 >= units.count)
            }
        }
    }

    private func postKey(_ keyCode: UInt16, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: down) else { return }
        e.flags = []
        post(e)
    }

    private func post(_ event: CGEvent, last: Bool = false) {
        event.setIntegerValueField(.eventSourceUserData, value: last ? Self.fenceTag : Self.syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Holding keys during a rewrite

    private func raiseFence() {
        fenceUp = true
        fenceGeneration += 1
        let generation = fenceGeneration
        // Never hold the keyboard hostage: give up after a moment even if the marker is lost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.fenceGeneration == generation { self?.lowerFence() }
        }
    }

    /// Replays held keys in order; they pass through the tap again as ordinary typing.
    private func lowerFence() {
        guard fenceUp else { return }
        fenceUp = false
        let events = heldEvents
        heldEvents.removeAll()
        let rebuild = switchedDuringFence
        switchedDuringFence = false
        for event in events {
            // A key typed during a fix that switched layouts was meant for the new layout. Events
            // built from a key code take their characters from the layout selected now.
            if rebuild, let fresh = CGEvent(keyboardEventSource: nil,
                                            virtualKey: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
                                            keyDown: event.type == .keyDown) {
                fresh.flags = event.flags
                fresh.post(tap: .cghidEventTap)
            } else {
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
