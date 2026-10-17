// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TypoCat",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, platform-free detection logic: layout maps, dictionaries, scoring.
        .target(name: "TypoCatCore"),
        // Menu-bar app: event tap, input sources (TIS/UCKeyTranslate), text rewriting.
        .executableTarget(
            name: "TypoCat",
            dependencies: ["TypoCatCore"],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("AppKit")]
        ),
        // Needs Xcode (XCTest isn't in the Command Line Tools); CI runs it.
        .testTarget(name: "TypoCatCoreTests", dependencies: ["TypoCatCore"]),
    ]
)
