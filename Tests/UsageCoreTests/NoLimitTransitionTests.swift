import Foundation
import Testing
@testable import UsageCore

/// Spec 041 FR-018, FR-019, SC-004, research R5: switching a token-based
/// account between No limit, an own budget and a group.
@Suite struct NoLimitTransitionTests {
    /// Accounts: `own` (monthly own budget, Value as and absolute times),
    /// `m1` and `solo` (members of "team" and "single"), `free` (No limit,
    /// monthly). Groups: "team" (weekly, two members), "single" (monthly,
    /// one member).
    static func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "own", displayName: "Own", kind: .tokenBased(TokenBasedSettings(
                membership: .ownBudget(BudgetSettings(period: .monthly, budgetUSD: 100, shownInBar: true, thresholds: [50])),
                valueAs: "claude-opus-5-5")), timeFormat: .absolute),
            Account(id: "m1", displayName: "Member one", kind: .tokenBased(TokenBasedSettings(groupId: "team"))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "team"))),
            Account(id: "solo", displayName: "Solo", kind: .tokenBased(TokenBasedSettings(groupId: "single"))),
            Account(id: "free", displayName: "Free", kind: .tokenBased(TokenBasedSettings(
                membership: .noLimit(NoLimitSettings(period: .monthly)), valueAs: "claude-sonnet-4-6"))),
        ]
        c.groups = [
            BudgetGroup(id: "team", name: "Team", period: .weekly, budgetUSD: 300, thresholds: [80]),
            BudgetGroup(id: "single", name: "Single", period: .monthly, budgetUSD: 40, thresholds: [90]),
        ]
        return c
    }

    static func settings(_ c: Configuration, _ id: String) -> TokenBasedSettings? { c.account(id: id)?.kind.tokenBased }

    /// Encoding and decoding gives the same configuration (SC-004).
    static func roundTrips(_ c: Configuration) throws -> Bool {
        try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(c)) == c
    }

    @Test func ownBudgetToNoLimit() throws {
        let moved = Self.config().movingAccountToNoLimit(accountId: "own")
        let s = try #require(Self.settings(moved, "own"))
        #expect(s.membership == .noLimit(NoLimitSettings(period: .monthly)))
        #expect(s.valueAs == "claude-opus-5-5")
        #expect(moved.account(id: "own")?.timeFormat == .absolute)
        #expect(moved.budgetOwner(forAccount: "own") == nil)
        try moved.validateForSaving()
        #expect(try Self.roundTrips(moved))
    }

    @Test func groupMemberToNoLimit() throws {
        let previous = Self.config()
        let moved = previous.movingAccountToNoLimit(accountId: "m1")
        #expect(Self.settings(moved, "m1")?.membership == .noLimit(NoLimitSettings(period: .weekly)))
        #expect(moved.members(of: "team").map(\.id) == ["m2"])
        try moved.validateForSaving()
        #expect(try Self.roundTrips(moved))

        // The last member leaving keeps its group (spec 009 FR-002) and takes
        // the group's period.
        let emptied = previous.movingAccountToNoLimit(accountId: "solo")
        #expect(emptied.groups == previous.groups)
        #expect(emptied.members(of: "single").isEmpty)
        #expect(Self.settings(emptied, "solo")?.noLimit == NoLimitSettings(period: .monthly))
        try emptied.validateForSaving()

        // The account gets its own entry right after its former group
        // (spec 008 FR-006).
        let placed = moved.reconcilingArrangement(previous: previous)
        let ids = placed.arrangedEntries.map(\.id)
        let group = try #require(ids.firstIndex(of: "group:team"))
        #expect(ids[group + 1] == "account:m1")
    }

    @Test func noLimitToOwnBudgetNeedsAnAmount() throws {
        let moved = Self.config().movingAccountToOwnBudget(accountId: "free")
        let s = try #require(Self.settings(moved, "free"))
        #expect(s.ownBudget == BudgetSettings(period: .monthly, budgetUSD: 0, shownInBar: true, thresholds: [80, 100]))
        #expect(s.valueAs == "claude-sonnet-4-6")
        #expect(throws: ConfigurationError(kind: .budget, message: "Monthly budget of account \"Free\" must be greater than 0.")) {
            try moved.validateForSaving()
        }
        var entered = moved
        var budget = try #require(s.ownBudget)
        budget.budgetUSD = 50
        var withAmount = s
        withAmount.membership = .ownBudget(budget)
        entered.accounts[4].kind = .tokenBased(withAmount)
        try entered.validateForSaving()
        #expect(try Self.roundTrips(entered))
        #expect(entered.budgetOwner(forAccount: "free")?.budget.budgetUSD == 50)
    }

    /// The amount field shows the amount 0 of a switch from No limit as
    /// empty; clearing it stores 0, which saving refuses (FR-018).
    @Test func enteredAmountReadsZeroAsEmpty() throws {
        var budget = try #require(Self.settings(Self.config().movingAccountToOwnBudget(accountId: "free"), "free")?.ownBudget)
        #expect(budget.enteredAmount == nil)
        budget.enteredAmount = 50
        #expect(budget.budgetUSD == 50)
        #expect(budget.enteredAmount == 50)
        budget.enteredAmount = nil
        #expect(budget.budgetUSD == 0)
        budget.enteredAmount = -5
        #expect(budget.enteredAmount == -5)
    }

    @Test func noLimitToGroupJoinsLastWithShareOff() throws {
        let previous = Self.config()
        let moved = previous.movingAccountToGroup(accountId: "free", groupId: "team")
        #expect(Self.settings(moved, "free")?.membership == .group(id: "team", shownInBar: false))
        #expect(Self.settings(moved, "free")?.valueAs == "claude-sonnet-4-6")
        try moved.validateForSaving()
        #expect(try Self.roundTrips(moved))
        let placed = moved.reconcilingArrangement(previous: previous)
        let members = placed.arrangedEntries.compactMap { entry -> [String]? in
            if case .group(let group, let members) = entry, group.id == "team" { return members.map(\.id) }
            return nil
        }.first
        #expect(members == ["m1", "m2", "free"])
        #expect(!placed.arrangedEntries.map(\.id).contains("account:free"))
    }

    /// Value as is kept through a budget and back (FR-018).
    @Test func valueAsReturnsWithNoLimit() throws {
        let back = Self.config().movingAccountToOwnBudget(accountId: "free").movingAccountToNoLimit(accountId: "free")
        #expect(Self.settings(back, "free")?.membership == .noLimit(NoLimitSettings(period: .monthly)))
        #expect(Self.settings(back, "free")?.valueAs == "claude-sonnet-4-6")
        let viaGroup = Self.config().movingAccountToGroup(accountId: "free", groupId: "single").movingAccountToNoLimit(accountId: "free")
        #expect(Self.settings(viaGroup, "free")?.valueAs == "claude-sonnet-4-6")
        #expect(try Self.roundTrips(viaGroup))
    }

    @Test func noLimitStaysNoLimit() {
        #expect(Self.config().movingAccountToNoLimit(accountId: "free") == Self.config())
        #expect(Self.config().movingAccountToNoLimit(accountId: "nope") == Self.config())
    }

    // MARK: Threshold state (FR-019)

    static let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    static func snapshot(ownPercent: Int?, noLimitTokens: Int? = nil) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: isoDate("2026-10-13T12:00:00Z"), window: month, windowSource: .fallback)
        if let ownPercent {
            s.accountBudgets["own"] = GroupEntry(spentUSD: Decimal(ownPercent), budgetUSD: 100, percent: ownPercent, incomplete: false,
                                                 period: .monthly, window: month, breakdown: .empty, members: ["own"])
        }
        if let noLimitTokens {
            s.noLimitAccounts["own"] = NoLimitEntry(period: .monthly, window: month,
                                                    breakdown: UsageBreakdown(perModel: [ModelUsage(model: "gateway-a/open-model-7b", inputTokens: noLimitTokens)]))
        }
        return s
    }

    /// An own budget over its threshold switched to No limit drops its
    /// state; switched back, the first refresh is a baseline without a
    /// notification (spec 004 FR-015).
    @Test func switchingDropsThresholdStateAndBaselinesAgain() {
        let budget = Self.config()
        let noLimit = budget.movingAccountToNoLimit(accountId: "own")
        var tracker = ThresholdTracker()
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 40), configuration: budget).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 120), configuration: budget).map(\.threshold) == [50])
        #expect(tracker.trackedEntityIds.contains("own"))

        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: nil, noLimitTokens: 9_000_000), configuration: noLimit).isEmpty)
        #expect(!tracker.trackedEntityIds.contains("own"))

        var back = noLimit.movingAccountToOwnBudget(accountId: "own")
        var settings = Self.settings(back, "own")!
        settings.membership = .ownBudget(BudgetSettings(period: .monthly, budgetUSD: 100, thresholds: [50]))
        back.accounts[0].kind = .tokenBased(settings)
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 130), configuration: back).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 140), configuration: back).isEmpty)
    }
}
