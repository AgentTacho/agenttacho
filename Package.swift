// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "agentmeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "AgentMeter", targets: ["AgentMeter"]),
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
            name: "AgentMeter",
            dependencies: ["UsageCore"],
            path: "Sources/AgentMeter"
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
