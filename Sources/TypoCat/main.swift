import AppKit

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
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
