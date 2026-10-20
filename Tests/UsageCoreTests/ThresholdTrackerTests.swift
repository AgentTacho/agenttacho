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

    /// spec 030 SC-004, US4 scenarios 3 and 4: the direction never changes
    /// when a notification fires, also when it is switched between two
    /// refreshes.
    @Test func directionNeverChangesWhenCrossingsFire() {
        let series: [(group: Int, seven: Double)] = [(70, 70), (83, 83), (90, 99.6), (115, 115)]
        var used = config()
        used.displayDirection = .used
        var remaining = used
        remaining.displayDirection = .remaining
        var usedTracker = ThresholdTracker()
        var remainingTracker = ThresholdTracker()
        var switchingTracker = ThresholdTracker()
        var usedCrossings: [[ThresholdCrossing]] = []
        for (index, step) in series.enumerated() {
            let s = snapshot(groupPercent: step.group, sevenDay: step.seven)
            let fromUsed = usedTracker.observe(snapshot: s, configuration: used)
            #expect(remainingTracker.observe(snapshot: s, configuration: remaining) == fromUsed)
            #expect(switchingTracker.observe(snapshot: s, configuration: index.isMultiple(of: 2) ? used : remaining) == fromUsed)
            usedCrossings.append(fromUsed)
        }
        // The series crosses 80 and 100 for the group and the 7-day window.
        #expect(usedCrossings.flatMap { $0 }.map(\.threshold).sorted() == [80, 80, 100, 100])
    }

    @Test func firstObservationIsBaselineOnly() {
        var tracker = ThresholdTracker()
        let c = config()
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 95, fiveHour: 90, sevenDay: 85), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 96, fiveHour: 91, sevenDay: 86), configuration: c).isEmpty)
    }

    /// Saved Claude values in the early result neither notify nor set the
    /// baseline; the first refresh does (spec 010 FR-019).
    @Test func preliminaryClaudeValuesSetNoBaseline() {
        var tracker = ThresholdTracker()
        let c = config()
        var early = snapshot(sevenDay: 75)
        early.isPreliminary = true
        #expect(tracker.observe(snapshot: early, configuration: c).isEmpty)
        // Without the early result as baseline, 85% is the first observation.
        #expect(tracker.observe(snapshot: snapshot(sevenDay: 85), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(sevenDay: 101), configuration: c).map(\.threshold) == [100])
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

        // A reset where the new window already starts above the threshold
        // compares with 0 and notifies once (spec 015 FR-001).
        let third = DateInterval(start: next.end, duration: window.duration)
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 90, window: third), configuration: c).map(\.threshold) == [80])
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

        // Since spec 009 the group stays with its last member gone; remove
        // it explicitly so the test still covers a removed entity.
        var removed = c.removingAccount(id: "acc-v")
        removed.groups.removeAll { $0.id == "grp" }
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
    /// `resetAt`; the threshold re-arms and the first observation of the new
    /// month is compared with 0 (spec 015 FR-001).
    @Test func newMonthResetsStateAndRearmsThresholds() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(45), configuration: c)
        #expect(tracker.observe(snapshot: snapshot(55), configuration: c).count == 1)

        #expect(tracker.observe(snapshot: snapshot(5, window: november), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: snapshot(55, window: november), configuration: c).map(\.threshold) == [50])

        // A month moved by a time zone change that already starts above a
        // threshold notifies once for it (spec 015 FR-001).
        let shifted = DateInterval(start: november.start.addingTimeInterval(-13 * 3600), end: november.end.addingTimeInterval(-13 * 3600))
        #expect(tracker.observe(snapshot: snapshot(70, window: shifted), configuration: c).map(\.threshold) == [50])
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
    /// stays the same (time zones that share the offset at the month end
    /// only); the reset compares with 0 (spec 015 FR-001).
    @Test func movedWindowStartWithTheSameEndResetsState() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(45), configuration: c)
        let moved = DateInterval(start: october.start.addingTimeInterval(3600), end: october.end)
        #expect(tracker.observe(snapshot: snapshot(55, window: moved), configuration: c).map(\.threshold) == [50])
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

/// spec 007 FR-014, FR-015: thresholds per Codex plan window.
@Suite struct CodexPlanThresholdTests {
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    static let now = isoDate("2026-10-14T15:00:00Z")
    static let fiveReset = isoDate("2026-10-14T18:00:00Z")
    static let weekReset = isoDate("2026-10-18T09:00:00Z")
    static let monthReset = isoDate("2026-11-06T09:00:00Z")

    static func config(thresholds: [Int] = [80, 95], liveLimits: Bool = true) -> Configuration {
        Configuration(accounts: [
            Account(id: "acc-codex", displayName: "ChatGPT Plus", harness: .codex,
                    kind: .codexSubscription(CodexSubscriptionSettings(thresholds: thresholds, liveLimits: liveLimits))),
        ])
    }

    static func plus(five: Double = 10, weekly: Double, weekReset: Date = weekReset, state: CodexLimitsState = .live) -> CodexLimitsEntry {
        CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: five, resetsAt: fiveReset),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: weekly, resetsAt: weekReset),
        ]), state: state)
    }

    static func free(_ percent: Double, state: CodexLimitsState = .localOnly) -> CodexLimitsEntry {
        CodexLimitsEntry(observation: CodexLimitObservation(planType: "free", observedAt: now, origin: .snapshot, windows: [
            CodexLimitWindow(lengthMinutes: 43200, usedPercent: percent, resetsAt: monthReset),
        ]), state: state)
    }

    static func snapshot(_ entry: CodexLimitsEntry?) -> UsageSnapshot {
        var snapshot = UsageSnapshot(generatedAt: now, window: window, windowSource: .fallback)
        snapshot.codexLimits["acc-codex"] = entry
        return snapshot
    }

    static func observe(_ tracker: inout ThresholdTracker, _ entry: CodexLimitsEntry?, config: Configuration = config()) -> [ThresholdCrossing] {
        tracker.observe(snapshot: snapshot(entry), configuration: config)
    }

    @Test func crossingNamesAccountWindowAndThreshold() {
        var tracker = ThresholdTracker()
        #expect(Self.observe(&tracker, Self.plus(weekly: 70)).isEmpty)
        let crossings = Self.observe(&tracker, Self.plus(weekly: 85))
        #expect(crossings == [ThresholdCrossing(entityId: "acc-codex", entityName: "ChatGPT Plus",
                                                windowKind: .codex(CodexLimitWindow(lengthMinutes: 10080, usedPercent: 85, resetsAt: nil), live: true),
                                                threshold: 80, percent: 85)])
        #expect(crossings.first?.windowKind.displayName == "weekly")
    }

    @Test func bothWindowsCrossingNotifyOnceEach() {
        var tracker = ThresholdTracker()
        _ = Self.observe(&tracker, Self.plus(five: 70, weekly: 70))
        let crossings = Self.observe(&tracker, Self.plus(five: 81, weekly: 82))
        #expect(crossings.map(\.windowKind.displayName).sorted() == ["5-hour", "weekly"])
        #expect(crossings.allSatisfy { $0.threshold == 80 })
    }

    /// spec 001 FR-028: the first observation after launch is a baseline.
    @Test func firstObservationIsABaseline() {
        var tracker = ThresholdTracker()
        #expect(Self.observe(&tracker, Self.plus(five: 99, weekly: 99)).isEmpty)
    }

    @Test func resetStartsOver() {
        var tracker = ThresholdTracker()
        _ = Self.observe(&tracker, Self.plus(weekly: 70))
        #expect(Self.observe(&tracker, Self.plus(weekly: 85)).count == 1)
        let next = Self.weekReset.addingTimeInterval(7 * 86400)
        #expect(Self.observe(&tracker, Self.plus(weekly: 5, weekReset: next)).isEmpty)
        #expect(Self.observe(&tracker, Self.plus(weekly: 85, weekReset: next)).map(\.threshold) == [80])
    }

    /// FR-015: values shown from a stale or local-only entry count.
    @Test func staleAndLocalOnlyValuesCount() {
        var tracker = ThresholdTracker()
        _ = Self.observe(&tracker, Self.plus(weekly: 70, state: .stale(reason: "offline")))
        #expect(Self.observe(&tracker, Self.plus(weekly: 85, state: .stale(reason: "offline"))).count == 1)

        var local = ThresholdTracker()
        let localConfig = Self.config(liveLimits: false)
        _ = Self.observe(&local, Self.free(50), config: localConfig)
        #expect(Self.observe(&local, Self.free(85), config: localConfig).map(\.windowKind.displayName) == ["30-day"])
    }

    @Test func unavailableEntryYieldsNoCrossing() {
        var tracker = ThresholdTracker()
        #expect(Self.observe(&tracker, CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline"))).isEmpty)
        #expect(tracker.trackedEntityIds.isEmpty)
    }

    /// FR-015: a window that disappears loses its state; a new window starts
    /// with a baseline.
    @Test func planChangeDropsOldWindowsAndBaselinesNewOnes() {
        var tracker = ThresholdTracker()
        _ = Self.observe(&tracker, Self.free(50, state: .live))
        #expect(Self.observe(&tracker, Self.plus(five: 90, weekly: 90)).isEmpty)
        // Back to Free: the 30-day state was dropped, so 90% is a baseline.
        #expect(Self.observe(&tracker, Self.free(90, state: .live)).isEmpty)
    }

    /// FR-015: toggling live limits starts a new baseline.
    @Test func togglingLiveLimitsStartsANewBaseline() {
        var tracker = ThresholdTracker()
        _ = Self.observe(&tracker, Self.plus(weekly: 70))
        #expect(Self.observe(&tracker, Self.plus(weekly: 85, state: .localOnly), config: Self.config(liveLimits: false)).isEmpty)
        #expect(Self.observe(&tracker, Self.plus(weekly: 96, state: .localOnly), config: Self.config(liveLimits: false)).map(\.threshold) == [95])
    }

    /// FR-015: an entry computed under the previous live-limits setting (a
    /// refresh that started before the toggle) neither notifies nor becomes
    /// the new setting's baseline.
    @Test func entryOfTheOtherSettingIsSkipped() {
        var tracker = ThresholdTracker()
        let live = Self.config(liveLimits: true)
        // Live limits were just turned on; the refresh still ran with them off.
        #expect(Self.observe(&tracker, Self.plus(weekly: 70, state: .localOnly), config: live).isEmpty)
        #expect(tracker.trackedEntityIds.isEmpty)
        // The first live value is the baseline, not a crossing from 70.
        #expect(Self.observe(&tracker, Self.plus(weekly: 85), config: live).isEmpty)
        #expect(Self.observe(&tracker, Self.plus(weekly: 96), config: live).map(\.threshold) == [95])
        // And the other way round.
        var local = ThresholdTracker()
        let off = Self.config(liveLimits: false)
        #expect(Self.observe(&local, Self.plus(weekly: 70, state: .stale(reason: "offline")), config: off).isEmpty)
        #expect(Self.observe(&local, Self.plus(weekly: 70, state: .newerSnapshot), config: off).isEmpty)
        #expect(local.trackedEntityIds.isEmpty)
    }

    /// A newer snapshot between fetches comes from a refresh with live
    /// limits on, so it uses the live keys: no new baseline (FR-015).
    @Test func newerSnapshotUsesTheLiveKeys() {
        var tracker = ThresholdTracker()
        let live = Self.config(liveLimits: true)
        #expect(Self.observe(&tracker, Self.plus(weekly: 70), config: live).isEmpty)
        #expect(Self.observe(&tracker, Self.plus(weekly: 85, state: .newerSnapshot), config: live).map(\.threshold) == [80])
    }

    /// A missing or unavailable entry in between keeps the state.
    @Test func gapsKeepTheState() {
        var tracker = ThresholdTracker()
        _ = Self.observe(&tracker, Self.plus(weekly: 70))
        _ = Self.observe(&tracker, CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline")))
        _ = Self.observe(&tracker, nil)
        #expect(tracker.trackedEntityIds == ["acc-codex"])
        #expect(Self.observe(&tracker, Self.plus(weekly: 85)).map(\.threshold) == [80])
    }

    /// FR-015: toggling live limits off and on while no values are shown
    /// (no snapshot in the Codex home) still starts a new baseline.
    @Test func toggleWhileUnavailableStartsANewBaseline() {
        var tracker = ThresholdTracker()
        let unavailable = CodexLimitsEntry(observation: nil, state: .unavailable(reason: "no Codex plan limits recorded in this Codex home"))
        #expect(Self.observe(&tracker, Self.plus(weekly: 70)).isEmpty)
        #expect(Self.observe(&tracker, unavailable, config: Self.config(liveLimits: false)).isEmpty)
        #expect(Self.observe(&tracker, Self.plus(weekly: 85)).isEmpty)
        #expect(Self.observe(&tracker, Self.plus(weekly: 96)).map(\.threshold) == [95])
    }

    /// FR-014: a window the source gave no reset time is still checked; a
    /// window whose reset passed is not (FR-010).
    @Test func windowWithoutResetTimeIsChecked() {
        func weekly(_ percent: Double, resetsAt: Date?) -> CodexLimitsEntry {
            CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: Self.now, origin: .live, windows: [
                CodexLimitWindow(lengthMinutes: 10080, usedPercent: percent, resetsAt: resetsAt),
            ]), state: .live)
        }
        var tracker = ThresholdTracker()
        #expect(Self.observe(&tracker, weekly(70, resetsAt: nil)).isEmpty)
        #expect(Self.observe(&tracker, weekly(85, resetsAt: nil)).map(\.threshold) == [80])

        var passed = ThresholdTracker()
        let past = Self.now.addingTimeInterval(-60)
        #expect(Self.observe(&passed, weekly(70, resetsAt: past)).isEmpty)
        #expect(Self.observe(&passed, weekly(99, resetsAt: past)).isEmpty)
    }

    /// Live and snapshot reset times differ slightly for the same window.
    @Test func smallResetDifferencesDoNotRebaseline() {
        var tracker = ThresholdTracker()
        _ = Self.observe(&tracker, Self.plus(weekly: 70))
        #expect(Self.observe(&tracker, Self.plus(weekly: 85, weekReset: Self.weekReset.addingTimeInterval(30))).count == 1)
        // A larger move forward is a reset, compared with 0 (spec 015 FR-001).
        #expect(Self.observe(&tracker, Self.plus(weekly: 96, weekReset: Self.weekReset.addingTimeInterval(600))).map(\.threshold) == [80, 95])
    }

    /// FR-010: a window whose reset passed has no reset time and is not
    /// evaluated, but keeps its state until the next observation.
    @Test func resetPassedWindowIsSkipped() {
        var seeded = ThresholdTracker()
        _ = Self.observe(&seeded, Self.plus(weekly: 70))
        let passed = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: Self.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 10, resetsAt: Self.fiveReset),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 70, resetsAt: Self.now.addingTimeInterval(-1)),
        ]), state: .stale(reason: "offline"))
        #expect(Self.observe(&seeded, passed).isEmpty)
        #expect(seeded.trackedEntityIds == ["acc-codex"])
        // The weekly state survived: the same reset time crossing 80 notifies.
        #expect(Self.observe(&seeded, Self.plus(weekly: 85)).map(\.threshold) == [80])

        var tracker = ThresholdTracker()
        let soon = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: Self.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 90, resetsAt: Self.now.addingTimeInterval(-1)),
        ]), state: .stale(reason: "offline"))
        #expect(Self.observe(&tracker, soon).isEmpty)
        #expect(tracker.trackedEntityIds.isEmpty)
    }
}

/// Spec 009 FR-006, research R5: empty groups and groups that get members
/// again.
extension OwnBudgetThresholdTests {
    /// An empty group has spend 0 and never notifies; when it gets a member
    /// whose spend already exceeds a threshold, the first refresh is a
    /// baseline, and a later crossing notifies.
    @Test func emptyGroupNeverNotifiesAndRebaselinesWhenRefilled() {
        var tracker = ThresholdTracker()
        let empty = config().removingAccount(id: "acc-g")
        #expect(empty.members(of: "grp").isEmpty)
        for _ in 0..<3 {
            #expect(tracker.observe(snapshot: snapshot(groupPercent: 0, groupMembers: []), configuration: empty).isEmpty)
        }

        let refilled = empty.movingAccountToGroup(accountId: "acc-o", groupId: "grp")
        #expect(tracker.observe(snapshot: snapshot(groupPercent: 95, groupMembers: ["acc-o"]), configuration: refilled).isEmpty)
        let later = tracker.observe(snapshot: snapshot(groupPercent: 101, groupMembers: ["acc-o"]), configuration: refilled)
        #expect(later.map(\.threshold) == [100])
    }
}

/// Spec 009 FR-006, FR-011, FR-012: thresholds after a group removal and
/// its undo. `grp` holds acc-g1 and acc-g2, `dest` holds acc-d.
@Suite struct GroupRemovalThresholdTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "acc-g1", displayName: "One", kind: .tokenBased(TokenBasedSettings(groupId: "grp"))),
            Account(id: "acc-g2", displayName: "Two", kind: .tokenBased(TokenBasedSettings(groupId: "grp"))),
            Account(id: "acc-d", displayName: "Dest member", kind: .tokenBased(TokenBasedSettings(groupId: "dest"))),
        ]
        c.groups = [
            BudgetGroup(id: "grp", name: "Team", budgetUSD: 100, thresholds: [80, 100]),
            BudgetGroup(id: "dest", name: "Destination", budgetUSD: 100, thresholds: [80, 100]),
        ]
        return c
    }

    func entry(_ percent: Int, members: [String]) -> GroupEntry {
        GroupEntry(spentUSD: Decimal(percent), budgetUSD: 100, percent: percent, incomplete: false,
                   window: window, breakdown: .empty, members: members)
    }

    func snapshot(groups: [String: GroupEntry] = [:], own: [String: GroupEntry] = [:]) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: window.start.addingTimeInterval(3600), window: window, windowSource: .fallback)
        s.groups = groups
        s.accountBudgets = own
        return s
    }

    func baseline(_ tracker: inout ThresholdTracker) {
        let before = snapshot(groups: ["grp": entry(40, members: ["acc-g1", "acc-g2"]), "dest": entry(40, members: ["acc-d"])])
        #expect(tracker.observe(snapshot: before, configuration: config()).isEmpty)
        #expect(tracker.trackedEntityIds == ["dest", "grp"])
    }

    /// "Own budgets": the new own budgets start with a baseline and the
    /// removed group's state is cleared.
    @Test func newOwnBudgetsRebaselineAndTheGroupIsCleared() {
        var tracker = ThresholdTracker()
        baseline(&tracker)
        let removed = config().removingGroup(id: "grp", destination: .ownBudgets)
        let above = snapshot(groups: ["dest": entry(40, members: ["acc-d"])],
                             own: ["acc-g1": entry(95, members: ["acc-g1"]), "acc-g2": entry(90, members: ["acc-g2"])])
        #expect(tracker.observe(snapshot: above, configuration: removed).isEmpty)
        #expect(!tracker.trackedEntityIds.contains("grp"))
        #expect(tracker.trackedEntityIds == ["acc-g1", "acc-g2", "dest"])
        let later = snapshot(groups: ["dest": entry(40, members: ["acc-d"])],
                             own: ["acc-g1": entry(101, members: ["acc-g1"]), "acc-g2": entry(90, members: ["acc-g2"])])
        #expect(tracker.observe(snapshot: later, configuration: removed).map { "\($0.entityId)/\($0.threshold)" } == ["acc-g1/100"])
    }

    /// Another group: the destination re-baselines with its new member set.
    @Test func destinationGroupRebaselines() {
        var tracker = ThresholdTracker()
        baseline(&tracker)
        let removed = config().removingGroup(id: "grp", destination: .group(id: "dest"))
        let ordered = removed.members(of: "dest").map(\.id)
        #expect(ordered == ["acc-g1", "acc-g2", "acc-d"])
        #expect(tracker.observe(snapshot: snapshot(groups: ["dest": entry(95, members: ordered)]), configuration: removed).isEmpty)
        #expect(!tracker.trackedEntityIds.contains("grp"))
        let later = tracker.observe(snapshot: snapshot(groups: ["dest": entry(101, members: ordered)]), configuration: removed)
        #expect(later.map(\.threshold) == [100])
    }

    /// Undo: the restored group re-baselines, even when it is already
    /// above a threshold.
    @Test func restoredGroupRebaselinesAfterUndo() {
        var tracker = ThresholdTracker()
        baseline(&tracker)
        let removed = config().removingGroup(id: "grp", destination: .ownBudgets)
        _ = tracker.observe(snapshot: snapshot(groups: ["dest": entry(40, members: ["acc-d"])],
                                               own: ["acc-g1": entry(40, members: ["acc-g1"]), "acc-g2": entry(40, members: ["acc-g2"])]),
                            configuration: removed)
        let restored = config()
        let above = snapshot(groups: ["grp": entry(95, members: ["acc-g1", "acc-g2"]), "dest": entry(40, members: ["acc-d"])])
        #expect(tracker.observe(snapshot: above, configuration: restored).isEmpty)
        #expect(tracker.trackedEntityIds == ["dest", "grp"])
        let later = snapshot(groups: ["grp": entry(101, members: ["acc-g1", "acc-g2"]), "dest": entry(40, members: ["acc-d"])])
        #expect(tracker.observe(snapshot: later, configuration: restored).map(\.threshold) == [100])
    }

    /// Undo of a removal into another group: the destination shrinks back
    /// to its old member set and re-baselines, even when it is already
    /// above a threshold (FR-012).
    @Test func destinationRebaselinesAfterUndo() {
        var tracker = ThresholdTracker()
        baseline(&tracker)
        let removed = config().removingGroup(id: "grp", destination: .group(id: "dest"))
        let merged = removed.members(of: "dest").map(\.id)
        _ = tracker.observe(snapshot: snapshot(groups: ["dest": entry(40, members: merged)]), configuration: removed)
        let restored = config()
        let above = snapshot(groups: ["grp": entry(40, members: ["acc-g1", "acc-g2"]), "dest": entry(95, members: ["acc-d"])])
        #expect(tracker.observe(snapshot: above, configuration: restored).isEmpty)
        let later = snapshot(groups: ["grp": entry(40, members: ["acc-g1", "acc-g2"]), "dest": entry(101, members: ["acc-d"])])
        #expect(tracker.observe(snapshot: later, configuration: restored).map { "\($0.entityId)/\($0.threshold)" } == ["dest/100"])
    }
}

/// Spec 015 FR-001 to FR-003, SC-001: a window reset compares the first
/// value of the new window with 0, while the five re-baseline events still
/// only record a baseline (research R1).
@Suite struct WindowResetThresholdTests {
    /// One window of each kind the tracker knows.
    enum Subject: String, CaseIterable, Sendable {
        case claudeFiveHour, claudeSevenDay, codexWeekly, weeklyGroup, monthlyOwnBudget

        var isBudgetOwner: Bool { self == .weeklyGroup || self == .monthlyOwnBudget }
    }

    static let now = isoDate("2026-10-14T15:00:00Z")
    static let week = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    static let october = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
    static let fiveHourReset = isoDate("2026-10-14T18:00:00Z")
    static let sevenDayReset = isoDate("2026-10-16T07:00:00Z")
    static let codexWeekReset = isoDate("2026-10-18T09:00:00Z")

    /// Which window an observation belongs to.
    enum Window { case old, new, movedStart }

    static func config(thresholds: [Int] = [80, 95], liveLimits: Bool = true, groupPeriod: BudgetPeriod = .weekly,
                       claudeDirectory: String = "~/.claude", codexHome: String = "~/.codex") -> Configuration {
        var c = Configuration(accounts: [
            Account(id: "acc-max", displayName: "Claude Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: claudeDirectory, shownInBar: true, thresholds: thresholds))),
            Account(id: "acc-codex", displayName: "ChatGPT Plus", harness: .codex,
                    kind: .codexSubscription(CodexSubscriptionSettings(codexHome: codexHome, thresholds: thresholds, liveLimits: liveLimits))),
            Account(id: "acc-g", displayName: "Group member", kind: .tokenBased(TokenBasedSettings(groupId: "grp"))),
            Account(id: "acc-o", displayName: "Personal Vertex",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(period: .monthly, budgetUSD: 100, thresholds: thresholds))))),
        ])
        c.groups = [BudgetGroup(id: "grp", name: "Team", period: groupPeriod, budgetUSD: 100, thresholds: thresholds)]
        return c
    }

    static func budgetWindow(_ base: DateInterval, _ window: Window) -> DateInterval {
        switch window {
        case .old: return base
        case .new: return DateInterval(start: base.end, duration: base.duration)
        case .movedStart: return DateInterval(start: base.start.addingTimeInterval(3600), end: base.end)
        }
    }

    static func reset(_ base: Date, length: TimeInterval, _ window: Window) -> Date {
        window == .new ? base.addingTimeInterval(length) : base
    }

    /// A snapshot with only `subject`'s value.
    static func snapshot(_ subject: Subject, _ percent: Int, _ window: Window = .old, stale: Bool = false,
                         members: [String] = ["acc-g"], codexState: CodexLimitsState = .live) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: now, window: week, windowSource: .fallback)
        switch subject {
        case .claudeFiveHour, .claudeSevenDay:
            let five = subject == .claudeFiveHour
            let limit = LimitWindow(utilizationPercent: Double(percent),
                                    resetsAt: five ? reset(fiveHourReset, length: 5 * 3600, window) : reset(sevenDayReset, length: 7 * 86400, window))
            let status = SubscriptionStatus(fiveHour: five ? limit : nil, sevenDay: five ? nil : limit, fetchedAt: now)
            s.subscriptions["acc-max"] = SubscriptionEntry(status: status, state: stale ? .stale(lastGoodAt: nil, error: "offline") : .ok)
        case .codexWeekly:
            s.codexLimits["acc-codex"] = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: now, origin: .live, windows: [
                CodexLimitWindow(lengthMinutes: 10080, usedPercent: Double(percent), resetsAt: reset(codexWeekReset, length: 7 * 86400, window)),
            ]), state: codexState)
        case .weeklyGroup:
            s.groups["grp"] = GroupEntry(spentUSD: Decimal(percent), budgetUSD: 100, percent: percent, incomplete: false,
                                         window: budgetWindow(week, window), breakdown: .empty, members: members, stale: stale)
        case .monthlyOwnBudget:
            s.accountBudgets["acc-o"] = GroupEntry(spentUSD: Decimal(percent), budgetUSD: 100, percent: percent, incomplete: false,
                                                   period: .monthly, window: budgetWindow(october, window), breakdown: .empty,
                                                   members: ["acc-o"], stale: stale)
        }
        return s
    }

    static func thresholds(_ tracker: inout ThresholdTracker, _ snapshot: UsageSnapshot, _ config: Configuration = config()) -> [Int] {
        tracker.observe(snapshot: snapshot, configuration: config).map(\.threshold)
    }

    /// US1 scenarios 1 to 3 for every window kind; budget owners also for a
    /// window whose start moved while its end stayed (spec 003 FR-016).
    @Test(arguments: Subject.allCases)
    func resetComparesTheFirstValueOfTheNewWindowWithZero(_ subject: Subject) {
        let resets: [Window] = subject.isBudgetOwner ? [.new, .movedStart] : [.new]
        for next in resets {
            var one = ThresholdTracker()
            #expect(Self.thresholds(&one, Self.snapshot(subject, 40)).isEmpty)
            #expect(Self.thresholds(&one, Self.snapshot(subject, 85, next)) == [80])
            #expect(Self.thresholds(&one, Self.snapshot(subject, 90, next)).isEmpty)

            var two = ThresholdTracker()
            _ = Self.thresholds(&two, Self.snapshot(subject, 40))
            #expect(Self.thresholds(&two, Self.snapshot(subject, 97, next)) == [80, 95])

            var none = ThresholdTracker()
            _ = Self.thresholds(&none, Self.snapshot(subject, 40))
            #expect(Self.thresholds(&none, Self.snapshot(subject, 30, next)).isEmpty)
            #expect(Self.thresholds(&none, Self.snapshot(subject, 82, next)) == [80])
        }
    }

    /// FR-003: refreshes without a usable value between the old and the new
    /// window keep the state, so the reset is still recognized.
    @Test(arguments: Subject.allCases)
    func resetAfterRefreshesWithoutAValueStillNotifies(_ subject: Subject) {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.snapshot(subject, 40))
        let empty = UsageSnapshot(generatedAt: Self.now, window: Self.week, windowSource: .fallback)
        #expect(Self.thresholds(&tracker, empty).isEmpty)
        if subject != .codexWeekly {
            #expect(Self.thresholds(&tracker, Self.snapshot(subject, 90, .new, stale: true)).isEmpty)
        } else {
            let unavailable = CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline"))
            var gap = empty
            gap.codexLimits["acc-codex"] = unavailable
            #expect(Self.thresholds(&tracker, gap).isEmpty)
        }
        #expect(Self.thresholds(&tracker, Self.snapshot(subject, 85, .new)) == [80])
    }

    /// Thresholds edited in the same refresh as a reset decide the crossings.
    @Test(arguments: Subject.allCases)
    func editedThresholdsApplyOnAReset(_ subject: Subject) {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.snapshot(subject, 40))
        #expect(Self.thresholds(&tracker, Self.snapshot(subject, 85, .new), Self.config(thresholds: [50, 90])) == [50])
    }

    /// Re-baseline 1, launch (spec 001 FR-028): the first observation of a
    /// window never notifies, whatever its window.
    @Test(arguments: Subject.allCases)
    func firstObservationAfterLaunchIsABaseline(_ subject: Subject) {
        var tracker = ThresholdTracker()
        #expect(Self.thresholds(&tracker, Self.snapshot(subject, 85, .new)).isEmpty)
        #expect(Self.thresholds(&tracker, Self.snapshot(subject, 90, .new)).isEmpty)
        #expect(Self.thresholds(&tracker, Self.snapshot(subject, 96, .new)) == [95])
    }

    /// Re-baseline 2, period switch (spec 003 FR-017), even though the new
    /// period's window differs from the old one.
    @Test func periodSwitchIsABaseline() {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.snapshot(.weeklyGroup, 40))
        var monthly = UsageSnapshot(generatedAt: Self.now, window: Self.week, windowSource: .fallback)
        monthly.groups["grp"] = GroupEntry(spentUSD: 85, budgetUSD: 100, percent: 85, incomplete: false, period: .monthly,
                                           window: Self.october, breakdown: .empty, members: ["acc-g"])
        #expect(Self.thresholds(&tracker, monthly, Self.config(groupPeriod: .monthly)).isEmpty)
    }

    /// Re-baseline 3, member set change (spec 004 FR-015), also when the
    /// window resets in the same refresh: the re-baseline wins (FR-002).
    @Test func memberSetChangeWinsOverAWindowReset() {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.snapshot(.weeklyGroup, 40))
        let moved = Self.config().movingAccountToGroup(accountId: "acc-o", groupId: "grp")
        let members = moved.members(of: "grp").map(\.id)
        #expect(Self.thresholds(&tracker, Self.snapshot(.weeklyGroup, 85, .new, members: members), moved).isEmpty)
        #expect(Self.thresholds(&tracker, Self.snapshot(.weeklyGroup, 96, .new, members: members), moved) == [95])

        // Same member set, same window: no reset, so the baseline is 40.
        var same = ThresholdTracker()
        _ = Self.thresholds(&same, Self.snapshot(.weeklyGroup, 40, members: members), moved)
        #expect(Self.thresholds(&same, Self.snapshot(.weeklyGroup, 85, members: members), moved) == [80])
    }

    /// Re-baseline 4, Codex live-limits toggle (spec 007 FR-015), also when
    /// the window moved.
    @Test func codexLiveLimitsToggleIsABaseline() {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.snapshot(.codexWeekly, 40))
        let off = Self.config(liveLimits: false)
        #expect(Self.thresholds(&tracker, Self.snapshot(.codexWeekly, 85, .new, codexState: .localOnly), off).isEmpty)
        #expect(Self.thresholds(&tracker, Self.snapshot(.codexWeekly, 96, .new, codexState: .localOnly), off) == [95])
    }

    /// Re-baseline 5, saved Claude values at launch (spec 010 FR-019): they
    /// set no state, so the first refresh is the launch baseline.
    @Test(arguments: [Subject.claudeFiveHour, .claudeSevenDay])
    func preliminaryValuesAtLaunchAreNoBaseline(_ subject: Subject) {
        var tracker = ThresholdTracker()
        var early = Self.snapshot(subject, 40)
        early.isPreliminary = true
        #expect(Self.thresholds(&tracker, early).isEmpty)
        #expect(Self.thresholds(&tracker, Self.snapshot(subject, 85, .new)).isEmpty)
    }

    /// Preliminary values seen while state exists neither notify nor move it.
    @Test func preliminaryValuesOfANewWindowDoNotNotify() {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.snapshot(.claudeFiveHour, 40))
        var early = Self.snapshot(.claudeFiveHour, 85, .new)
        early.isPreliminary = true
        #expect(Self.thresholds(&tracker, early).isEmpty)
    }

    static func codex(_ percent: Int, resetsAt: Date?) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: now, window: week, windowSource: .fallback)
        s.codexLimits["acc-codex"] = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: Double(percent), resetsAt: resetsAt),
        ]), state: .live)
        return s
    }

    /// A reset time that moves within the Codex tolerance is the same window.
    @Test func codexMoveWithinTheToleranceIsNoReset() {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.codex(85, resetsAt: Self.codexWeekReset))
        let near = Self.codexWeekReset.addingTimeInterval(ThresholdTracker.codexResetTolerance)
        #expect(Self.thresholds(&tracker, Self.codex(86, resetsAt: near)).isEmpty)
        #expect(Self.thresholds(&tracker, Self.codex(87, resetsAt: Self.codexWeekReset.addingTimeInterval(-60))).isEmpty)
    }

    /// Gaining or losing the reset time re-baselines without notifying.
    @Test func codexGainingOrLosingTheResetTimeIsABaseline() {
        var gaining = ThresholdTracker()
        _ = Self.thresholds(&gaining, Self.codex(40, resetsAt: nil))
        #expect(Self.thresholds(&gaining, Self.codex(85, resetsAt: Self.codexWeekReset)).isEmpty)
        #expect(Self.thresholds(&gaining, Self.codex(96, resetsAt: Self.codexWeekReset)) == [95])

        var losing = ThresholdTracker()
        _ = Self.thresholds(&losing, Self.codex(40, resetsAt: Self.codexWeekReset))
        #expect(Self.thresholds(&losing, Self.codex(85, resetsAt: nil)).isEmpty)
        #expect(Self.thresholds(&losing, Self.codex(96, resetsAt: nil)) == [95])
    }

    /// Live and snapshot values alternating between two ends notify at most
    /// once, for the later window.
    @Test func codexAlternatingEndsNotifyOnce() {
        var tracker = ThresholdTracker()
        let a = Self.codexWeekReset
        let b = a.addingTimeInterval(7 * 86400)
        _ = Self.thresholds(&tracker, Self.codex(40, resetsAt: a))
        var all: [Int] = []
        for (index, end) in [b, a, b, a, b].enumerated() {
            all += Self.thresholds(&tracker, Self.codex(85 + index, resetsAt: end))
        }
        #expect(all == [80])
    }

    /// An observation with an earlier end is older data: ignored, and the
    /// state of the later window is kept.
    @Test func codexEarlierEndIsIgnored() {
        var tracker = ThresholdTracker()
        let later = Self.codexWeekReset.addingTimeInterval(7 * 86400)
        _ = Self.thresholds(&tracker, Self.codex(40, resetsAt: later))
        #expect(Self.thresholds(&tracker, Self.codex(99, resetsAt: Self.codexWeekReset)).isEmpty)
        #expect(Self.thresholds(&tracker, Self.codex(85, resetsAt: later)) == [80])
    }

    /// The same rule holds for Claude windows: an earlier end is ignored.
    @Test func claudeEarlierEndIsIgnored() {
        var tracker = ThresholdTracker()
        _ = Self.thresholds(&tracker, Self.snapshot(.claudeFiveHour, 40, .new))
        #expect(Self.thresholds(&tracker, Self.snapshot(.claudeFiveHour, 99, .old)).isEmpty)
        #expect(Self.thresholds(&tracker, Self.snapshot(.claudeFiveHour, 85, .new)) == [80])
    }

    /// Re-baseline 6, a changed credential directory or Codex home (spec 015
    /// FR-002): the account may now read another login whose window ends
    /// earlier or later, so neither an older end is ignored nor a later end
    /// counts as a reset.
    @Test(arguments: [Subject.claudeFiveHour, .claudeSevenDay, .codexWeekly])
    func directoryChangeIsABaseline(_ subject: Subject) {
        let moved = Self.config(claudeDirectory: "~/.claude-work", codexHome: "~/.codex-work")

        var earlier = ThresholdTracker()
        _ = Self.thresholds(&earlier, Self.snapshot(subject, 40, .new))
        #expect(Self.thresholds(&earlier, Self.snapshot(subject, 85, .old), moved).isEmpty)
        #expect(Self.thresholds(&earlier, Self.snapshot(subject, 96, .old), moved) == [95])

        var later = ThresholdTracker()
        _ = Self.thresholds(&later, Self.snapshot(subject, 40))
        #expect(Self.thresholds(&later, Self.snapshot(subject, 85, .new), moved).isEmpty)
        #expect(Self.thresholds(&later, Self.snapshot(subject, 96, .new), moved) == [95])
    }

    /// Claude reset times are rounded to the minute, so jitter across a
    /// minute boundary is the same window, not a reset (spec 015 FR-001).
    @Test func claudeMinuteJitterIsNoReset() {
        var tracker = ThresholdTracker()
        let end = Self.fiveHourReset
        var all: [Int] = []
        for (index, shift) in [0.0, 60, 0, 60, -60, 0].enumerated() {
            var s = Self.snapshot(.claudeFiveHour, 85 + index)
            s.subscriptions["acc-max"] = SubscriptionEntry(status: SubscriptionStatus(
                fiveHour: LimitWindow(utilizationPercent: Double(85 + index), resetsAt: end.addingTimeInterval(shift)),
                sevenDay: nil, fetchedAt: Self.now), state: .ok)
            all += Self.thresholds(&tracker, s)
        }
        #expect(all.isEmpty)
        // A real reset is still one.
        #expect(Self.thresholds(&tracker, Self.snapshot(.claudeFiveHour, 85, .new)) == [80])
    }

    /// A Codex window that appears while the app runs (spec 007 FR-015) has
    /// no state yet and records a baseline.
    @Test func codexWindowAppearingWhileRunningIsABaseline() {
        var tracker = ThresholdTracker()
        var five = UsageSnapshot(generatedAt: Self.now, window: Self.week, windowSource: .fallback)
        five.codexLimits["acc-codex"] = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: Self.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 10, resetsAt: Self.fiveHourReset),
        ]), state: .live)
        _ = Self.thresholds(&tracker, five)
        var both = five
        both.codexLimits["acc-codex"] = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: Self.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 10, resetsAt: Self.fiveHourReset),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 90, resetsAt: Self.codexWeekReset),
        ]), state: .live)
        #expect(Self.thresholds(&tracker, both).isEmpty)
    }
}
