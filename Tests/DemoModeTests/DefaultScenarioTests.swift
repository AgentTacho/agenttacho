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
        // The `glance` shot shows the first Claude Max account's 7-day row
        // with its orange note, and the published shots show the default
        // relative times (spec 025 FR-035, clarification, spec 031 FR-006).
        #expect(report.attentionRows.contains(.claude("acc-max", .sevenDay)), "attention rows \(report.attentionRows)")
        #expect(report.absoluteTimeOwners.isEmpty, "absolute times \(report.absoluteTimeOwners)")
        #expect(scenario.configuration.groups.contains { scenario.configuration.members(of: $0.id).count >= 2 })
        // The `harnesses` shot shows the group's details; the budget section
        // keeps its two member lines and "Show account details" button
        // (spec 026 FR-007).
        let company = try #require(report.memberDisplays["Company budget"])
        #expect(company.lines.count == 2, "member lines \(company.lines)")
        #expect(company.showsAccountsButton)
        // The `menubar` and `glance` shots show the first Claude Max entry on
        // its 5-hour window with the tag; the second Claude Max account and
        // ChatGPT Plus keep their defaults (spec 027 FR-015, spec 031 FR-006).
        #expect(report.barTags == ["acc-max": "5h"], "bar tags \(report.barTags)")
        #expect(report.barValues["acc-max"] == "58%", "bar values \(report.barValues)")
        #expect(report.headlineRows == ["acc-max": "5-hour", "acc-max-personal": "7-day", "acc-codex": "weekly"],
                "headline rows \(report.headlineRows)")
        // The `menubar` shot shows a threshold-driven red: the Side project
        // budget is critical at its second threshold, below 100%, in the bar
        // and in the dropdown (spec 030 FR-020).
        #expect(report.thresholdCriticalRows.contains(.accountBudget("acc-side")), "critical rows \(report.thresholdCriticalRows)")
        #expect(report.thresholdCriticalEntries.contains("acc-side"), "critical entries \(report.thresholdCriticalEntries)")
    }

    /// The `menubar` and `menubar-settings` shots show the pill level color:
    /// the critical Side project entry on its red background (spec 031
    /// FR-005a).
    @Test func defaultScenarioUsesPills() throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        #expect(scenario.configuration.levelColor == .pill)
    }

    /// The `same-provider` shot shows two Claude Max accounts on the Claude
    /// Code harness with their own directories and names, side by side in
    /// the bar and the dropdown; the `glance` shot shows the first one's
    /// details. The second reads calm: normal level, below its thresholds,
    /// no pace note, each window at least 15 points from the first's
    /// (spec 031 FR-001 to FR-007).
    /// The first Claude Max section shows two gift glyphs for the `glance`
    /// shot: one ticket that expires within 3 days and one without expiry
    /// (spec 033 FR-021).
    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioShowsResetTickets(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        #expect(report.resetTicketsWithExpiry)
        #expect(report.resetTicketsWithoutExpiry)
        let first = try #require(BarLayout.shotClaudeAccountIds(configuration: scenario.configuration).first)
        let tickets = report.snapshot.subscriptions[first]?.resetTickets ?? []
        let glyphs = tickets.glyphs(at: report.snapshot.generatedAt)
        #expect(glyphs.shown.count == 2)
        #expect(glyphs.overflow.isEmpty)
        let expiry = try #require(glyphs.shown.first?.expiresAt)
        #expect(expiry.timeIntervalSince(report.snapshot.generatedAt) < 3 * 86400)
        #expect(glyphs.shown.last?.expiresAt == nil)
    }

    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioHasTwoClaudeMaxAccounts(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        let configuration = scenario.configuration
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        let claude = configuration.accounts.filter { $0.kind.isSubscription && $0.harness == .claudeCode }
        #expect(claude.count == 2)
        #expect(Set(claude.compactMap(\.kind.subscription?.credentialDirectory)).count == 2)
        #expect(claude.map(\.displayName) == ["Claude Max \u{00B7} Work", "Claude Max \u{00B7} Personal"])
        #expect(BarLayout.shotClaudeAccountIds(configuration: configuration) == ["acc-max", "acc-max-personal"])

        let arranged = configuration.arrangedEntries.map(\.id)
        let first = try #require(arranged.firstIndex(of: "account:acc-max"))
        #expect(arranged.firstIndex(of: "account:acc-max-personal") == first + 1, "arrangement \(arranged)")
        let segments = BarLayout.segments(snapshot: report.snapshot, configuration: configuration)
        let bar = segments.map(\.id)
        let firstItem = try #require(bar.firstIndex(of: "acc-max"))
        #expect(bar.firstIndex(of: "acc-max-personal") == firstItem + 1, "bar \(bar)")

        for id in ["acc-max", "acc-max-personal"] {
            #expect(report.snapshot.subscriptions[id]?.breakdown.isEmpty == false, "breakdown of \(id)")
        }
        let personal = try #require(segments.first { $0.id == "acc-max-personal" })
        #expect(personal.level == .normal)
        let now = report.snapshot.generatedAt
        let work = try #require(report.snapshot.subscriptions["acc-max"]?.status?.effective(now: now))
        let second = try #require(report.snapshot.subscriptions["acc-max-personal"]?.status?.effective(now: now))
        let pairs = [(work.fiveHour, second.fiveHour), (work.sevenDay, second.sevenDay)]
        for (workWindow, secondWindow) in pairs {
            let used = try #require(secondWindow?.utilizationPercent)
            let workUsed = try #require(workWindow?.utilizationPercent)
            #expect(used < 80, "second account at \(used)%")
            #expect(abs(workUsed - used) >= 15, "work \(workUsed)%, personal \(used)%")
        }
        // On pace, within the band either side of even use, so no note.
        let raw = try #require(report.snapshot.subscriptions["acc-max-personal"]?.status)
        for pace in [raw.fiveHourPace(now: now), raw.sevenDayPace(now: now)] {
            #expect(pace?.status == .onPace, "pace \(String(describing: pace?.status))")
        }
        let calm = report.attentionRows.allSatisfy { key in
            if case .claude("acc-max-personal", _) = key { return false }
            return true
        }
        #expect(calm, "attention rows \(report.attentionRows)")
    }

    /// A budget above 100% after the last frame stays available in a demo
    /// scenario, for the remaining-mode check of a negative value (spec 030
    /// FR-020, US3).
    @Test(arguments: DemoSourcesTests.launches)
    func someScenarioHasABudgetAboveHundred(launch: Date) async throws {
        var percents: [Int] = []
        for url in [Self.defaultURL, Self.variantsURL] {
            let scenario = try Scenario.load(from: url)
            let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
            percents += report.snapshot.groups.values.map(\.percent) + report.snapshot.accountBudgets.values.map(\.percent)
        }
        #expect(percents.contains { $0 > 100 }, "budget percents \(percents)")
    }

    /// The dropdown alternates plain and tinted bands over its five
    /// sections, Max Work, Max Personal, Codex, the Company budget and Side,
    /// so the two Claude Max sections of the `same-provider` shot read as
    /// two (spec 028 FR-012, spec 031 FR-009). A demo scenario cannot have
    /// Unassigned usage (every usage record names a configured account), so
    /// the sequence is pinned to the five entries; the Unassigned stripe is
    /// covered by `SectionBandsTests`.
    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioAlternatesSectionBands(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        #expect(report.snapshot.unassigned.breakdown.isEmpty)
        #expect(report.sectionStripes == [.plain, .tinted, .plain, .tinted, .plain], "stripes \(report.sectionStripes)")
    }

    /// The demo build runs with the default theme, so the capture's
    /// appearance switch decides the panel, and the default scenario shows
    /// orange and red text, the colors the light shots rely on (spec 032
    /// FR-014).
    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioShowsWarningAndErrorTextUnderAuto(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        #expect(scenario.configuration.dropdownTheme == .auto)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        #expect(!report.attentionRows.isEmpty, "attention rows \(report.attentionRows)")
        #expect(!report.thresholdCriticalRows.isEmpty, "critical rows \(report.thresholdCriticalRows)")
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
        // A one-member group has no member line and no "Show account details"
        // (spec 026 FR-007, spec 025 FR-010).
        let display = try #require(report.memberDisplays[group.name])
        #expect(display.lines.isEmpty)
        #expect(!display.showsAccountsButton)
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

    /// The `harnesses` shot crops the breakdown of the budget
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
        #expect(configuration.subscriptionAccounts.count == 2)
        #expect(configuration.codexSubscriptionAccounts.count == 1)
    }
}
