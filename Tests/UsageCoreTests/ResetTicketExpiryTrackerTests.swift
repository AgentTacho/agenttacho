import Foundation
import Testing
@testable import UsageCore

/// spec 033 FR-014, FR-016, FR-017, SC-003, data-model
/// "ResetTicketExpiryTracker": two expiry steps per account and expiry
/// time, never repeated, also across a relaunch.
@Suite struct ResetTicketExpiryTrackerTests {
    static let now = isoDate("2026-10-21T08:00:00Z")
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86400
    static let expiry = now.addingTimeInterval(5 * day)

    static func claude(_ id: String = "acc-max", name: String = "Claude Max") -> Account {
        Account(id: id, displayName: name,
                kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: [])))
    }

    static func codex(_ id: String = "acc-codex", name: String = "ChatGPT Plus") -> Account {
        Account(id: id, displayName: name, harness: .codex,
                kind: .codexSubscription(CodexSubscriptionSettings(codexHome: "~/.codex", liveLimits: true)))
    }

    static func config(_ accounts: [Account] = [claude()], notify: Bool = true) -> Configuration {
        var config = Configuration(accounts: accounts)
        config.notifyFreeResetExpiry = notify
        return config
    }

    static func snapshot(claude: [String: [ResetTicket]] = [:], codex: [String: [ResetTicket]] = [:],
                         preliminary: Bool = false) -> UsageSnapshot {
        UsageSnapshot(generatedAt: now, window: DateInterval(start: now, duration: day), windowSource: .fallback,
                      subscriptions: claude.mapValues { SubscriptionEntry(status: nil, state: .ok, resetTickets: $0) },
                      codexLimits: codex.mapValues { CodexLimitsEntry(observation: nil, state: .live, resetTickets: $0) },
                      isPreliminary: preliminary)
    }

    static func tickets(_ expiries: Date?...) -> [ResetTicket] { expiries.map { ResetTicket(expiresAt: $0) } }

    /// The steps delivered (or suppressed) in one observation, as
    /// "<accountId> <step> <count>" with "suppressed " in front when off.
    static func steps(_ events: [ResetTicketExpiryEvent]) -> [String] {
        events.map { event in
            switch event {
            case .deliver(let alert): return "\(alert.accountId) \(alert.step.rawValue) \(alert.count)"
            case .suppressed(let alert): return "suppressed \(alert.accountId) \(alert.step.rawValue) \(alert.count)"
            }
        }
    }

    /// Observes `tickets` of acc-max at `expiry - remaining`.
    static func observe(_ tracker: inout ResetTicketExpiryTracker, remaining: TimeInterval, tickets: [ResetTicket]? = nil,
                        config: Configuration = config()) -> [String] {
        let at = expiry.addingTimeInterval(-remaining)
        return steps(tracker.observe(snapshot: snapshot(claude: ["acc-max": tickets ?? Self.tickets(expiry)]), configuration: config, now: at))
    }

    @Test func farFromExpiryNothingIsDelivered() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(Self.observe(&tracker, remaining: 5 * Self.day) == [])
        #expect(Self.observe(&tracker, remaining: 3 * Self.day + 60) == [])
    }

    @Test func eachStepIsDeliveredOnce() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(Self.observe(&tracker, remaining: 4 * Self.day) == [])
        #expect(Self.observe(&tracker, remaining: 3 * Self.day - 60) == ["acc-max 3d 1"])
        #expect(Self.observe(&tracker, remaining: 2 * Self.day) == [])
        #expect(Self.observe(&tracker, remaining: Self.day - 60) == ["acc-max 24h 1"])
        #expect(Self.observe(&tracker, remaining: Self.hour) == [])
    }

    @Test func firstSeenAtThirtyHoursGivesTheThreeDayStepThenTheOther() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(Self.observe(&tracker, remaining: 30 * Self.hour) == ["acc-max 3d 1"])
        #expect(Self.observe(&tracker, remaining: 25 * Self.hour) == [])
        #expect(Self.observe(&tracker, remaining: 23 * Self.hour) == ["acc-max 24h 1"])
    }

    @Test func firstSeenAtTenHoursGivesOnlyTheOneDayStep() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(Self.observe(&tracker, remaining: 10 * Self.hour) == ["acc-max 24h 1"])
        #expect(Self.observe(&tracker, remaining: 9 * Self.hour) == [])
    }

    @Test func ticketsWithoutExpiryNeverNotify() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        for remaining in [5 * Self.day, 2 * Self.day, Self.hour] {
            #expect(Self.observe(&tracker, remaining: remaining, tickets: Self.tickets(nil, nil)) == [])
        }
    }

    @Test func ticketsWithOneExpiryGiveOneAlert() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let other = Self.expiry.addingTimeInterval(Self.hour)
        #expect(Self.observe(&tracker, remaining: 2 * Self.day, tickets: Self.tickets(Self.expiry, Self.expiry, other, nil))
            == ["acc-max 3d 2", "acc-max 3d 1"])
    }

    @Test func alertCarriesNameExpiryAndCount() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let events = tracker.observe(snapshot: Self.snapshot(claude: ["acc-max": Self.tickets(Self.expiry, Self.expiry)]),
                                     configuration: Self.config(), now: Self.expiry.addingTimeInterval(-Self.day * 2))
        #expect(events == [.deliver(ResetTicketExpiryAlert(accountId: "acc-max", accountName: "Claude Max", step: .threeDays,
                                                           expiresAt: Self.expiry, count: 2))])
    }

    @Test func lateTicketAtADeliveredStepGivesNothing() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(Self.observe(&tracker, remaining: 2 * Self.day) == ["acc-max 3d 1"])
        #expect(Self.observe(&tracker, remaining: 2 * Self.day - 60, tickets: Self.tickets(Self.expiry, Self.expiry)) == [])
        // The next step counts it with the others.
        #expect(Self.observe(&tracker, remaining: 10 * Self.hour, tickets: Self.tickets(Self.expiry, Self.expiry)) == ["acc-max 24h 2"])
    }

    @Test func relaunchDeliversNothingAlreadyRecorded() {
        let store = InMemoryResetTicketNoticeStore()
        var first = ResetTicketExpiryTracker(store: store)
        #expect(Self.observe(&first, remaining: 2 * Self.day) == ["acc-max 3d 1"])
        var second = ResetTicketExpiryTracker(store: store)
        #expect(Self.observe(&second, remaining: 2 * Self.day - Self.hour) == [])
        #expect(Self.observe(&second, remaining: 20 * Self.hour) == ["acc-max 24h 1"])
        var third = ResetTicketExpiryTracker(store: store)
        #expect(Self.observe(&third, remaining: 19 * Self.hour) == [])
    }

    @Test func keysArePrunedAfterExpiryAndForRemovedAccounts() {
        let store = InMemoryResetTicketNoticeStore()
        var tracker = ResetTicketExpiryTracker(store: store)
        let other = Self.claude("acc-other", name: "Other")
        let config = Self.config([Self.claude(), other])
        let soon = Self.now.addingTimeInterval(Self.hour)
        _ = tracker.observe(snapshot: Self.snapshot(claude: ["acc-max": Self.tickets(soon), "acc-other": Self.tickets(soon)]),
                            configuration: config, now: Self.now)
        #expect(store.load().count == 4)
        // acc-other removed: its keys go.
        _ = tracker.observe(snapshot: Self.snapshot(claude: ["acc-max": Self.tickets(soon)]), configuration: Self.config(), now: Self.now)
        #expect(Set(store.load().map(\.accountId)) == ["acc-max"])
        // After the expiry time every key goes.
        _ = tracker.observe(snapshot: Self.snapshot(), configuration: Self.config(), now: soon)
        #expect(store.load().isEmpty)
    }

    @Test func renamedAccountKeepsItsKeysAndUsesTheNewName() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(Self.observe(&tracker, remaining: 2 * Self.day) == ["acc-max 3d 1"])
        let renamed = Self.config([Self.claude(name: "Renamed")])
        #expect(Self.observe(&tracker, remaining: 2 * Self.day - 60, config: renamed) == [])
        let events = tracker.observe(snapshot: Self.snapshot(claude: ["acc-max": Self.tickets(Self.expiry)]), configuration: renamed,
                                     now: Self.expiry.addingTimeInterval(-Self.hour))
        guard case .deliver(let alert)? = events.first else {
            Issue.record("expected a delivery")
            return
        }
        #expect(alert.accountName == "Renamed")
        #expect(alert.step == .oneDay)
    }

    @Test func preliminarySnapshotsAreSkipped() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let events = tracker.observe(snapshot: Self.snapshot(claude: ["acc-max": Self.tickets(Self.expiry)], preliminary: true),
                                     configuration: Self.config(), now: Self.expiry.addingTimeInterval(-Self.hour))
        #expect(events.isEmpty)
        #expect(Self.observe(&tracker, remaining: Self.hour) == ["acc-max 24h 1"])
    }

    @Test func twoAccountsOnOneLoginEachNotify() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let config = Self.config([Self.claude(), Self.claude("acc-max-2", name: "Same login")])
        let events = tracker.observe(snapshot: Self.snapshot(claude: ["acc-max": Self.tickets(Self.expiry), "acc-max-2": Self.tickets(Self.expiry)]),
                                     configuration: config, now: Self.expiry.addingTimeInterval(-Self.day * 2))
        #expect(Self.steps(events) == ["acc-max 3d 1", "acc-max-2 3d 1"])
    }

    @Test func claudeAndCodexEntriesBothFeedIt() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let config = Self.config([Self.claude(), Self.codex()])
        let events = tracker.observe(snapshot: Self.snapshot(claude: ["acc-max": Self.tickets(Self.expiry)],
                                                             codex: ["acc-codex": Self.tickets(Self.expiry, Self.expiry)]),
                                     configuration: config, now: Self.expiry.addingTimeInterval(-Self.hour))
        #expect(Self.steps(events) == ["acc-max 24h 1", "acc-codex 24h 2"])
    }

    @Test func clockMovedBackwardsNeitherRepeatsNorExpires() {
        let store = InMemoryResetTicketNoticeStore()
        var tracker = ResetTicketExpiryTracker(store: store)
        #expect(Self.observe(&tracker, remaining: 10 * Self.hour) == ["acc-max 24h 1"])
        // Back by two days: inside the 3-day range again, recorded already.
        #expect(Self.observe(&tracker, remaining: 2 * Self.day + 10 * Self.hour) == [])
        // Back by a week: the key stays, the expiry lies in the future.
        #expect(Self.observe(&tracker, remaining: 7 * Self.day) == [])
        #expect(store.load().count == 2)
        #expect(Self.observe(&tracker, remaining: 5 * Self.hour) == [])
    }

    @Test func expiredTicketsNeverNotify() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(Self.observe(&tracker, remaining: 0) == [])
        #expect(Self.observe(&tracker, remaining: -Self.hour) == [])
    }
}

/// spec 033 FR-014: a range holds the times less than its lead time before
/// the expiry.
@Suite struct ResetTicketExpiryStepRangeTests {
    @Test func boundaries() {
        #expect(ResetTicketExpiryTracker.step(remaining: 3 * 86400) == nil)
        #expect(ResetTicketExpiryTracker.step(remaining: 3 * 86400 - 1) == .threeDays)
        #expect(ResetTicketExpiryTracker.step(remaining: 86400) == .threeDays)
        #expect(ResetTicketExpiryTracker.step(remaining: 86400 - 1) == .oneDay)
        #expect(ResetTicketExpiryTracker.step(remaining: 1) == .oneDay)
    }
}

/// spec 033 FR-017, US3: with the switch off a step that falls due is
/// suppressed and counts as delivered.
@Suite struct ResetTicketExpirySwitchTests {
    typealias T = ResetTicketExpiryTrackerTests

    @Test func switchOffSuppressesAndRecords() {
        let store = InMemoryResetTicketNoticeStore()
        var tracker = ResetTicketExpiryTracker(store: store)
        let off = T.config(notify: false)
        #expect(T.observe(&tracker, remaining: 2 * T.day, config: off) == ["suppressed acc-max 3d 1"])
        #expect(store.load().count == 1)
        // Turned on again: the suppressed step is not delivered later.
        #expect(T.observe(&tracker, remaining: 2 * T.day - T.hour) == [])
        // The next step is delivered with the switch on.
        #expect(T.observe(&tracker, remaining: 10 * T.hour) == ["acc-max 24h 1"])
    }

    @Test func switchOffSuppressesBothSteps() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let off = T.config(notify: false)
        #expect(T.observe(&tracker, remaining: 2 * T.day, config: off) == ["suppressed acc-max 3d 1"])
        #expect(T.observe(&tracker, remaining: 10 * T.hour, config: off) == ["suppressed acc-max 24h 1"])
        #expect(T.observe(&tracker, remaining: 5 * T.hour) == [])
    }

    /// The switch belongs to this tracker only: the threshold and the
    /// credential trackers read their own settings.
    @Test func otherSwitchesStayIndependent() {
        var config = T.config(notify: false)
        #expect(config.notifySignInProblems)
        config.notifySignInProblems = false
        config.notifyFreeResetExpiry = true
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        #expect(T.observe(&tracker, remaining: 2 * T.day, config: config) == ["acc-max 3d 1"])
    }
}

/// spec 033 FR-001, FR-014: tickets of a refresh that started before an
/// account's login changed in the settings belong to the previous login
/// and do not notify; Codex accounts with live limits off never notify.
@Suite struct ResetTicketExpiryTrackerFenceTests {
    typealias T = ResetTicketExpiryTrackerTests

    static func snapshot(at generatedAt: Date, claude: [String: [ResetTicket]] = [:],
                         codex: [String: [ResetTicket]] = [:]) -> UsageSnapshot {
        UsageSnapshot(generatedAt: generatedAt, window: DateInterval(start: generatedAt, duration: T.day), windowSource: .fallback,
                      subscriptions: claude.mapValues { SubscriptionEntry(status: nil, state: .ok, resetTickets: $0) },
                      codexLimits: codex.mapValues { CodexLimitsEntry(observation: nil, state: .live, resetTickets: $0) })
    }

    static func moved(_ directory: String) -> Configuration {
        T.config([Account(id: "acc-max", displayName: "Claude Max",
                          kind: .subscription(SubscriptionSettings(credentialDirectory: directory, shownInBar: true, thresholds: [])))])
    }

    @Test func aChangedLoginIgnoresRefreshesThatStartedBefore() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let soon = T.tickets(T.now.addingTimeInterval(2 * T.day))
        #expect(T.steps(tracker.observe(snapshot: Self.snapshot(at: T.now, claude: [:]), configuration: T.config(), now: T.now)) == [])
        let changedAt = T.now.addingTimeInterval(60)
        tracker.configurationChanged(Self.moved("~/.claude-work"), now: changedAt)
        // A refresh that started before the change: the previous login's tickets.
        let stale = tracker.observe(snapshot: Self.snapshot(at: T.now, claude: ["acc-max": soon]),
                                    configuration: Self.moved("~/.claude-work"), now: changedAt.addingTimeInterval(1))
        #expect(T.steps(stale) == [])
        // A refresh that started after it counts.
        let fresh = tracker.observe(snapshot: Self.snapshot(at: changedAt.addingTimeInterval(5), claude: ["acc-max": soon]),
                                    configuration: Self.moved("~/.claude-work"), now: changedAt.addingTimeInterval(6))
        #expect(T.steps(fresh) == ["acc-max 3d 1"])
    }

    @Test func aSaveWithTheSameLoginSetsNoFence() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        _ = tracker.observe(snapshot: Self.snapshot(at: T.now), configuration: T.config(), now: T.now)
        tracker.configurationChanged(T.config(), now: T.now.addingTimeInterval(60))
        let events = tracker.observe(snapshot: Self.snapshot(at: T.now, claude: ["acc-max": T.tickets(T.now.addingTimeInterval(2 * T.day))]),
                                     configuration: T.config(), now: T.now.addingTimeInterval(61))
        #expect(T.steps(events) == ["acc-max 3d 1"])
    }

    @Test func codexWithLiveLimitsOffNeverNotifies() {
        var tracker = ResetTicketExpiryTracker(store: InMemoryResetTicketNoticeStore())
        let off = Account(id: "acc-codex", displayName: "ChatGPT Plus", harness: .codex,
                          kind: .codexSubscription(CodexSubscriptionSettings(codexHome: "~/.codex", liveLimits: false)))
        let events = tracker.observe(snapshot: Self.snapshot(at: T.now, codex: ["acc-codex": T.tickets(T.now.addingTimeInterval(2 * T.day))]),
                                     configuration: T.config([off]), now: T.now)
        #expect(T.steps(events) == [])
        let on = tracker.observe(snapshot: Self.snapshot(at: T.now, codex: ["acc-codex": T.tickets(T.now.addingTimeInterval(2 * T.day))]),
                                 configuration: T.config([T.codex()]), now: T.now)
        #expect(T.steps(on) == ["acc-codex 3d 1"])
    }
}
