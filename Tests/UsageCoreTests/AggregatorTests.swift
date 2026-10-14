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
        c.groups = [BudgetGroup(id: "grp", name: "Vertex weekly", label: "V", budgetUSD: 60, shownInBar: true, thresholds: [80, 100])]
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

/// Spec 003: monthly groups are measured over the local calendar month while
/// Unassigned and subscription breakdowns stay on the weekly window
/// (FR-008, FR-009, FR-011, FR-013).
@Suite struct MonthlyAggregatorTests {
    let aggregator = Aggregator()
    /// Weekly window Monday 2026-10-12 to Monday 2026-10-19 (UTC).
    let weekly = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// `grp-m` (monthly, $400) holds acc-v2; `grp-w` (weekly, $60) holds acc-v1.
    func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "acc-max", label: "M", displayName: "Claude Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: []))),
            Account(id: "acc-v1", label: "V1", displayName: "Vertex weekly", kind: .tokenBased(TokenBasedSettings(groupId: "grp-w"))),
            Account(id: "acc-v2", label: "V2", displayName: "Vertex monthly", kind: .tokenBased(TokenBasedSettings(groupId: "grp-m"))),
        ]
        c.groups = [
            BudgetGroup(id: "grp-w", name: "Weekly", label: "W", period: .weekly, budgetUSD: 60),
            BudgetGroup(id: "grp-m", name: "Monthly", label: "MO", period: .monthly, budgetUSD: 400, thresholds: [50, 90]),
        ]
        return c
    }

    func aggregate(_ records: [UsageRecord], subscriptions: [String: SubscriptionEntry] = [:], now: Date? = nil,
                   window: DateInterval? = nil) -> UsageSnapshot {
        aggregator.aggregate(records: records, subscriptions: subscriptions, configuration: config(),
                             window: window ?? weekly, windowSource: .fallback, now: now ?? self.now, calendar: utc)
    }

    /// A weekly window that straddles the 1st: the weekly group, its member
    /// and its trend include the last days of September, the monthly group,
    /// its member and its trend do not (spec US1 scenario 2, FR-008).
    @Test func weekStraddlingTheFirstSplitsBetweenWeeklyAndMonthlyGroups() {
        let straddling = DateInterval(start: isoDate("2026-09-28T00:00:00Z"), end: isoDate("2026-10-05T00:00:00Z"))
        let snapshot = aggregate([
            makeRecord(id: "w-sep", accountId: "acc-v1", timestamp: isoDate("2026-09-29T10:00:00Z"), cost: 6),
            makeRecord(id: "w-oct", accountId: "acc-v1", timestamp: isoDate("2026-10-01T10:00:00Z"), cost: 12),
            makeRecord(id: "m-sep", accountId: "acc-v2", timestamp: isoDate("2026-09-29T10:00:00Z"), cost: 300),
            makeRecord(id: "m-oct", accountId: "acc-v2", timestamp: isoDate("2026-10-01T10:00:00Z"), cost: 40),
        ], now: isoDate("2026-10-02T12:00:00Z"), window: straddling)

        let weeklyGroup = snapshot.groups["grp-w"]!
        #expect(weeklyGroup.window == straddling)
        #expect(weeklyGroup.spentUSD == 18)
        #expect(snapshot.tokenAccounts["acc-v1"]?.breakdown.pricedCostUSD == 18)
        #expect(weeklyGroup.breakdown.perDay.count == 7)
        #expect(weeklyGroup.breakdown.perDay.first?.day == straddling.start)

        let monthlyGroup = snapshot.groups["grp-m"]!
        #expect(monthlyGroup.window == month)
        #expect(monthlyGroup.spentUSD == 40)
        #expect(monthlyGroup.percent == 10)
        #expect(snapshot.tokenAccounts["acc-v2"]?.breakdown.pricedCostUSD == 40)
        #expect(monthlyGroup.breakdown.perDay.map(\.day) == [month.start, isoDate("2026-10-02T00:00:00Z")])
        #expect(snapshot.tokenAccounts["acc-v2"]?.breakdown.perDay.count == 2)
    }

    /// Spec US1 scenarios 1 and 2.
    @Test func monthlyGroupCountsMonthToDateOnly() {
        let snapshot = aggregate([
            makeRecord(id: "prev", accountId: "acc-v2", timestamp: isoDate("2026-09-30T23:59:59Z"), cost: 999),
            makeRecord(id: "first", accountId: "acc-v2", timestamp: month.start, cost: 30),
            makeRecord(id: "early", accountId: "acc-v2", timestamp: isoDate("2026-10-05T10:00:00Z"), cost: 20),
            makeRecord(id: "week", accountId: "acc-v2", timestamp: isoDate("2026-10-13T10:00:00Z"), cost: 50),
        ])
        let group = snapshot.groups["grp-m"]
        #expect(group?.period == .monthly)
        #expect(group?.window == month)
        #expect(group?.resetAt == month.end)
        #expect(group?.spentUSD == 100)
        #expect(group?.budgetUSD == 400)
        #expect(group?.percent == 25)
        #expect(group?.members == ["acc-v2"])
        // The snapshot window still describes the weekly window (research R3).
        #expect(snapshot.window == weekly)
    }

    @Test func monthlyPercentUsesExistingRoundingAndOver100Rules() {
        let below = aggregate([makeRecord(id: "a", accountId: "acc-v2", timestamp: isoDate("2026-10-02T10:00:00Z"), cost: Decimal(string: "401.98")!)])
        #expect(below.groups["grp-m"]?.percent == 100)          // 100.495%
        let half = aggregate([makeRecord(id: "a", accountId: "acc-v2", timestamp: isoDate("2026-10-02T10:00:00Z"), cost: 402)])
        #expect(half.groups["grp-m"]?.percent == 101)           // 100.5% rounds away from zero
        let over = aggregate([makeRecord(id: "a", accountId: "acc-v2", timestamp: isoDate("2026-10-02T10:00:00Z"), cost: 600)])
        #expect(over.groups["grp-m"]?.percent == 150)
    }

    @Test func monthlyGroupWithoutUsageShowsZero() {
        let snapshot = aggregate([makeRecord(id: "prev", accountId: "acc-v2", timestamp: isoDate("2026-09-20T10:00:00Z"), cost: 10)])
        #expect(snapshot.groups["grp-m"]?.spentUSD == 0)
        #expect(snapshot.groups["grp-m"]?.percent == 0)
        #expect(snapshot.groups["grp-m"]?.incomplete == false)
    }

    /// Spec US1 scenario 5: member breakdowns cover the group's own window.
    @Test func memberAccountBreakdownCoversTheMonthlyWindow() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v2", model: "claude-opus-5-5", timestamp: isoDate("2026-10-02T10:00:00Z"), input: 10, cost: 30),
            makeRecord(id: "b", accountId: "acc-v2", model: "claude-sonnet-4-6", timestamp: isoDate("2026-10-13T10:00:00Z"), input: 5, cost: 10),
        ])
        let group = snapshot.groups["grp-m"]!
        let member = snapshot.tokenAccounts["acc-v2"]!.breakdown
        #expect(member.pricedCostUSD == 40)
        #expect(member.inputTokens == 15)
        #expect(member.perModel.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) } == group.spentUSD)
        #expect(member.perDay.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) } == group.spentUSD)
        #expect(group.breakdown.perModel.map(\.model) == ["claude-opus-5-5", "claude-sonnet-4-6"])
    }

    @Test func weeklyAndMonthlyGroupsUseTheirOwnWindows() {
        let snapshot = aggregate([
            makeRecord(id: "w-early", accountId: "acc-v1", timestamp: isoDate("2026-10-05T10:00:00Z"), cost: 25),
            makeRecord(id: "w-week", accountId: "acc-v1", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 6),
            makeRecord(id: "m-early", accountId: "acc-v2", timestamp: isoDate("2026-10-05T10:00:00Z"), cost: 40),
            makeRecord(id: "m-week", accountId: "acc-v2", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 40),
        ])
        let weeklyGroup = snapshot.groups["grp-w"]!
        #expect(weeklyGroup.period == .weekly)
        #expect(weeklyGroup.window == weekly)
        #expect(weeklyGroup.resetAt == weekly.end)
        #expect(weeklyGroup.spentUSD == 6)
        #expect(weeklyGroup.percent == 10)
        #expect(snapshot.tokenAccounts["acc-v1"]?.breakdown.pricedCostUSD == 6)
        #expect(weeklyGroup.breakdown.perDay.count == 7)

        let monthlyGroup = snapshot.groups["grp-m"]!
        #expect(monthlyGroup.spentUSD == 80)
        #expect(monthlyGroup.percent == 20)
        #expect(snapshot.tokenAccounts["acc-v2"]?.breakdown.pricedCostUSD == 80)
    }

    /// FR-009: Unassigned and subscription breakdowns keep the weekly window.
    @Test func unassignedAndSubscriptionsStayOnTheWeeklyWindow() {
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: nil, fetchedAt: now)
        let snapshot = aggregate([
            makeRecord(id: "u-early", accountId: nil, timestamp: isoDate("2026-10-05T10:00:00Z"), input: 1000, cost: 1),
            makeRecord(id: "u-week", accountId: nil, timestamp: isoDate("2026-10-12T10:00:00Z"), input: 7, cost: 1),
            makeRecord(id: "s-early", accountId: "acc-max", timestamp: isoDate("2026-10-05T10:00:00Z"), input: 2000, cost: 1),
            makeRecord(id: "s-week", accountId: "acc-max", timestamp: isoDate("2026-10-12T10:00:00Z"), input: 9, cost: 1),
        ], subscriptions: ["acc-max": SubscriptionEntry(status: status, state: .ok)])
        #expect(snapshot.unassigned.breakdown.inputTokens == 7)
        #expect(snapshot.unassigned.breakdown.perDay.count == 7)
        #expect(snapshot.subscriptions["acc-max"]?.breakdown.inputTokens == 9)
        #expect(snapshot.subscriptions["acc-max"]?.breakdown.perDay.count == 7)
    }

    // MARK: Per-day trend (FR-013, research R6)

    @Test func monthlyTrendRunsFromTheFirstThroughToday() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v2", timestamp: isoDate("2026-10-01T08:00:00Z"), input: 10, cost: 3),
            makeRecord(id: "b", accountId: "acc-v2", timestamp: isoDate("2026-10-13T08:00:00Z"), input: 20, cost: 4),
        ])
        let days = snapshot.groups["grp-m"]!.breakdown.perDay
        #expect(days.count == 13)
        #expect(days.map(\.day) == (0..<13).map { utc.date(byAdding: .day, value: $0, to: month.start)! })
        #expect(days.first?.costUSD == 3)
        #expect(days.last?.costUSD == 4)
        #expect(days.dropFirst().dropLast().allSatisfy { $0.costUSD == 0 && $0.totalTokens == 0 })
        #expect(snapshot.tokenAccounts["acc-v2"]?.breakdown.perDay.count == 13)

        // On the 1st itself the trend has exactly one day.
        let first = aggregate([], now: isoDate("2026-10-01T00:00:00Z"))
        #expect(first.groups["grp-m"]?.breakdown.perDay.map(\.day) == [month.start])
    }

    @Test func weeklyTrendKeepsEveryDayOfTheWindow() {
        let snapshot = aggregate([])
        let days = snapshot.groups["grp-w"]!.breakdown.perDay
        #expect(days.count == 7)
        #expect(days.last?.day == isoDate("2026-10-18T00:00:00Z"))   // after today, zero-filled
    }
}
