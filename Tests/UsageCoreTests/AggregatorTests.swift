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
            Account(id: "acc-max", displayName: "Claude Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: [80]))),
            Account(id: "acc-v1", displayName: "Vertex one", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
            Account(id: "acc-v2", displayName: "Vertex two", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
        ]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex weekly", budgetUSD: 60, shownInBar: true, thresholds: [80, 100])]
        return c
    }

    func aggregate(_ records: [UsageRecord], subscriptions: [String: SubscriptionEntry] = [:], config: Configuration? = nil) -> UsageSnapshot {
        aggregator.aggregate(records: records, subscriptions: subscriptions, configuration: config ?? self.config(),
                             window: window, windowSource: .fallback, now: now, calendar: utc)
    }

    let agenttacho = Project(rootPath: "/Users/me/work/agenttacho")
    let cfp = Project(rootPath: "/Users/me/work/cfp")

    @Test func perProjectTotalsAndRankingByCost() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1000, cost: 2, project: agenttacho),
            makeRecord(id: "b", accountId: "acc-v1", input: 10, cost: 5, project: cfp),
            makeRecord(id: "c", accountId: "acc-v2", input: 20, cost: 1, project: agenttacho),
            makeRecord(id: "d", accountId: "acc-v2", input: 7, cost: 1, project: nil),
        ])
        let projects = snapshot.groups["grp"]!.breakdown.perProject
        #expect(projects.map(\.displayName) == ["cfp", "agenttacho", "Unknown"])
        #expect(projects.map(\.pricedCostUSD) == [5, 3, 1])
        #expect(projects[1].totalTokens == 1020)
        #expect(projects[1].costUSD == 3)
        #expect(projects.map(\.id) == ["/Users/me/work/cfp", "/Users/me/work/agenttacho", ""])
    }

    @Test func perProjectRanksByTokensWithoutCostAndBreaksTiesByName() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-max", input: 100, cost: nil, project: cfp),
            makeRecord(id: "b", accountId: "acc-max", input: 300, cost: nil, project: agenttacho),
            makeRecord(id: "c", accountId: "acc-max", input: 100, cost: nil, project: Project(rootPath: "/x/beta")),
        ], subscriptions: ["acc-max": SubscriptionEntry(status: nil, state: .ok)])
        let projects = snapshot.subscriptions["acc-max"]!.breakdown.perProject
        #expect(projects.map(\.displayName) == ["agenttacho", "beta", "cfp"])
        #expect(projects.allSatisfy { $0.costUSD == nil && $0.priced })
    }

    @Test func unpricedProjectKeepsItsPricedPartForRanking() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1, cost: 4, project: agenttacho),
            makeRecord(id: "b", accountId: "acc-v1", input: 1, cost: nil, project: agenttacho),
            makeRecord(id: "c", accountId: "acc-v1", input: 1, cost: 3, project: cfp),
        ])
        let projects = snapshot.groups["grp"]!.breakdown.perProject
        #expect(projects.map(\.displayName) == ["agenttacho", "cfp"])
        #expect(projects[0].priced == false)
        #expect(projects[0].costUSD == nil)
        #expect(projects[0].pricedCostUSD == 4)
    }

    @Test func sameFolderNameInDifferentRootsShowsTheParent() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1, cost: 2, project: Project(rootPath: "/Users/me/work/app")),
            makeRecord(id: "b", accountId: "acc-v1", input: 1, cost: 1, project: Project(rootPath: "/Users/me/private/app")),
            makeRecord(id: "c", accountId: "acc-v1", input: 1, cost: 0, project: cfp),
        ])
        let names = snapshot.groups["grp"]!.breakdown.perProject.map(\.displayName)
        #expect(names == ["app (work)", "app (private)", "cfp"])
    }

    private func projects(_ tokens: [Int]) -> UsageBreakdown {
        let records = tokens.enumerated().map { i, t in
            makeRecord(id: "r\(i)", accountId: "acc-max", input: t, cost: nil, project: Project(rootPath: "/p/project\(i)"))
        }
        return aggregate(records, subscriptions: ["acc-max": SubscriptionEntry(status: nil, state: .ok)])
            .subscriptions["acc-max"]!.breakdown
    }

    @Test func topProjectsWithoutUsage() {
        let ranking = UsageBreakdown.empty.topProjects(byCost: false)
        #expect(ranking.top.isEmpty)
        #expect(ranking.other == nil)
    }

    @Test func topProjectsBelowAndAtTheLimitHaveNoOtherRow() {
        let three = projects([500, 300, 200]).topProjects(byCost: false)
        #expect(three.top.map(\.sharePercent) == [50, 30, 20])
        #expect(three.other == nil)
        let five = projects([5, 4, 3, 2, 1]).topProjects(byCost: false)
        #expect(five.top.count == 5)
        #expect(five.other == nil)
    }

    @Test func topProjectsAboveTheLimitAddAnOtherRow() {
        let ranking = projects([400, 200, 100, 100, 50, 50, 50, 50]).topProjects(byCost: false)
        #expect(ranking.top.map(\.usage.displayName) == ["project0", "project1", "project2", "project3", "project4"])
        #expect(ranking.other?.count == 3)
        #expect(ranking.other?.totalTokens == 150)
        #expect(ranking.other?.costUSD == nil)
        let shares = ranking.top.compactMap(\.sharePercent) + [ranking.other?.sharePercent ?? 0]
        #expect(shares == [40, 20, 10, 10, 5, 15])
    }

    @Test func sharesAlwaysAddUpTo100() {
        let ranking = projects([1, 1, 1]).topProjects(byCost: false)
        #expect(ranking.top.compactMap(\.sharePercent).reduce(0, +) == 100)
        #expect(ranking.top.map(\.sharePercent) == [34, 33, 33])
    }

    @Test func zeroTotalHidesShares() {
        let breakdown = UsageBreakdown(perProject: [ProjectUsage(project: agenttacho, displayName: "agenttacho")])
        #expect(breakdown.topProjects(byCost: true).top.map(\.sharePercent) == [nil])
    }

    @Test func pricedSharesUseCostAndOtherCostIsNilWhenUnpriced() {
        let snapshot = aggregate((0..<7).map { i in
            makeRecord(id: "r\(i)", accountId: "acc-v1", input: 1, cost: i == 6 ? nil : Decimal(10 - i),
                       project: Project(rootPath: "/p/project\(i)"))
        })
        let ranking = snapshot.groups["grp"]!.breakdown.topProjects(byCost: true)
        // Priced costs 10, 9, 8, 7, 6 | 5, 0 (unpriced): total 45.
        #expect(ranking.top.map(\.sharePercent) == [22, 20, 18, 16, 13])
        #expect(ranking.other?.count == 2)
        #expect(ranking.other?.costUSD == nil)
        #expect(ranking.other?.sharePercent == 11)
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
        // Absurd values from an untrusted source never trap (spec 007).
        #expect(PercentFormatter.rounded(1e19) == 1_000_000_000)
        #expect(PercentFormatter.rounded(-1e19) == -1_000_000_000)
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
            Account(id: "acc-max", displayName: "Claude Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: []))),
            Account(id: "acc-v1", displayName: "Vertex weekly", kind: .tokenBased(TokenBasedSettings(groupId: "grp-w"))),
            Account(id: "acc-v2", displayName: "Vertex monthly", kind: .tokenBased(TokenBasedSettings(groupId: "grp-m"))),
        ]
        c.groups = [
            BudgetGroup(id: "grp-w", name: "Weekly", period: .weekly, budgetUSD: 60),
            BudgetGroup(id: "grp-m", name: "Monthly", period: .monthly, budgetUSD: 400, thresholds: [50, 90]),
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

    /// Spec 009 FR-004, FR-005: an empty group still gets an entry with
    /// spend 0 and percent 0, and its window and reset follow its period.
    @Test func emptyGroupsYieldZeroEntriesInTheirPeriod() throws {
        var empty = config()
        empty.accounts.removeAll { $0.kind.tokenBased != nil }
        let snapshot = aggregator.aggregate(
            records: [makeRecord(id: "a", accountId: "acc-v2", timestamp: isoDate("2026-10-02T10:00:00Z"), cost: 40)],
            subscriptions: [:], configuration: empty, window: weekly, windowSource: .fallback, now: now, calendar: utc)
        let weeklyGroup = try #require(snapshot.groups["grp-w"])
        #expect(weeklyGroup.spentUSD == 0)
        #expect(weeklyGroup.percent == 0)
        #expect(weeklyGroup.members == [])
        #expect(weeklyGroup.window == weekly)
        #expect(weeklyGroup.resetAt == weekly.end)
        let monthlyGroup = try #require(snapshot.groups["grp-m"])
        #expect(monthlyGroup.spentUSD == 0)
        #expect(monthlyGroup.percent == 0)
        #expect(monthlyGroup.members == [])
        #expect(monthlyGroup.period == .monthly)
        #expect(monthlyGroup.window == month)
        #expect(monthlyGroup.resetAt == month.end)
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

/// Spec 004 FR-010, FR-017, FR-018a, research R4: own budgets and member
/// shares in the snapshot.
@Suite struct OwnBudgetAggregatorTests {
    let aggregator = Aggregator()
    /// Tuesday 2026-10-13; the weekly window is Oct 12 to Oct 19.
    let weekly = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// `own` has its own monthly $100 budget; `m1` and `m2` share the weekly
    /// $300 group `team`.
    func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "own", displayName: "Personal Vertex",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(period: .monthly, budgetUSD: 100, thresholds: [50]))))),
            Account(id: "m1", displayName: "Member one", kind: .tokenBased(TokenBasedSettings(groupId: "team"))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "team"))),
        ]
        c.groups = [BudgetGroup(id: "team", name: "Team", budgetUSD: 300)]
        return c
    }

    func aggregate(_ records: [UsageRecord]) -> UsageSnapshot {
        aggregator.aggregate(records: records, subscriptions: [:], configuration: config(),
                             window: weekly, windowSource: .fallback, now: now, calendar: utc)
    }

    /// US2 scenario 1: $25 of $100 per month, 25%, reset on the 1st.
    @Test func ownBudgetGetsItsOwnEntry() throws {
        let snapshot = aggregate([
            makeRecord(id: "sep", accountId: "own", timestamp: isoDate("2026-09-30T10:00:00Z"), cost: 70),
            makeRecord(id: "early", accountId: "own", timestamp: isoDate("2026-10-03T10:00:00Z"), cost: 15),
            makeRecord(id: "week", accountId: "own", timestamp: isoDate("2026-10-13T08:00:00Z"), input: 10, cost: 10),
        ])
        let entry = try #require(snapshot.accountBudgets["own"])
        #expect(entry.spentUSD == 25)
        #expect(entry.budgetUSD == 100)
        #expect(entry.percent == 25)
        #expect(entry.period == .monthly)
        #expect(entry.window == month)
        #expect(entry.resetAt == month.end)
        #expect(entry.members == ["own"])
        #expect(entry.memberSpendUSD == ["own": 25])
        #expect(entry.breakdown.pricedCostUSD == 25)
        // Per-day trend from the 1st to today (spec 003 FR-013).
        #expect(entry.breakdown.perDay.first?.day == month.start)
        #expect(entry.breakdown.perDay.count == 13)

        // The account's own breakdown uses the same window.
        #expect(snapshot.tokenAccounts["own"]?.breakdown.pricedCostUSD == 25)
        #expect(snapshot.tokenAccounts["own"]?.breakdown.perDay.count == 13)
        // It is not a group.
        #expect(snapshot.groups["own"] == nil)
        #expect(snapshot.groups.keys.sorted() == ["team"])
    }

    /// SC-004: member shares of the group budget add up to the group percent.
    @Test func memberSharesOfTheGroupBudget() throws {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "m1", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 90),
            makeRecord(id: "b", accountId: "m2", timestamp: isoDate("2026-10-13T10:00:00Z"), cost: 60),
            // Before the weekly window: not counted for either member.
            makeRecord(id: "c", accountId: "m1", timestamp: isoDate("2026-10-11T10:00:00Z"), cost: 1000),
        ])
        let group = try #require(snapshot.groups["team"])
        #expect(group.percent == 50)
        #expect(group.memberPercent("m1") == 30)
        #expect(group.memberPercent("m2") == 20)
        #expect(group.memberSpendUSD.values.reduce(Decimal(0), +) == group.spentUSD)
        #expect(group.memberPercent("unknown") == nil)
        #expect(snapshot.accountBudgets["team"] == nil)
    }

    /// FR-017: above 100% the actual value is shown.
    @Test func memberShareIsUncapped() throws {
        let snapshot = aggregate([makeRecord(id: "a", accountId: "m1", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 330)])
        #expect(snapshot.groups["team"]?.memberPercent("m1") == 110)
        #expect(snapshot.groups["team"]?.memberPercent("m2") == 0)
    }
}

// MARK: - Spec 006: per-harness split, reasoning, stale harnesses

/// spec 006 FR-021, FR-008, research R7, R10.
@Suite struct HarnessAggregatorTests {
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
            Account(id: "acc-max", displayName: "Claude Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "acc-v1", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
            Account(id: "acc-oai", displayName: "OpenAI",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), provider: .openai))),
        ]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex weekly", budgetUSD: 60)]
        return c
    }

    func aggregate(_ records: [UsageRecord], staleHarnesses: Set<Harness> = []) -> UsageSnapshot {
        aggregator.aggregate(records: records, subscriptions: ["acc-max": SubscriptionEntry(status: nil, state: .ok)],
                             configuration: config(), window: window, windowSource: .fallback, now: now, calendar: utc,
                             staleHarnesses: staleHarnesses)
    }

    @Test func perHarnessSplitSumsToTheEntryAndSortsByCost() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 100, cost: 20),
            makeRecord(id: "b", accountId: "acc-v1", input: 4, output: 1, cost: 30, harness: .openCode),
            makeRecord(id: "c", accountId: "acc-v1", input: 1, cost: 5, harness: .claudeCode),
        ])
        let group = snapshot.groups["grp"]!
        #expect(group.spentUSD == 55)
        // OpenCode costs more with fewer tokens and is declared later: only
        // the cost ranking puts it first.
        let split = group.breakdown.perHarness
        #expect(split.map(\.harness) == [.openCode, .claudeCode])
        #expect(split.map(\.costUSD) == [30, 25])
        #expect(split.map(\.totalTokens) == [5, 101])
        #expect(split.reduce(0) { $0 + $1.totalTokens } == group.breakdown.totalTokens)
        #expect(split.allSatisfy { $0.priced })
    }

    @Test func perHarnessIsTokenOnlyForUnpricedBreakdowns() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: nil, input: 10, cost: nil, harness: .codex),
            makeRecord(id: "b", accountId: nil, input: 30, cost: nil, harness: .openCode),
        ])
        let split = snapshot.unassigned.breakdown.perHarness
        #expect(split.map(\.harness) == [.openCode, .codex])
        #expect(split.allSatisfy { $0.costUSD == nil })
    }

    @Test func unpricedHarnessRecordMarksItsRowUnpriced() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-oai", model: "gpt-9", input: 10, cost: nil, harness: .codex),
            makeRecord(id: "b", accountId: "acc-oai", input: 10, cost: 3, harness: .openCode),
        ])
        let split = snapshot.accountBudgets["acc-oai"]!.breakdown.perHarness
        let codex = split.first { $0.harness == .codex }!
        #expect(codex.priced == false)
        #expect(codex.costUSD == nil)
        #expect(split.first { $0.harness == .openCode }?.costUSD == 3)
    }

    @Test func reasoningTokensSumPerModel() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", output: 100, cost: 1, harness: .openCode, reasoning: 40),
            makeRecord(id: "b", accountId: "acc-v1", output: 50, cost: 1, harness: .openCode, reasoning: 5),
        ])
        let model = snapshot.groups["grp"]!.breakdown.perModel[0]
        #expect(model.outputTokens == 150)
        #expect(model.reasoningTokens == 45)
    }

    @Test func staleHarnessMarksOnlyEntriesWithItsRecords() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 10, cost: 1, harness: .openCode),
            makeRecord(id: "b", accountId: "acc-oai", input: 10, cost: 1, harness: .codex),
            makeRecord(id: "c", accountId: "acc-max", input: 10, cost: nil),
        ], staleHarnesses: [.openCode])
        #expect(snapshot.groups["grp"]?.stale == true)
        #expect(snapshot.tokenAccounts["acc-v1"]?.stale == true)
        #expect(snapshot.accountBudgets["acc-oai"]?.stale == false)
        #expect(snapshot.tokenAccounts["acc-oai"]?.stale == false)
        #expect(snapshot.unassigned.stale == false)
    }
}

/// spec 006 FR-017: Codex subscription accounts are token-only plan entries.
@Suite struct CodexPlanAggregatorTests {
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
            Account(id: "acc-codex", displayName: "ChatGPT Plus", kind: .codexSubscription(CodexSubscriptionSettings())),
            Account(id: "acc-v1", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
        ]
        // A monthly group widens the collection window; the plan entry stays weekly.
        c.groups = [BudgetGroup(id: "grp", name: "Vertex", period: .monthly, budgetUSD: 60)]
        return c
    }

    func aggregate(_ records: [UsageRecord], staleHarnesses: Set<Harness> = []) -> UsageSnapshot {
        aggregator.aggregate(records: records, subscriptions: [:], configuration: config(), window: window,
                             windowSource: .fallback, now: now, calendar: utc, staleHarnesses: staleHarnesses)
    }

    @Test func codexPlanTokensCoverTheWeeklyWindowWithTokensOnly() throws {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-codex", model: "gpt-5.5", input: 100, output: 20, cost: 3, harness: .codex),
            makeRecord(id: "b", accountId: "acc-codex", model: "gpt-5.5", timestamp: isoDate("2026-10-13T08:00:00Z"),
                       input: 50, cost: nil, harness: .codex, reasoning: 0),
            // Before the weekly window (inside the monthly collection window).
            makeRecord(id: "old", accountId: "acc-codex", model: "gpt-5.5", timestamp: isoDate("2026-10-05T08:00:00Z"),
                       input: 1_000, cost: 1, harness: .codex),
        ])
        let entry = try #require(snapshot.codexPlanTokens["acc-codex"])
        #expect(entry.breakdown.totalTokens == 170)
        #expect(entry.breakdown.perModel.allSatisfy { $0.costUSD == nil })
        #expect(entry.breakdown.perDay.count == 7)
        #expect(entry.breakdown.perDay.allSatisfy { $0.costUSD == nil })
        #expect(entry.breakdown.unpricedModels.isEmpty)
        #expect(entry.breakdown.perHarness.map(\.harness) == [.codex])
        #expect(entry.incomplete == false)
        #expect(entry.stale == false)
        #expect(aggregate([], staleHarnesses: [.codex]).codexPlanTokens["acc-codex"]?.stale == false)
        #expect(aggregate([makeRecord(id: "a", accountId: "acc-codex", input: 1, cost: nil, harness: .codex)],
                          staleHarnesses: [.codex]).codexPlanTokens["acc-codex"]?.stale == true)
    }

    @Test func codexPlanTokensAreNotBudgetsOrTokenAccounts() {
        let snapshot = aggregate([makeRecord(id: "a", accountId: "acc-codex", input: 100, cost: 3, harness: .codex)])
        #expect(snapshot.tokenAccounts["acc-codex"] == nil)
        #expect(snapshot.groups["acc-codex"] == nil)
        #expect(snapshot.accountBudgets["acc-codex"] == nil)
        #expect(snapshot.unassigned.breakdown.isEmpty)
        #expect(snapshot.groups["grp"]?.spentUSD == 0)
    }
}
