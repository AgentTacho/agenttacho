import Foundation
import Testing
@testable import UsageCore

/// spec 014 FR-001 to FR-008, FR-011, data-model.md transitions.
@Suite struct CredentialAlertTrackerTests {
    static let home = URL(fileURLWithPath: "/Users/tester")
    static let paths = Paths(home: home)
    static let t0 = isoDate("2026-10-14T12:00:00Z")
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    // MARK: Helpers

    static func claude(_ id: String = "claude", name: String = "Claude (Work)", directory: String = "~/.claude-work",
                       shownInBar: Bool = true) -> Account {
        Account(id: id, displayName: name,
                kind: .subscription(SubscriptionSettings(credentialDirectory: directory, shownInBar: shownInBar)))
    }

    static func codex(_ id: String = "codex", name: String = "Codex", home: String = "~/.codex", liveLimits: Bool = true) -> Account {
        Account(id: id, displayName: name, harness: .codex,
                kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home, liveLimits: liveLimits)))
    }

    static func config(_ accounts: [Account], notify: Bool = true) -> Configuration {
        Configuration(accounts: accounts, notifySignInProblems: notify)
    }

    static let observation = CodexLimitObservation(planType: "plus", observedAt: t0, origin: .live,
                                                   windows: [CodexLimitWindow(lengthMinutes: 10080, usedPercent: 10, resetsAt: nil)])

    /// Claude entries by state name.
    static func entry(_ state: String, expiresAt: Date? = nil) -> SubscriptionEntry {
        switch state {
        case "ok": return SubscriptionEntry(status: nil, state: .ok)
        case "rejected": return SubscriptionEntry(status: nil, state: .signInRejected(lastGoodAt: t0))
        case "missing": return SubscriptionEntry(status: nil, state: .notSignedIn)
        case "expired": return SubscriptionEntry(status: nil, state: .credentialsExpired, credentialExpiresAt: expiresAt)
        default: return SubscriptionEntry(status: nil, state: .stale(lastGoodAt: t0, error: state))
        }
    }

    /// Codex entries by state name.
    static func codexEntry(_ state: String, expiresAt: Date? = nil) -> CodexLimitsEntry {
        switch state {
        case "ok": return CodexLimitsEntry(observation: observation, state: .live)
        case "rejected": return CodexLimitsEntry(observation: observation, state: .stale(reason: "rejected"), signInRejected: true)
        case "missing": return CodexLimitsEntry(observation: nil, state: .unavailable(reason: "missing"), credentialProblem: .notSignedIn)
        case "keychain": return CodexLimitsEntry(observation: nil, state: .unavailable(reason: "keychain"), credentialProblem: .keychain)
        case "expired":
            return CodexLimitsEntry(observation: observation, state: .stale(reason: "expired"),
                                    credentialProblem: .expired(at: expiresAt ?? t0))
        case "local": return CodexLimitsEntry(observation: observation, state: .localOnly)
        default: return CodexLimitsEntry(observation: observation, state: .stale(reason: state))
        }
    }

    static func snapshot(at offset: TimeInterval = 0, claude: [String: SubscriptionEntry] = [:],
                         codex: [String: CodexLimitsEntry] = [:], preliminary: Bool = false) -> UsageSnapshot {
        UsageSnapshot(generatedAt: t0.addingTimeInterval(offset), window: window, windowSource: .fallback,
                      subscriptions: claude, codexLimits: codex, isPreliminary: preliminary)
    }

    /// Feeds one Claude account's states in order and returns the events of
    /// each refresh.
    static func run(_ states: [String], account: Account = claude(), tracker: inout CredentialAlertTracker) -> [[CredentialAlertEvent]] {
        let c = config([account])
        return states.enumerated().map { index, state in
            let claude = state == "absent" ? [:] : [account.id: entry(state)]
            return tracker.observe(snapshot: snapshot(at: TimeInterval(index * 300), claude: claude), configuration: c)
        }
    }

    static func deliver(_ kind: CredentialAlert.Kind, id: String = "claude", name: String = "Claude (Work)",
                        provider: CredentialAlert.Provider = .claude, directory: String? = "~/.claude-work") -> CredentialAlertEvent {
        .deliver(CredentialAlert(accountId: id, accountName: name, provider: provider, kind: kind, directory: directory))
    }

    // MARK: Baseline (FR-004)

    @Test func failingAtTheFirstRefreshIsASilentBaseline() {
        for failing in ["rejected", "missing"] {
            var tracker = CredentialAlertTracker(paths: Self.paths)
            let events = Self.run([failing, failing, "rejected", "missing"], tracker: &tracker)
            #expect(events.allSatisfy { $0.isEmpty }, "\(failing)")
        }
    }

    /// Clarification Q2: unchanged results and a missing entry leave the
    /// baseline unset, so a rejection after them is the baseline.
    @Test func unchangedResultsBeforeTheBaselineLeaveItUnset() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.run(["offline", "absent", "rate limited", "rejected", "ok", "rejected"], tracker: &tracker)
        #expect(events[0...4].allSatisfy { $0.isEmpty })
        #expect(events[5] == [Self.deliver(.rejected)])
    }

    // MARK: Episodes (FR-003, FR-006, FR-007)

    @Test func rejectionAfterWorkingDeliversOnceAndRecoveryWithdraws() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.run(["ok", "rejected", "rejected", "absent", "rejected", "ok", "ok", "rejected"], tracker: &tracker)
        #expect(events[0].isEmpty)
        #expect(events[1] == [Self.deliver(.rejected)])
        #expect(events[2].isEmpty)
        // A missing entry is unchanged: no withdraw.
        #expect(events[3].isEmpty)
        #expect(events[4].isEmpty)
        #expect(events[5] == [.withdraw(accountId: "claude")])
        #expect(events[6].isEmpty)
        // A second episode delivers again.
        #expect(events[7] == [Self.deliver(.rejected)])
    }

    @Test func missingSignInAfterWorkingDelivers() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.run(["ok", "missing", "missing"], tracker: &tracker)
        #expect(events[1] == [Self.deliver(.notSignedIn)])
        #expect(events[2].isEmpty)
    }

    @Test func kindChangeAfterDeliveryDeliversNothing() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.run(["ok", "rejected", "missing", "rejected"], tracker: &tracker)
        #expect(events[1] == [Self.deliver(.rejected)])
        #expect(events[2].isEmpty)
        #expect(events[3].isEmpty)
    }

    /// Transport errors, rate limits and service changes never end an
    /// episode nor keep a later rejection from notifying.
    @Test func otherFailuresBetweenWorkingAndRejectedDoNotPreventTheDelivery() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.run(["ok", "offline", "rate limited", "service changed", "rejected"], tracker: &tracker)
        #expect(events[0...3].allSatisfy { $0.isEmpty })
        #expect(events[4] == [Self.deliver(.rejected)])
    }

    @Test func recoveryWithoutDeliveryWithdrawsNothing() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        // A baseline that fails, then works: no episode, no withdraw.
        let events = Self.run(["rejected", "ok"], tracker: &tracker)
        #expect(events.allSatisfy { $0.isEmpty })
    }

    @Test func preliminarySnapshotsAreIgnored() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let c = Self.config([Self.claude()])
        // Saved values at launch show as `.ok`, but no request was made.
        #expect(tracker.observe(snapshot: Self.snapshot(claude: ["claude": Self.entry("ok")], preliminary: true), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 10, claude: ["claude": Self.entry("rejected")]), configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 20, claude: ["claude": Self.entry("ok")]), configuration: c).isEmpty)
        // A preliminary result between refreshes changes nothing either.
        #expect(tracker.observe(snapshot: Self.snapshot(at: 30, claude: ["claude": Self.entry("rejected")], preliminary: true),
                                configuration: c).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 40, claude: ["claude": Self.entry("rejected")]), configuration: c)
            == [Self.deliver(.rejected)])
    }

    // MARK: Codex (FR-001, FR-009)

    @Test func codexFailuresDeliver() {
        for (state, kind) in [("rejected", CredentialAlert.Kind.rejected), ("missing", .notSignedIn), ("keychain", .notReadable)] {
            var tracker = CredentialAlertTracker(paths: Self.paths)
            let c = Self.config([Self.codex()])
            #expect(tracker.observe(snapshot: Self.snapshot(codex: ["codex": Self.codexEntry("ok")]), configuration: c).isEmpty)
            #expect(tracker.observe(snapshot: Self.snapshot(at: 300, codex: ["codex": Self.codexEntry("offline")]), configuration: c).isEmpty)
            let events = tracker.observe(snapshot: Self.snapshot(at: 600, codex: ["codex": Self.codexEntry(state)]), configuration: c)
            #expect(events == [Self.deliver(kind, id: "codex", name: "Codex", provider: .codex, directory: nil)], "\(state)")
            let again = tracker.observe(snapshot: Self.snapshot(at: 900, codex: ["codex": Self.codexEntry(state)]), configuration: c)
            #expect(again.isEmpty)
            let recovered = tracker.observe(snapshot: Self.snapshot(at: 1200, codex: ["codex": Self.codexEntry("ok")]), configuration: c)
            #expect(recovered == [.withdraw(accountId: "codex")])
        }
    }

    @Test func codexWithLiveLimitsOffNeverNotifies() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let c = Self.config([Self.codex(liveLimits: false)])
        for (index, state) in ["local", "rejected", "ok", "missing"].enumerated() {
            let events = tracker.observe(snapshot: Self.snapshot(at: TimeInterval(index * 300), codex: ["codex": Self.codexEntry(state)]),
                                         configuration: c)
            #expect(events.isEmpty, "\(state)")
        }
    }

    @Test func turningLiveLimitsOffWithdrawsAndOnAgainStartsANewBaseline() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let on = Self.config([Self.codex()])
        let off = Self.config([Self.codex(liveLimits: false)])
        _ = tracker.observe(snapshot: Self.snapshot(codex: ["codex": Self.codexEntry("ok")]), configuration: on)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 300, codex: ["codex": Self.codexEntry("rejected")]), configuration: on).count == 1)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 600, codex: ["codex": Self.codexEntry("local")]), configuration: off)
            == [.withdraw(accountId: "codex")])
        // On again: the first health is the baseline, whatever it is.
        #expect(tracker.observe(snapshot: Self.snapshot(at: 900, codex: ["codex": Self.codexEntry("rejected")]), configuration: on).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1200, codex: ["codex": Self.codexEntry("ok")]), configuration: on).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1500, codex: ["codex": Self.codexEntry("missing")]), configuration: on).count == 1)
    }

    // MARK: Accounts (FR-002, FR-008, FR-011)

    @Test func accountsHiddenFromTheBarStillDeliver() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.run(["ok", "rejected"], account: Self.claude(shownInBar: false), tracker: &tracker)
        #expect(events[1] == [Self.deliver(.rejected)])
    }

    @Test func accountsSharingADirectoryEachDeliver() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let c = Self.config([Self.claude("a", name: "A"), Self.claude("b", name: "B")])
        _ = tracker.observe(snapshot: Self.snapshot(claude: ["a": Self.entry("ok"), "b": Self.entry("ok")]), configuration: c)
        let events = tracker.observe(snapshot: Self.snapshot(at: 300, claude: ["a": Self.entry("rejected"), "b": Self.entry("rejected")]),
                                     configuration: c)
        #expect(events == [Self.deliver(.rejected, id: "a", name: "A"), Self.deliver(.rejected, id: "b", name: "B")])
    }

    @Test func tokenBasedAccountsAndGroupsNeverProduceEvents() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        var c = Self.config([Account(id: "vertex", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "grp")))])
        c.groups = [BudgetGroup(id: "grp", name: "Group", budgetUSD: 100)]
        // Even an entry under their ids is not read.
        for (index, state) in ["ok", "rejected", "ok", "missing"].enumerated() {
            let snapshot = Self.snapshot(at: TimeInterval(index * 300), claude: ["vertex": Self.entry(state), "grp": Self.entry(state)])
            #expect(tracker.observe(snapshot: snapshot, configuration: c).isEmpty)
        }
    }

    @Test func removedAccountWithdrawsAndDropsItsState() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let c = Self.config([Self.claude()])
        _ = Self.run(["ok", "rejected"], tracker: &tracker)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 900), configuration: Self.config([])) == [.withdraw(accountId: "claude")])
        // Added back: a new baseline.
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1200, claude: ["claude": Self.entry("rejected")]), configuration: c).isEmpty)
        // A removed account without a delivered notification withdraws nothing.
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1500), configuration: Self.config([])).isEmpty)
    }

    @Test func changedCredentialDirectoryWithdrawsAndStartsANewBaseline() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        _ = Self.run(["ok", "rejected"], tracker: &tracker)
        let moved = Self.config([Self.claude(directory: "~/.claude-other")])
        #expect(tracker.observe(snapshot: Self.snapshot(at: 900, claude: ["claude": Self.entry("rejected")]), configuration: moved)
            == [.withdraw(accountId: "claude")])
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1200, claude: ["claude": Self.entry("missing")]), configuration: moved).isEmpty)
    }

    /// The same directory written another way is the same identity.
    @Test func equivalentDirectoryIsNotAChange() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        _ = Self.run(["ok"], tracker: &tracker)
        let expanded = Self.config([Self.claude(directory: "/Users/tester/.claude-work/")])
        #expect(tracker.observe(snapshot: Self.snapshot(at: 300, claude: ["claude": Self.entry("rejected")]), configuration: expanded)
            == [Self.deliver(.rejected, directory: "/Users/tester/.claude-work/")])
    }

    /// A refresh that started before the directory change was computed for
    /// the old directory: its result must not become the new baseline
    /// (FR-004, checkpoint review).
    @Test func refreshStartedBeforeADirectoryChangeIsNotTheNewBaseline() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        _ = Self.run(["ok", "rejected"], tracker: &tracker)
        let moved = Self.config([Self.claude(directory: "~/.claude-other")])
        let savedAt = Self.t0.addingTimeInterval(1000)
        #expect(tracker.configurationChanged(moved, now: savedAt) == [.withdraw(accountId: "claude")])
        // Started before the save: the old directory's working sign-in.
        #expect(tracker.observe(snapshot: Self.snapshot(at: 990, claude: ["claude": Self.entry("ok")]), configuration: moved).isEmpty)
        // The first refresh for the new directory is the baseline.
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1010, claude: ["claude": Self.entry("missing")]), configuration: moved).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1300, claude: ["claude": Self.entry("ok")]), configuration: moved).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1600, claude: ["claude": Self.entry("missing")]), configuration: moved)
            == [Self.deliver(.notSignedIn, directory: "~/.claude-other")])
    }

    /// A save that changes nothing about an account keeps its state.
    @Test func unrelatedSaveKeepsTheState() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        _ = Self.run(["ok"], tracker: &tracker)
        #expect(tracker.configurationChanged(Self.config([Self.claude(name: "Renamed")]), now: Self.t0.addingTimeInterval(1000)).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 990, claude: ["claude": Self.entry("rejected")]),
                                configuration: Self.config([Self.claude(name: "Renamed")]))
            == [Self.deliver(.rejected, name: "Renamed")])
    }

    @Test func changedCodexHomeWithdraws() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let c = Self.config([Self.codex()])
        _ = tracker.observe(snapshot: Self.snapshot(codex: ["codex": Self.codexEntry("ok")]), configuration: c)
        _ = tracker.observe(snapshot: Self.snapshot(at: 300, codex: ["codex": Self.codexEntry("rejected")]), configuration: c)
        let moved = Self.config([Self.codex(home: "~/.codex-work")])
        #expect(tracker.observe(snapshot: Self.snapshot(at: 600, codex: ["codex": Self.codexEntry("rejected")]), configuration: moved)
            == [.withdraw(accountId: "codex")])
    }

    // MARK: Expiry delay (FR-005, FR-006)

    static let hour: TimeInterval = 3600

    /// Feeds one Claude account's entries at the given offsets from `t0`.
    static func feed(_ steps: [(TimeInterval, SubscriptionEntry?)], tracker: inout CredentialAlertTracker,
                     account: Account = claude()) -> [[CredentialAlertEvent]] {
        let c = config([account])
        return steps.map { offset, entry in
            tracker.observe(snapshot: snapshot(at: offset, claude: entry.map { [account.id: $0] } ?? [:]), configuration: c)
        }
    }

    @Test func expiryNotifiesOnceTheDelayPassed() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        // The token expires one hour after t0.
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        let expired = Self.entry("expired", expiresAt: expiresAt)
        let events = Self.feed([(0, Self.entry("ok")),
                                (2 * Self.hour, expired),
                                (24 * Self.hour, expired),
                                (25 * Self.hour - 1, expired),
                                (25 * Self.hour, expired),
                                (26 * Self.hour, expired)], tracker: &tracker)
        #expect(events[0...3].allSatisfy { $0.isEmpty })
        #expect(events[4] == [Self.deliver(.expired)])
        #expect(events[5].isEmpty)
        #expect(CredentialAlertTracker.expiryDelay == 24 * 3600)
    }

    /// The delay is checked on unchanged results too.
    @Test func expiryNotifiesOnAnUnchangedRefreshAfterTheDelay() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        let events = Self.feed([(0, Self.entry("ok")),
                                (2 * Self.hour, Self.entry("expired", expiresAt: expiresAt)),
                                (25 * Self.hour, Self.entry("offline")),
                                (26 * Self.hour, nil)], tracker: &tracker)
        #expect(events[2] == [Self.deliver(.expired)])
        #expect(events[3].isEmpty)
    }

    @Test func renewalBeforeTheDelayDeliversNothing() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        let events = Self.feed([(0, Self.entry("ok")),
                                (2 * Self.hour, Self.entry("expired", expiresAt: expiresAt)),
                                (20 * Self.hour, Self.entry("ok")),
                                (30 * Self.hour, Self.entry("ok"))], tracker: &tracker)
        #expect(events.allSatisfy { $0.isEmpty })
    }

    /// US2 scenario 4: a launch whose first health is expired is a silent
    /// baseline, even 30 hours after the expiry.
    @Test func expiredAtLaunchIsASilentBaseline() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let expiresAt = Self.t0.addingTimeInterval(-30 * Self.hour)
        let expired = Self.entry("expired", expiresAt: expiresAt)
        let events = Self.feed([(0, expired), (Self.hour, expired), (48 * Self.hour, expired)], tracker: &tracker)
        #expect(events.allSatisfy { $0.isEmpty })
    }

    @Test func rejectionInsideTheDelayDeliversAtOnce() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        let events = Self.feed([(0, Self.entry("ok")),
                                (2 * Self.hour, Self.entry("expired", expiresAt: expiresAt)),
                                (3 * Self.hour, Self.entry("rejected")),
                                (30 * Self.hour, Self.entry("expired", expiresAt: expiresAt))], tracker: &tracker)
        #expect(events[1].isEmpty)
        #expect(events[2] == [Self.deliver(.rejected)])
        #expect(events[3].isEmpty)
    }

    /// FR-006 names not signed in too: an expiry inside its delay that turns
    /// into a missing sign-in delivers at once, and only once.
    @Test func missingSignInInsideTheDelayDeliversAtOnce() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        let events = Self.feed([(0, Self.entry("ok")),
                                (2 * Self.hour, Self.entry("expired", expiresAt: expiresAt)),
                                (3 * Self.hour, Self.entry("missing")),
                                (4 * Self.hour, Self.entry("rejected"))], tracker: &tracker)
        #expect(events[1].isEmpty)
        #expect(events[2] == [Self.deliver(.notSignedIn)])
        #expect(events[3].isEmpty)
    }

    /// The Codex variant: an expiry inside its delay that turns into a
    /// sign-in kept in the keychain delivers at once (FR-006, FR-009).
    @Test func codexKeychainInsideTheDelayDeliversAtOnce() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let c = Self.config([Self.codex()])
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        func observe(_ offset: TimeInterval, _ state: String) -> [CredentialAlertEvent] {
            tracker.observe(snapshot: Self.snapshot(at: offset, codex: ["codex": Self.codexEntry(state, expiresAt: expiresAt)]),
                            configuration: c)
        }
        #expect(observe(0, "ok").isEmpty)
        #expect(observe(2 * Self.hour, "expired").isEmpty)
        #expect(observe(3 * Self.hour, "keychain")
            == [Self.deliver(.notReadable, id: "codex", name: "Codex", provider: .codex, directory: nil)])
        #expect(observe(4 * Self.hour, "missing").isEmpty)
    }

    /// FR-005: the delay counts from the expiry time the credential records
    /// now, so a newer (still past) expiry time inside an episode moves it.
    @Test func expiryTimeChangeInsideAnEpisodeCountsFromTheNewTime() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.feed([(0, Self.entry("ok")),
                                (2 * Self.hour, Self.entry("expired", expiresAt: Self.t0.addingTimeInterval(Self.hour))),
                                (25 * Self.hour, Self.entry("expired", expiresAt: Self.t0.addingTimeInterval(10 * Self.hour))),
                                (34 * Self.hour - 1, nil),
                                (34 * Self.hour, nil)], tracker: &tracker)
        #expect(events[0...3].allSatisfy { $0.isEmpty })
        #expect(events[4] == [Self.deliver(.expired)])
    }

    /// Edge case "Clock moved backwards": the delay is measured against the
    /// clock of each refresh, so a refresh dated before the delay passed
    /// delivers nothing, even after a later one.
    @Test func clockMovedBackwardsDoesNotNotifyEarly() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        let events = Self.feed([(0, Self.entry("ok")),
                                (20 * Self.hour, Self.entry("expired", expiresAt: expiresAt)),
                                (10 * Self.hour, nil),
                                (24 * Self.hour, Self.entry("expired", expiresAt: expiresAt)),
                                (25 * Self.hour, nil)], tracker: &tracker)
        #expect(events[0...3].allSatisfy { $0.isEmpty })
        #expect(events[4] == [Self.deliver(.expired)])
    }

    @Test func kindChangeAfterAnExpiryDeliveryDeliversNothing() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        let events = Self.feed([(0, Self.entry("ok")),
                                (25 * Self.hour, Self.entry("expired", expiresAt: expiresAt)),
                                (26 * Self.hour, Self.entry("rejected")),
                                (27 * Self.hour, Self.entry("missing")),
                                (28 * Self.hour, Self.entry("ok"))], tracker: &tracker)
        #expect(events[1] == [Self.deliver(.expired)])
        #expect(events[2].isEmpty)
        #expect(events[3].isEmpty)
        #expect(events[4] == [.withdraw(accountId: "claude")])
    }

    @Test func codexExpiryBehavesTheSame() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let c = Self.config([Self.codex()])
        let expiresAt = Self.t0.addingTimeInterval(Self.hour)
        func observe(_ offset: TimeInterval, _ state: String) -> [CredentialAlertEvent] {
            tracker.observe(snapshot: Self.snapshot(at: offset, codex: ["codex": Self.codexEntry(state, expiresAt: expiresAt)]),
                            configuration: c)
        }
        #expect(observe(0, "ok").isEmpty)
        #expect(observe(2 * Self.hour, "expired").isEmpty)
        #expect(observe(24 * Self.hour, "expired").isEmpty)
        #expect(observe(25 * Self.hour, "expired") == [Self.deliver(.expired, id: "codex", name: "Codex", provider: .codex, directory: nil)])
        #expect(observe(26 * Self.hour, "expired").isEmpty)
    }

    /// An expiry without a known time is unchanged (edge case "Expiry time
    /// unknown").
    @Test func expiryWithoutATimeIsUnchanged() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let events = Self.feed([(0, Self.entry("ok")),
                                (2 * Self.hour, Self.entry("expired")),
                                (48 * Self.hour, Self.entry("expired")),
                                (49 * Self.hour, Self.entry("rejected"))], tracker: &tracker)
        #expect(events[0...2].allSatisfy { $0.isEmpty })
        // The account stayed working, so the rejection starts an episode.
        #expect(events[3] == [Self.deliver(.rejected)])
    }

    // MARK: Switch (FR-012)

    static func alert(_ kind: CredentialAlert.Kind, id: String = "claude", name: String = "Claude (Work)") -> CredentialAlert {
        CredentialAlert(accountId: id, accountName: name, provider: .claude, kind: kind, directory: "~/.claude-work")
    }

    @Test func switchOffSuppressesAndTheEpisodeCountsAsNotified() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let off = Self.config([Self.claude()], notify: false)
        let on = Self.config([Self.claude()])
        func observe(_ offset: TimeInterval, _ state: String, _ c: Configuration) -> [CredentialAlertEvent] {
            tracker.observe(snapshot: Self.snapshot(at: offset, claude: ["claude": Self.entry(state)]), configuration: c)
        }
        #expect(observe(0, "ok", off).isEmpty)
        #expect(observe(300, "rejected", off) == [.suppressed(Self.alert(.rejected))])
        #expect(observe(600, "rejected", off).isEmpty)
        // Not on a change of kind, and not after the switch is turned on.
        #expect(observe(900, "missing", off).isEmpty)
        #expect(tracker.configurationChanged(on, now: Self.t0.addingTimeInterval(1000)).isEmpty)
        #expect(observe(1200, "rejected", on).isEmpty)
        // The next episode notifies.
        #expect(observe(1500, "ok", on).isEmpty)
        #expect(observe(1800, "rejected", on) == [Self.deliver(.rejected)])
    }

    @Test func turningTheSwitchOffWithdrawsDeliveredNotificationsOnly() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let accounts = [Self.claude("a", name: "A"), Self.claude("b", name: "B"), Self.claude("c", name: "C")]
        let on = Self.config(accounts)
        let off = Self.config(accounts, notify: false)
        _ = tracker.observe(snapshot: Self.snapshot(claude: ["a": Self.entry("ok"), "b": Self.entry("ok"), "c": Self.entry("rejected")]),
                            configuration: on)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 300, claude: ["a": Self.entry("rejected"), "b": Self.entry("ok")]),
                                configuration: on) == [Self.deliver(.rejected, id: "a", name: "A")])
        let changedAt = Self.t0.addingTimeInterval(400)
        #expect(tracker.configurationChanged(off, now: changedAt) == [.withdraw(accountId: "a")])
        #expect(tracker.configurationChanged(off, now: changedAt).isEmpty)
        #expect(tracker.configurationChanged(on, now: changedAt).isEmpty)
        // The withdrawn episode is still notified: recovery withdraws nothing more.
        #expect(tracker.observe(snapshot: Self.snapshot(at: 600, claude: ["a": Self.entry("ok")]), configuration: on).isEmpty)
    }

    /// A hand-edited file that turns the switch off takes effect at the
    /// next refresh.
    @Test func observeWithTheSwitchOffWithdraws() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        _ = Self.run(["ok", "rejected"], tracker: &tracker)
        let off = Self.config([Self.claude()], notify: false)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 900, claude: ["claude": Self.entry("rejected")]), configuration: off)
            == [.withdraw(accountId: "claude")])
        #expect(tracker.observe(snapshot: Self.snapshot(at: 1200, claude: ["claude": Self.entry("rejected")]), configuration: off).isEmpty)
    }

    @Test func expiryInsideItsDelayNotifiesWhenTheSwitchWasTurnedOnMeanwhile() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let off = Self.config([Self.claude()], notify: false)
        let on = Self.config([Self.claude()])
        let expired = Self.entry("expired", expiresAt: Self.t0.addingTimeInterval(Self.hour))
        #expect(tracker.observe(snapshot: Self.snapshot(claude: ["claude": Self.entry("ok")]), configuration: off).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 2 * Self.hour, claude: ["claude": expired]), configuration: off).isEmpty)
        #expect(tracker.configurationChanged(on, now: Self.t0.addingTimeInterval(3 * Self.hour)).isEmpty)
        #expect(tracker.observe(snapshot: Self.snapshot(at: 25 * Self.hour, claude: ["claude": expired]), configuration: on)
            == [Self.deliver(.expired)])
    }

    @Test func healthIsTrackedWhileTheSwitchIsOff() {
        var tracker = CredentialAlertTracker(paths: Self.paths)
        let off = Self.config([Self.claude()], notify: false)
        let on = Self.config([Self.claude()])
        func observe(_ offset: TimeInterval, _ state: String, _ c: Configuration) -> [CredentialAlertEvent] {
            tracker.observe(snapshot: Self.snapshot(at: offset, claude: ["claude": Self.entry(state)]), configuration: c)
        }
        #expect(observe(0, "ok", off).isEmpty)
        #expect(observe(300, "rejected", off) == [.suppressed(Self.alert(.rejected))])
        // A recovery while off ends the episode, without a withdraw.
        #expect(observe(600, "ok", off).isEmpty)
        #expect(observe(900, "rejected", on) == [Self.deliver(.rejected)])
    }

    // MARK: Directory in the text (FR-009)

    @Test func directoryIsNilOnlyForTheDefault() {
        func delivered(_ account: Account) -> CredentialAlert? {
            var tracker = CredentialAlertTracker(paths: Self.paths)
            let c = Self.config([account])
            let isCodex = account.kind.isCodexSubscription
            func snap(_ offset: TimeInterval, _ state: String) -> UsageSnapshot {
                isCodex ? Self.snapshot(at: offset, codex: [account.id: Self.codexEntry(state)])
                    : Self.snapshot(at: offset, claude: [account.id: Self.entry(state)])
            }
            _ = tracker.observe(snapshot: snap(0, "ok"), configuration: c)
            guard case .deliver(let alert)? = tracker.observe(snapshot: snap(300, "rejected"), configuration: c).first else { return nil }
            return alert
        }
        #expect(delivered(Self.claude(directory: "~/.claude"))?.directory == nil)
        #expect(delivered(Self.claude(directory: "/Users/tester/.claude"))?.directory == nil)
        #expect(delivered(Self.claude(directory: "~/.claude/"))?.directory == nil)
        #expect(delivered(Self.claude(directory: "~/.claude-work"))?.directory == "~/.claude-work")
        #expect(delivered(Self.codex(home: "~/.codex"))?.directory == nil)
        #expect(delivered(Self.codex(home: "/Users/tester/.codex"))?.directory == nil)
        #expect(delivered(Self.codex(home: "~/.codex-work"))?.directory == "~/.codex-work")
    }
}
