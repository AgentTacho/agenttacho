import Foundation
import Testing
@testable import DemoMode
import UsageCore

/// The demo build's launch setup and its isolation (spec 024 FR-005, FR-006,
/// FR-009, SC-002, research R11).
@Suite struct DemoSetupTests {
    static func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("demo-home-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    static func scenarioWithPrices() throws -> Scenario {
        let text = ScenarioTests.json().replacingOccurrences(of: #""importedPrices": { "version": 1, "batches": [] }"#, with: """
            "importedPrices": { "version": 1, "batches": [ { "kind": "openai", "origin": "demo", "importedAt": "2026-10-01T08:00:00Z",
              "entries": [ { "model": "gpt-5.6", "inputPerMTok": 1.5, "outputPerMTok": 12, "cacheWrite5mPerMTok": 1.5,
                             "cacheWrite1hPerMTok": 1.5, "cacheReadPerMTok": 0.15 } ] } ] }
            """)
        return try ScenarioTests.decode(text)
    }

    @Test func prepareWritesTheScenarioIntoTheDemoFolders() throws {
        let home = try Self.temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home, appFolder: "agenttacho-demo")
        // What an earlier demo run left behind.
        try FileManager.default.createDirectory(at: paths.configFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"accounts\": []}".utf8).write(to: paths.configFileURL)
        try Data("{}".utf8).write(to: paths.importedPricesFileURL)
        try FileManager.default.createDirectory(at: paths.lastGoodFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paths.lastGoodFileURL)

        let scenario = try Self.scenarioWithPrices()
        let launch = Date(timeIntervalSince1970: 1_791_000_000)
        try DemoSetup.prepare(scenario: scenario, paths: paths, launch: launch)

        let store = ConfigStore(fileURL: paths.configFileURL)
        let (configuration, error) = store.load()
        #expect(error == nil)
        #expect(configuration == scenario.configuration)
        let prices = ImportedPriceStore(fileURL: paths.importedPricesFileURL)
        let loaded = prices.load()
        #expect(prices.loadError == nil)
        let batch = try #require(loaded.batches.first)
        let expected = try #require(scenario.importedPrices?.batches.first)
        #expect(loaded.batches.count == 1)
        #expect(batch.kind == expected.kind)
        #expect(batch.origin == expected.origin)
        #expect(batch.entries == expected.entries)
        // Dates read as current: the import happened a day before launch (FR-011).
        #expect(batch.importedAt == launch.addingTimeInterval(-86_400))
        #expect(!FileManager.default.fileExists(atPath: paths.lastGoodFileURL.path))
    }

    /// A scenario without imported prices replaces the imports an earlier
    /// run left (FR-009).
    @Test func prepareWithoutImportedPricesReplacesEarlierImports() throws {
        let home = try Self.temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home, appFolder: "agenttacho-demo")
        try DemoSetup.prepare(scenario: try Self.scenarioWithPrices(), paths: paths)
        #expect(ImportedPriceStore(fileURL: paths.importedPricesFileURL).load().batches.count == 1)
        let text = ScenarioTests.json().replacingOccurrences(of: #""importedPrices": { "version": 1, "batches": [] },"#, with: "")
        let scenario = try ScenarioTests.decode(text)
        #expect(scenario.importedPrices == nil)
        try DemoSetup.prepare(scenario: scenario, paths: paths)
        #expect(ImportedPriceStore(fileURL: paths.importedPricesFileURL).load() == .empty)
    }

    /// Without a playable scenario the demo app stays empty: no account of
    /// an earlier run is shown (FR-013).
    @Test func clearLeavesTheDemoEmpty() throws {
        let home = try Self.temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home, appFolder: "agenttacho-demo")
        try DemoSetup.prepare(scenario: try Self.scenarioWithPrices(), paths: paths)
        try FileManager.default.createDirectory(at: paths.lastGoodFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paths.lastGoodFileURL)
        try DemoSetup.clear(paths: paths)
        let (configuration, error) = ConfigStore(fileURL: paths.configFileURL).load()
        #expect(error == nil)
        #expect(configuration.accounts.isEmpty)
        #expect(configuration.groups.isEmpty)
        #expect(ImportedPriceStore(fileURL: paths.importedPricesFileURL).load() == .empty)
        #expect(!FileManager.default.fileExists(atPath: paths.lastGoodFileURL.path))
    }

    /// The installed AgentTacho's folders stay as they are (FR-005, SC-003).
    @Test func prepareNeverTouchesTheAgentTachoFolders() throws {
        let home = try Self.temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let real = Paths(home: home)
        let files = [real.configFileURL, real.importedPricesFileURL, real.lastGoodFileURL, real.logFileURL]
        for (index, url) in files.enumerated() {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("real \(index)".utf8).write(to: url)
        }
        try DemoSetup.prepare(scenario: try Self.scenarioWithPrices(), paths: Paths(home: home, appFolder: "agenttacho-demo"))
        for (index, url) in files.enumerated() {
            #expect(try Data(contentsOf: url) == Data("real \(index)".utf8))
        }
    }

    @Test func sourcesAreTheThreeDemoSourcesAndNothingNetworkBound() throws {
        let scenario = try ScenarioTests.decode(ScenarioTests.json())
        let player = ScenarioPlayer(scenario: scenario, launch: Date())
        let sources = DemoSetup.sources(player: player, builtInPrices: try PriceTable.builtIn(), importedPrices: { .empty })
        #expect(sources.count == 3)
        #expect(sources.contains { $0 is DemoSubscriptionSource })
        #expect(sources.contains { $0 is DemoCodexLimitsSource })
        #expect(sources.contains { $0 is DemoRecordSource })
        #expect(Set(sources.map(\.name)).count == 3)
        for source in sources {
            #expect(!(source is NetworkBoundSource), "\(source.name) is network bound")
            #expect(!(source is SavedValuesSource), "\(source.name) restores saved values")
            #expect(!(source is EndpointGatedSource), "\(source.name) gates an endpoint")
            #expect(!(source is WindowSensitiveSource), "\(source.name) is window sensitive")
        }
    }

    @Test func noCredentialsHasNone() throws {
        let reader = NoCredentials()
        #expect(try reader.read(configDirectory: "~/.claude") == nil)
        #expect(!reader.hasDefaultCredential())
    }

    @Test func frameOffsetsAreTheFrameTimes() throws {
        let scenario = try ScenarioTests.decode(ScenarioTests.json(frames: #"[ { "at": "12s" }, { "at": "1m" } ]"#))
        #expect(DemoSetup.frameOffsets(scenario) == [12, 60])
    }

    /// The app and the coverage check refresh half a second after each
    /// frame, well within FR-012's 2 s; the last frame marks the final state.
    @Test func frameRefreshTimes() throws {
        let launch = Date(timeIntervalSince1970: 1_791_000_000)
        let scenario = try ScenarioTests.decode(ScenarioTests.json(frames: #"[ { "at": "12s" }, { "at": "1m" } ]"#))
        #expect(DemoSetup.frameRefreshDates(scenario, launch: launch) == [launch.addingTimeInterval(12.5), launch.addingTimeInterval(60.5)])
        #expect(DemoSetup.lastFrameDate(scenario, launch: launch) == launch.addingTimeInterval(60))
        let none = try ScenarioTests.decode(ScenarioTests.json(frames: "[]"))
        #expect(DemoSetup.frameRefreshDates(none, launch: launch).isEmpty)
        #expect(DemoSetup.lastFrameDate(none, launch: launch) == launch)
    }

    /// The app's demo branches name no update client, price download,
    /// credential reader or networking type either (FR-006, FR-007, SC-002):
    /// every `#if AGENTTACHO_DEMO` branch of the app sources is checked.
    @Test func appDemoBranchesNameNoNetworkOrCredentialType() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentTacho")
        let forbidden = ["URLSession", "UpdateClient", ".fetch()", "LiteLLMImporter()", "SecurityToolCredentialReader",
                         "FileCodexCredentialReader", "UsageEndpointClient", "CodexUsageClient", "InstallEnvironment"]
        var branches = 0
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.pathExtension == "swift" {
            var inDemo = false
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "#if AGENTTACHO_DEMO" { inDemo = true; branches += 1; continue }
                if inDemo, trimmed == "#else" || trimmed == "#endif" { inDemo = false; continue }
                guard inDemo else { continue }
                for name in forbidden {
                    #expect(!line.contains(name), "\(file.lastPathComponent) demo branch mentions \(name)")
                }
            }
        }
        #expect(branches >= 8)
    }

    /// The demo target names no networking, credential or download type, so
    /// the demo build cannot reach the network or a credential through it
    /// (SC-002, research R11).
    @Test func demoSourcesNameNoNetworkOrCredentialType() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DemoMode")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 6)
        let forbidden = ["URLSession", "SecurityToolCredentialReader", "FileCodexCredentialReader", "UsageEndpointClient",
                         "CodexUsageClient", "LiteLLMImporter(", "/usr/bin/security"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in forbidden {
                #expect(!text.contains(name), "\(file.lastPathComponent) mentions \(name)")
            }
        }
    }
}
