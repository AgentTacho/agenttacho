import Foundation
import Testing
@testable import UsageCore

@Suite struct EndpointPolicyTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func fetched(_ policy: inout EndpointPolicy, at date: Date) {
        _ = policy.decide(.launch, now: date)
        _ = policy.record(.success, now: date)
    }

    private func isReuse(_ decision: EndpointPolicy.Decision, prefix: String) -> Bool {
        if case .reuse(let reason, _) = decision { return reason.hasPrefix(prefix) }
        return false
    }

    @Test func localAlwaysReusesEvenBeforeTheFirstFetch() {
        var policy = EndpointPolicy(refreshInterval: 300)
        #expect(isReuse(policy.decide(.local, now: t0), prefix: "local change"))
    }

    @Test func firstDecisionFetchesForEveryNetworkTrigger() {
        for trigger in RefreshTrigger.allCases where trigger != .local {
            var policy = EndpointPolicy(refreshInterval: 300)
            #expect(policy.decide(trigger, now: t0) == .fetch, "trigger \(trigger)")
        }
    }

    @Test func userTriggersAreSpacedBySixtySecondsWithAnInclusiveBoundary() {
        for trigger in [RefreshTrigger.manual, .wake, .settings] {
            var policy = EndpointPolicy(refreshInterval: 300)
            fetched(&policy, at: t0)
            #expect(isReuse(policy.decide(trigger, now: t0.addingTimeInterval(59)), prefix: "last fetch 59 s ago"), "trigger \(trigger)")
            #expect(policy.decide(trigger, now: t0.addingTimeInterval(60)) == .fetch, "trigger \(trigger)")
        }
    }

    @Test func scheduledAndLaunchIgnoreSpacing() {
        var policy = EndpointPolicy(refreshInterval: 300)
        fetched(&policy, at: t0)
        #expect(policy.decide(.scheduled, now: t0.addingTimeInterval(10)) == .fetch)
        #expect(policy.decide(.launch, now: t0.addingTimeInterval(10)) == .fetch)
    }

    @Test func retryAfterSuccessIsReusedAsAlreadyFresh() {
        var policy = EndpointPolicy(refreshInterval: 300)
        fetched(&policy, at: t0)
        #expect(isReuse(policy.decide(.retry, now: t0.addingTimeInterval(120)), prefix: "already fresh"))
    }

    @Test func rateLimitBlocksEveryTriggerUntilRetryAfter() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.decide(.launch, now: t0)
        let retryAt = policy.record(.rateLimited(retryAfter: 120), now: t0)
        #expect(retryAt == t0.addingTimeInterval(120))
        #expect(policy.blockedUntil == t0.addingTimeInterval(120))
        for trigger in [RefreshTrigger.scheduled, .launch, .wake, .manual, .settings, .retry] {
            #expect(isReuse(policy.decide(trigger, now: t0.addingTimeInterval(119)), prefix: "rate limited until"), "trigger \(trigger)")
        }
        #expect(policy.decide(.retry, now: t0.addingTimeInterval(120)) == .fetch)
    }

    @Test func wakeDuringABlockDoesNotFetch() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.decide(.launch, now: t0)
        _ = policy.record(.rateLimited(retryAfter: 600), now: t0)
        #expect(isReuse(policy.decide(.wake, now: t0.addingTimeInterval(300)), prefix: "rate limited until"))
    }

    @Test func retryAfterZeroDoesNotLeaveABlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.decide(.launch, now: t0)
        let retryAt = policy.record(.rateLimited(retryAfter: 0), now: t0)
        #expect(retryAt == t0)
        #expect(policy.decide(.retry, now: t0.addingTimeInterval(1)) == .fetch)
    }

    @Test func backoffDoublesAndCapsAtTheRefreshInterval() {
        var policy = EndpointPolicy(refreshInterval: 300)
        var waits: [TimeInterval] = []
        var now = t0
        for _ in 0..<5 {
            _ = policy.record(.rateLimited(retryAfter: nil), now: now)
            waits.append(policy.blockedUntil!.timeIntervalSince(now))
            now = policy.blockedUntil!
        }
        #expect(waits == [60, 120, 240, 300, 300])
    }

    @Test func backoffCapFollowsAChangedRefreshInterval() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        policy.refreshInterval = 90
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        #expect(policy.blockedUntil == t0.addingTimeInterval(90))
    }

    @Test func retryAfterHeaderWinsOverBackoff() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: 1000), now: t0)
        #expect(policy.blockedUntil == t0.addingTimeInterval(1000))
    }

    @Test func successResetsBackoffAndBlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        _ = policy.record(.success, now: t0.addingTimeInterval(200))
        #expect(policy.blockedUntil == nil)
        #expect(policy.consecutiveRateLimits == 0)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0.addingTimeInterval(300))
        #expect(policy.blockedUntil == t0.addingTimeInterval(360))
    }

    @Test func onlyOneRetryPerScheduledPeriod() {
        var policy = EndpointPolicy(refreshInterval: 300)
        #expect(policy.record(.rateLimited(retryAfter: 60), now: t0) != nil)
        #expect(policy.record(.rateLimited(retryAfter: 60), now: t0.addingTimeInterval(61)) == nil)
        // A scheduled tick inside the block resets the allowance and asks for one retry.
        let decision = policy.decide(.scheduled, now: t0.addingTimeInterval(100))
        #expect(decision == .reuse(reason: decision.reason, retryAt: t0.addingTimeInterval(121)))
        #expect(policy.retryUsed)
        #expect(policy.record(.rateLimited(retryAfter: 60), now: t0.addingTimeInterval(121)) == nil)
    }

    @Test func otherErrorCountsForSpacingButDoesNotBlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        #expect(policy.record(.otherError, now: t0) == nil)
        #expect(policy.blockedUntil == nil)
        #expect(isReuse(policy.decide(.manual, now: t0.addingTimeInterval(10)), prefix: "last fetch"))
        #expect(policy.decide(.scheduled, now: t0.addingTimeInterval(10)) == .fetch)
    }

    @Test func clockMovingBackwardsExpiresTheBlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: 3600), now: t0)
        #expect(policy.decide(.scheduled, now: t0.addingTimeInterval(-600)) == .fetch)
        #expect(policy.blockedUntil == nil)
    }

    @Test func combinedOutcomes() {
        #expect(FetchOutcome.combined([]) == nil)
        #expect(FetchOutcome.combined([.success, .success]) == .success)
        #expect(FetchOutcome.combined([.success, .otherError]) == .otherError)
        #expect(FetchOutcome.combined([.success, .rateLimited(retryAfter: 30), .rateLimited(retryAfter: 90)]) == .rateLimited(retryAfter: 90))
        #expect(FetchOutcome.combined([.rateLimited(retryAfter: nil), .otherError]) == .rateLimited(retryAfter: nil))
        #expect(FetchOutcome.combined([.rateLimited(retryAfter: nil), .rateLimited(retryAfter: 30)]) == .rateLimited(retryAfter: 30))
    }

    @Test func triggerRanks() {
        #expect(RefreshTrigger.scheduled.rank == RefreshTrigger.retry.rank)
        #expect(RefreshTrigger.retry.rank > RefreshTrigger.manual.rank)
        #expect(RefreshTrigger.manual.rank == RefreshTrigger.settings.rank)
        #expect(RefreshTrigger.launch.rank > RefreshTrigger.local.rank)
    }
}

extension EndpointPolicy.Decision {
    /// The reason of a reuse decision, empty for `.fetch` (test helper).
    var reason: String {
        if case .reuse(let reason, _) = self { return reason }
        return ""
    }
}
