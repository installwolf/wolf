// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "wolf",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, testable logic. No system side effects live here.
        .target(name: "WolfCore"),

        // The `wolf` CLI: add/remove/status, talks to the daemon via state files.
        .executableTarget(
            name: "wolf",
            dependencies: ["WolfCore"]
        ),

        // The root watchdog daemon: self-heals enforcement, drains the removal queue.
        .executableTarget(
            name: "wolfd",
            dependencies: ["WolfCore"]
        ),

        // Menu-bar app: a friendly front end over the CLI (SwiftUI MenuBarExtra).
        .executableTarget(
            name: "WolfBar",
            dependencies: ["WolfCore"]
        ),

        .testTarget(
            name: "WolfCoreTests",
            dependencies: ["WolfCore"]
        ),
    ]
)
