import AppKit
import SwiftUI
import TypoCatCore

/// What the setup window shows; the app delegate keeps it current.
final class SetupModel: ObservableObject {
    struct Layout: Identifiable {
        let language: Language
        let name: String
        let hasWordList: Bool
        var id: String { language.rawValue }
    }

    @Published var trusted = false
    @Published var layouts: [Layout] = []
    /// A word to type, how it looks typed on another layout, and that layout's name.
    @Published var example: (word: String, typed: String, layout: String)?
    @Published var lastFix: String?
    @Published var openAtLogin = false
    @Published var fixTypos = false
    @Published var matchLayout = true
    @Published var learnWords = false
    @Published var matchSite = false

    var setOpenAtLogin: (Bool) -> Void = { _ in }
    var setFixTypos: (Bool) -> Void = { _ in }
    var setMatchLayout: (Bool) -> Void = { _ in }
    var setLearnWords: (Bool) -> Void = { _ in }
    var setMatchSite: (Bool) -> Void = { _ in }
    var done: () -> Void = {}
}

/// Shown on first launch, and from the menu: permission, layouts, a field to try it, options.
final class SetupWindowController: NSWindowController {
    convenience init(model: SetupModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 770),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "Set up TypoCat"
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum Brand {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light) })
    }
    static func rgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    static let lagoon = color(0x0B7A75, 0x4CC3B9)
    /// Text on lagoon fills: white on the dark teal, ink on the light one.
    static let onLagoon = color(0xFFFFFF, 0x142220)
    /// White on marigold is too faint to read, in either mode.
    static let onMarigold = Color(rgb(0x142220))
    static let marigold = Color(rgb(0xF2A12B))
    static let coral = color(0xE5603D, 0xF0866A)
    static let ink = color(0x142220, 0xEEF2EE)
    static let page = color(0xEEF2EE, 0x142220)
    static let card = color(0xFFFFFF, 0x1E302D)
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel
    @State private var tryText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 12) {
                step(1, "Let TypoCat see your typing", done: model.trusted) { permission }
                step(2, "Your keyboards", done: model.layouts.filter(\.hasWordList).count >= 2) { keyboards }
                step(3, "Try it", done: model.lastFix != nil) { tryIt }
                step(4, "Options", done: nil) { options }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 12)
            footer
        }
        .frame(width: 540, height: 770)
        .background(Brand.page)
        .foregroundColor(Brand.ink)
    }

    private var header: some View {
        VStack(spacing: 6) {
            if let url = Bundle.main.url(forResource: "Manee", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            } else {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            }
            (Text("Typo") + Text("Cat").foregroundColor(Brand.marigold))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Typed on the wrong keyboard? Keep typing. Manee fixes the word when you press Space.")
                .font(.system(size: 13)).multilineTextAlignment(.center).opacity(0.75)
                .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 34).padding(.bottom, 18)
    }

    private func step<Content: View>(_ n: Int, _ title: String, done: Bool?,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done == true ? Brand.lagoon : Brand.ink.opacity(0.12)).frame(width: 26, height: 26)
                if done == true {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(Brand.onLagoon)
                } else {
                    Text("\(n)").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                content().font(.system(size: 12))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Brand.card))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    @ViewBuilder private var permission: some View {
        if model.trusted {
            Text("Accessibility access is on. TypoCat never saves or sends what you type.").opacity(0.75)
        } else {
            Text("Turn on TypoCat in System Settings → Privacy & Security → Accessibility. This window updates by itself.")
                .opacity(0.75).fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(Pill(color: Brand.marigold, text: Brand.onMarigold))
        }
    }

    @ViewBuilder private var keyboards: some View {
        FlowRow(model.layouts) { layout in
            HStack(spacing: 5) {
                Text(layout.language.shortName).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(layout.hasWordList ? Brand.lagoon : .gray))
                    .foregroundColor(layout.hasWordList ? Brand.onLagoon : .white)
                Text(layout.hasWordList ? layout.name : "\(layout.name) (not supported)")
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(Brand.ink.opacity(0.06)))
        }
        if model.layouts.filter(\.hasWordList).count < 2 {
            Text("Add the keyboards you type with, for example English plus Thai, Russian or Hebrew.").opacity(0.75)
            Button("Open Keyboard Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
            .buttonStyle(Pill(color: Brand.marigold, text: Brand.onMarigold))
        }
    }

    @ViewBuilder private var tryIt: some View {
        if let example = model.example {
            (Text("Switch to ") + Text(example.layout).bold() + Text(", type ") + Text(example.word).bold()
                + Text(" with the same keys you'd use in English, then press Space."))
                .opacity(0.75).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                // A space first, so a leading combining mark (Thai ้) has a base to sit on.
                Text("\u{00A0}" + example.typed).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Brand.coral.opacity(0.14)))
                Image(systemName: "arrow.right").foregroundColor(Brand.marigold)
                Text(example.word).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Brand.lagoon.opacity(0.14)))
            }
        } else {
            Text("Type a word on the wrong keyboard, then press Space.").opacity(0.75)
        }
        TextField("Type here", text: $tryText)
            .textFieldStyle(.roundedBorder).font(.system(size: 14))
            .disabled(!model.trusted)
        if let fix = model.lastFix {
            Label(fix, systemImage: "sparkles").foregroundColor(Brand.lagoon).font(.system(size: 12, weight: .medium))
        }
    }

    @ViewBuilder private var options: some View {
        Toggle("Open at login", isOn: binding(\.openAtLogin, model.setOpenAtLogin))
        Toggle("Match the keyboard to each app", isOn: binding(\.matchLayout, model.setMatchLayout))
        Toggle("Match the keyboard to each website (keeps site names on this Mac)", isOn: binding(\.matchSite, model.setMatchSite))
        Toggle("Fix typos too (beta): recieve → receive", isOn: binding(\.fixTypos, model.setFixTypos))
        Toggle("Learn words I convert with ⌃⌥Space (saved on this Mac only)", isOn: binding(\.learnWords, model.setLearnWords))
    }

    private func binding(_ key: ReferenceWritableKeyPath<SetupModel, Bool>, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { model[keyPath: key] }, set: { model[keyPath: key] = $0; set($0) })
    }

    private var footer: some View {
        HStack {
            Text("⌃⌥Space converts the word you're typing. Undo a fix with Backspace.")
                .font(.system(size: 11)).opacity(0.6)
            Spacer()
            Button(model.trusted ? "Done" : "Later") { model.done() }
                .buttonStyle(Pill(color: model.trusted ? Brand.lagoon : Brand.ink.opacity(0.35),
                                  text: model.trusted ? Brand.onLagoon : .white))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }
}

private struct Pill: ButtonStyle {
    let color: Color
    let text: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(text)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(color))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Lays chips out left to right, wrapping onto new lines.
private struct FlowRow<Item: Identifiable, Chip: View>: View {
    let items: [Item]
    let chip: (Item) -> Chip
    init(_ items: [Item], @ViewBuilder chip: @escaping (Item) -> Chip) { self.items = items; self.chip = chip }

    var body: some View {
        // Three per row fits 540 pt; layouts rarely number more than a handful.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(items[start..<min(start + 3, items.count)]) { chip($0) }
                }
            }
        }
    }
}
