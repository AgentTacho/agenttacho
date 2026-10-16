import Foundation
import Testing
@testable import UsageCore

/// spec 010 FR-004, FR-006, FR-009: one quick retry per failure episode.
@Suite struct RetryEpisodesTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func delayIsThirtySeconds() {
        #expect(RetryEpisodes.delay == 30)
    }

    @Test func firstTransportFailureStartsAGracePeriod() {
        var episodes = RetryEpisodes()
        let phase = episodes.failed("a", category: .transport, now: t0, hasLiveValuesThisRun: true)
        #expect(phase == .grace(retryAt: t0.addingTimeInterval(30), unmarked: true))
        #expect(episodes.retryAt("a") == t0.addingTimeInterval(30))
    }

    @Test func graceIsMarkedWithoutLiveValuesThisRun() {
        var episodes = RetryEpisodes()
        let phase = episodes.failed("a", category: .transport, now: t0, hasLiveValuesThisRun: false)
        #expect(phase == .grace(retryAt: t0.addingTimeInterval(30), unmarked: false))
        #expect(episodes.retryAt("a") == t0.addingTimeInterval(30))
    }

    @Test func firstNonTransportFailureIsExhausted() {
        for category in [FailureCategory.signInRejected, .rateLimited, .serviceChanged] {
            var episodes = RetryEpisodes()
            #expect(episodes.failed("a", category: category, now: t0, hasLiveValuesThisRun: true) == .exhausted, "\(category)")
            #expect(episodes.retryAt("a") == nil)
        }
    }

    @Test func failureInGraceIsExhausted() {
        for category in [FailureCategory.transport, .signInRejected, .rateLimited, .serviceChanged] {
            var episodes = RetryEpisodes()
            _ = episodes.failed("a", category: .transport, now: t0, hasLiveValuesThisRun: true)
            #expect(episodes.failed("a", category: category, now: t0.addingTimeInterval(31), hasLiveValuesThisRun: true) == .exhausted)
            #expect(episodes.retryAt("a") == nil)
        }
    }

    @Test func failureWhenExhaustedStaysExhausted() {
        var episodes = RetryEpisodes()
        _ = episodes.failed("a", category: .serviceChanged, now: t0, hasLiveValuesThisRun: true)
        #expect(episodes.failed("a", category: .transport, now: t0.addingTimeInterval(300), hasLiveValuesThisRun: true) == .exhausted)
    }

    @Test func expireInGraceIsExhausted() {
        var episodes = RetryEpisodes()
        _ = episodes.failed("a", category: .transport, now: t0, hasLiveValuesThisRun: true)
        episodes.expire("a")
        #expect(episodes.phases["a"] == .exhausted)
        #expect(episodes.retryAt("a") == nil)
    }

    @Test func expireWithoutAnEpisodeDoesNothing() {
        var episodes = RetryEpisodes()
        episodes.expire("a")
        #expect(episodes.phases["a"] == nil)
    }

    @Test func successClearsTheAccountFromAnyPhase() {
        var episodes = RetryEpisodes()
        _ = episodes.failed("a", category: .transport, now: t0, hasLiveValuesThisRun: true)
        episodes.succeeded("a")
        #expect(episodes.phases["a"] == nil)
        // A new episode gets a new grace period.
        #expect(episodes.failed("a", category: .transport, now: t0.addingTimeInterval(60), hasLiveValuesThisRun: true)
                == .grace(retryAt: t0.addingTimeInterval(90), unmarked: true))

        _ = episodes.failed("a", category: .transport, now: t0.addingTimeInterval(100), hasLiveValuesThisRun: true)
        #expect(episodes.phases["a"] == .exhausted)
        episodes.succeeded("a")
        #expect(episodes.phases["a"] == nil)
    }

    @Test func forgetDropsUnknownAccounts() {
        var episodes = RetryEpisodes()
        _ = episodes.failed("a", category: .transport, now: t0, hasLiveValuesThisRun: true)
        _ = episodes.failed("b", category: .transport, now: t0, hasLiveValuesThisRun: true)
        episodes.forget(except: ["b"])
        #expect(episodes.phases["a"] == nil)
        #expect(episodes.retryAt("b") == t0.addingTimeInterval(30))
    }

    @Test func accountsAreIndependent() {
        var episodes = RetryEpisodes()
        _ = episodes.failed("a", category: .transport, now: t0, hasLiveValuesThisRun: true)
        _ = episodes.failed("a", category: .transport, now: t0.addingTimeInterval(31), hasLiveValuesThisRun: true)
        #expect(episodes.failed("b", category: .transport, now: t0.addingTimeInterval(31), hasLiveValuesThisRun: false)
                == .grace(retryAt: t0.addingTimeInterval(61), unmarked: false))
        episodes.succeeded("b")
        #expect(episodes.phases["a"] == .exhausted)
    }
}
