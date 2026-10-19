import AppKit
import TypoCatCore

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}
// Build step: `--compile-dict th Data/th_50k.txt out/th_50k.tcdict`
if let i = CommandLine.arguments.firstIndex(of: "--compile-dict") {
    let args = Array(CommandLine.arguments.dropFirst(i + 1))
    guard args.count == 3 else { print("usage: --compile-dict <language> <in.txt> <out.tcdict>"); exit(2) }
    do {
        try Dictionaries.compile(Language(rawValue: args[0]), from: URL(fileURLWithPath: args[1]))
            .write(to: URL(fileURLWithPath: args[2]))
        exit(0)
    } catch {
        print("compile \(args[1]) failed: \(error)")
        exit(1)
    }
}
// Time to load word lists, as the app does at launch: `--bench en th`
if let i = CommandLine.arguments.firstIndex(of: "--bench") {
    let languages = CommandLine.arguments.dropFirst(i + 1).map { Language(rawValue: $0) }
    let start = Date()
    let detector = Dictionaries.makeDetector(for: languages)
    let seconds = Date().timeIntervalSince(start)
    // Footprint is the "Memory" column in Activity Monitor; freed loading buffers don't count.
    var vm = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    print(String(format: "load %@: %.2fs, word lists %.0f MB, Activity Monitor footprint %.0f MB",
                 detector.languages.map(\.rawValue).sorted().joined(separator: ","), seconds,
                 Double(stats.size_in_use) / 1_048_576, Double(vm.phys_footprint) / 1_048_576))
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
