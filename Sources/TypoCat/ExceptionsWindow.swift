import AppKit
import SwiftUI

/// What the Exceptions window shows: words TypoCat leaves alone and apps it's off in.
final class ExceptionsModel: ObservableObject {
    struct App: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
    }

    @Published var words: [String] = []
    @Published var apps: [App] = []

    var addWord: (String) -> Void = { _ in }
    var removeWord: (String) -> Void = { _ in }
    var removeApp: (String) -> Void = { _ in }
}

final class ExceptionsWindowController: NSWindowController {
    convenience init(model: ExceptionsModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = L("Exceptions")
        window.contentView = NSHostingView(rootView: ExceptionsView(model: model))
        window.setContentSize(NSSize(width: 420, height: 480))
        window.minSize = NSSize(width: 360, height: 320)
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ExceptionsView: View {
    @ObservedObject var model: ExceptionsModel
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Words TypoCat never changes").font(.headline)
            Text("Undoing a fix with Backspace adds the word here. Names, brands and slang can be added by hand.")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Add a word", text: $newWord).onSubmit(add)
                Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            List {
                if model.words.isEmpty { Text("No words yet").foregroundColor(.secondary) }
                ForEach(model.words, id: \.self) { word in
                    row { Text(verbatim: word) } remove: { model.removeWord(word) }
                }
            }
            .frame(minHeight: 120)

            Text("Apps TypoCat is off in").font(.headline).padding(.top, 6)
            Text("Turn TypoCat off for the app in front from the menu bar.")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                if model.apps.isEmpty { Text("No apps").foregroundColor(.secondary) }
                ForEach(model.apps) { app in
                    row {
                        HStack(spacing: 6) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                            Text(verbatim: app.name)
                        }
                    } remove: { model.removeApp(app.id) }
                }
            }
            .frame(minHeight: 80)
        }
        .padding(16)
        .environment(\.layoutDirection, appLayoutDirection)
    }

    private func row<Label: View>(@ViewBuilder _ label: () -> Label, remove: @escaping () -> Void) -> some View {
        HStack {
            label()
            Spacer()
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help(Text("Remove"))
        }
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        model.addWord(word)
        newWord = ""
    }
}
