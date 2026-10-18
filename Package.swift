// swift-tools-version: 5.10
import Foundation
import PackageDescription

/// `DEMO=1` is set only by `make app-demo`, which builds into its own scratch
/// path (.build/demo). Only then is the app compiled with AGENTTACHO_DEMO and
/// linked with the demo target, so one switch decides both: linker
/// dead stripping keeps Swift type metadata, so a regular build that merely
/// depended on DemoMode would carry its symbols (spec 024 FR-003, research R2).
let demoBuild = ProcessInfo.processInfo.environment["DEMO"] == "1"

let package = Package(
    name: "agenttacho",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "AgentTacho", targets: ["AgentTacho"]),
    ],
    targets: [
        .target(
            name: "UsageCore",
            path: "Sources/UsageCore",
            resources: [
                .copy("Resources/prices.json"),
                .copy("Resources/FontAwesome")
            ]
        ),
        // The demo build's scenario player and sources (spec 024 research
        // R2). The app imports it only under AGENTTACHO_DEMO and depends on
        // it only in a demo build, so regular builds link none of its
        // symbols (checked by build-app.sh).
        .target(
            name: "DemoMode",
            dependencies: ["UsageCore"],
            path: "Sources/DemoMode"
        ),
        .executableTarget(
            name: "AgentTacho",
            dependencies: ["UsageCore"] + (demoBuild ? ["DemoMode"] : []),
            path: "Sources/AgentTacho",
            swiftSettings: demoBuild ? [.define("AGENTTACHO_DEMO")] : []
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "DemoModeTests",
            dependencies: ["DemoMode", "UsageCore"],
            path: "Tests/DemoModeTests"
        ),
    ]
)
