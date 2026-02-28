// swift-tools-version: 6.2
import CompilerPluginSupport
import Foundation
import PackageDescription

let package = Package(
    name: "CodexBar",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/Commander", from: "0.2.1"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-syntax", from: "600.0.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
    ],
    targets: {
        var targets: [Target] = [
            .target(
                name: "CodexBarCore",
                dependencies: [
                    "CodexBarMacroSupport",
                    .product(name: "Logging", package: "swift-log"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .macro(
                name: "CodexBarMacros",
                dependencies: [
                    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                    .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                ]),
            .target(
                name: "CodexBarMacroSupport",
                dependencies: [
                    "CodexBarMacros",
                ]),
            .executableTarget(
                name: "CodexBarCLI",
                dependencies: [
                    "CodexBarCore",
                    .product(name: "Commander", package: "Commander"),
                ],
                path: "Sources/CodexBarCLI",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .testTarget(
                name: "CodexBarLinuxTests",
                dependencies: ["CodexBarCore", "CodexBarCLI"],
                path: "TestsLiteLinux",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
        ]

        #if os(macOS)
        targets.append(contentsOf: [
            .executableTarget(
                name: "CodexBarClaudeWatchdog",
                dependencies: [],
                path: "Sources/CodexBarClaudeWatchdog",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "CodexBar",
                dependencies: [
                    .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                    "CodexBarMacroSupport",
                    "CodexBarCore",
                ],
                path: "Sources/CodexBar",
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    // Opt into Swift 6 strict concurrency (approachable migration path).
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "CodexBarWidget",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarWidget",
                swiftSettings: [
                    // Build as an app-extension-safe binary so WidgetKit boots via NSExtensionMain.
                    .unsafeFlags(["-application-extension"]),
                    .enableUpcomingFeature("StrictConcurrency"),
                ],
                linkerSettings: [
                    // Use the extension entrypoint instead of a standalone app main.
                    .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
                ]),
        ])

        targets.append(.testTarget(
            name: "CodexBarTests",
            dependencies: ["CodexBar", "CodexBarCore", "CodexBarCLI"],
            path: "TestsLite",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]))
        #endif

        return targets
    }())
