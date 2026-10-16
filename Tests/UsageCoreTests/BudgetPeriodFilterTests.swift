import Foundation
import Testing
@testable import UsageCore

/// Spec 015 FR-004, FR-005, research R2: carried-over budget entries
/// computed for another period than the configured one are dropped, so the
/// owner shows its waiting-for-data presentation.
@Suite struct BudgetPeriodFilterTests {
    let week = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    /// `grp` and `same` are groups, `own-a` and `own-b` accounts with their
    /// own budget; `grp` and `own-a` are configured monthly.
    func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "m1", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "grp"))),
            Account(id: "m2", displayName: "Other member", kind: .tokenBased(TokenBasedSettings(groupId: "same"))),
            Account(id: "own-a", displayName: "Own monthly",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(period: .monthly, budgetUSD: 100))))),
            Account(id: "own-b", displayName: "Own weekly",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(period: .weekly, budgetUSD: 100))))),
        ]
        c.groups = [
            BudgetGroup(id: "grp", name: "Switched", period: .monthly, budgetUSD: 100, thresholds: [80, 95]),
            BudgetGroup(id: "same", name: "Unchanged", period: .weekly, budgetUSD: 100),
        ]
        return c
    }

    func entry(_ period: BudgetPeriod, members: [String]) -> GroupEntry {
        GroupEntry(spentUSD: 90, budgetUSD: 100, percent: 90, incomplete: false, period: period,
                   window: period == .weekly ? week : month, breakdown: .empty, members: members, stale: true)
    }

    func snapshot() -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: week.start, window: week, windowSource: .fallback)
        s.groups = ["grp": entry(.weekly, members: ["m1"]), "same": entry(.weekly, members: ["m2"])]
        s.accountBudgets = ["own-a": entry(.weekly, members: ["own-a"]), "own-b": entry(.weekly, members: ["own-b"])]
        return s
    }

    @Test func mismatchedGroupEntryIsDroppedAndMatchingOnesKept() {
        let filtered = snapshot().droppingBudgetPeriodMismatches(configuration: config())
        #expect(filtered.groups["grp"] == nil)
        #expect(filtered.groups["same"] == snapshot().groups["same"])
    }

    @Test func mismatchedOwnBudgetEntryIsDroppedAndMatchingOnesKept() {
        let filtered = snapshot().droppingBudgetPeriodMismatches(configuration: config())
        #expect(filtered.accountBudgets["own-a"] == nil)
        #expect(filtered.accountBudgets["own-b"] == snapshot().accountBudgets["own-b"])
    }

    /// Nothing else in the snapshot changes.
    @Test func everythingElseIsUnchanged() {
        var s = snapshot()
        s.groups["grp"] = entry(.monthly, members: ["m1"])
        s.accountBudgets["own-a"] = entry(.monthly, members: ["own-a"])
        #expect(s.droppingBudgetPeriodMismatches(configuration: config()) == s)
    }

    /// FR-005: the dropped owner has no level in the bar and sets no
    /// threshold state.
    @Test func droppedOwnerShowsNoLevelAndNotifiesNothing() {
        let filtered = snapshot().droppingBudgetPeriodMismatches(configuration: config())
        let item = BarLayout.segments(snapshot: filtered, configuration: config()).first { $0.id == "grp" }
        #expect(item?.value == "…")
        #expect(item?.level == .normal)
        #expect(item?.stale == false)

        // The weekly state exists before the switch (a fresh weekly value),
        // so a notification after the switch would come from the dropped
        // entry or a reset, not from a missing baseline.
        var weeklyConfig = config()
        weeklyConfig.groups[0].period = .weekly
        var weekly = snapshot()
        weekly.groups["grp"]?.stale = false
        var tracker = ThresholdTracker()
        #expect(tracker.observe(snapshot: weekly, configuration: weeklyConfig).isEmpty)
        #expect(tracker.observe(snapshot: filtered, configuration: config()).isEmpty)
        var monthly = filtered
        monthly.groups["grp"] = GroupEntry(spentUSD: 85, budgetUSD: 100, percent: 85, incomplete: false, period: .monthly,
                                           window: month, breakdown: .empty, members: ["m1"])
        // The first monthly value is the new period's baseline, although it
        // is above 80.
        #expect(tracker.observe(snapshot: monthly, configuration: config()).isEmpty)
        monthly.groups["grp"]?.percent = 96
        #expect(tracker.observe(snapshot: monthly, configuration: config()).map(\.threshold) == [95])
    }
}
