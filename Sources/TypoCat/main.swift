import AppKit
import TypoCatCore

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}
// Time to load word lists, as the app does at launch: `--bench en th`
if let i = CommandLine.arguments.firstIndex(of: "--bench") {
    let languages = CommandLine.arguments.dropFirst(i + 1).map { Language(rawValue: $0) }
    let start = Date()
    let detector = Dictionaries.makeDetector(for: languages)
    print(String(format: "load %@: %.2fs", detector.languages.map(\.rawValue).sorted().joined(separator: ","), Date().timeIntervalSince(start)))
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--eval-typos") {
    SelfTest.evaluateTypos(top: CommandLine.arguments.dropFirst(i + 1).first.flatMap { Int($0) } ?? 5000)
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--eval") {
    let n = CommandLine.arguments.dropFirst(i + 1).first.flatMap { Int($0) } ?? 5000
    SelfTest.evaluate(top: n)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
