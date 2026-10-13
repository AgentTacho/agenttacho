// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "llm-usage-menubar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "LLMUsageMenuBar", targets: ["LLMUsageMenuBar"]),
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
            name: "LLMUsageMenuBar",
            dependencies: ["UsageCore"],
            path: "Sources/LLMUsageMenuBar"
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
