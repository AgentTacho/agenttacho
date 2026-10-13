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
            Account(id: "acc-max", label: "M", displayName: "Claude Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: subscriptionThresholds))),
            Account(id: "acc-v", label: "VC", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex))),
        ]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex weekly", label: "V", weeklyBudgetUSD: 100, shownInBar: true, thresholds: groupThresholds)]
        return c
    }

    func snapshot(groupPercent: Int? = nil, groupStale: Bool = false, window: DateInterval? = nil,
                  fiveHour: Double? = nil, sevenDay: Double? = nil, fiveHourReset: Date? = nil, sevenDayReset: Date? = nil,
                  state: SubscriptionState = .ok) -> UsageSnapshot {
        let w = window ?? self.window
        var s = UsageSnapshot(generatedAt: w.start.addingTimeInterval(3600), window: w, windowSource: .fallback)
        if let groupPercent {
            s.groups["grp"] = GroupEntry(spentUSD: Decimal(groupPercent), budgetUSD: 100, percent: groupPercent, incomplete: false,
                                         resetAt: w.end, breakdown: .empty, members: ["acc-v"], stale: groupStale)
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
