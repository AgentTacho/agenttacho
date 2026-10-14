import Foundation
import Testing
@testable import UsageCore

@Suite struct ThresholdTrackerTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let fiveHourReset = isoDate("2026-10-13T12:00:00Z")
    let sevenDayReset = isoDate("2026-10-16T07:00:00Z")

    func config(groupThresholds: [Int] = [80, 100], subscriptionThresholds: [Int] = [80, 100]) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "acc-max", displayName: "Claude Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: subscriptionThresholds))),
            Account(id: "acc-v", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
        ]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex weekly", budgetUSD: 100, shownInBar: true, thresholds: groupThresholds)]
        return c
    }

    func snapshot(groupPercent: Int? = nil, groupStale: Bool = false, window: DateInterval? = nil,
                  fiveHour: Double? = nil, sevenDay: Double? = nil, fiveHourReset: Date? = nil, sevenDayReset: Date? = nil,
                  state: SubscriptionState = .ok) -> UsageSnapshot {
        let w = window ?? self.window
        var s = UsageSnapshot(generatedAt: w.start.addingTimeInterval(3600), window: w, windowSource: .fallback)
        if let groupPercent {
            s.groups["grp"] = GroupEntry(spentUSD: Decimal(groupPercent), budgetUSD: 100, percent: groupPercent, incomplete: false,
                                         window: w, breakdown: .empty, members: ["acc-v"], stale: groupStale)
        }
        if fiveHour != nil || sevenDay != nil || state != .ok {
            let status = SubscriptionStatus(
                fiveHour: fiveHour.map { LimitWindow(utilizationPercent: $0, resetsAt: fiveHourReset ?? self.fiveHourReset) },
                sevenDay: sevenDay.map { LimitWindow(utilizationPercent: $0, resetsAt: sevenDayReset ?? self.sevenDayReset) },
                fetchedAt: s.generatedAt)
            s.subscriptions["acc-max"] = SubscriptionEntry(status: status, state: state)
        }
        return s
    }

    @Test func crossingFiresOnceAndNotWhileStayingAbove() {
        var tracker = ThresholdTracker()
        let c = config()
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 75), configuration: c).isEmpty)   // baseline
        let crossings = tracker.observe(snapshot: snapshot(groupPercent: 82), configuration: c)
        #expect(crossings == [ThresholdCrossing(entityId: "grp", entityName: "Vertex weekly", windowKind: .weekly, threshold: 80, percent: 82)])
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 85), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 99), configuration: c).isEmpty)
        let hundred = tracker.observe(snapshot: snapshot(groupPercent: 100), configuration: c)
        #expect(hundred.map(\.threshold) == [100])
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 130), configuration: c).isEmpty)
    }

    @Test func firstObservationIsBaselineOnly() {
        var tracker = ThresholdTracker()
        let c = config()
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 95, fiveHour: 90, sevenDay: 85), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 96, fiveHour: 91, sevenDay: 86), configuration: c).isEmpty)
    }

    @Test func windowEndChangeResetsState() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(groupPercent: 10), configuration: c)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 85), configuration: c).count == 1)

        // New week: usage drops, then crosses again.
        let next = DateInterval(start: window.end, duration: window.duration)
        let afterReset = tracker.observe(snapshot: snapshot(groupPercent: 10, window: next), configuration: c)
        #expect(afterReset.isEmpty)
        let again = tracker.observe(snapshot: snapshot(groupPercent: 85, window: next), configuration: c)
        #expect(again.map(\.threshold) == [80])

        // A reset where the new window already starts above the threshold is a new baseline: no notification.
        let third = DateInterval(start: next.end, duration: window.duration)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 90, window: third), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 95, window: third), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 100, window: third), configuration: c).map(\.threshold) == [100])
    }

    @Test func singleJumpOverTwoThresholdsYieldsTwoCrossingsAndDuplicatesCollapse() {
        var tracker = ThresholdTracker()
        let c = config(groupThresholds: [50, 80, 80, 100])
        _ = tracker.observe(snapshot: snapshot(groupPercent: 10), configuration: c)
        let crossings = tracker.observe(snapshot: snapshot(groupPercent: 85), configuration: c)
        #expect(crossings.map(\.threshold) == [50, 80])
        #expect(crossings.allSatisfy { $0.percent == 85 && $0.entityId == "grp" })
    }

    @Test func subscriptionWindowsAreTrackedIndependently() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(fiveHour: 10, sevenDay: 70), configuration: c)
        let first = tracker.observe(snapshot: snapshot(fiveHour: 85, sevenDay: 75), configuration: c)
        #expect(first == [ThresholdCrossing(entityId: "acc-max", entityName: "Claude Max", windowKind: .fiveHour, threshold: 80, percent: 85)])
        let second = tracker.observe(snapshot: snapshot(fiveHour: 90, sevenDay: 81), configuration: c)
        #expect(second == [ThresholdCrossing(entityId: "acc-max", entityName: "Claude Max", windowKind: .sevenDay, threshold: 80, percent: 81)])

        // The 5-hour window resets (new resets_at) while the 7-day window continues.
        let later = snapshot(fiveHour: 5, sevenDay: 82, fiveHourReset: fiveHourReset.addingTimeInterval(5 * 3600))
        #expect(tracker.observe(snapshot: later, configuration: c).isEmpty)
        let fiveAgain = tracker.observe(snapshot: snapshot(fiveHour: 80, sevenDay: 83, fiveHourReset: fiveHourReset.addingTimeInterval(5 * 3600)), configuration: c)
        #expect(fiveAgain.map(\.windowKind) == [.fiveHour])
    }

    @Test func staleAndNotSignedInEntriesProduceNoCrossingAndKeepBaseline() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(groupPercent: 70, fiveHour: 70, sevenDay: 70), configuration: c)

        let stale = snapshot(groupPercent: 90, groupStale: true, fiveHour: 90, sevenDay: 90, state: .stale(lastGoodAt: nil, error: "offline"))
        #expect(tracker.observe(snapshot: stale, configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 90, groupStale: true, fiveHour: 90, sevenDay: 90, state: .notSignedIn), configuration: c).isEmpty)

        // Back to live values: the baseline is still 70, so this crosses 80.
        let live = tracker.observe(snapshot: snapshot(groupPercent: 90, fiveHour: 90, sevenDay: 90), configuration: c)
        #expect(Set(live.map { "\($0.entityId)/\($0.windowKind.rawValue)" }) == ["grp/weekly", "acc-max/fiveHour", "acc-max/sevenDay"])
        #expect(live.allSatisfy { $0.threshold == 80 })
    }

    @Test func removedEntitiesAreDropped() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(groupPercent: 70, fiveHour: 70, sevenDay: 70), configuration: c)
        #expect(tracker.trackedEntityIds == ["acc-max", "grp"])

        let removed = c.removingAccount(id: "acc-v")
        _ = tracker.observe(snapshot: snapshot(fiveHour: 71, sevenDay: 71), configuration: removed)
        #expect(tracker.trackedEntityIds == ["acc-max"])

        // Re-adding the group starts from a fresh baseline.
        _ = tracker.observe(snapshot: snapshot(groupPercent: 95, fiveHour: 71, sevenDay: 71), configuration: c)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 96, fiveHour: 71, sevenDay: 71), configuration: c).isEmpty)
    }

    @Test func tokenAccountsAndUnassignedCarryNoThresholds() {
        var tracker = ThresholdTracker()
        let c = config()
        func withTokens(_ percent: Int, tokens: Int) -> UsageSnapshot {
            var s = snapshot(groupPercent: percent)
            let usage = UsageBreakdown(perModel: [ModelUsage(model: "claude-opus-5-5", inputTokens: tokens, costUSD: nil, priced: true)])
            s.tokenAccounts["acc-v"] = TokenAccountEntry(breakdown: usage, incomplete: false)
            s.unassigned = TokenAccountEntry(breakdown: usage, incomplete: false)
            return s
        }
        _ = tracker.observe(snapshot: withTokens(10, tokens: 1_000), configuration: c)
        let crossings = tracker.observe(snapshot: withTokens(10, tokens: 1_000_000), configuration: c)
        #expect(crossings.isEmpty)
        #expect(tracker.trackedEntityIds == ["grp"])
    }

    @Test func halfPercentRoundsUpToTheThreshold() {
        var tracker = ThresholdTracker()
        let c = config(subscriptionThresholds: [80])
        _ = tracker.observe(snapshot: snapshot(fiveHour: 79.4), configuration: c)
        let crossings = tracker.observe(snapshot: snapshot(fiveHour: 79.5), configuration: c)
        #expect(crossings == [ThresholdCrossing(entityId: "acc-max", entityName: "Claude Max", windowKind: .fiveHour, threshold: 80, percent: 80)])
    }
}

/// Spec 003: thresholds of monthly groups (FR-015, FR-016, FR-017, SC-005).
@Suite struct MonthlyThresholdTrackerTests {
    let october = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
    let november = DateInterval(start: isoDate("2026-11-01T00:00:00Z"), end: isoDate("2026-12-01T00:00:00Z"))

    func config(period: BudgetPeriod = .monthly) -> Configuration {
        var c = Configuration()
        c.accounts = [Account(id: "acc-v", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "grp")))]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex", period: period, budgetUSD: 400, thresholds: [50, 90])]
        return c
    }

    func snapshot(_ percent: Int, window: DateInterval? = nil, period: BudgetPeriod = .monthly) -> UsageSnapshot {
        let w = window ?? october
        var s = UsageSnapshot(generatedAt: w.start.addingTimeInterval(3600), window: w, windowSource: .fallback)
        s.groups["grp"] = GroupEntry(spentUSD: Decimal(percent * 4), budgetUSD: 400, percent: percent, incomplete: false,
                                     period: period, window: w, breakdown: .empty, members: ["acc-v"])
        return s
    }

    @Test func monthlyCrossingNamesTheMonthlyWindowOncePerMonth() {
        var tracker = ThresholdTracker()
        let c = config()
        #expect(tracker.observe(snapshot: snapshot(45), configuration: c).isEmpty)       // baseline
        let crossings = tracker.observe(snapshot: snapshot(55), configuration: c)
        #expect(crossings == [ThresholdCrossing(entityId: "grp", entityName: "Vertex", windowKind: .monthly, threshold: 50, percent: 55)])
        #expect(tracker.observe(snapshot: snapshot(60), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(51), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(89), configuration: c).isEmpty)
    }

    /// Month rollover, or a time zone change that moves the month, changes
    /// `resetAt`; the next observation is a baseline and the threshold re-arms.
    @Test func newMonthResetsStateWithABaseline() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(45), configuration: c)
        #expect(tracker.observe(snapshot: snapshot(55), configuration: c).count == 1)

        #expect(tracker.observe(snapshot: snapshot(5, window: november), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(55, window: november), configuration: c).map(\.threshold) == [50])

        // A month that already starts above a threshold is a baseline only.
        let shifted = DateInterval(start: november.start.addingTimeInterval(-13 * 3600), end: november.end.addingTimeInterval(-13 * 3600))
        #expect(tracker.observe(snapshot: snapshot(70, window: shifted), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(75, window: shifted), configuration: c).isEmpty)
    }

    /// FR-017: a period switch resets state even when the new window ends at
    /// the same instant as the old one, and does not notify for thresholds
    /// already exceeded.
    @Test func periodSwitchEstablishesABaseline() {
        var tracker = ThresholdTracker()
        // A weekly window that ends exactly at the month boundary.
        let week = DateInterval(start: isoDate("2026-10-25T00:00:00Z"), end: october.end)
        _ = tracker.observe(snapshot: snapshot(40, window: week, period: .weekly), configuration: config(period: .weekly))
        #expect(tracker.observe(snapshot: snapshot(45, window: week, period: .weekly), configuration: config(period: .weekly)).isEmpty)

        let afterSwitch = tracker.observe(snapshot: snapshot(95, window: october), configuration: config(period: .monthly))
        #expect(afterSwitch.isEmpty)
        #expect(tracker.observe(snapshot: snapshot(96, window: october), configuration: config(period: .monthly)).isEmpty)

        // Switching back is again a baseline.
        #expect(tracker.observe(snapshot: snapshot(97, window: week, period: .weekly), configuration: config(period: .weekly)).isEmpty)
        #expect(tracker.trackedEntityIds == ["grp"])
    }

    /// FR-017: a snapshot computed for the old period (a refresh that was
    /// running while the period was switched) does not set the new period's
    /// baseline. The window is the same in both snapshots, so only the period
    /// guard can skip the first one.
    @Test func snapshotOfTheOldPeriodIsSkippedAfterASwitch() {
        var tracker = ThresholdTracker()
        // Monthly config, but the snapshot still carries a weekly entry at 10%.
        #expect(tracker.observe(snapshot: snapshot(10, window: october, period: .weekly), configuration: config(period: .monthly)).isEmpty)
        // The first monthly snapshot is the baseline, so 95% does not notify.
        #expect(tracker.observe(snapshot: snapshot(95, window: october), configuration: config(period: .monthly)).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(96, window: october), configuration: config(period: .monthly)).isEmpty)
    }

    /// FR-016: a moved window start counts as a reset even when the end
    /// stays the same (time zones that share the offset at the month end only).
    @Test func movedWindowStartWithTheSameEndResetsState() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(45), configuration: c)
        let moved = DateInterval(start: october.start.addingTimeInterval(3600), end: october.end)
        #expect(tracker.observe(snapshot: snapshot(55, window: moved), configuration: c).isEmpty)   // baseline
        #expect(tracker.observe(snapshot: snapshot(91, window: moved), configuration: c).map(\.threshold) == [90])
    }
}

/// Spec 004 FR-012, FR-015, SC-005: thresholds of own budgets and
/// re-baselining after membership changes.
@Suite struct OwnBudgetThresholdTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    /// `acc-g` is the member of `grp`; `acc-o` has its own budget with a 50%
    /// threshold.
    func config(ownPeriod: BudgetPeriod = .monthly) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "acc-g", displayName: "Group member", kind: .tokenBased(TokenBasedSettings(groupId: "grp"))),
            Account(id: "acc-o", displayName: "Personal Vertex",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(period: ownPeriod, budgetUSD: 100, thresholds: [50]))))),
        ]
        c.groups = [BudgetGroup(id: "grp", name: "Team", budgetUSD: 300, thresholds: [80, 100])]
        return c
    }

    func snapshot(groupPercent: Int? = nil, groupMembers: [String] = ["acc-g"],
                  ownPercent: Int? = nil, ownPeriod: BudgetPeriod = .monthly, ownStale: Bool = false) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: window.start.addingTimeInterval(3600), window: window, windowSource: .fallback)
        if let groupPercent {
            s.groups["grp"] = GroupEntry(spentUSD: Decimal(groupPercent * 3), budgetUSD: 300, percent: groupPercent, incomplete: false,
                                         window: window, breakdown: .empty, members: groupMembers)
        }
        if let ownPercent {
            s.accountBudgets["acc-o"] = GroupEntry(spentUSD: Decimal(ownPercent), budgetUSD: 100, percent: ownPercent, incomplete: false,
                                                   period: ownPeriod, window: ownPeriod == .monthly ? month : window,
                                                   breakdown: .empty, members: ["acc-o"], stale: ownStale)
        }
        return s
    }

    /// US2 scenario 3: one notification naming the account and the window.
    @Test func ownBudgetCrossingNamesTheAccount() {
        var tracker = ThresholdTracker()
        let c = config()
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 10, ownPercent: 40), configuration: c).isEmpty)
        let crossings = tracker.observe(snapshot: snapshot(groupPercent: 10, ownPercent: 55), configuration: c)
        #expect(crossings == [ThresholdCrossing(entityId: "acc-o", entityName: "Personal Vertex", windowKind: .monthly, threshold: 50, percent: 55)])
        // At most once per threshold and window (SC-005).
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 10, ownPercent: 70), configuration: c).isEmpty)

        let weekly = config(ownPeriod: .weekly)
        var weeklyTracker = ThresholdTracker()
        _ = weeklyTracker.observe(snapshot: snapshot(ownPercent: 10, ownPeriod: .weekly), configuration: weekly)
        let weeklyCrossings = weeklyTracker.observe(snapshot: snapshot(ownPercent: 60, ownPeriod: .weekly), configuration: weekly)
        #expect(weeklyCrossings.map(\.windowKind) == [.weekly])
    }

    /// Stale own-budget entries are skipped, as for groups.
    @Test func staleOwnBudgetIsSkipped() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(ownPercent: 40), configuration: c)
        #expect(tracker.observe(snapshot: snapshot(ownPercent: 60, ownStale: true), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(ownPercent: 61), configuration: c).map(\.threshold) == [50])
    }

    /// FR-015: moving the account into the group drops its own state, and the
    /// group's next observation with the new member set is a baseline.
    @Test func movingIntoAGroupRebaselines() {
        var tracker = ThresholdTracker()
        let before = config()
        _ = tracker.observe(snapshot: snapshot(groupPercent: 40, ownPercent: 30), configuration: before)
        #expect(tracker.trackedEntityIds == ["acc-o", "grp"])

        let after = before.movingAccountToGroup(accountId: "acc-o", groupId: "grp")
        // The group jumps above 80% with its new member: no notification.
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 95, groupMembers: ["acc-g", "acc-o"]), configuration: after).isEmpty)
        #expect(tracker.trackedEntityIds == ["grp"])
        // Later crossings notify again.
        let next = tracker.observe(snapshot: snapshot(groupPercent: 101, groupMembers: ["acc-g", "acc-o"]), configuration: after)
        #expect(next.map(\.threshold) == [100])
    }

    /// FR-015, reverse direction: leaving the group re-baselines both the
    /// group and the new own budget.
    @Test func movingOutOfAGroupRebaselines() {
        var tracker = ThresholdTracker()
        var before = config()
        before = before.movingAccountToGroup(accountId: "acc-o", groupId: "grp")
        _ = tracker.observe(snapshot: snapshot(groupPercent: 40, groupMembers: ["acc-g", "acc-o"]), configuration: before)

        let after = before.movingAccountToOwnBudget(accountId: "acc-o")
        #expect(after.account(id: "acc-o")?.kind.tokenBased?.ownBudget?.thresholds == [80, 100])
        // Group drops to the remaining member's share and the own budget
        // starts above its thresholds: neither notifies.
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 85, ownPercent: 120, ownPeriod: .weekly), configuration: after).isEmpty)
        #expect(tracker.trackedEntityIds == ["acc-o", "grp"])
    }
}

extension OwnBudgetThresholdTests {
    /// FR-015 race: a refresh computed with the old member set that arrives
    /// after the move is skipped, so the baseline includes the new member.
    @Test func snapshotForTheOldMemberSetIsSkipped() {
        var tracker = ThresholdTracker()
        let before = config()
        _ = tracker.observe(snapshot: snapshot(groupPercent: 40, ownPercent: 30), configuration: before)
        let after = before.movingAccountToGroup(accountId: "acc-o", groupId: "grp")
        // Old-config snapshot (group without acc-o) under the new configuration.
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 41), configuration: after).isEmpty)
        // First snapshot with the new member set: a baseline, even above 80%.
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 90, groupMembers: ["acc-g", "acc-o"]), configuration: after).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 100, groupMembers: ["acc-g", "acc-o"]), configuration: after).map(\.threshold) == [100])
    }

    /// A group and an own-budget account with the same id keep separate state.
    @Test func groupAndAccountWithTheSameIdDoNotShareState() {
        var c = Configuration()
        c.accounts = [
            Account(id: "x", displayName: "Own X",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 100, thresholds: [50]))))),
            Account(id: "m", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
        ]
        c.groups = [BudgetGroup(id: "x", name: "Group X", budgetUSD: 100, thresholds: [50])]
        func snap(group: Int, own: Int) -> UsageSnapshot {
            var s = UsageSnapshot(generatedAt: window.start.addingTimeInterval(3600), window: window, windowSource: .fallback)
            s.groups["x"] = GroupEntry(spentUSD: Decimal(group), budgetUSD: 100, percent: group, incomplete: false,
                                       window: window, breakdown: .empty, members: ["m"])
            s.accountBudgets["x"] = GroupEntry(spentUSD: Decimal(own), budgetUSD: 100, percent: own, incomplete: false,
                                               window: window, breakdown: .empty, members: ["x"])
            return s
        }
        var tracker = ThresholdTracker()
        #expect(tracker.observe(snapshot: snap(group: 10, own: 90), configuration: c).isEmpty)
        let crossings = tracker.observe(snapshot: snap(group: 60, own: 95), configuration: c)
        #expect(crossings.map(\.entityName) == ["Group X"])
    }
}

/// spec 006 FR-017: no thresholds for Codex subscription accounts.
@Suite struct CodexPlanThresholdTests {
    @Test func codexSubscriptionYieldsNoCrossings() {
        let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
        let configuration = Configuration(accounts: [
            Account(id: "acc-codex", displayName: "ChatGPT", kind: .codexSubscription(CodexSubscriptionSettings())),
        ])
        var tracker = ThresholdTracker()
        for tokens in [0, 1_000_000, 5_000_000] {
            var snapshot = UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback)
            snapshot.planAccounts["acc-codex"] = TokenAccountEntry(breakdown: UsageBreakdown(perModel: [ModelUsage(model: "gpt-5.5", inputTokens: tokens)]))
            #expect(tracker.observe(snapshot: snapshot, configuration: configuration).isEmpty)
        }
    }
}
