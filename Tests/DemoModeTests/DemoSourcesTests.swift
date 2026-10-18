import Foundation
import Testing
@testable import DemoMode
import UsageCore

/// The three demo sources (spec 024 FR-006, FR-010, research R3, R6).
@Suite struct DemoSourcesTests {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// The launch dates the coverage check also uses: the 1st, the 15th
    /// and the last day of a month (research R6).
    static let launches = [date("2026-10-01T09:00:00Z"), date("2026-10-15T09:00:00Z"), date("2026-10-31T09:00:00Z")]

    static func scenario(usage: String? = nil) throws -> Scenario {
        try ScenarioTests.decode(ScenarioTests.json(usage: usage))
    }

    static func context(_ scenario: Scenario, now: Date) -> RefreshContext {
        RefreshContext(configuration: scenario.configuration,
                       window: DateInterval(start: now.addingTimeInterval(-40 * 86_400), end: now.addingTimeInterval(86_400)), now: now)
    }

    static let builtIn = try! PriceTable.builtIn()

    // MARK: Claude plan windows

    @Test func subscriptionSourceReportsPlanWindowsAtRefreshTime() async throws {
        let scenario = try Self.scenario()
        let launch = Self.launches[1]
        let player = ScenarioPlayer(scenario: scenario, launch: launch)
        let now = launch.addingTimeInterval(5)
        let output = try await DemoSubscriptionSource(player: player).collect(context: Self.context(scenario, now: now))
        guard case .subscriptions(let entries) = output else {
            Issue.record("expected subscriptions, got \(output)")
            return
        }
        #expect(Array(entries.keys) == ["acc-max"])
        let entry = try #require(entries["acc-max"])
        #expect(entry.state == .ok)
        let status = try #require(entry.status)
        #expect(status.fetchedAt == now)
        #expect(status.subscriptionType == "max")
        #expect(status.fiveHour == LimitWindow(utilizationPercent: 58, resetsAt: launch.addingTimeInterval(2 * 3600)))
        #expect(status.sevenDay == LimitWindow(utilizationPercent: 70, resetsAt: launch.addingTimeInterval(3.5 * 86_400)))
    }

    // MARK: Codex plan limits

    @Test func codexSourceReportsLiveLimits() async throws {
        let scenario = try Self.scenario()
        let launch = Self.launches[1]
        let player = ScenarioPlayer(scenario: scenario, launch: launch)
        let now = launch.addingTimeInterval(7)
        let output = try await DemoCodexLimitsSource(player: player).collect(context: Self.context(scenario, now: now))
        guard case .codexLimits(let entries) = output else {
            Issue.record("expected Codex limits, got \(output)")
            return
        }
        let entry = try #require(entries["acc-codex"])
        #expect(entry.state == .live)
        let observation = try #require(entry.observation)
        #expect(observation.origin == .live)
        #expect(observation.observedAt == now)
        #expect(observation.planType == "plus")
        #expect(observation.windows.map(\.name) == ["5-hour", "weekly"])
        #expect(observation.windows.map(\.usedPercent) == [40, 60])
        #expect(observation.windows.map(\.resetsAt) == [launch.addingTimeInterval(5400), launch.addingTimeInterval(3.5 * 86_400)])
        #expect(observation.windows.allSatisfy { !$0.limitReached })
    }

    /// Frames reach the plan windows the app sees (FR-012): both sources
    /// report the frame's values from its offset on, the old ones before.
    @Test func planSourcesFollowFrames() async throws {
        let scenario = try ScenarioTests.decode(ScenarioTests.json(frames: """
            [ { "at": "12s", "claude": { "acc-max": { "sevenDay": { "used": 75 } } },
                "codex": { "acc-codex": { "windows": [ { "lengthMinutes": 10080, "used": 66 } ] } } } ]
            """))
        let launch = Self.launches[1]
        let player = ScenarioPlayer(scenario: scenario, launch: launch)
        for (offset, claude, codex) in [(11.0, 70.0, 60.0), (13.0, 75.0, 66.0)] {
            let context = Self.context(scenario, now: launch.addingTimeInterval(offset))
            guard case .subscriptions(let entries) = try await DemoSubscriptionSource(player: player).collect(context: context),
                  case .codexLimits(let limits) = try await DemoCodexLimitsSource(player: player).collect(context: context) else {
                Issue.record("unexpected output")
                return
            }
            #expect(entries["acc-max"]?.status?.sevenDay?.utilizationPercent == claude)
            #expect(limits["acc-codex"]?.observation?.windows.last?.usedPercent == codex)
        }
    }

    @Test func modelLimitsAreReported() async throws {
        let scenario = try ScenarioTests.decode(ScenarioTests.json(claude: """
            { "acc-max": { "plan": "max", "fiveHour": { "used": 58, "resetsIn": "2h" },
                           "sevenDay": { "used": 70, "resetsIn": "3d12h" },
                           "models": { "Fable": { "used": 44, "resetsIn": "2d" } } } }
            """))
        let launch = Self.launches[1]
        let output = try await DemoSubscriptionSource(player: ScenarioPlayer(scenario: scenario, launch: launch))
            .collect(context: Self.context(scenario, now: launch))
        guard case .subscriptions(let entries) = output else {
            Issue.record("expected subscriptions")
            return
        }
        #expect(entries["acc-max"]?.status?.modelLimits == [ModelLimit(modelName: "Fable", utilizationPercent: 44,
                                                                      resetsAt: launch.addingTimeInterval(2 * 86_400))])
    }

    // MARK: Records

    static func records(_ scenario: Scenario, launch: Date, importedPrices: ImportedPrices = .empty) async throws -> [UsageRecord] {
        let player = ScenarioPlayer(scenario: scenario, launch: launch)
        let source = DemoRecordSource(player: player, builtInPrices: builtIn, importedPrices: { importedPrices }, calendar: utc)
        let output = try await source.collect(context: context(scenario, now: launch))
        guard case .records(let records) = output else {
            Issue.record("expected records, got \(output)")
            return []
        }
        return records
    }

    @Test func recordSourceTurnsEntriesIntoPricedRecords() async throws {
        let scenario = try Self.scenario(usage: """
            [ { "at": "-2h", "account": "acc-max", "harness": "claudeCode", "model": "claude-opus-5-5",
                "project": "~/src/checkout-service", "input": 1000000, "output": 100000, "cacheRead": 2000000, "cacheWrite": 400000 },
              { "at": "-1h", "account": "acc-codex", "harness": "codex", "model": "gpt-5-codex",
                "project": "~/src/billing", "input": 10, "output": 20, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        let launch = Self.launches[1]
        let records = try await Self.records(scenario, launch: launch)
        #expect(records.count == 2)
        let first = records[0]
        #expect(first.messageId == "test-0")
        #expect(first.timestamp == launch.addingTimeInterval(-7200))
        #expect(first.accountId == "acc-max")
        #expect(first.harness == .claudeCode)
        #expect(first.model == "claude-opus-5-5")
        #expect(first.canonicalModel == "claude-opus-5-5")
        #expect(first.project?.name == "checkout-service")
        #expect(first.inputTokens == 1_000_000)
        #expect(first.outputTokens == 100_000)
        #expect(first.cacheReadTokens == 2_000_000)
        #expect(first.cacheWrite5mTokens == 400_000)
        #expect(first.cacheWrite1hTokens == 0)
        // 4 + 2 + 0.4 + 2 (input, output, cache read, 5-minute write) from the built-in table.
        #expect(first.costUSD == Decimal(string: "8.4"))
        // A model without any price stays unpriced.
        #expect(records[1].messageId == "test-1")
        #expect(records[1].costUSD == nil)
    }

    @Test func importedPricesPriceTheirModels() async throws {
        let scenario = try Self.scenario(usage: """
            [ { "at": "-1h", "account": "acc-codex", "harness": "codex", "model": "gpt-5-codex",
                "project": "~/src/billing", "input": 1000000, "output": 0, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        let batch = PriceBatch(kind: .openai, origin: "demo", importedAt: Self.launches[0],
                               entries: [PriceEntry(model: "gpt-5-codex", inputPerMTok: 1.25, outputPerMTok: 10, cacheWrite5mPerMTok: 1.25,
                                                    cacheWrite1hPerMTok: 1.25, cacheReadPerMTok: 0.125)])
        let records = try await Self.records(scenario, launch: Self.launches[1], importedPrices: ImportedPrices(batches: [batch]))
        #expect(records.first?.costUSD == Decimal(string: "1.25"))
    }

    @Test func messageIdsAreStableAcrossRefreshes() async throws {
        let scenario = try Self.scenario()
        let first = try await Self.records(scenario, launch: Self.launches[1])
        let second = try await Self.records(scenario, launch: Self.launches[1])
        #expect(first.map(\.messageId) == second.map(\.messageId))
    }

    /// A monthly-budget record before the first of the launch month moves
    /// to the first at the same time of day (research R6).
    @Test func monthlyRecordBeforeTheMonthMovesToItsFirstDay() async throws {
        let scenario = try Self.scenario(usage: """
            [ { "at": "-2d3h", "account": "acc-vertex", "harness": "openCode", "model": "claude-sonnet-5-5",
                "project": "~/src/x", "input": 1, "output": 1, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        let launch = Self.launches[0]
        let records = try await Self.records(scenario, launch: launch)
        // 2026-09-29 06:00 becomes 2026-10-01 06:00.
        #expect(records.first?.timestamp == Self.date("2026-10-01T06:00:00Z"))
    }

    /// A moved record never lands after launch: it goes to the start of the
    /// month instead.
    @Test func movedRecordNeverLandsAfterLaunch() async throws {
        let scenario = try Self.scenario(usage: """
            [ { "at": "-20h", "account": "acc-vertex", "harness": "openCode", "model": "claude-sonnet-5-5",
                "project": "~/src/x", "input": 1, "output": 1, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        let records = try await Self.records(scenario, launch: Self.launches[0])
        #expect(records.first?.timestamp == Self.date("2026-10-01T00:00:00Z"))
    }

    @Test(arguments: [1, 2])
    func monthlyRecordInsideTheMonthStays(launchIndex: Int) async throws {
        let scenario = try Self.scenario(usage: """
            [ { "at": "-2d3h", "account": "acc-vertex", "harness": "openCode", "model": "claude-sonnet-5-5",
                "project": "~/src/x", "input": 1, "output": 1, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        let launch = Self.launches[launchIndex]
        let records = try await Self.records(scenario, launch: launch)
        #expect(records.first?.timestamp == launch.addingTimeInterval(-(2 * 86_400 + 3 * 3600)))
    }

    @Test func recordsOfOtherAccountsNeverMove() async throws {
        let scenario = try Self.scenario(usage: """
            [ { "at": "-2d3h", "account": "acc-max", "harness": "claudeCode", "model": "claude-sonnet-5-5",
                "project": "~/src/x", "input": 1, "output": 1, "cacheRead": 0, "cacheWrite": 0 } ]
            """)
        let launch = Self.launches[0]
        let records = try await Self.records(scenario, launch: launch)
        #expect(records.first?.timestamp == launch.addingTimeInterval(-(2 * 86_400 + 3 * 3600)))
    }
}
