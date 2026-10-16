import Foundation
import Testing
@testable import UsageCore

/// Spec 004 FR-004, FR-011, FR-020 and the unchanged subscription rules of
/// spec 001 FR-002, FR-003: the bar's items, in order, with values and levels.
@Suite struct BarLayoutTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    /// Accounts list: sub-a, own-x, member m1 (of g1), sub-b, own-y (hidden),
    /// member m2 (of g2). Groups list: g2, then g1 (hidden).
    func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub-a", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.a", thresholds: [70]))),
            Account(id: "own-x", icon: "solid:robot", displayName: "Personal",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 100, thresholds: [60, 100]))))),
            Account(id: "m1", displayName: "Member one", kind: .tokenBased(TokenBasedSettings(groupId: "g1"))),
            Account(id: "sub-b", displayName: "Work", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.b"))),
            Account(id: "own-y", displayName: "Hidden own",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50, shownInBar: false))))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "g2"))),
        ]
        c.groups = [
            BudgetGroup(id: "g2", name: "Team", budgetUSD: 300, thresholds: [50]),
            BudgetGroup(id: "g1", name: "Hidden group", budgetUSD: 10, shownInBar: false),
        ]
        return c
    }

    func entry(percent: Int, members: [String], stale: Bool = false) -> GroupEntry {
        GroupEntry(spentUSD: Decimal(percent), budgetUSD: 100, percent: percent, incomplete: false,
                   window: window, breakdown: .empty, members: members, stale: stale)
    }

    func snapshot(subA: SubscriptionEntry? = nil, own: GroupEntry? = nil, team: GroupEntry? = nil) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback)
        s.subscriptions["sub-a"] = subA
        s.accountBudgets["own-x"] = own
        s.groups["g2"] = team
        return s
    }

    func ok(_ percent: Double) -> SubscriptionEntry {
        // The bar shows the 7-day window (spec 001 FR-005).
        SubscriptionEntry(status: SubscriptionStatus(fiveHour: nil,
                                                     sevenDay: LimitWindow(utilizationPercent: percent, resetsAt: window.end),
                                                     fetchedAt: window.start), state: .ok)
    }

    @Test func orderSubscriptionsAndOwnBudgetsThenGroups() {
        let items = BarLayout.segments(snapshot: snapshot(), configuration: config())
        #expect(items.map(\.id) == ["sub-a", "own-x", "sub-b", "g2"])
        #expect(items.map(\.name) == ["Max", "Personal", "Work", "Team"])
        #expect(items.map(\.icon) == ["brands:claude", "solid:robot", "brands:claude", "solid:wallet"])
    }

    @Test func ownBudgetValuesAndLevels() {
        func own(_ percent: Int, stale: Bool = false) -> BarItem? {
            BarLayout.segments(snapshot: snapshot(own: entry(percent: percent, members: ["own-x"], stale: stale)), configuration: config())
                .first { $0.id == "own-x" }
        }
        #expect(own(25)?.value == "25%")
        #expect(own(25)?.level == .normal)
        #expect(own(60)?.level == .warning)        // lowest threshold
        #expect(own(100)?.level == .critical)
        #expect(own(130)?.value == "130%")
        #expect(own(30, stale: true)?.stale == true)
        #expect(own(30)?.stale == false)

        // No data yet: placeholder.
        let none = BarLayout.segments(snapshot: snapshot(), configuration: config()).first { $0.id == "own-x" }
        #expect(none?.value == "…")
        #expect(none?.level == .normal)
        let noSnapshot = BarLayout.segments(snapshot: nil, configuration: config())
        #expect(noSnapshot.map(\.value) == ["…", "…", "…", "…"])
    }

    @Test func groupValues() {
        let team = BarLayout.segments(snapshot: snapshot(team: entry(percent: 55, members: ["m2"], stale: true)), configuration: config())
            .first { $0.id == "g2" }
        #expect(team?.value == "55%")
        #expect(team?.level == .warning)
        #expect(team?.stale == true)
    }

    /// Spec 009 FR-005: an empty group shown in the bar shows 0% with
    /// normal styling once refreshed, and the usual placeholder before.
    @Test func emptyGroupShowsZeroPercent() {
        var empty = config()
        empty.accounts.removeAll { $0.id == "m2" }
        let refreshed = BarLayout.segments(snapshot: snapshot(team: entry(percent: 0, members: [])), configuration: empty)
            .first { $0.id == "g2" }
        #expect(refreshed?.value == "0%")
        #expect(refreshed?.level == .normal)
        #expect(refreshed?.stale == false)
        let before = BarLayout.segments(snapshot: snapshot(), configuration: empty).first { $0.id == "g2" }
        #expect(before?.value == "…")
        #expect(before?.level == .normal)
        #expect(BarLayout.segments(snapshot: nil, configuration: empty).first { $0.id == "g2" }?.value == "…")
    }

    /// Spec 001 rules for subscriptions are unchanged.
    @Test func subscriptionRules() {
        func subA(_ entry: SubscriptionEntry?) -> BarItem? {
            BarLayout.segments(snapshot: snapshot(subA: entry), configuration: config()).first { $0.id == "sub-a" }
        }
        #expect(subA(ok(42))?.value == "42%")
        #expect(subA(ok(42))?.level == .normal)
        #expect(subA(ok(75))?.level == .warning)
        #expect(subA(ok(100))?.level == .critical)
        #expect(subA(nil)?.value == "…")
        #expect(subA(SubscriptionEntry(status: nil, state: .notSignedIn))?.value == "--")
        #expect(subA(SubscriptionEntry(status: nil, state: .credentialsExpired))?.value == "--")
        #expect(subA(SubscriptionEntry(status: nil, state: .credentialsExpired))?.stale == false)
        let stale = SubscriptionEntry(status: ok(90).status, state: .stale(lastGoodAt: window.start, error: "x"))
        #expect(subA(stale)?.stale == true)
        #expect(subA(stale)?.level == .warning)
        let staleNoData = SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "x"))
        #expect(subA(staleNoData)?.value == "--")
        #expect(subA(staleNoData)?.stale == false)
    }

    /// spec 010 FR-005: values in a grace period are shown without the stale marker.
    @Test func retryingSubscriptionIsNotStale() {
        func subA(_ entry: SubscriptionEntry?) -> BarItem? {
            BarLayout.segments(snapshot: snapshot(subA: entry), configuration: config()).first { $0.id == "sub-a" }
        }
        let retrying = SubscriptionEntry(status: ok(42).status,
                                         state: .retrying(lastGoodAt: window.start, error: "offline", retryAt: window.start.addingTimeInterval(30)))
        #expect(subA(retrying)?.value == "42%")
        #expect(subA(retrying)?.stale == false)
        #expect(subA(retrying)?.level == .normal)
    }

    /// spec 010 FR-010, FR-015: a rejected sign-in and expired credentials
    /// keep their values with the stale marker; without values "--".
    @Test func rejectedAndExpiredKeepTheirValuesStale() {
        func subA(_ entry: SubscriptionEntry?) -> BarItem? {
            BarLayout.segments(snapshot: snapshot(subA: entry), configuration: config()).first { $0.id == "sub-a" }
        }
        let rejected = SubscriptionEntry(status: ok(75).status, state: .signInRejected(lastGoodAt: window.start))
        #expect(subA(rejected)?.value == "75%")
        #expect(subA(rejected)?.stale == true)
        #expect(subA(rejected)?.level == .warning)
        let rejectedNoData = SubscriptionEntry(status: nil, state: .signInRejected(lastGoodAt: nil))
        #expect(subA(rejectedNoData)?.value == "--")
        #expect(subA(rejectedNoData)?.stale == false)
        let expired = SubscriptionEntry(status: ok(42).status, state: .credentialsExpired)
        #expect(subA(expired)?.value == "42%")
        #expect(subA(expired)?.stale == true)
    }

    /// spec 010 FR-016: a window whose reset passed shows 0% without a reset.
    @Test func effectiveStatusZeroesResetWindows() {
        let now = isoDate("2026-10-14T12:00:00Z")
        let past = now.addingTimeInterval(-60)
        let future = now.addingTimeInterval(3600)
        let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 30, resetsAt: past),
                                        sevenDay: LimitWindow(utilizationPercent: 60, resetsAt: future),
                                        modelLimits: [ModelLimit(modelName: "Fable", utilizationPercent: 90, resetsAt: past),
                                                      ModelLimit(modelName: "Other", utilizationPercent: 10, resetsAt: future)],
                                        fetchedAt: past)
        let effective = status.effective(now: now)
        #expect(effective.fiveHour == LimitWindow(utilizationPercent: 0, resetsAt: nil))
        #expect(effective.sevenDay == status.sevenDay)
        #expect(effective.modelLimits[0] == ModelLimit(modelName: "Fable", utilizationPercent: 0, resetsAt: nil))
        #expect(effective.modelLimits[1] == status.modelLimits[1])
        #expect(effective.fetchedAt == past)
        // Exactly at the reset time the window has reset.
        let atReset = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 50, resetsAt: now), fetchedAt: past)
        #expect(atReset.effective(now: now).sevenDay == LimitWindow(utilizationPercent: 0, resetsAt: nil))
        // A window that has not started is unchanged.
        let notStarted = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 0, resetsAt: nil), sevenDay: nil, fetchedAt: past)
        #expect(notStarted.effective(now: now) == notStarted)
    }

    @Test func staleEntryWhoseWeeklyWindowResetShowsZero() {
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 85, resetsAt: window.start.addingTimeInterval(-1)),
                                        fetchedAt: window.start.addingTimeInterval(-86400))
        let stale = SubscriptionEntry(status: status, state: .stale(lastGoodAt: status.fetchedAt, error: "offline"))
        let item = BarLayout.segments(snapshot: snapshot(subA: stale), configuration: config()).first { $0.id == "sub-a" }
        #expect(item?.value == "0%")
        #expect(item?.stale == true)
        #expect(item?.level == .normal)
    }

    @Test func warningThresholdDefaultsTo80() {
        #expect(BarLayout.warningThreshold([]) == 80)
        #expect(BarLayout.warningThreshold([90, 60]) == 60)
        #expect(BarLayout.level(percent: nil, thresholds: []) == .normal)
        #expect(BarLayout.level(percent: 80, thresholds: []) == .warning)
    }
}

/// Spec 004 FR-017 to FR-020: group members shown individually in the bar.
@Suite struct BarLayoutMemberTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    /// Accounts list: m3 (team, shown), sub, m1 (hidden group, shown),
    /// m2 (team, shown), m4 (team, not shown). Groups list: team ($300,
    /// warning at 50%), then the hidden group.
    func config(teamShown: Bool = true) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "m3", displayName: "Member three", kind: .tokenBased(TokenBasedSettings(membership: .group(id: "team", shownInBar: true)))),
            Account(id: "sub", displayName: "Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "m1", icon: "solid:robot", displayName: "Member one",
                    kind: .tokenBased(TokenBasedSettings(membership: .group(id: "hidden", shownInBar: true)))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(membership: .group(id: "team", shownInBar: true)))),
            Account(id: "m4", displayName: "Member four", kind: .tokenBased(TokenBasedSettings(groupId: "team"))),
        ]
        c.groups = [
            BudgetGroup(id: "team", name: "Team", budgetUSD: 300, shownInBar: teamShown, thresholds: [50]),
            BudgetGroup(id: "hidden", name: "Hidden", budgetUSD: 100, shownInBar: false),
        ]
        return c
    }

    func team(_ spend: [String: Decimal], stale: Bool = false) -> GroupEntry {
        let total = spend.values.reduce(Decimal(0), +)
        return GroupEntry(spentUSD: total, budgetUSD: 300, percent: PercentFormatter.rounded(spent: total, budget: 300), incomplete: false,
                          window: window, breakdown: .empty, members: ["m3", "m2", "m4"], memberSpendUSD: spend, stale: stale)
    }

    func snapshot(team: GroupEntry? = nil) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback)
        s.groups["team"] = team
        return s
    }

    /// FR-019, FR-020: members follow their group in accounts-list order; a
    /// hidden group's members take its position.
    @Test func membersFollowTheirGroup() {
        let items = BarLayout.segments(snapshot: snapshot(), configuration: config())
        #expect(items.map(\.id) == ["sub", "team", "team/m3", "team/m2", "hidden/m1"])
        #expect(items.map(\.name) == ["Max", "Team", "Member three", "Member two", "Member one"])
        #expect(items.first { $0.id == "hidden/m1" }?.icon == "solid:robot")

        // US3 scenario 3: the group hidden, its members stand in its place.
        let hidden = BarLayout.segments(snapshot: snapshot(), configuration: config(teamShown: false))
        #expect(hidden.map(\.id) == ["sub", "team/m3", "team/m2", "hidden/m1"])
    }

    /// FR-017, FR-018, US3 scenarios 1 and 4.
    @Test func memberValuesAndLevels() {
        func member(_ id: String, in entry: GroupEntry?) -> BarItem? {
            BarLayout.segments(snapshot: snapshot(team: entry), configuration: config()).first { $0.id == "team/\(id)" }
        }
        let entry = team(["m3": 90, "m2": 165, "m4": 0])
        #expect(member("m3", in: entry)?.value == "30%")
        #expect(member("m3", in: entry)?.level == .normal)
        #expect(member("m2", in: entry)?.value == "55%")
        #expect(member("m2", in: entry)?.level == .warning)      // group's warning threshold
        let over = team(["m3": 330])
        #expect(member("m3", in: over)?.value == "110%")         // actual value above 100%
        #expect(member("m3", in: over)?.level == .critical)

        // The group's data state: placeholder and stale.
        #expect(member("m3", in: nil)?.value == "…")
        #expect(member("m3", in: team(["m3": 30], stale: true))?.stale == true)
        #expect(member("m3", in: team(["m3": 30]))?.stale == false)
        let noSnapshot = BarLayout.segments(snapshot: nil, configuration: config()).first { $0.id == "team/m3" }
        #expect(noSnapshot?.value == "…")
        // Group values computed before the member joined: placeholder, not
        // 0%, with the group's stale flag.
        let before = member("m2", in: team(["m3": 30], stale: true))
        #expect(before?.value == "…")
        #expect(before?.level == .normal)
        #expect(before?.stale == true)
    }

    /// Members never add threshold state or notifications (FR-018).
    @Test func membersDoNotNotify() {
        var tracker = ThresholdTracker()
        let c = config()
        _ = tracker.observe(snapshot: snapshot(team: team(["m3": 10])), configuration: c)
        let crossings = tracker.observe(snapshot: snapshot(team: team(["m3": 160])), configuration: c)
        #expect(crossings.map(\.entityId) == ["team"])
        // Only the group has state; no member id is tracked.
        #expect(tracker.trackedEntityIds == ["team"])
    }
}

/// spec 007 FR-012: Codex subscription accounts in the bar.
@Suite struct CodexPlanBarLayoutTests {
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    static let now = isoDate("2026-10-14T15:00:00Z")

    static func config(shownInBar: Bool = true, thresholds: [Int] = []) -> Configuration {
        Configuration(accounts: [
            Account(id: "acc-max", displayName: "Claude Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "acc-codex", displayName: "ChatGPT", harness: .codex,
                    kind: .codexSubscription(CodexSubscriptionSettings(shownInBar: shownInBar, thresholds: thresholds))),
        ])
    }

    static func entry(five: Double = 70, weekly: Double = 20.4, fiveReached: Bool = false, fiveResetsIn: TimeInterval = 3600,
                      state: CodexLimitsState = .live) -> CodexLimitsEntry {
        CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: five, resetsAt: now.addingTimeInterval(fiveResetsIn), limitReached: fiveReached),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: weekly, resetsAt: now.addingTimeInterval(86400)),
        ]), state: state)
    }

    static func item(_ entry: CodexLimitsEntry?, config: Configuration = config()) -> BarItem? {
        var snapshot = UsageSnapshot(generatedAt: now, window: window, windowSource: .fallback)
        snapshot.codexLimits["acc-codex"] = entry
        return BarLayout.segments(snapshot: snapshot, configuration: config).first { $0.id == "acc-codex" }
    }

    @Test func shownAccountShowsTheLongestWindowInConfigurationOrder() {
        var snapshot = UsageSnapshot(generatedAt: Self.now, window: Self.window, windowSource: .fallback)
        snapshot.codexLimits["acc-codex"] = Self.entry()
        let items = BarLayout.segments(snapshot: snapshot, configuration: Self.config())
        #expect(items.map(\.id) == ["acc-max", "acc-codex"])
        #expect(items[1] == BarItem(id: "acc-codex", icon: "brands:openai", name: "ChatGPT", value: "20%", level: .normal, stale: false))
    }

    @Test func hiddenAccountHasNoItem() {
        #expect(Self.item(Self.entry(), config: Self.config(shownInBar: false)) == nil)
    }

    @Test func statesAndPlaceholders() {
        #expect(Self.item(Self.entry())?.stale == false)
        #expect(Self.item(Self.entry(state: .stale(reason: "offline")))?.stale == true)
        #expect(Self.item(Self.entry(state: .stale(reason: "offline")))?.value == "20%")
        let unavailable = Self.item(CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline")))
        #expect(unavailable?.value == "--")
        #expect(unavailable?.stale == false)
        #expect(unavailable?.level == .normal)
        #expect(Self.item(nil)?.value == "…")
        let noSnapshot = BarLayout.segments(snapshot: nil, configuration: Self.config()).first { $0.id == "acc-codex" }
        #expect(noSnapshot?.value == "…")
    }

    /// spec 010 FR-005: values in a grace period are not styled stale.
    @Test func retryingIsNotStale() {
        let item = Self.item(Self.entry(state: .retrying(reason: "offline", retryAt: Self.now.addingTimeInterval(30))))
        #expect(item?.stale == false)
        #expect(item?.value == "20%")
    }

    /// FR-012: local-only values (live limits off) are not styled stale.
    @Test func localOnlyIsNotStale() {
        let item = Self.item(Self.entry(state: .localOnly))
        #expect(item?.stale == false)
        #expect(item?.value == "20%")
    }

    /// FR-006: a newer snapshot shown between fetches is not styled stale.
    @Test func newerSnapshotIsNotStale() {
        let item = Self.item(Self.entry(state: .newerSnapshot))
        #expect(item?.stale == false)
        #expect(item?.value == "20%")
    }

    @Test func levelFollowsThresholds() {
        #expect(Self.item(Self.entry(weekly: 79))?.level == .normal)
        #expect(Self.item(Self.entry(weekly: 80))?.level == .warning)
        #expect(Self.item(Self.entry(weekly: 60), config: Self.config(thresholds: [50, 90]))?.level == .warning)
        #expect(Self.item(Self.entry(weekly: 100))?.level == .critical)
    }

    /// Any reached window uses the at-or-above-100% style, whatever the bar shows.
    @Test func reachedWindowIsCriticalAtAnyPercent() {
        let item = Self.item(Self.entry(five: 100, weekly: 40, fiveReached: true))
        #expect(item?.value == "40%")
        #expect(item?.level == .critical)
        // After the 5-hour reset the note is gone (FR-010).
        #expect(Self.item(Self.entry(five: 100, weekly: 40, fiveReached: true, fiveResetsIn: -1))?.level == .normal)
    }
}

/// Spec 008 FR-002: the bar follows the arrangement. Without a stored
/// arrangement the suites above keep the spec 004 FR-020 order.
@Suite struct BarLayoutArrangementTests {
    static func refs(_ items: [(EntryKind, String)]) -> [EntryRef] {
        items.map { EntryRef(kind: $0.0, id: $0.1) }
    }

    @Test func storedOrderIsFollowed() {
        var c = BarLayoutTests().config()
        c.arrangement = Arrangement(entries: Self.refs([(.group, "g2"), (.account, "own-x"), (.account, "sub-a"), (.account, "sub-b")]))
        #expect(BarLayout.segments(snapshot: nil, configuration: c).map(\.id) == ["g2", "own-x", "sub-a", "sub-b"])
    }

    /// Members follow their group in stored member order, and take a hidden
    /// group's position (spec 004 FR-019 unchanged).
    @Test func membersFollowStoredMemberOrder() {
        var c = BarLayoutMemberTests().config()
        c.arrangement = Arrangement(entries: Self.refs([(.group, "team"), (.account, "sub"), (.group, "hidden")]),
                                    members: ["team": ["m2", "m4", "m3"]])
        #expect(BarLayout.segments(snapshot: nil, configuration: c).map(\.id) == ["team", "team/m2", "team/m3", "sub", "hidden/m1"])

        var hidden = BarLayoutMemberTests().config(teamShown: false)
        hidden.arrangement = c.arrangement
        #expect(BarLayout.segments(snapshot: nil, configuration: hidden).map(\.id) == ["team/m2", "team/m3", "sub", "hidden/m1"])
    }

    /// Research R1: a group and an account sharing an id keep their own positions.
    @Test func sharedIdsKeepTheirOwnPositions() {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub", displayName: "Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "x", displayName: "Own x", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
            Account(id: "m", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
        ]
        c.groups = [BudgetGroup(id: "x", name: "Group x", budgetUSD: 10)]
        #expect(BarLayout.segments(snapshot: nil, configuration: c).map(\.name) == ["Max", "Own x", "Group x"])

        c.arrangement = Arrangement(entries: Self.refs([(.group, "x"), (.account, "sub"), (.account, "x")]))
        #expect(BarLayout.segments(snapshot: nil, configuration: c).map(\.name) == ["Group x", "Max", "Own x"])
        c.arrangement = Arrangement(entries: Self.refs([(.account, "x"), (.account, "sub"), (.group, "x")]))
        #expect(BarLayout.segments(snapshot: nil, configuration: c).map(\.name) == ["Own x", "Max", "Group x"])
    }

    @Test func hiddenEntriesAreSkipped() {
        var c = BarLayoutTests().config()
        c.arrangement = Arrangement(entries: Self.refs([(.account, "own-y"), (.group, "g1"), (.account, "sub-b"),
                                                        (.group, "g2"), (.account, "sub-a"), (.account, "own-x")]))
        #expect(BarLayout.segments(snapshot: nil, configuration: c).map(\.id) == ["sub-b", "g2", "sub-a", "own-x"])
    }

    /// Codex subscription accounts take part in the order (spec 007 FR-012).
    @Test func codexAccountFollowsTheArrangement() {
        var c = CodexPlanBarLayoutTests.config()
        c.arrangement = Arrangement(entries: Self.refs([(.account, "acc-codex")]))
        #expect(BarLayout.segments(snapshot: nil, configuration: c).map(\.id) == ["acc-codex", "acc-max"])
    }
}

/// spec 011 FR-012 to FR-015, research R6: the run-out marker on bar
/// entries whose bar window or budget has a counting run-out.
@Suite struct RunOutMarkerBarLayoutTests {
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    /// 25% of the week has elapsed.
    static let now = window.start.addingTimeInterval(window.duration / 4)

    static func config(marker: Bool = true) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.a", thresholds: [80]))),
            Account(id: "own", displayName: "Personal",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 100, thresholds: [80]))))),
            Account(id: "codex", displayName: "ChatGPT", harness: .codex,
                    kind: .codexSubscription(CodexSubscriptionSettings(shownInBar: true, thresholds: [80]))),
            Account(id: "m1", displayName: "Member", kind: .tokenBased(TokenBasedSettings(membership: .group(id: "team", shownInBar: true)))),
        ]
        c.groups = [BudgetGroup(id: "team", name: "Team", budgetUSD: 100, thresholds: [80])]
        c.showsRunOutMarker = marker
        return c
    }

    /// A Claude subscription fetched at `at`: the 7-day window ends with
    /// the week, the 5-hour window is half elapsed.
    static func sub(seven: Double, five: Double = 10, at: Date = now, state: SubscriptionState = .ok) -> SubscriptionEntry {
        SubscriptionEntry(status: SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: five, resetsAt: at.addingTimeInterval(2.5 * 3600)),
                                                     sevenDay: LimitWindow(utilizationPercent: seven, resetsAt: window.end),
                                                     fetchedAt: at), state: state)
    }

    /// A Codex plan observed at `observedAt` (default `now`): a 5-hour
    /// window half elapsed at `now` and a weekly window ending with the week.
    static func codex(five: Double = 10, weekly: Double, fiveReached: Bool = false, state: CodexLimitsState = .live,
                      observedAt: Date = now) -> CodexLimitsEntry {
        CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: observedAt, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: five, resetsAt: now.addingTimeInterval(2.5 * 3600), limitReached: fiveReached),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: weekly, resetsAt: window.end),
        ]), state: state)
    }

    static func budget(_ spent: Decimal, members: [String] = ["m1"], stale: Bool = false) -> GroupEntry {
        GroupEntry(spentUSD: spent, budgetUSD: 100, percent: PercentFormatter.rounded(spent: spent, budget: 100), incomplete: false,
                   window: window, breakdown: .empty, members: members,
                   memberSpendUSD: Dictionary(uniqueKeysWithValues: members.map { ($0, spent) }), stale: stale)
    }

    static func items(at: Date = now, sub: SubscriptionEntry? = nil, own: GroupEntry? = nil, team: GroupEntry? = nil,
                      codex: CodexLimitsEntry? = nil, marker: Bool = true) -> [String: BarItem] {
        var s = UsageSnapshot(generatedAt: at, window: window, windowSource: .fallback)
        s.subscriptions["sub"] = sub
        s.accountBudgets["own"] = own
        s.groups["team"] = team
        s.codexLimits["codex"] = codex
        let list = BarLayout.segments(snapshot: s, configuration: config(marker: marker))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    /// Story 3 scenarios 1 and 2: 40% with 25% elapsed gets the marker; at
    /// the warning threshold the glyph takes over.
    @Test func subscriptionStoryScenarios() {
        #expect(Self.items(sub: Self.sub(seven: 40))["sub"]?.runOutMarker == true)
        let warning = Self.items(sub: Self.sub(seven: 85))["sub"]
        #expect(warning?.level == .warning)
        #expect(warning?.runOutMarker == false)
    }

    /// The bar window of a subscription is the 7-day window (FR-012).
    @Test func subscriptionUsesTheSevenDayWindow() {
        // Ahead on 7-day, on pace on 5-hour.
        #expect(Self.items(sub: Self.sub(seven: 40, five: 50))["sub"]?.runOutMarker == true)
        // Ahead on 5-hour only.
        #expect(Self.items(sub: Self.sub(seven: 25, five: 90))["sub"]?.runOutMarker == false)
    }

    @Test func noMarkerWhenStaleHeldBackOrOnPace() {
        let stale = Self.sub(seven: 40, state: .stale(lastGoodAt: Self.now, error: "x"))
        #expect(Self.items(sub: stale)["sub"]?.stale == true)
        #expect(Self.items(sub: stale)["sub"]?.runOutMarker == false)
        // Story 3 scenario 3: 5% of the window elapsed.
        let early = Self.window.start.addingTimeInterval(Self.window.duration * 0.05)
        #expect(Self.items(at: early, sub: Self.sub(seven: 60, at: early))["sub"]?.runOutMarker == false)
        // +5 is on pace.
        #expect(Self.items(sub: Self.sub(seven: 30))["sub"]?.runOutMarker == false)
    }

    /// The bar window of a Codex plan is its longest effective window.
    @Test func codexUsesTheLongestWindow() {
        #expect(Self.items(codex: Self.codex(weekly: 40))["codex"]?.runOutMarker == true)
        #expect(Self.items(codex: Self.codex(five: 90, weekly: 25))["codex"]?.runOutMarker == false)
        // A reached limit is critical: no marker.
        let reached = Self.items(codex: Self.codex(five: 90, weekly: 40, fiveReached: true))["codex"]
        #expect(reached?.level == .critical)
        #expect(reached?.runOutMarker == false)
        // Stale values carry no marker.
        #expect(Self.items(codex: Self.codex(weekly: 40, state: .stale(reason: "offline")))["codex"]?.runOutMarker == false)
    }

    /// FR-002: the marker uses the pace at the observation time (Claude
    /// fetch time, Codex observation time), not at the snapshot time. Each
    /// pair flips if the snapshot time were used instead.
    @Test func markerUsesTheObservationTime() {
        let early = Self.window.start.addingTimeInterval(Self.window.duration * 0.05)
        let half = Self.window.start.addingTimeInterval(Self.window.duration / 2)
        // Observed in the hold back (5% elapsed), snapshot at 25%: no marker.
        #expect(Self.items(sub: Self.sub(seven: 60, at: early))["sub"]?.runOutMarker == false)
        #expect(Self.items(codex: Self.codex(weekly: 60, state: .localOnly, observedAt: early))["codex"]?.runOutMarker == false)
        // Observed 15 points ahead at 25%, snapshot at 50% (10 behind there): marker.
        #expect(Self.items(at: half, sub: Self.sub(seven: 40))["sub"]?.runOutMarker == true)
        #expect(Self.items(at: half, codex: Self.codex(weekly: 40, state: .localOnly))["codex"]?.runOutMarker == true)
    }

    /// FR-005: +6 (rounded) is the first delta whose run-out counts.
    @Test func firstAheadDeltaGetsTheMarker() {
        #expect(Self.items(sub: Self.sub(seven: 31))["sub"]?.runOutMarker == true)
    }

    @Test func budgetsUseTheirBudgetPace() {
        let items = Self.items(own: Self.budget(40), team: Self.budget(40))
        #expect(items["own"]?.runOutMarker == true)
        #expect(items["team"]?.runOutMarker == true)
        // A member's share entry never carries the marker (FR-013).
        #expect(items["team/m1"]?.runOutMarker == false)
        // Warning level, stale, on pace and empty group: no marker.
        #expect(Self.items(own: Self.budget(85))["own"]?.runOutMarker == false)
        #expect(Self.items(own: Self.budget(40, stale: true))["own"]?.runOutMarker == false)
        #expect(Self.items(own: Self.budget(28))["own"]?.runOutMarker == false)
        #expect(Self.items(team: Self.budget(0, members: []))["team"]?.runOutMarker == false)
    }

    /// Story 3 scenario 4: the toggle off removes every marker (FR-014).
    @Test func toggleOffRemovesTheMarker() {
        let items = Self.items(sub: Self.sub(seven: 40), own: Self.budget(40), team: Self.budget(40),
                               codex: Self.codex(weekly: 40), marker: false)
        #expect(items.values.allSatisfy { !$0.runOutMarker })
        #expect(items.count == 5)
    }

    @Test func placeholdersNeverCarryTheMarker() {
        let none = BarLayout.segments(snapshot: nil, configuration: Self.config())
        #expect(none.allSatisfy { !$0.runOutMarker })
        let empty = Self.items()
        #expect(empty.values.allSatisfy { !$0.runOutMarker })
        let notSignedIn = Self.items(sub: SubscriptionEntry(status: nil, state: .notSignedIn))["sub"]
        #expect(notSignedIn?.value == "--")
        #expect(notSignedIn?.runOutMarker == false)
    }

    /// FR-015: the accessibility wording.
    @Test func accessibilitySuffix() {
        let marked = BarItem(id: "a", icon: "x", name: "A", value: "40%", level: .normal, stale: false, runOutMarker: true)
        #expect(marked.accessibilitySuffix == ", projected to run out before reset")
        let plain = BarItem(id: "a", icon: "x", name: "A", value: "40%", level: .normal, stale: false)
        #expect(plain.runOutMarker == false)
        #expect(plain.accessibilitySuffix == "")
    }
}
