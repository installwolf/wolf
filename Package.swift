// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bulwark",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, testable logic. No system side effects live here.
        .target(name: "BulwarkCore"),

        // The `bulwark` CLI: add/remove/status, talks to the daemon via state files.
        .executableTarget(
            name: "bulwark",
            dependencies: ["BulwarkCore"]
        ),

        // The root watchdog daemon: self-heals enforcement, drains the removal queue.
        .executableTarget(
            name: "bulwarkd",
            dependencies: ["BulwarkCore"]
        ),

        // Menu-bar app: a friendly front end over the CLI (SwiftUI MenuBarExtra).
        .executableTarget(
            name: "BulwarkBar",
            dependencies: ["BulwarkCore"]
        ),

        .testTarget(
            name: "BulwarkCoreTests",
            dependencies: ["BulwarkCore"]
        ),
    ]
)
