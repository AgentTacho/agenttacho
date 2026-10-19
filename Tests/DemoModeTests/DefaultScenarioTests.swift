import Foundation
import Testing
@testable import DemoMode
import UsageCore

/// The bundled scenarios, and the coverage of the `default` scenario
/// through the app's own level, pace, marker and threshold logic (spec 024
/// FR-014, FR-015, FR-016, SC-005).
@Suite struct DefaultScenarioTests {
    static let demoDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/demo")
    static let defaultURL = demoDirectory.appendingPathComponent("default.json")

    static func scenarioFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "litellm-prices.json" }
    }

    @Test func everyBundledScenarioLoads() throws {
        let files = try Self.scenarioFiles()
        #expect(files.contains(Self.defaultURL))
        for file in files {
            _ = try Scenario.load(from: file)
        }
    }

    /// Invented names only (FR-015): no "Red Hat" in any spelling and
    /// nothing that looks like an email address, in every demo file.
    @Test func demoFilesUseInventedNamesOnly() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.demoDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count >= 2)
        let email = try Regex(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            // Letters only, so any separator between the two words counts.
            let letters = String(text.lowercased().filter(\.isLetter))
            #expect(!letters.contains("redhat"), "\(file.lastPathComponent)")
            #expect(text.firstMatch(of: email) == nil, "\(file.lastPathComponent)")
        }
    }

    /// The made-up price list the demo's "Import from LiteLLM" previews
    /// instead of downloading (FR-007): LiteLLM's format, usable for every
    /// provider import, and a little different from the scenario's own
    /// imported prices, so the preview shows changes.
    @Test(arguments: [ImportKind.anthropic, .openai, .gemini])
    func bundledLiteLLMPricesImport(kind: ImportKind) throws {
        let data = try Data(contentsOf: Self.demoDirectory.appendingPathComponent("litellm-prices.json"))
        let batch = try LiteLLMImporter.batch(from: data, kind: kind, origin: "demo", importedAt: Date())
        #expect(!batch.entries.isEmpty)
        guard kind == .openai else { return }
        let imported = try #require(try Scenario.load(from: Self.defaultURL).importedPrices?.batch(for: .openai))
        let current = Dictionary(uniqueKeysWithValues: imported.entries.map { ($0.model, $0) })
        let changed = batch.entries.filter { entry in current[entry.model].map { !$0.samePrices(as: entry) } ?? false }
        let new = batch.entries.filter { current[$0.model] == nil }
        #expect(!changed.isEmpty)
        #expect(!new.isEmpty)
    }

    static var utc: Calendar { DemoSourcesTests.utc }

    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioCoversTheShotList(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        #expect(report.levels.isSuperset(of: [.normal, .warning, .critical]), "levels \(report.levels)")
        #expect(report.markers.isSuperset(of: ["\u{2197}", "\u{2191}"]), "markers \(report.markers)")
        #expect(report.paceStates.isSuperset(of: ["onPace", "behind", "ahead"]), "pace states \(report.paceStates)")
        #expect(report.incompleteOwners.isEmpty, "incomplete \(report.incompleteOwners)")
        #expect(report.harnesses == [.claudeCode, .codex, .openCode])
        // The `pace` shot crops Claude's 7-day row with its orange note, and
        // the published shots show the default relative times (spec 025
        // FR-035, clarification).
        #expect(report.attentionRows.contains(.claude("acc-max", .sevenDay)), "attention rows \(report.attentionRows)")
        #expect(report.absoluteTimeOwners.isEmpty, "absolute times \(report.absoluteTimeOwners)")
        #expect(scenario.configuration.groups.contains { scenario.configuration.members(of: $0.id).count >= 2 })
    }

    static let variantsURL = demoDirectory.appendingPathComponent("variants.json")

    /// The second scenario, never captured, shows what the published shots
    /// leave out: a section with absolute times and a group with one member
    /// (spec 025 FR-035).
    @Test(arguments: DemoSourcesTests.launches)
    func variantsScenarioCoversAbsoluteTimesAndASingleMember(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.variantsURL)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        #expect(report.absoluteTimeOwners.contains("Claude Max"), "absolute times \(report.absoluteTimeOwners)")
        #expect(!report.singleMemberGroups.isEmpty)
        let group = try #require(scenario.configuration.groups.first { report.singleMemberGroups.contains($0.name) })
        #expect(report.snapshot.groups[group.id] != nil)
    }

    /// Exactly one alert between launch and the last frame, the Company
    /// budget at 80%, and the last frame at most 20 s after launch (FR-012,
    /// FR-014, US2).
    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioFiresOneAlert(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        #expect(report.crossings == ["Company budget@80"])
        let last = try #require(DemoSetup.frameOffsets(scenario).last)
        #expect(last <= 20)
    }

    /// The `details` and `harnesses` shots crop the breakdown of the budget
    /// the dropdown marks for the capture: the Company budget, with usage
    /// from all three harnesses (FR-019).
    @Test(arguments: DemoSourcesTests.launches)
    func shotBudgetHasAllHarnesses(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        let owner = try #require(BarLayout.shotBudgetOwner(snapshot: report.snapshot, configuration: scenario.configuration))
        #expect(owner.name == "Company budget")
        let entry = try #require(report.snapshot.groups[owner.id])
        #expect(Set(entry.breakdown.perHarness.map(\.harness)) == [.claudeCode, .codex, .openCode])
    }

    /// The coverage counts the time format that takes effect (spec 025
    /// FR-016, FR-021): a group member's own absolute value does not count,
    /// its group's does, and so does an account with its own budget.
    @Test func absoluteTimeOwnersFollowTheEffectiveFormat() {
        let configuration = Configuration(accounts: [
            Account(id: "a-claude", displayName: "Claude", kind: .subscription(SubscriptionSettings()), timeFormat: .absolute),
            Account(id: "a-member", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "g-relative")),
                    timeFormat: .absolute),
            Account(id: "a-member2", displayName: "Member 2", kind: .tokenBased(TokenBasedSettings(groupId: "g-absolute"))),
            Account(id: "a-own", displayName: "Own", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 10)))),
                    timeFormat: .absolute),
        ], groups: [
            BudgetGroup(id: "g-relative", name: "Relative group", budgetUSD: 10),
            BudgetGroup(id: "g-absolute", name: "Absolute group", budgetUSD: 10, timeFormat: .absolute),
        ])
        #expect(Set(ScenarioCoverage.absoluteTimeOwners(configuration)) == ["Claude", "Own", "Absolute group"])
    }

    /// The story of brainstorm 18: a monthly "Company budget" with a
    /// building icon holding a Vertex and an OpenAI API account (FR-014).
    @Test func defaultScenarioHasTheCompanyBudget() throws {
        let configuration = try Scenario.load(from: Self.defaultURL).configuration
        let group = try #require(configuration.groups.first { $0.name == "Company budget" })
        #expect(group.icon == "solid:building")
        #expect(group.period == .monthly)
        let providers = configuration.members(of: group.id).compactMap { $0.kind.tokenBased?.provider }
        #expect(Set(providers) == [.vertex, .openai])
        #expect(configuration.subscriptionAccounts.count == 1)
        #expect(configuration.codexSubscriptionAccounts.count == 1)
    }
}
