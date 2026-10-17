// swift-tools-version: 5.10
import PackageDescription

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
        .executableTarget(
            name: "AgentTacho",
            dependencies: ["UsageCore"],
            path: "Sources/AgentTacho"
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
