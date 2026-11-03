import Foundation
import Testing
@testable import UsageCore

/// Spec 043 FR-002, FR-003, FR-009, FR-019, SC-005 (amending spec 041
/// FR-018, FR-019): switching a token-based account between an own budget
/// without an amount, one with an amount and a group.
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

    /// The configuration after the own budget editor of `id` set its amount
    /// to `amount` (nil clears it), through `OwnBudgetForm` (spec 043 R7).
    static func settingAmount(_ amount: Decimal?, of id: String, in c: Configuration) -> Configuration {
        guard let index = c.accounts.firstIndex(where: { $0.id == id }), var s = c.accounts[index].kind.tokenBased else { return c }
        var form = OwnBudgetForm(s.membership)
        form.amount = amount
        s.membership = form.membership
        var copy = c
        copy.accounts[index].kind = .tokenBased(s)
        return copy
    }

    /// Clearing the amount keeps period, thresholds, shown-in-bar, Value as
    /// and the time format (spec 043 FR-003).
    @Test func clearingTheAmountGivesNoLimit() throws {
        let moved = Self.settingAmount(nil, of: "own", in: Self.config())
        let s = try #require(Self.settings(moved, "own"))
        #expect(s.membership == .noLimit(NoLimitSettings(period: .monthly, thresholds: [50], shownInBar: true)))
        #expect(s.valueAs == "claude-opus-5-5")
        #expect(moved.account(id: "own")?.timeFormat == .absolute)
        #expect(moved.budgetOwner(forAccount: "own") == nil)
        try moved.validateForSaving()
        #expect(try Self.roundTrips(moved))
    }

    /// A member gets its own budget prefilled from the group (spec 004
    /// FR-014, spec 043 FR-019) and can then clear the amount.
    @Test func groupMemberToOwnBudgetWithoutAnAmount() throws {
        let previous = Self.config()
        let own = previous.movingAccountToOwnBudget(accountId: "m1")
        #expect(Self.settings(own, "m1")?.ownBudget == BudgetSettings(period: .weekly, budgetUSD: 300, thresholds: [80]))
        let moved = Self.settingAmount(nil, of: "m1", in: own)
        #expect(Self.settings(moved, "m1")?.membership == .noLimit(NoLimitSettings(period: .weekly, thresholds: [80], shownInBar: true)))
        #expect(moved.members(of: "team").map(\.id) == ["m2"])
        try moved.validateForSaving()
        #expect(try Self.roundTrips(moved))

        // The last member leaving keeps its group (spec 009 FR-002) and takes
        // the group's period.
        let emptied = Self.settingAmount(nil, of: "solo", in: previous.movingAccountToOwnBudget(accountId: "solo"))
        #expect(emptied.groups == previous.groups)
        #expect(emptied.members(of: "single").isEmpty)
        #expect(Self.settings(emptied, "solo")?.noLimit?.period == .monthly)
        try emptied.validateForSaving()

        // The account gets its own entry right after its former group
        // (spec 008 FR-006).
        let placed = moved.reconcilingArrangement(previous: previous)
        let ids = placed.arrangedEntries.map(\.id)
        let group = try #require(ids.firstIndex(of: "group:team"))
        #expect(ids[group + 1] == "account:m1")
    }

    /// Choosing Own budget on an own budget without an amount changes
    /// nothing: it already is one (spec 043 FR-002, FR-003). It used to
    /// write an amount of 0 and drop the thresholds.
    @Test func ownBudgetChoiceKeepsAnAccountWithoutAnAmount() {
        var c = Self.config()
        c = Self.settingAmount(nil, of: "own", in: c)
        #expect(c.movingAccountToOwnBudget(accountId: "own") == c)
        #expect(Self.config().movingAccountToOwnBudget(accountId: "free") == Self.config())
        #expect(Self.config().movingAccountToOwnBudget(accountId: "own") == Self.config())
        #expect(Self.config().movingAccountToOwnBudget(accountId: "nope") == Self.config())
    }

    /// Entering an amount turns it into a budget owner with the kept
    /// settings (spec 043 FR-003).
    @Test func enteringAnAmountMakesABudgetOwner() throws {
        let entered = Self.settingAmount(50, of: "free", in: Self.config())
        let s = try #require(Self.settings(entered, "free"))
        #expect(s.ownBudget == BudgetSettings(period: .monthly, budgetUSD: 50, shownInBar: true, thresholds: [80, 100]))
        #expect(s.valueAs == "claude-sonnet-4-6")
        try entered.validateForSaving()
        #expect(try Self.roundTrips(entered))
        #expect(entered.budgetOwner(forAccount: "free")?.budget.budgetUSD == 50)
    }

    /// A group editor's amount field shows 0 as empty; clearing it stores
    /// 0, which saving refuses (spec 003 FR-019).
    @Test func enteredAmountReadsZeroAsEmpty() {
        var budget = BudgetSettings(period: .monthly, budgetUSD: 0)
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

    /// Value as is kept through a budget and back (spec 041 FR-018).
    @Test func valueAsReturnsWithNoLimit() throws {
        let back = Self.settingAmount(nil, of: "free", in: Self.settingAmount(70, of: "free", in: Self.config()))
        #expect(Self.settings(back, "free")?.membership == .noLimit(NoLimitSettings(period: .monthly)))
        #expect(Self.settings(back, "free")?.valueAs == "claude-sonnet-4-6")
        let viaGroup = Self.settingAmount(nil, of: "free", in: Self.config().movingAccountToGroup(accountId: "free", groupId: "single")
            .movingAccountToOwnBudget(accountId: "free"))
        #expect(Self.settings(viaGroup, "free")?.valueAs == "claude-sonnet-4-6")
        #expect(try Self.roundTrips(viaGroup))
    }

    /// SC-005: every change between an empty amount, an amount and a group
    /// leaves a valid configuration that loads again unchanged.
    @Test func everyPathStaysValidAndRoundTrips() throws {
        func check(_ steps: [(Configuration) -> Configuration]) throws {
            var c = Self.config()
            for step in steps {
                c = step(c)
                try c.validateForSaving()
                #expect(try Self.roundTrips(c))
            }
        }
        let empty: (Configuration) -> Configuration = { Self.settingAmount(nil, of: "free", in: $0) }
        let amount: (Configuration) -> Configuration = { Self.settingAmount(300, of: "free", in: $0) }
        let group: (Configuration) -> Configuration = { $0.movingAccountToGroup(accountId: "free", groupId: "team") }
        let own: (Configuration) -> Configuration = { $0.movingAccountToOwnBudget(accountId: "free") }
        try check([empty, amount, empty])
        try check([amount, group, own])
        try check([empty, group, own])
        try check([amount, empty, amount, group, own, empty])
    }

    /// A stored Percent or Money is carried through an amount, a group and
    /// back to an own budget, and through save and load after every step
    /// (FR-010, FR-012, FR-018a, SC-005).
    @Test(arguments: [DropdownShow.percent, .money])
    func storedShowSurvivesEveryPath(show: DropdownShow) throws {
        var c = Self.config()
        let index = try #require(c.accounts.firstIndex { $0.id == "free" })
        var s = try #require(c.accounts[index].kind.tokenBased)
        s.show = show
        c.accounts[index].kind = .tokenBased(s)
        let steps: [(String, (Configuration) -> Configuration)] = [
            ("amount", { Self.settingAmount(300, of: "free", in: $0) }),
            ("group", { $0.movingAccountToGroup(accountId: "free", groupId: "team") }),
            ("own", { $0.movingAccountToOwnBudget(accountId: "free") }),
            ("empty", { Self.settingAmount(nil, of: "free", in: $0) }),
        ]
        for (name, step) in steps {
            c = step(c)
            #expect(Self.settings(c, "free")?.show == show, "after \(name)")
            try c.validateForSaving()
            let reloaded = try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(c))
            #expect(Self.settings(reloaded, "free")?.show == show, "after \(name), saved and loaded")
            #expect(reloaded == c)
        }
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
        let noLimit = Self.settingAmount(nil, of: "own", in: budget)
        var tracker = ThresholdTracker()
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 40), configuration: budget).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 120), configuration: budget).map(\.threshold) == [50])
        #expect(tracker.trackedEntityIds.contains("own"))

        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: nil, noLimitTokens: 9_000_000), configuration: noLimit).isEmpty)
        #expect(!tracker.trackedEntityIds.contains("own"))

        let back = Self.settingAmount(100, of: "own", in: noLimit)
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 130), configuration: back).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(ownPercent: 140), configuration: back).isEmpty)
    }
}
