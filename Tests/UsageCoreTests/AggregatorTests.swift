import Foundation
import Testing
@testable import UsageCore

@Suite struct AggregatorTests {
    let aggregator = Aggregator()
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "acc-max", label: "M", displayName: "Claude Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: [80]))),
            Account(id: "acc-v1", label: "V1", displayName: "Vertex one", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
            Account(id: "acc-v2", label: "V2", displayName: "Vertex two", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
        ]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex weekly", label: "V", weeklyBudgetUSD: 60, shownInBar: true, thresholds: [80, 100])]
        return c
    }

    func aggregate(_ records: [UsageRecord], subscriptions: [String: SubscriptionEntry] = [:], config: Configuration? = nil) -> UsageSnapshot {
        aggregator.aggregate(records: records, subscriptions: subscriptions, configuration: config ?? self.config(),
                             window: window, windowSource: .fallback, now: now, calendar: utc)
    }

    @Test func groupTotalSumsMemberAccounts() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1000, output: 100, cost: 10),
            makeRecord(id: "b", accountId: "acc-v2", input: 2000, output: 200, cost: 20),
            makeRecord(id: "c", accountId: "acc-v2", model: "claude-sonnet-4-6", input: 5, cost: Decimal(string: "0.5")!),
        ])
        let group = snapshot.groups["grp"]
        #expect(group?.spentUSD == Decimal(string: "30.5"))
        #expect(group?.budgetUSD == 60)
        #expect(group?.percent == 51)
        #expect(group?.incomplete == false)
        #expect(group?.resetAt == window.end)
        #expect(group?.members == ["acc-v1", "acc-v2"])
        #expect(group?.stale == false)
        #expect(snapshot.tokenAccounts["acc-v1"]?.breakdown.pricedCostUSD == 10)
        #expect(snapshot.tokenAccounts["acc-v2"]?.breakdown.pricedCostUSD == Decimal(string: "20.5"))
        #expect(snapshot.tokenAccounts["acc-v2"]?.breakdown.perModel.count == 2)
        #expect(group?.breakdown.perModel.map(\.model) == ["claude-opus-5-5", "claude-sonnet-4-6"])
        #expect(snapshot.window == window)
        #expect(snapshot.generatedAt == now)
    }

    @Test func percentIsRoundedAndUncapped() {
        let half = aggregate([makeRecord(id: "a", accountId: "acc-v1", cost: Decimal(string: "29.9")!)])
        #expect(half.groups["grp"]?.percent == 50)
        let low = aggregate([makeRecord(id: "a", accountId: "acc-v1", cost: Decimal(string: "29.69")!)])
        #expect(low.groups["grp"]?.percent == 49)
        let over = aggregate([makeRecord(id: "a", accountId: "acc-v1", cost: 78)])
        #expect(over.groups["grp"]?.percent == 130)
        let none = aggregate([])
        #expect(none.groups["grp"]?.percent == 0)
        #expect(none.groups["grp"]?.spentUSD == 0)
        // Exactly half a percent rounds away from zero (FR-009a).
        let upperHalf = aggregate([makeRecord(id: "a", accountId: "acc-v1", cost: Decimal(string: "30.3")!)])   // 50.5%
        #expect(upperHalf.groups["grp"]?.percent == 51)
        let lowerHalf = aggregate([makeRecord(id: "a", accountId: "acc-v1", cost: Decimal(string: "29.7")!)])   // 49.5%
        #expect(lowerHalf.groups["grp"]?.percent == 50)
    }

    @Test func percentFormatterRoundsHalfAwayFromZero() {
        #expect(PercentFormatter.rounded(79.5) == 80)
        #expect(PercentFormatter.rounded(80.5) == 81)
        #expect(PercentFormatter.rounded(79.49) == 79)
        #expect(PercentFormatter.rounded(0.5) == 1)
        #expect(PercentFormatter.rounded(130.4) == 130)
        #expect(PercentFormatter.rounded(.nan) == 0)
        #expect(PercentFormatter.rounded(.infinity) == 0)
        #expect(PercentFormatter.rounded(spent: 1, budget: 0) == 0)
        #expect(PercentFormatter.text(nil) == "--")
        #expect(PercentFormatter.text(42) == "42%")
    }

    @Test func perModelAndPerDayTotalsCoverEveryTokenClass() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1, output: 2, cw5m: 3, cw1h: 4, cr: 5, cost: 1),
            makeRecord(id: "b", accountId: "acc-v1", input: 10, output: 20, cw5m: 30, cw1h: 40, cr: 50, cost: 2),
        ])
        let breakdown = snapshot.groups["grp"]!.breakdown
        let row = breakdown.perModel.first
        #expect(breakdown.perModel.count == 1)
        #expect(row?.inputTokens == 11)
        #expect(row?.outputTokens == 22)
        #expect(row?.cacheWrite5mTokens == 33)
        #expect(row?.cacheWrite1hTokens == 44)
        #expect(row?.cacheReadTokens == 55)
        #expect(row?.cacheWriteTokens == 77)
        #expect(row?.totalTokens == 165)
        let day = breakdown.perDay.first
        #expect(day?.inputTokens == 11)
        #expect(day?.outputTokens == 22)
        #expect(day?.cacheWriteTokens == 77)
        #expect(day?.cacheReadTokens == 55)
        #expect(day?.totalTokens == 165)
        #expect(day?.costUSD == 3)
    }

    @Test func unpricedModelFlagsTotalIncomplete() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", cost: 10),
            makeRecord(id: "b", accountId: "acc-v1", model: "claude-mystery-9", input: 500, output: 20, cost: nil),
        ])
        let group = snapshot.groups["grp"]
        #expect(group?.incomplete == true)
        #expect(group?.spentUSD == 10)
        #expect(group?.breakdown.unpricedModels == ["claude-mystery-9"])
        let unpriced = group?.breakdown.perModel.first { $0.model == "claude-mystery-9" }
        #expect(unpriced?.priced == false)
        #expect(unpriced?.costUSD == nil)
        #expect(unpriced?.inputTokens == 500)
        #expect(snapshot.tokenAccounts["acc-v1"]?.incomplete == true)
    }

    @Test func unassignedIsSeparateAndTokensOnly() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", cost: 10),
            makeRecord(id: "b", accountId: nil, input: 300, output: 30, cost: 5),
            makeRecord(id: "c", accountId: "acc-removed", input: 700, output: 70, cost: 5),
        ])
        #expect(snapshot.groups["grp"]?.spentUSD == 10)
        #expect(snapshot.unassigned.breakdown.inputTokens == 1000)
        #expect(snapshot.unassigned.breakdown.outputTokens == 100)
        #expect(snapshot.unassigned.breakdown.perModel.allSatisfy { $0.costUSD == nil })
        #expect(snapshot.unassigned.incomplete == false)
    }

    @Test func recordsOutsideWindowAreExcluded() {
        let snapshot = aggregate([
            makeRecord(id: "before", accountId: "acc-v1", timestamp: window.start.addingTimeInterval(-1), cost: 100),
            makeRecord(id: "atStart", accountId: "acc-v1", timestamp: window.start, cost: 1),
            makeRecord(id: "inside", accountId: "acc-v1", timestamp: window.start.addingTimeInterval(3600), cost: 2),
            makeRecord(id: "atEnd", accountId: "acc-v1", timestamp: window.end, cost: 100),
            makeRecord(id: "after", accountId: "acc-v1", timestamp: window.end.addingTimeInterval(1), cost: 100),
        ])
        #expect(snapshot.groups["grp"]?.spentUSD == 3)
    }

    // MARK: Per-day trend (T054)

    @Test func perModelRowsSumToGroupTotal() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", model: "claude-opus-5-5", input: 100, cost: Decimal(string: "1.25")!),
            makeRecord(id: "b", accountId: "acc-v2", model: "claude-opus-5-5", input: 100, cost: Decimal(string: "2.5")!),
            makeRecord(id: "c", accountId: "acc-v2", model: "claude-sonnet-4-6", input: 100, cost: Decimal(string: "0.75")!),
        ])
        let group = snapshot.groups["grp"]!
        let rowSum = group.breakdown.perModel.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) }
        #expect(rowSum == group.spentUSD)
        #expect(group.breakdown.perModel.map(\.costUSD) == [Decimal(string: "3.75"), Decimal(string: "0.75")])
        let daySum = group.breakdown.perDay.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) }
        #expect(daySum == group.spentUSD)
    }

    @Test func perDayHasOneZeroFilledEntryPerLocalCalendarDay() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", timestamp: isoDate("2026-10-12T10:00:00Z"), input: 10, cost: 1),
            makeRecord(id: "b", accountId: "acc-v1", timestamp: isoDate("2026-10-12T23:00:00Z"), input: 20, cost: 2),
            makeRecord(id: "c", accountId: "acc-v1", timestamp: isoDate("2026-10-15T08:00:00Z"), input: 30, cost: 4),
        ])
        let days = snapshot.groups["grp"]!.breakdown.perDay
        #expect(days.count == 7)
        #expect(days.map(\.day) == (0..<7).map { utc.date(byAdding: .day, value: $0, to: window.start)! })
        #expect(days.map { $0.costUSD ?? -1 } == [3, 0, 0, 4, 0, 0, 0])
        #expect(days.map(\.inputTokens) == [30, 0, 0, 30, 0, 0, 0])
    }

    @Test func windowStartingMidDayCoversEightCalendarDays() {
        let aligned = DateInterval(start: isoDate("2026-10-09T07:00:00Z"), end: isoDate("2026-10-16T07:00:00Z"))
        let snapshot = aggregator.aggregate(records: [makeRecord(id: "a", accountId: "acc-v1", timestamp: isoDate("2026-10-16T06:59:59Z"), cost: 1)],
                                            subscriptions: [:], configuration: config(), window: aligned, windowSource: .aligned(accountId: "acc-max"),
                                            now: now, calendar: utc)
        let days = snapshot.groups["grp"]!.breakdown.perDay
        #expect(days.count == 8)
        #expect(days.first?.day == isoDate("2026-10-09T00:00:00Z"))
        #expect(days.last?.day == isoDate("2026-10-16T00:00:00Z"))
        #expect(days.last?.costUSD == 1)

        // A window ending exactly at midnight does not add an empty day.
        let exact = DateInterval(start: isoDate("2026-10-09T00:00:00Z"), end: isoDate("2026-10-16T00:00:00Z"))
        let exactSnapshot = aggregator.aggregate(records: [], subscriptions: [:], configuration: config(), window: exact,
                                                 windowSource: .fallback, now: now, calendar: utc)
        #expect(exactSnapshot.groups["grp"]!.breakdown.perDay.count == 7)
    }

    @Test func dstChangeStillYieldsOneEntryPerCalendarDay() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // Monday 2026-10-19 00:00 CEST to Monday 2026-10-26 00:00 CET (DST ends Oct 25).
        let dst = DateInterval(start: isoDate("2026-10-18T22:00:00Z"), end: isoDate("2026-10-25T23:00:00Z"))
        let snapshot = aggregator.aggregate(records: [makeRecord(id: "a", accountId: "acc-v1", timestamp: isoDate("2026-10-25T10:00:00Z"), cost: 1)],
                                            subscriptions: [:], configuration: config(), window: dst, windowSource: .fallback,
                                            now: isoDate("2026-10-25T12:00:00Z"), calendar: berlin)
        let days = snapshot.groups["grp"]!.breakdown.perDay
        #expect(days.count == 7)
        #expect(days.map(\.day) == (0..<7).map { berlin.date(byAdding: .day, value: $0, to: dst.start)! })
        #expect(days[6].costUSD == 1)
        #expect(days[6].day == isoDate("2026-10-24T22:00:00Z"))
    }

    @Test func subscriptionAndUnassignedTrendsCarryTokensOnly() {
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: nil, fetchedAt: now)
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-max", timestamp: isoDate("2026-10-13T10:00:00Z"), input: 400, cost: 1),
            makeRecord(id: "b", accountId: nil, timestamp: isoDate("2026-10-14T10:00:00Z"), output: 50, cost: 1),
        ], subscriptions: ["acc-max": SubscriptionEntry(status: status, state: .ok)])
        let subDays = snapshot.subscriptions["acc-max"]!.breakdown.perDay
        #expect(subDays.count == 7)
        #expect(subDays[1].inputTokens == 400)
        #expect(subDays.allSatisfy { $0.costUSD == nil })
        let unassignedDays = snapshot.unassigned.breakdown.perDay
        #expect(unassignedDays[2].outputTokens == 50)
        #expect(unassignedDays.allSatisfy { $0.costUSD == nil })
    }

    @Test func subscriptionBreakdownCarriesTokensOnly() {
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: nil, fetchedAt: now)
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-max", input: 400, output: 40, cr: 4000, cost: 1),
        ], subscriptions: ["acc-max": SubscriptionEntry(status: status, state: .ok)])
        let entry = snapshot.subscriptions["acc-max"]
        #expect(entry?.state == .ok)
        #expect(entry?.breakdown.inputTokens == 400)
        #expect(entry?.breakdown.cacheReadTokens == 4000)
        #expect(entry?.breakdown.perModel.first?.costUSD == nil)
        #expect(snapshot.groups["grp"]?.spentUSD == 0)
    }
}
