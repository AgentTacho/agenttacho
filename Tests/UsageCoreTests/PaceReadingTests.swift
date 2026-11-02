import Foundation
import Testing
@testable import UsageCore

/// spec 025 FR-030, research R1: one value carries a row's pace and burn
/// rate, resolved from the same inputs as the per-entry pace accessors and
/// `burnRate(for:)`.
@Suite struct PaceReadingTests {
    typealias Fixture = SnapshotBurnRateTests
    static let now = Fixture.now
    static let fetched = Fixture.fetched
    static let hour = Fixture.hour
    static let week = Fixture.week

    @Test func claudeWindowsMatchTheStatusAccessors() throws {
        let fiveReset = Self.fetched.addingTimeInterval(2.5 * Self.hour)
        let weekReset = Self.fetched.addingTimeInterval(4 * 24 * Self.hour)
        let limit = ClaudeLimit.model("Fable", 30, resetsAt: weekReset)
        let status = SubscriptionStatus(windows: [ClaudeLimit.fiveHour(70, resetsAt: fiveReset),
                                                  ClaudeLimit.sevenDay(62, resetsAt: weekReset)] + [limit],
                                        fetchedAt: Self.fetched)
        let snapshot = Fixture.claude(status)

        let five = try #require(snapshot.paceReading(for: .claude("c", .fiveHour)))
        #expect(five.pace == status.pace(of: try #require(status.window(.fiveHour)), now: Self.now))
        #expect(five.burn == snapshot.burnRate(for: .claude("c", .fiveHour)))
        let seven = try #require(snapshot.paceReading(for: .claude("c", .sevenDay)))
        #expect(seven.pace == status.pace(of: try #require(status.window(.sevenDay)), now: Self.now))
        #expect(seven.burn == snapshot.burnRate(for: .claude("c", .sevenDay)))
        #expect(seven.burn != nil)
        let model = try #require(snapshot.paceReading(for: .claude("c", .model("Fable"))))
        #expect(model.pace == status.pace(of: try #require(status.window(limit.identity)), now: Self.now))
        #expect(model.burn == snapshot.burnRate(for: .claude("c", .model("Fable"))))
    }

    @Test func codexWindowMatchesTheEntryAccessor() throws {
        let observed = Self.now.addingTimeInterval(-600)
        let entry = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: observed, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 50, resetsAt: Self.now.addingTimeInterval(4 * Self.hour)),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 40, resetsAt: Self.now.addingTimeInterval(72 * Self.hour)),
        ]), state: .live)
        let snapshot = Fixture.snapshot(codexLimits: ["x": entry])
        for window in entry.windows(now: Self.now) {
            let reading = try #require(snapshot.paceReading(for: .codex("x", window.name)))
            #expect(reading.pace == entry.pace(of: window, now: Self.now))
            #expect(reading.burn == snapshot.burnRate(for: .codex("x", window.name)))
        }
    }

    @Test func budgetsMatchTheEntryAccessor() throws {
        let group = GroupEntry(spentUSD: 40, budgetUSD: 100, percent: 40, incomplete: false, window: Fixture.window,
                               breakdown: .empty, members: ["a"])
        let own = GroupEntry(spentUSD: 62, budgetUSD: 100, percent: 62, incomplete: false, window: Fixture.window,
                             breakdown: .empty, members: ["b"])
        let snapshot = Fixture.snapshot(groups: ["g": group], accountBudgets: ["b": own])
        let g = try #require(snapshot.paceReading(for: .group("g")))
        #expect(g.pace == group.pace(now: Self.now))
        #expect(g.burn == snapshot.burnRate(for: .group("g")))
        let b = try #require(snapshot.paceReading(for: .accountBudget("b")))
        #expect(b.pace == own.pace(now: Self.now))
        #expect(b.burn == snapshot.burnRate(for: .accountBudget("b")))
    }

    /// No pace, no reading (spec 011 FR-007): a window that has not
    /// started, one at 100%, one reset at the snapshot time, a reached Codex
    /// limit, an empty group and unknown keys.
    @Test func nilWithoutAPace() {
        let status = SubscriptionStatus(windows: [ClaudeLimit.fiveHour(0, resetsAt: nil),
                                                  ClaudeLimit.sevenDay(100, resetsAt: Self.now.addingTimeInterval(Self.hour)),
                                                  ClaudeLimit.model("Fable", 40, resetsAt: Self.now)],
                                        fetchedAt: Self.fetched)
        let claude = Fixture.claude(status)
        #expect(claude.paceReading(for: .claude("c", .fiveHour)) == nil)
        #expect(claude.paceReading(for: .claude("c", .sevenDay)) == nil)
        #expect(claude.paceReading(for: .claude("c", .model("Fable"))) == nil)
        #expect(claude.paceReading(for: .claude("other", .sevenDay)) == nil)

        let reached = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: Self.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 10, resetsAt: Self.now.addingTimeInterval(Self.hour), limitReached: true),
        ]), state: .live)
        let codex = Fixture.snapshot(codexLimits: ["x": reached])
        #expect(codex.paceReading(for: .codex("x", "5-hour")) == nil)
        #expect(codex.paceReading(for: .codex("x", "weekly")) == nil)

        let empty = GroupEntry(spentUSD: 0, budgetUSD: 100, percent: 0, incomplete: false, window: Fixture.window,
                               breakdown: .empty, members: [])
        let budgets = Fixture.snapshot(groups: ["e": empty])
        #expect(budgets.paceReading(for: .group("e")) == nil)
        #expect(budgets.paceReading(for: .group("z")) == nil)
        #expect(budgets.paceReading(for: .accountBudget("e")) == nil)
    }

    /// A budget at 0% spend has a pace (spec 025 edge cases).
    @Test func budgetAtZeroSpendHasAReading() throws {
        let group = GroupEntry(spentUSD: 0, budgetUSD: 100, percent: 0, incomplete: false, window: Fixture.window,
                               breakdown: .empty, members: ["a"])
        let reading = try #require(Fixture.snapshot(groups: ["g": group]).paceReading(for: .group("g")))
        #expect(reading.pace.runOut == nil)
    }

    @Test func callsForAttention() {
        let runOut = Self.now.addingTimeInterval(10 * Self.hour)
        let ahead = Pace(expectedPercent: 40, delta: 15, status: .ahead(15), runOut: runOut)
        let onPace = Pace(expectedPercent: 40, delta: 2, status: .onPace, runOut: nil)
        let fast = BurnRate(sustainablePerHour: 1, averagePerHour: 1, recentPerHour: 3, fastRunOut: runOut)
        let calm = BurnRate(sustainablePerHour: 1, averagePerHour: 1, recentPerHour: nil, fastRunOut: nil)
        #expect(PaceReading(pace: ahead, burn: nil).callsForAttention)
        #expect(PaceReading(pace: ahead, burn: calm).callsForAttention)
        #expect(PaceReading(pace: onPace, burn: fast).callsForAttention)
        #expect(!PaceReading(pace: onPace, burn: calm).callsForAttention)
        #expect(!PaceReading(pace: onPace, burn: nil).callsForAttention)
        #expect(!PaceReading(pace: Pace(expectedPercent: 40, delta: -20, status: .behind(20), runOut: nil), burn: nil).callsForAttention)
    }

    /// `paceKeys` lists every key that may have a pace, and the readings of
    /// the keys agree with `burnRate(for:)`.
    @Test func paceKeysCoverEveryRow() {
        let reset = Self.fetched.addingTimeInterval(4 * 24 * Self.hour)
        let status = SubscriptionStatus(windows: [ClaudeLimit.fiveHour(10, resetsAt: Self.fetched.addingTimeInterval(Self.hour)),
                                                  ClaudeLimit.sevenDay(62, resetsAt: reset), ClaudeLimit.model("Fable", 30, resetsAt: reset)],
                                        fetchedAt: Self.fetched)
        let group = GroupEntry(spentUSD: 40, budgetUSD: 100, percent: 40, incomplete: false, window: Fixture.window,
                               breakdown: .empty, members: ["a"])
        let snapshot = Fixture.snapshot(subscriptions: ["c": SubscriptionEntry(status: status, state: .ok)],
                                        groups: ["g": group], accountBudgets: ["b": group])
        #expect(Set(snapshot.paceKeys) == [.claude("c", .fiveHour), .claude("c", .sevenDay), .claude("c", .model("Fable")),
                                           .group("g"), .accountBudget("b")])
        for key in snapshot.paceKeys {
            #expect(snapshot.paceReading(for: key)?.burn == snapshot.burnRate(for: key))
        }
    }

    /// spec 040 FR-007: keys come from the windows the status contains; a
    /// window without a length has no key and no reading.
    @Test func paceKeysFollowTheWindowList() {
        let reset = Self.fetched.addingTimeInterval(4 * 24 * Self.hour)
        let daily = ClaudeLimit(identity: ClaudeWindow(rawValue: "limit:daily_all"), kind: "daily_all", group: "daily", length: nil,
                                name: "daily", modelName: nil, allowancePercentOfWeekly: nil, utilizationPercent: 40, resetsAt: reset)
        let status = SubscriptionStatus(windows: [.sevenDay(62, resetsAt: reset), daily, .model("Fable", 30, resetsAt: reset)],
                                        fetchedAt: Self.fetched)
        let snapshot = Fixture.claude(status)
        #expect(Set(snapshot.paceKeys) == [.claude("c", .sevenDay), .claude("c", .model("Fable"))])
        #expect(snapshot.paceReading(for: .claude("c", daily.identity)) == nil)
        #expect(snapshot.paceReading(for: .claude("c", .fiveHour)) == nil)
        #expect(snapshot.paceReading(for: .claude("c", .model("Fable"))) != nil)
    }
}
