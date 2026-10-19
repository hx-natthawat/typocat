import Carbon
import Foundation
import TypoCatCore

/// Enabled keyboard layouts, their key maps (via UCKeyTranslate) and switching (via TIS).
final class InputSources {
    private(set) var layouts: [Language: LayoutMap] = [:]
    private var sources: [Language: TISInputSource] = [:]
    /// Each enabled layout's name as System Settings shows it ("Thai", "ABC").
    private(set) var names: [Language: String] = [:]
    /// Input source ID → its key in `layouts`, which is a variant (en+dvorak) for a second
    /// layout of a language.
    private var keys: [String: Language] = [:]

    func reload() {
        layouts = [:]
        sources = [:]
        names = [:]
        keys = [:]
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        var korean: TISInputSource?
        for source in list {
            // Korean is an input method with no key map to read; it's built once U.S. keys are known.
            if Hangul.isTwoSet(Self.idOf(source)) { korean = korean ?? source; continue }
            guard let base = Self.language(of: source), var map = Self.buildMap(source: source, language: base) else { continue }
            var language = base
            if let first = layouts[base] {
                // A second layout counts only if it moves letters (Dvorak next to ABC).
                guard map.movesLetters(comparedTo: first) else { continue }
                language = Language(base, variant: Self.variantName(of: source))
                guard layouts[language] == nil else { continue }
                map = map.named(language)
            }
            sources[language] = source
            layouts[language] = map
            keys[Self.idOf(source)] = language
            names[language] = Self.property(source, kTISPropertyLocalizedName) ?? language.shortName
        }
        if let korean, layouts[Hangul.language] == nil {
            let language = Hangul.language
            sources[language] = korean
            layouts[language] = Hangul.twoSetLayout(over: layouts[.english], inputSourceID: Self.idOf(korean))
            keys[Self.idOf(korean)] = language
            names[language] = Self.property(korean, kTISPropertyLocalizedName) ?? "2-Set Korean"
        }
    }

    /// Whether `language` is typed through an input method that holds letters while it joins
    /// them (Korean): its last syllable must be committed before Backspace can erase whole ones.
    func composes(_ language: Language) -> Bool { layouts[language]?.joinsHangul ?? false }

    func currentLanguage() -> Language? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return keys[Self.idOf(source)] ?? Self.language(of: source)
    }

    /// "com.apple.keylayout.Dvorak" → "dvorak".
    private static func variantName(of source: TISInputSource) -> String {
        String(idOf(source).split(separator: ".").last ?? "alt")
    }

    func select(_ language: Language) {
        guard let source = sources[language] else { return }
        TISSelectInputSource(source)
    }

    // MARK: - TIS helpers

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? T
    }

    static func language(of source: TISInputSource) -> Language? {
        let languages: [String] = property(source, kTISPropertyInputSourceLanguages) ?? []
        guard let primary = languages.first else { return nil }
        let language = Language(rawValue: primary)
        return language.rawValue.isEmpty ? nil : language
    }

    /// One layout per language among every layout installed on this Mac, enabled or not.
    /// Used by --eval to measure languages the user hasn't turned on.
    static func installedLayouts() -> [Language: LayoutMap] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return [:] }
        var out: [Language: LayoutMap] = [:]
        // Prefer each language's plain layout ("Russian", "Hebrew") over variants.
        let sorted = list.sorted { (Self.idOf($0)).count < (Self.idOf($1)).count }
        for source in sorted {
            guard let language = language(of: source), let map = buildMap(source: source, language: language) else { continue }
            if let first = out[language] {
                // Also every variant that moves letters, for LS_LANGS=en+dvorak.
                let variant = Language(language, variant: variantName(of: source))
                if out[variant] == nil && map.movesLetters(comparedTo: first) { out[variant] = map.named(variant) }
            } else {
                out[language] = map
            }
        }
        // Korean has no key map; 2-Set is built in, so it's measured even when not installed.
        out[Hangul.language] = Hangul.twoSetLayout(over: out[.english])
        return out
    }

    private static func idOf(_ source: TISInputSource) -> String { property(source, kTISPropertyInputSourceID) ?? "" }

    /// Asks the layout what every key produces with and without Shift.
    static func buildMap(source: TISInputSource, language: Language) -> LayoutMap? {
        guard let data: Data = property(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let id: String = property(source, kTISPropertyInputSourceID) ?? "?"
        let kbdType = UInt32(LMGetKbdType())
        var forward: [KeyStroke: String] = [:]
        var deadKeys: [KeyStroke: [KeyStroke: String]] = [:]
        let strokes = (UInt16(0)..<UInt16(128)).flatMap { code in [false, true].map { KeyStroke(keyCode: code, shift: $0) } }
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            /// Output of `stroke` from `state`; a dead key returns nil and leaves its state in `state`.
            func translate(_ stroke: KeyStroke, _ state: inout UInt32, options: OptionBits) -> String? {
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let modifiers = stroke.shift ? UInt32(shiftKey >> 8) & 0xFF : 0
                let status = UCKeyTranslate(layout, stroke.keyCode, UInt16(kUCKeyActionDown), modifiers, kbdType,
                                            options, &state, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { return nil }
                let s = String(utf16CodeUnits: chars, count: length)
                return s.unicodeScalars.allSatisfy(isPrintable) && s != " " ? s : nil
            }
            for stroke in strokes {
                var state: UInt32 = 0
                if let s = translate(stroke, &state, options: OptionBits(kUCKeyTranslateNoDeadKeysMask)) { forward[stroke] = s }
                // Dead key: no output, but a state that changes the next key.
                var deadState: UInt32 = 0
                guard translate(stroke, &deadState, options: 0) == nil, deadState != 0 else { continue }
                var follow: [KeyStroke: String] = [:]
                for next in strokes {
                    var state = deadState
                    if let s = translate(next, &state, options: 0), s.unicodeScalars.count == 1 { follow[next] = s }
                }
                if !follow.isEmpty { deadKeys[stroke] = follow }
            }
        }
        return forward.isEmpty ? nil : LayoutMap(language: language, inputSourceID: id, forward: forward, deadKeys: deadKeys)
    }

    private static func isPrintable(_ s: Unicode.Scalar) -> Bool {
        s.value >= 0x20 && s.value != 0x7F && !(0xF700...0xF8FF).contains(s.value)
    }
}
