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
        // The bar holds four entries: the Company budget stays out of it so
        // the `menubar` shot fits a phone screen and its 86% does not sit
        // next to the Side project's 87% (maintainer request, 2026-10-22).
        // The warning level shows in the dropdown, on the Company budget.
        #expect(report.barValues.count == 4, "bar values \(report.barValues)")
        #expect(report.barValues["grp-company"] == nil, "bar values \(report.barValues)")
        #expect(report.levels.isSuperset(of: [.normal, .critical]), "levels \(report.levels)")
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
        // keeps its member lines and "Show account details" button (spec 026
        // FR-007). Since spec 037 the Vertex usage of Claude Code and of
        // OpenCode has one account each, so there are three lines (plan
        // "Screenshots and website").
        let company = try #require(report.memberDisplays["Company budget"])
        #expect(company.lines.count == 3, "member lines \(company.lines)")
        #expect(company.showsAccountsButton)
        // The `menubar` and `glance` shots show the first Claude Max entry on
        // its Fable limit with the tag; the second Claude Max account and
        // ChatGPT Plus keep their defaults (spec 027 FR-015, spec 031 FR-006,
        // spec 040 FR-020).
        #expect(report.barTags == ["acc-max": "Fable"], "bar tags \(report.barTags)")
        #expect(report.barValues["acc-max"] == "50%", "bar values \(report.barValues)")
        #expect(report.headlineRows == ["acc-max": "Fable", "acc-max-personal": "7-day", "acc-codex": "weekly"],
                "headline rows \(report.headlineRows)")
        // spec 040 FR-006, FR-020: the Claude accounts report no 5-hour
        // window, so their sections show no 5-hour row. Both Max accounts
        // report a Fable limit, so the `same-provider` crop of the two
        // sections keeps an aspect within 4:3 (spec 040 FR-021).
        #expect(report.claudeRows == ["acc-max": ["7-day", "Fable"], "acc-max-personal": ["7-day", "Fable"]],
                "claude rows \(report.claudeRows)")
        #expect(report.claudeRows.values.allSatisfy { !$0.contains("5-hour") })
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
        let used = try #require(second.window(.sevenDay)?.utilizationPercent)
        let workUsed = try #require(work.window(.sevenDay)?.utilizationPercent)
        #expect(used < 80, "second account at \(used)%")
        #expect(abs(workUsed - used) >= 15, "work \(workUsed)%, personal \(used)%")
        // On pace, within the band either side of even use, so no note.
        let raw = try #require(report.snapshot.subscriptions["acc-max-personal"]?.status)
        for pace in raw.planWindows.map({ raw.pace(of: $0, now: now) }) {
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

    /// The dropdown alternates plain and tinted bands over its six
    /// sections, Max Work, Max Personal, Codex, the Company budget, Side and
    /// Free models (spec 041), so the two Claude Max sections of the
    /// `same-provider` shot read as two (spec 028 FR-012, spec 031 FR-009).
    /// A demo scenario cannot have Unassigned usage (every usage record
    /// names a configured account), so the sequence is pinned to the six
    /// entries; the Unassigned stripe is covered by `SectionBandsTests`.
    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioAlternatesSectionBands(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        #expect(report.snapshot.unassigned.breakdown.isEmpty)
        #expect(report.sectionStripes == [.plain, .tinted, .plain, .tinted, .plain, .tinted], "stripes \(report.sectionStripes)")
    }

    /// Spec 041 FR-022: the No limit account `acc-free` shows a token
    /// headline and a value line, and has no menu bar entry; the bar keeps
    /// its four entries.
    @Test(arguments: DemoSourcesTests.launches)
    func defaultScenarioShowsANoLimitAccount(launch: Date) async throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        #expect(scenario.configuration.account(id: "acc-free")?.kind.tokenBased?.noLimit?.period == .monthly)
        let report = try await ScenarioCoverage.evaluate(scenario: scenario, launch: launch, calendar: Self.utc)
        let section = try #require(report.noLimitSections["acc-free"])
        let headline = try #require(section.headline)
        #expect(headline.hasSuffix("M"), "headline \(headline)")
        let value = try #require(section.valueLine)
        #expect(value.hasPrefix("\u{2248} $") && value.hasSuffix(" at claude-opus-5-5 prices"), "value \(value)")
        #expect(section.notes.isEmpty, "notes \(section.notes)")
        #expect(report.barValues["acc-free"] == nil, "bar values \(report.barValues)")
        #expect(report.barValues.count == 4, "bar values \(report.barValues)")
        #expect(report.snapshot.accountBudgets["acc-free"] == nil)
        #expect(!report.incompleteOwners.contains("acc-free"))
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

    /// spec 037 FR-008, FR-019: every usage entry's harness is its
    /// account's harness, and every token account names its harness and
    /// session kind, so the scenario loads without a migration note.
    @Test func everyUsageEntryMatchesItsAccountsHarness() throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        #expect(ScenarioCoverage.harnessMismatches(scenario).isEmpty)
        let text = try String(contentsOf: Self.defaultURL, encoding: .utf8)
        #expect(!text.contains("\"provider\""))
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        _ = try decoder.decode(Scenario.self, from: Data(text.utf8))
        #expect(notes.notes.isEmpty)
        #expect(scenario.configuration.account(id: "acc-side")?.kind.tokenBased?.sessionKind == .openCodeOpenAI)
    }

    /// spec 038 FR-010, plan "Screenshots and website": the four token-based
    /// accounts store their session kinds, and the scenario has no
    /// `matchRule` left.
    @Test func tokenBasedAccountsUseSessionKinds() throws {
        let scenario = try Scenario.load(from: Self.defaultURL)
        func kind(_ id: String) -> SessionKind? { scenario.configuration.account(id: id)?.kind.tokenBased?.sessionKind }
        #expect(kind("acc-vertex") == .claudeCodeVertex)
        #expect(kind("acc-vertex-opencode") == .openCodeVertex)
        #expect(kind("acc-openai-company") == .codexAPIKey)
        #expect(kind("acc-side") == .openCodeOpenAI)
        #expect(kind("acc-free") == .claudeCodeOtherProvider)
        let text = try String(contentsOf: Self.defaultURL, encoding: .utf8)
        #expect(!text.contains("matchRule"))
    }

    /// The coverage check itself finds a usage entry whose harness is not
    /// its account's, so the check above is not empty by construction.
    @Test func harnessMismatchesFindsAWrongHarness() throws {
        let text = try String(contentsOf: Self.defaultURL, encoding: .utf8)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        var usage = try #require(json["usage"] as? [[String: Any]])
        let first = try #require(usage.first)
        let account = try #require(first["account"] as? String)
        let harness = try #require((first["harness"] as? String).flatMap(Harness.init(rawValue:)))
        let other = try #require(Harness.allCases.first { $0 != harness })
        usage[0]["harness"] = other.rawValue
        json["usage"] = usage
        let scenario = try JSONDecoder().decode(Scenario.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(ScenarioCoverage.harnessMismatches(scenario) == ["\(account): \(other.rawValue)"])
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
        // One account per harness since spec 037: Vertex from Claude Code
        // and from OpenCode, and the OpenAI API from Codex (FR-019).
        let harnesses = configuration.members(of: group.id).compactMap { $0.kind.tokenBased?.harness }
        #expect(harnesses == [.claudeCode, .openCode, .codex])
        #expect(configuration.members(of: group.id).map(\.id) == ["acc-vertex", "acc-vertex-opencode", "acc-openai-company"])
        #expect(configuration.subscriptionAccounts.count == 2)
        #expect(configuration.codexSubscriptionAccounts.count == 1)
    }
}
