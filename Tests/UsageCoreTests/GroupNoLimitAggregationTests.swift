import Foundation
import Testing
@testable import UsageCore

/// Spec 044 FR-003, FR-007, SC-003, research R3: a group without an amount
/// gets one `NoLimitEntry` over its members' combined records in its
/// period, and is never a budget.
@Suite struct GroupNoLimitAggregationTests {
    /// The Monday week Oct 12 to Oct 19; now is Tuesday Oct 13.
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    static let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
    static let now = isoDate("2026-10-13T12:00:00Z")
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// "Free models", monthly, no amount, with a Claude Code and a Codex
    /// member, plus an empty group without an amount.
    static func config(period: BudgetPeriod = .monthly) -> Configuration {
        Configuration(
            accounts: [
                Account(id: "acc-claude", displayName: "Free models (Claude Code)",
                        kind: .tokenBased(TokenBasedSettings(groupId: "grp-free", harness: .claudeCode))),
                Account(id: "acc-codex", displayName: "Free models (Codex)",
                        kind: .tokenBased(TokenBasedSettings(groupId: "grp-free", harness: .codex))),
            ],
            groups: [
                BudgetGroup(id: "grp-free", name: "Free models", icon: "solid:gift", period: period, budgetUSD: nil),
                BudgetGroup(id: "grp-empty", name: "Empty", period: .weekly, budgetUSD: nil),
            ])
    }

    /// Priced records costing 92.84 (Claude Code) and 0.62 (Codex) US$
    /// this month, unpriced records of `gateway-a/open-model-7b`, and one
    /// record of last month.
    static let records = [
        makeRecord(id: "sep", accountId: "acc-claude", model: "claude-opus-5-5", timestamp: isoDate("2026-09-28T10:00:00Z"),
                   input: 5_000, cost: 50),
        makeRecord(id: "c1", accountId: "acc-claude", model: "claude-opus-5-5", timestamp: isoDate("2026-10-05T10:00:00Z"),
                   input: 20_000_000, cost: 90),
        makeRecord(id: "c2", accountId: "acc-claude", model: "claude-opus-5-5", timestamp: isoDate("2026-10-12T10:00:00Z"),
                   input: 500_000, output: 42_000, cost: Decimal(string: "2.84")!),
        makeRecord(id: "x1", accountId: "acc-codex", model: "gpt-5", timestamp: isoDate("2026-10-13T09:00:00Z"),
                   input: 300_000, output: 2_000, cost: Decimal(string: "0.62")!, harness: .codex),
        makeRecord(id: "u1", accountId: "acc-claude", model: "gateway-a/open-model-7b", timestamp: isoDate("2026-10-13T10:00:00Z"),
                   input: 1_000_000, cost: nil),
        makeRecord(id: "u2", accountId: "acc-codex", model: "gateway-a/open-model-7b", timestamp: isoDate("2026-10-02T10:00:00Z"),
                   input: 200_000, output: 5, cost: nil, harness: .codex),
    ]

    static func aggregate(_ records: [UsageRecord] = records, config: Configuration = config(),
                          staleHarnesses: Set<Harness> = []) -> UsageSnapshot {
        Aggregator().aggregate(records: records, subscriptions: [:], configuration: config, window: window, windowSource: .fallback,
                               now: now, calendar: utc, staleHarnesses: staleHarnesses)
    }

    @Test func groupEntrySumsTheMembersRecordsOfThePeriod() throws {
        let snapshot = Self.aggregate()
        let entry = try #require(snapshot.noLimitGroups["grp-free"])
        #expect(entry.period == .monthly)
        #expect(entry.window == Self.month)
        #expect(entry.spentUSD == Decimal(string: "93.46"))
        #expect(entry.hasPricedUsage)
        #expect(entry.unpricedModels == ["gateway-a/open-model-7b"])
        #expect(entry.unpricedUsage.first?.totalTokens == 1_200_005)
        // September stays outside the month.
        #expect(entry.totalTokens == 20_000_000 + 542_000 + 302_000 + 1_000_000 + 200_005)
        #expect(entry.breakdown.perModel.map(\.model) == ["claude-opus-5-5", "gateway-a/open-model-7b", "gpt-5"])
        #expect(entry.breakdown.perHarness.map(\.harness) == [.claudeCode, .codex])
        #expect(entry.tokenBreakdown?.totalTokens == entry.totalTokens)
        #expect(entry.tokenBreakdown?.perModel.allSatisfy { $0.costUSD == nil } == true)
        #expect(entry.stale == false)
    }

    /// SC-003: the group's spend equals its members' spend to the cent.
    @Test func groupSpendEqualsTheSumOfTheMembersSpend() throws {
        let snapshot = Self.aggregate()
        let entry = try #require(snapshot.noLimitGroups["grp-free"])
        let claude = try #require(snapshot.tokenAccounts["acc-claude"])
        let codex = try #require(snapshot.tokenAccounts["acc-codex"])
        #expect(claude.breakdown.spentUSD == Decimal(string: "92.84"))
        #expect(codex.breakdown.spentUSD == Decimal(string: "0.62"))
        #expect(claude.breakdown.spentUSD + codex.breakdown.spentUSD == entry.spentUSD)
        // Unpriced tokens per record, matching the group's unpriced usage.
        #expect(claude.unpricedTokens == 1_000_000)
        #expect(codex.unpricedTokens == 200_005)
        #expect(claude.unpricedTokens + codex.unpricedTokens == entry.unpricedUsage.reduce(0) { $0 + $1.totalTokens })
    }

    @Test func groupWithoutAnAmountIsNoBudget() {
        let snapshot = Self.aggregate()
        #expect(snapshot.groups.isEmpty)
        #expect(snapshot.accountBudgets.isEmpty)
        #expect(snapshot.noLimitAccounts.isEmpty)
        #expect(snapshot.unassigned.breakdown.isEmpty)
    }

    @Test func weeklyGroupCountsTheWeek() throws {
        let entry = try #require(Self.aggregate(config: Self.config(period: .weekly)).noLimitGroups["grp-free"])
        #expect(entry.window == Self.window)
        #expect(entry.spentUSD == Decimal(string: "3.46"))
    }

    @Test func emptyGroupHasAnEntryWithoutTokens() throws {
        let entry = try #require(Self.aggregate().noLimitGroups["grp-empty"])
        #expect(entry.period == .weekly)
        #expect(entry.totalTokens == 0)
        #expect(entry.spentUSD == 0)
        #expect(entry.hasPricedUsage == false)
        #expect(entry.breakdown.isEmpty)
    }

    @Test func staleHarnessMarksTheGroupStale() {
        #expect(Self.aggregate(staleHarnesses: [.codex]).noLimitGroups["grp-free"]?.stale == true)
        #expect(Self.aggregate(staleHarnesses: [.openCode]).noLimitGroups["grp-free"]?.stale == false)
    }

    /// Spec 015 FR-004: an entry computed for another period is dropped.
    @Test func periodMismatchDropsTheEntry() {
        let snapshot = Self.aggregate()
        #expect(snapshot.droppingBudgetPeriodMismatches(configuration: Self.config()).noLimitGroups["grp-free"] != nil)
        #expect(snapshot.droppingBudgetPeriodMismatches(configuration: Self.config(period: .weekly)).noLimitGroups["grp-free"] == nil)
        // A group that got an amount meanwhile loses its no-limit entry too.
        var withAmount = Self.config()
        withAmount.groups[0].budgetUSD = 100
        #expect(snapshot.droppingBudgetPeriodMismatches(configuration: withAmount).noLimitGroups["grp-free"] == nil)
    }

    /// A group whose amount was cleared loses its budget entry, so a carried
    /// entry of the old amount never returns once an amount is entered again.
    @Test func clearedAmountDropsTheBudgetEntry() {
        var withAmount = Self.config()
        withAmount.groups[0].budgetUSD = 100
        let snapshot = Self.aggregate(config: withAmount)
        #expect(snapshot.groups["grp-free"] != nil)
        #expect(snapshot.droppingBudgetPeriodMismatches(configuration: withAmount).groups["grp-free"] != nil)
        #expect(snapshot.droppingBudgetPeriodMismatches(configuration: Self.config()).groups["grp-free"] == nil)
    }

    /// FR-014: a member's table under a Tokens headline ranks its projects
    /// by tokens, as the group's Details do; under Money by cost. Only
    /// members of a group without an amount carry the token ranking.
    @Test func memberTablesRankByTheGroupsMeasure() throws {
        let cheap = Project(rootPath: "/Users/me/work/cheap")
        let costly = Project(rootPath: "/Users/me/work/costly")
        let records = [
            makeRecord(id: "a", accountId: "acc-claude", timestamp: isoDate("2026-10-12T10:00:00Z"), input: 5_000_000, cost: 1,
                       project: cheap),
            makeRecord(id: "b", accountId: "acc-claude", timestamp: isoDate("2026-10-12T11:00:00Z"), input: 1_000, cost: 40,
                       project: costly),
        ]
        let member = try #require(Self.aggregate(records).tokenAccounts["acc-claude"])
        #expect(member.details(showsCost: true).perProject.map(\.project) == [costly, cheap])
        #expect(member.details(showsCost: false).perProject.map(\.project) == [cheap, costly])
        #expect(member.details(showsCost: false).perProject.allSatisfy { $0.costUSD == nil })

        var withAmount = Self.config()
        withAmount.groups[0].budgetUSD = 100
        let paid = try #require(Self.aggregate(records, config: withAmount).tokenAccounts["acc-claude"])
        #expect(paid.tokenBreakdown == nil)
        #expect(paid.details(showsCost: false) == paid.breakdown)
    }
}
