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

    /// Spec 015 FR-004, FR-005: a group whose carried-over entry was
    /// computed for the old period shows the placeholder without a level,
    /// like a group before its first value.
    @Test func periodMismatchedGroupShowsThePlaceholder() {
        var monthly = config()
        monthly.groups[0].budget.period = .monthly
        let carried = snapshot(team: entry(percent: 95, members: ["m2"], stale: true))
        let item = BarLayout.segments(snapshot: carried.droppingBudgetPeriodMismatches(configuration: monthly), configuration: monthly)
            .first { $0.id == "g2" }
        #expect(item?.value == "…")
        #expect(item?.level == .normal)
        #expect(item?.stale == false)
        #expect(item?.runOutMarker == false)
        // A group without an entry looks the same.
        #expect(BarLayout.segments(snapshot: snapshot(), configuration: monthly).first { $0.id == "g2" } == item)
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
        #expect(LevelThresholds([]).warning == 80)
        #expect(BarLayout.defaultWarningThreshold == 80)
        #expect(LevelThresholds([90, 60]).warning == 60)
        #expect(LevelThresholds([]).level(usedPercent: nil) == .normal)
        #expect(LevelThresholds([]).level(usedPercent: 80) == .warning)
    }

    /// spec 030 FR-002: the second threshold is the critical level.
    @Test func secondThresholdIsCritical() {
        var c = config()
        c.groups[0].budget.thresholds = [80, 90]
        let team = BarLayout.segments(snapshot: snapshot(team: entry(percent: 91, members: ["m2"])), configuration: c)
            .first { $0.id == "g2" }
        #expect(team?.level == .critical)
        #expect(LevelThresholds([80, 90]).level(usedPercent: 91) == .critical)
        #expect(LevelThresholds([80, 90]).level(usedPercent: 85) == .warning)
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

/// spec 017 FR-008 to FR-010, spec 011 FR-012, FR-013, research R8: the bar
/// entry shows "↑" when its bar window or budget burns fast, with the
/// suppression rules of "↗". Uses the fixtures of `RunOutMarkerBarLayoutTests`
/// (25% of the week elapsed). 50% burns fast by its average rate (ratio 3);
/// 33% is 8% ahead with a spec 011 run-out but a ratio of about 1.5.
@Suite struct BurnRateBarLayoutTests {
    typealias F = RunOutMarkerBarLayoutTests

    static func flags(_ item: BarItem?) -> (Bool?, Bool?) {
        (item?.runOutMarker, item?.burnsFast)
    }

    @Test func subscriptionFollowsTheSevenDayBurnRate() {
        let fast = F.items(sub: F.sub(seven: 50))["sub"]
        #expect(fast?.runOutMarker == true)
        #expect(fast?.burnsFast == true)
        let slow = F.items(sub: F.sub(seven: 33))["sub"]
        #expect(slow?.runOutMarker == true)
        #expect(slow?.burnsFast == false)
        // A fast 5-hour window does not count: the bar follows the 7-day window.
        let five = F.items(sub: F.sub(seven: 25, five: 90))["sub"]
        #expect(five?.runOutMarker == false)
        #expect(five?.burnsFast == false)
    }

    @Test func codexFollowsTheLongestWindowBurnRate() {
        let fast = F.items(codex: F.codex(weekly: 50))["codex"]
        #expect(fast?.runOutMarker == true)
        #expect(fast?.burnsFast == true)
        let slow = F.items(codex: F.codex(weekly: 33))["codex"]
        #expect(slow?.runOutMarker == true)
        #expect(slow?.burnsFast == false)
        let five = F.items(codex: F.codex(five: 90, weekly: 20))["codex"]
        #expect(five?.runOutMarker == false)
        #expect(five?.burnsFast == false)
    }

    /// A group and an own budget sharing an id (spec 008) each follow their
    /// own burn rate: the own budget burns fast, the group is on pace.
    @Test func sharedIdBudgetsFollowTheirOwnBurnRate() {
        var c = Configuration()
        c.accounts = [
            Account(id: "x", displayName: "Own x", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 100))))),
            Account(id: "m", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
        ]
        c.groups = [BudgetGroup(id: "x", name: "Group x", budgetUSD: 100)]
        c.showsRunOutMarker = true
        var s = UsageSnapshot(generatedAt: F.now, window: F.window, windowSource: .fallback)
        s.accountBudgets["x"] = F.budget(50, members: ["x"])
        s.groups["x"] = F.budget(25, members: ["m"])
        let items = Dictionary(uniqueKeysWithValues: BarLayout.segments(snapshot: s, configuration: c).map { ($0.name, $0) })
        #expect(Self.flags(items["Own x"]) == (true, true))
        #expect(Self.flags(items["Group x"]) == (false, false))
    }

    @Test func budgetsFollowTheirOwnBurnRate() {
        let items = F.items(own: F.budget(50), team: F.budget(50))
        #expect(items["own"]?.runOutMarker == true)
        #expect(items["own"]?.burnsFast == true)
        #expect(items["team"]?.runOutMarker == true)
        #expect(items["team"]?.burnsFast == true)
        // A member's share entry never carries either marker (FR-009).
        #expect(items["team/m1"]?.runOutMarker == false)
        #expect(items["team/m1"]?.burnsFast == false)
        let slow = F.items(own: F.budget(33))["own"]
        #expect(slow?.runOutMarker == true)
        #expect(slow?.burnsFast == false)
    }

    /// FR-009: a fast entry at a warning or critical level, or stale, shows
    /// neither marker.
    @Test func suppressedLikeTheRunOutMarker() {
        let warning = F.items(sub: F.sub(seven: 85))["sub"]
        #expect(warning?.level == .warning)
        #expect(warning?.runOutMarker == false)
        #expect(warning?.burnsFast == false)
        let stale = F.items(sub: F.sub(seven: 50, state: .stale(lastGoodAt: F.now, error: "x")))["sub"]
        #expect(stale?.stale == true)
        #expect(stale?.runOutMarker == false)
        #expect(stale?.burnsFast == false)
        let staleBudget = F.items(own: F.budget(50, stale: true))["own"]
        #expect(staleBudget?.runOutMarker == false)
        #expect(staleBudget?.burnsFast == false)
        let reached = F.items(codex: F.codex(five: 90, weekly: 50, fiveReached: true))["codex"]
        #expect(reached?.level == .critical)
        #expect(reached?.runOutMarker == false)
        #expect(reached?.burnsFast == false)
        let warningBudget = F.items(own: F.budget(85))["own"]
        #expect(warningBudget?.runOutMarker == false)
        #expect(warningBudget?.burnsFast == false)
    }

    /// FR-010: the toggle covers both markers.
    @Test func toggleOffRemovesBothMarkers() {
        let items = F.items(sub: F.sub(seven: 50), own: F.budget(50), team: F.budget(50),
                            codex: F.codex(weekly: 50), marker: false)
        #expect(items.count == 5)
        #expect(items.values.allSatisfy { !$0.runOutMarker && !$0.burnsFast })
    }

    /// Research R8: without a bar percent (no 7-day values) there is no
    /// marker, even when another window of the account burns fast.
    @Test func noBarPercentNoMarker() {
        let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 90, resetsAt: F.now.addingTimeInterval(2.5 * 3600)),
                                        sevenDay: nil, fetchedAt: F.now)
        var snapshot = UsageSnapshot(generatedAt: F.now, window: F.window, windowSource: .fallback)
        snapshot.subscriptions["sub"] = SubscriptionEntry(status: status, state: .ok)
        #expect(snapshot.burnRate(for: .claude("sub", .fiveHour))?.burnsFast == true)
        let item = BarLayout.segments(snapshot: snapshot, configuration: F.config()).first { $0.id == "sub" }
        #expect(item?.value == "--")
        #expect(item?.runOutMarker == false)
        #expect(item?.burnsFast == false)
    }
}

/// spec 017 US2 (FR-005 to FR-009) with an empty observation log: the
/// average rate alone turns "↗" into "↑".
@Suite struct AverageEscalationBarLayoutTests {
    typealias F = RunOutMarkerBarLayoutTests
    static let week = WindowResolver.weekSeconds
    static let monthly = DateInterval(start: isoDate("2026-11-01T00:00:00Z"), end: isoDate("2026-12-01T00:00:00Z"))

    /// The bar items with the Claude 7-day window, the Codex weekly window
    /// and the budgets observed after `elapsedShare` of `F.window`.
    static func items(_ used: Double, elapsedShare: Double) -> [String: BarItem] {
        let at = F.window.start.addingTimeInterval(week * elapsedShare)
        return F.items(at: at, sub: F.sub(seven: used, at: at), own: F.budget(Decimal(used)),
                       codex: F.codex(weekly: used, observedAt: at))
    }

    static func presentation(_ item: BarItem?) -> BarEntryPresentation? {
        item.flatMap { BarPresentation.entries([$0], settings: LevelDisplaySettings(levelColor: .text, showSymbols: true)).first }
    }

    /// US2 AS1: 62% with 43% elapsed (ratio about 2.2) shows "62%↑".
    @Test func storyTwoScenarioOne() {
        let items = Self.items(62, elapsedShare: 0.43)
        for id in ["sub", "codex", "own"] {
            #expect(items[id]?.runOutMarker == true, "\(id)")
            #expect(items[id]?.burnsFast == true, "\(id)")
        }
        let entry = Self.presentation(items["sub"])
        #expect(entry?.valueText == "62%")
        #expect(entry?.runOutMarker == "↑")
    }

    /// US2 AS2: 55% with 45% elapsed is 10% ahead but below twice the
    /// sustainable rate: "55%↗".
    @Test func storyTwoScenarioTwo() {
        let items = Self.items(55, elapsedShare: 0.45)
        for id in ["sub", "codex", "own"] {
            #expect(items[id]?.runOutMarker == true, "\(id)")
            #expect(items[id]?.burnsFast == false, "\(id)")
        }
        #expect(Self.presentation(items["sub"])?.runOutMarker == "↗")
    }

    /// US2 AS3: an entry that would burn fast at its warning threshold shows
    /// the warning glyph and its value only.
    @Test func storyTwoScenarioThree() {
        let items = Self.items(85, elapsedShare: 0.43)
        for id in ["sub", "codex", "own"] {
            #expect(items[id]?.level == .warning, "\(id)")
            #expect(items[id]?.runOutMarker == false, "\(id)")
            #expect(items[id]?.burnsFast == false, "\(id)")
        }
        let entry = Self.presentation(items["sub"])
        #expect(entry?.glyph == "⚠")
        #expect(entry?.valueText == "85%")
        #expect(entry?.runOutMarker == nil)
    }

    /// A monthly budget escalates by its average rate the same way.
    @Test func monthlyBudget() {
        func item(spent: Decimal, elapsedDays: Double) -> BarItem? {
            let at = Self.monthly.start.addingTimeInterval(elapsedDays * 86_400)
            let entry = GroupEntry(spentUSD: spent, budgetUSD: 100, percent: PercentFormatter.rounded(spent: spent, budget: 100),
                                   incomplete: false, period: .monthly, window: Self.monthly, breakdown: .empty, members: ["m1"],
                                   memberSpendUSD: ["m1": spent])
            return F.items(at: at, own: entry)["own"]
        }
        // 62% after 13 of 30 days: average 4.77 per day, sustainable 2.24.
        #expect(item(spent: 62, elapsedDays: 13)?.burnsFast == true)
        // 55% after 13.5 of 30 days: ahead with a run-out, below twice.
        let slow = item(spent: 55, elapsedDays: 13.5)
        #expect(slow?.runOutMarker == true)
        #expect(slow?.burnsFast == false)
    }
}

/// spec 017 US1 (FR-004, FR-006, FR-008, FR-009) through the bar: a burst
/// in the observation log turns on "↑" for an entry that is on pace or
/// behind, for every entry kind, with the suppression rules of "↗". Uses the
/// fixtures of `RunOutMarkerBarLayoutTests` (25% of the week elapsed at
/// `now`): 14% 50 minutes before `now` and 20% at `now` is 7.2 points per
/// hour against 80 / 126 h sustainable, while 20% is on pace (no "↗").
@Suite struct RecentBurstBarLayoutTests {
    typealias F = RunOutMarkerBarLayoutTests
    static let before = F.now.addingTimeInterval(-50 * 60)

    static func snapshot(at: Date, sub: SubscriptionEntry? = nil, own: GroupEntry? = nil,
                         codex: CodexLimitsEntry? = nil) -> UsageSnapshot {
        var s = UsageSnapshot(generatedAt: at, window: F.window, windowSource: .fallback)
        s.subscriptions["sub"] = sub
        s.accountBudgets["own"] = own
        s.codexLimits["codex"] = codex
        return s
    }

    /// The bar items of `second` with the log of both snapshots attached.
    static func items(_ first: UsageSnapshot, _ second: UsageSnapshot, marker: Bool = true) -> [String: BarItem] {
        var s = second
        s.observations = ObservationLog().updated(with: first, budgetPricesChanged: false)
            .updated(with: second, budgetPricesChanged: false)
        let list = BarLayout.segments(snapshot: s, configuration: F.config(marker: marker))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    static func burst(to used: Double, state: SubscriptionState = .ok, stale: Bool = false, codexState: CodexLimitsState = .live,
                      marker: Bool = true) -> [String: BarItem] {
        let from = used - 6
        let first = snapshot(at: before, sub: F.sub(seven: from, at: before), own: F.budget(Decimal(from)),
                             codex: F.codex(weekly: from, observedAt: before))
        let second = snapshot(at: F.now, sub: F.sub(seven: used, state: state), own: F.budget(Decimal(used), stale: stale),
                              codex: F.codex(weekly: used, state: codexState))
        return items(first, second, marker: marker)
    }

    /// US1 AS1 and AS3: the Claude 7-day window, the own budget and the
    /// Codex longest window all show "↑" from the recent rate alone.
    @Test func burstShowsUpArrowForEveryKind() {
        let items = Self.burst(to: 20)
        for id in ["sub", "own", "codex"] {
            #expect(items[id]?.runOutMarker == true, "\(id)")
            #expect(items[id]?.burnsFast == true, "\(id)")
        }
        // Without the log the same values show no marker.
        let quiet = F.items(sub: F.sub(seven: 20), own: F.budget(20), codex: F.codex(weekly: 20))
        for id in ["sub", "own", "codex"] {
            #expect(quiet[id]?.runOutMarker == false, "\(id)")
            #expect(quiet[id]?.burnsFast == false, "\(id)")
        }
    }

    /// FR-009, FR-010, SC-004: a recent-rate burst is suppressed like "↗":
    /// toggle off, stale, and at the warning level.
    @Test func recentBurstFollowsTheSuppressionRules() {
        let off = Self.burst(to: 20, marker: false)
        #expect(off.values.allSatisfy { !$0.runOutMarker && !$0.burnsFast })
        // The stale Claude and Codex entries keep their observations and
        // burn fast in the snapshot; the bar's stale rule removes the marker.
        // A stale budget adds no observation, so it has no recent rate.
        let stale = Self.burst(to: 20, state: .stale(lastGoodAt: F.now, error: "x"), stale: true,
                               codexState: .stale(reason: "x"))
        for id in ["sub", "own", "codex"] {
            #expect(stale[id]?.stale == true, "\(id)")
            #expect(stale[id]?.runOutMarker == false, "\(id)")
            #expect(stale[id]?.burnsFast == false, "\(id)")
        }
        let first = Self.snapshot(at: Self.before, sub: F.sub(seven: 14, at: Self.before), codex: F.codex(weekly: 14, observedAt: Self.before))
        var second = Self.snapshot(at: F.now, sub: F.sub(seven: 20, state: .stale(lastGoodAt: F.now, error: "x")),
                                   codex: F.codex(weekly: 20, state: .stale(reason: "x")))
        second.observations = ObservationLog().updated(with: first, budgetPricesChanged: false)
            .updated(with: second, budgetPricesChanged: false)
        #expect(second.burnRate(for: .claude("sub", .sevenDay))?.burnsFast == true)
        #expect(second.burnRate(for: .codex("codex", "weekly"))?.burnsFast == true)
        let warning = Self.burst(to: 81)
        for id in ["sub", "own", "codex"] {
            #expect(warning[id]?.level == .warning, "\(id)")
            #expect(warning[id]?.runOutMarker == false, "\(id)")
            #expect(warning[id]?.burnsFast == false, "\(id)")
        }
    }
}

/// spec 027 FR-007 to FR-009: the bar entry of a Claude or Codex
/// subscription follows its headline window, with tag, level and markers.
/// Uses the fixtures of `RunOutMarkerBarLayoutTests` (25% of the week
/// elapsed, the 5-hour window half elapsed).
@Suite struct HeadlineBarLayoutTests {
    typealias F = RunOutMarkerBarLayoutTests

    static func config(claude: HeadlineChoice? = nil, codex: HeadlineChoice? = nil) -> Configuration {
        F.config().settingHeadline(claude, accountId: "sub").settingHeadline(codex, accountId: "codex")
    }

    static func items(sub: SubscriptionEntry? = nil, codex: CodexLimitsEntry? = nil, own: GroupEntry? = nil, team: GroupEntry? = nil,
                      claudeChoice: HeadlineChoice? = nil, codexChoice: HeadlineChoice? = nil) -> [String: BarItem] {
        var s = UsageSnapshot(generatedAt: F.now, window: F.window, windowSource: .fallback)
        s.subscriptions["sub"] = sub
        s.codexLimits["codex"] = codex
        s.accountBudgets["own"] = own
        s.groups["team"] = team
        let list = BarLayout.segments(snapshot: s, configuration: config(claude: claudeChoice, codex: codexChoice))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    static func claude(_ sub: SubscriptionEntry?, _ choice: HeadlineChoice? = .claudeFiveHour) -> BarItem? {
        items(sub: sub, claudeChoice: choice)["sub"]
    }

    /// With the default window the entry looks as today: no tag.
    @Test func defaultWindowHasNoTag() {
        for choice in [nil, HeadlineChoice.claudeSevenDay] {
            let item = Self.claude(F.sub(seven: 70, five: 58), choice)
            #expect(item?.value == "70%")
            #expect(item?.tag == nil)
            #expect(item?.windowName == nil)
        }
        let codex = Self.items(codex: F.codex(five: 40, weekly: 60))["codex"]
        #expect(codex?.value == "60%")
        #expect(codex?.tag == nil)
    }

    /// US1 scenario 2: the 5-hour window with its tag.
    @Test func fiveHourWindowWithTag() {
        let item = Self.claude(F.sub(seven: 70, five: 58))
        #expect(item?.value == "58%")
        #expect(item?.tag == "5h")
        #expect(item?.windowName == "5-hour window")
    }

    /// US1 scenario 3: the 5-hour window at the warning threshold.
    @Test func levelFollowsTheHeadline() {
        let item = Self.claude(F.sub(seven: 30, five: 85))
        #expect(item?.level == .warning)
        #expect(Self.claude(F.sub(seven: 85, five: 30))?.level == .normal)
    }

    /// US1 scenario 3a: a full 7-day window stays critical (clarification).
    @Test func fullSevenDayWindowStaysCritical() {
        let item = Self.claude(F.sub(seven: 100, five: 40))
        #expect(item?.value == "40%")
        #expect(item?.tag == "5h")
        #expect(item?.level == .critical)
        #expect(Self.claude(F.sub(seven: 30, five: 100))?.level == .critical)
    }

    /// US1 scenario 4: the markers follow the 5-hour window, not the 7-day.
    @Test func markersFollowTheHeadline() {
        let slow = Self.claude(F.sub(seven: 25, five: 58))
        #expect(slow?.runOutMarker == true)
        #expect(slow?.burnsFast == false)
        let fast = Self.claude(F.sub(seven: 25, five: 70))
        #expect(fast?.runOutMarker == true)
        #expect(fast?.burnsFast == true)
        // Ahead on the 7-day window only: no marker with the 5-hour headline.
        let sevenOnly = Self.claude(F.sub(seven: 50, five: 50))
        #expect(sevenOnly?.runOutMarker == false)
        #expect(sevenOnly?.burnsFast == false)
        #expect(Self.claude(F.sub(seven: 50, five: 50), nil)?.burnsFast == true)
    }

    /// FR-007, FR-008: a chosen fixed window without values reads "--" with
    /// its tag, also for a signed-in entry without a status.
    @Test func fixedWindowWithoutValues() {
        let noFive = SubscriptionEntry(status: SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 70, resetsAt: F.window.end),
                                                                  fetchedAt: F.now), state: .ok)
        for entry in [noFive, SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "offline")),
                      SubscriptionEntry(status: nil, state: .credentialsExpired)] {
            let item = Self.claude(entry)
            #expect(item?.value == "--")
            #expect(item?.tag == "5h")
            #expect(item?.windowName == "5-hour window")
            #expect(item?.stale == false)
            #expect(item?.runOutMarker == false)
        }
    }

    /// FR-008: no tag before the first values and when not signed in.
    @Test func placeholdersCarryNoTag() {
        let notSignedIn = Self.claude(SubscriptionEntry(status: nil, state: .notSignedIn))
        #expect(notSignedIn?.value == "--")
        #expect(notSignedIn?.tag == nil)
        let before = Self.claude(nil)
        #expect(before?.value == "…")
        #expect(before?.tag == nil)
        let none = BarLayout.segments(snapshot: nil, configuration: Self.config(claude: .claudeFiveHour, codex: .codexWindow("5-hour")))
        #expect(none.allSatisfy { $0.tag == nil && $0.value == "…" })
        let codexUnavailable = Self.items(codex: CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline")),
                                          codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(codexUnavailable?.value == "--")
        #expect(codexUnavailable?.tag == nil)
    }

    /// Stale values keep the tag and the stale marker.
    @Test func staleValuesKeepTheTag() {
        let item = Self.claude(F.sub(seven: 70, five: 58, state: .stale(lastGoodAt: F.now, error: "offline")))
        #expect(item?.stale == true)
        #expect(item?.tag == "5h")
        #expect(item?.value == "58%")
    }

    /// A model limit chosen and reported: its percent with the model name.
    @Test func modelLimitWithTag() {
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 70, resetsAt: F.window.end),
                                        modelLimits: [ModelLimit(modelName: "Fable", utilizationPercent: 31, resetsAt: F.window.end)],
                                        fetchedAt: F.now)
        let item = Self.claude(SubscriptionEntry(status: status, state: .ok), .claudeModel("Fable"))
        #expect(item?.value == "31%")
        #expect(item?.tag == "Fable")
        #expect(item?.windowName == "Fable weekly limit")
    }

    /// US2 scenario 1: the Codex 5-hour window with its tag, level and markers.
    @Test func codexFiveHourWindow() {
        let item = Self.items(codex: F.codex(five: 40, weekly: 60), codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(item?.value == "40%")
        #expect(item?.tag == "5h")
        #expect(item?.windowName == "5-hour window")
        #expect(Self.items(codex: F.codex(five: 85, weekly: 20), codexChoice: .codexWindow("5-hour"))["codex"]?.level == .warning)
        let marked = Self.items(codex: F.codex(five: 58, weekly: 20), codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(marked?.runOutMarker == true)
    }

    /// US2 scenario 1, negatives: a weekly window at the warning threshold
    /// does not color a 5-hour headline, and the fast burn follows the
    /// headline's burn key.
    @Test func codexLevelAndBurnFollowTheHeadline() {
        let calm = Self.items(codex: F.codex(five: 30, weekly: 85), codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(calm?.level == .normal)
        #expect(calm?.tag == "5h")
        let fast = Self.items(codex: F.codex(five: 70, weekly: 20), codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(fast?.runOutMarker == true)
        #expect(fast?.burnsFast == true)
        let weekly = Self.items(codex: F.codex(five: 70, weekly: 20))["codex"]
        #expect(weekly?.burnsFast == false)
    }

    /// FR-007: a full 7-day window keeps the entry critical also when the
    /// chosen 5-hour window has no values ("5h --"); a 7-day window at 100%
    /// whose reset passed shows 0% and no longer does (spec 010 FR-016).
    @Test func sevenDayCriticalRuleEdges() {
        let noFive = SubscriptionEntry(status: SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 100, resetsAt: F.window.end),
                                                                  fetchedAt: F.now), state: .ok)
        let dashes = Self.claude(noFive)
        #expect(dashes?.value == "--")
        #expect(dashes?.tag == "5h")
        #expect(dashes?.level == .critical)
        let resetSeven = SubscriptionEntry(status: SubscriptionStatus(
            fiveHour: LimitWindow(utilizationPercent: 40, resetsAt: F.now.addingTimeInterval(2.5 * 3600)),
            sevenDay: LimitWindow(utilizationPercent: 100, resetsAt: F.now.addingTimeInterval(-3600)),
            fetchedAt: F.now.addingTimeInterval(-7200)), state: .ok)
        let item = Self.claude(resetSeven)
        #expect(item?.value == "40%")
        #expect(item?.level == .normal)
    }

    /// A chosen 5-hour window whose reset passed reads "5h 0%" and keeps
    /// the choice (edge case, spec 010 FR-016).
    @Test func resetFiveHourWindowShowsZeroWithTag() {
        let item = Self.claude(F.sub(seven: 70, five: 58, at: F.now.addingTimeInterval(-3 * 3600)))
        #expect(item?.value == "0%")
        #expect(item?.tag == "5h")
    }

    /// US2 scenario 2: a reached window keeps the at-or-above-100% style,
    /// whichever window is the headline.
    @Test func codexReachedWindowStaysCritical() {
        // The sources mark a window at 100% as reached (spec 007 research R2).
        let windows = CodexLimitWindow.applyingReachedRule([
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 30, resetsAt: F.now.addingTimeInterval(2.5 * 3600)),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 100, resetsAt: F.window.end),
        ], sourceReportsReached: false)
        let full = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: F.now, origin: .live, windows: windows),
                                    state: .live)
        let item = Self.items(codex: full, codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(item?.value == "30%")
        #expect(item?.level == .critical)
        let reached = Self.items(codex: F.codex(five: 90, weekly: 40, fiveReached: true), codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(reached?.level == .critical)
    }

    /// FR-004: budgets and member shares never carry a tag.
    @Test func budgetsAndMembersHaveNoTag() {
        let items = Self.items(sub: F.sub(seven: 70), own: F.budget(40), team: F.budget(40), claudeChoice: .claudeFiveHour)
        #expect(items["own"]?.tag == nil)
        #expect(items["team"]?.tag == nil)
        #expect(items["team/m1"]?.tag == nil)
        #expect(items["own"]?.windowName == nil)
    }
}

/// spec 027 FR-006, US3: a chosen model limit or Codex window the latest
/// values no longer contain falls back to the default window, and comes
/// back with the window, without changing the stored choice.
@Suite struct HeadlineFallbackBarLayoutTests {
    typealias F = RunOutMarkerBarLayoutTests
    typealias H = HeadlineBarLayoutTests

    static func sub(fable: Double?) -> SubscriptionEntry {
        let models = fable.map { [ModelLimit(modelName: "Fable", utilizationPercent: $0, resetsAt: F.window.end)] } ?? []
        return SubscriptionEntry(status: SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 70, resetsAt: F.window.end),
                                                            modelLimits: models, fetchedAt: F.now), state: .ok)
    }

    /// US3 scenarios 1 and 2: the Fable limit vanishes and comes back.
    @Test func modelLimitFallsBackAndReturns() {
        let config = H.config(claude: .claudeModel("Fable"))
        var snapshot = UsageSnapshot(generatedAt: F.now, window: F.window, windowSource: .fallback)
        snapshot.subscriptions["sub"] = Self.sub(fable: nil)
        let gone = BarLayout.segments(snapshot: snapshot, configuration: config).first { $0.id == "sub" }
        #expect(gone?.value == "70%")
        #expect(gone?.tag == nil)
        #expect(gone?.windowName == nil)
        // The dropdown puts the `●` on the 7-day row during the fallback.
        let headline = HeadlineWindow.claude(accountId: "sub", status: snapshot.subscriptions["sub"]?.status,
                                             choice: .claudeModel("Fable"), now: F.now)
        #expect(headline.rowName == "7-day")

        snapshot.subscriptions["sub"] = Self.sub(fable: 31)
        let back = BarLayout.segments(snapshot: snapshot, configuration: config).first { $0.id == "sub" }
        #expect(back?.value == "31%")
        // The tag returns with the same configuration: the fallback left the
        // stored choice alone (FR-006).
        #expect(back?.tag == "Fable")
    }

    /// A Codex 5-hour choice while the plan reports only a weekly window.
    @Test func codexWindowFallsBack() {
        let weeklyOnly = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: F.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 60, resetsAt: F.window.end),
        ]), state: .live)
        let item = H.items(codex: weeklyOnly, codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(item?.value == "60%")
        #expect(item?.tag == nil)
        let back = H.items(codex: F.codex(five: 40, weekly: 60), codexChoice: .codexWindow("5-hour"))["codex"]
        #expect(back?.value == "40%")
        #expect(back?.tag == "5h")
    }

    /// US3 scenario 3: a click on the default row during the fallback
    /// clears the stored choice.
    @Test func clickOnTheDefaultRowClearsTheChoice() {
        let config = H.config(claude: .claudeModel("Fable"), codex: .codexWindow("5-hour"))
        let cleared = config.settingHeadline(HeadlineWindow.choice(forClaude: .sevenDay), accountId: "sub")
        #expect(cleared.account(id: "sub")?.kind.subscription?.headlineWindow == nil)
        let weeklyOnly = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: F.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 60, resetsAt: F.window.end),
        ]), state: .live)
        let codexCleared = config.settingHeadline(HeadlineWindow.choice(forCodex: "weekly", entry: weeklyOnly, now: F.now), accountId: "codex")
        #expect(codexCleared.account(id: "codex")?.kind.codexSubscription?.headlineWindow == nil)
    }
}

/// spec 030 FR-002 to FR-004: the levels of bar entries from the second
/// threshold, and the real-limit flag that tells "critical" from "over
/// limit". Uses the fixtures of `RunOutMarkerBarLayoutTests`.
@Suite struct ThresholdLevelBarLayoutTests {
    typealias F = RunOutMarkerBarLayoutTests

    /// Every owner with `thresholds`; markers off so only levels matter.
    static func config(_ thresholds: [Int], claude: HeadlineChoice? = nil) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.a", thresholds: thresholds))),
            Account(id: "own", displayName: "Personal",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 100, thresholds: thresholds))))),
            Account(id: "codex", displayName: "ChatGPT", harness: .codex,
                    kind: .codexSubscription(CodexSubscriptionSettings(shownInBar: true, thresholds: thresholds))),
            Account(id: "m1", displayName: "Member", kind: .tokenBased(TokenBasedSettings(membership: .group(id: "team", shownInBar: true)))),
        ]
        c.groups = [BudgetGroup(id: "team", name: "Team", budgetUSD: 100, thresholds: thresholds)]
        c.showsRunOutMarker = false
        return c.settingHeadline(claude, accountId: "sub")
    }

    static func items(_ c: Configuration, sub: SubscriptionEntry? = nil, own: GroupEntry? = nil, team: GroupEntry? = nil,
                      codex: CodexLimitsEntry? = nil) -> [String: BarItem] {
        var s = UsageSnapshot(generatedAt: F.now, window: F.window, windowSource: .fallback)
        s.subscriptions["sub"] = sub
        s.accountBudgets["own"] = own
        s.groups["team"] = team
        s.codexLimits["codex"] = codex
        let list = BarLayout.segments(snapshot: s, configuration: c)
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    /// US1 scenario 1: thresholds 80 and 90, the headline at 91% is
    /// critical without a real limit; 85% is warning, 79% normal.
    @Test func subscriptionCriticalAtTheSecondThreshold() {
        let c = Self.config([80, 90])
        let critical = Self.items(c, sub: F.sub(seven: 91))["sub"]
        #expect(critical?.level == .critical)
        #expect(critical?.overLimit == false)
        #expect(Self.items(c, sub: F.sub(seven: 85))["sub"]?.level == .warning)
        #expect(Self.items(c, sub: F.sub(seven: 79))["sub"]?.level == .normal)
        #expect(Self.items(c, sub: F.sub(seven: 85))["sub"]?.overLimit == false)
    }

    /// FR-003: the Claude 7-day window at 100% while the 5-hour window is
    /// the headline is a real limit.
    @Test func fullSevenDayWindowIsARealLimit() {
        let item = Self.items(Self.config([80, 90], claude: .claudeFiveHour), sub: F.sub(seven: 100, five: 40))["sub"]
        #expect(item?.value == "40%")
        #expect(item?.level == .critical)
        #expect(item?.overLimit == true)
    }

    /// FR-003: any reached Codex limit is a real limit.
    @Test func reachedCodexLimitIsARealLimit() {
        let item = Self.items(Self.config([80, 90]), codex: F.codex(five: 90, weekly: 40, fiveReached: true))["codex"]
        #expect(item?.level == .critical)
        #expect(item?.overLimit == true)
        let threshold = Self.items(Self.config([50, 55]), codex: F.codex(five: 10, weekly: 60))["codex"]
        #expect(threshold?.level == .critical)
        #expect(threshold?.overLimit == false)
    }

    /// US1 scenario 6: thresholds 80 and 120, a window at 100% is critical
    /// at a real limit; at 99% it is warning.
    @Test func hundredIsARealLimitAboveAHigherThreshold() {
        let c = Self.config([80, 120])
        let full = Self.items(c, sub: F.sub(seven: 100))["sub"]
        #expect(full?.level == .critical)
        #expect(full?.overLimit == true)
        #expect(Self.items(c, sub: F.sub(seven: 99))["sub"]?.level == .warning)
        let budget = Self.items(c, own: F.budget(110, members: ["own"]))["own"]
        #expect(budget?.level == .critical)
        #expect(budget?.overLimit == true)
    }

    /// US1 scenario 4: a budget with thresholds 50 and 75 is warning at
    /// 60% and critical at 80%, without a real limit.
    @Test func budgetLevelsFromItsThresholds() {
        let c = Self.config([50, 75])
        #expect(Self.items(c, own: F.budget(60, members: ["own"]))["own"]?.level == .warning)
        let critical = Self.items(c, own: F.budget(80, members: ["own"]))["own"]
        #expect(critical?.level == .critical)
        #expect(critical?.overLimit == false)
        #expect(Self.items(c, team: F.budget(80))["team"]?.level == .critical)
    }

    /// FR-004: a member keeps the group's thresholds, with the same rule.
    @Test func memberKeepsTheGroupsThresholds() throws {
        let c = Self.config([50, 75])
        let member = Self.items(c, team: F.budget(80))["team/m1"]
        #expect(member?.value == "80%")
        #expect(member?.level == .critical)
        #expect(member?.overLimit == false)
        #expect(Self.items(c, team: F.budget(60))["team/m1"]?.level == .warning)
        // A share at or above 100% is a real limit: "over limit", not
        // "critical", in the accessibility text.
        let full = try #require(Self.items(c, team: F.budget(110))["team/m1"])
        #expect(full.level == .critical)
        #expect(full.overLimit == true)
        let settings = LevelDisplaySettings(levelColor: .text, showSymbols: false)
        #expect(BarPresentation.entries([full], settings: settings).first?.accessibilityText == "\(full.name) over limit 110%")
        let critical = try #require(member)
        #expect(BarPresentation.entries([critical], settings: settings).first?.accessibilityText == "\(critical.name) critical 80%")
    }

    /// US1 scenario 5: without thresholds the levels are 80 and 100.
    @Test func noThresholdsKeepTheDefaults() {
        let c = Self.config([])
        #expect(Self.items(c, sub: F.sub(seven: 91))["sub"]?.level == .warning)
        #expect(Self.items(c, sub: F.sub(seven: 100))["sub"]?.level == .critical)
        #expect(Self.items(c, sub: F.sub(seven: 79))["sub"]?.level == .normal)
    }
}

/// spec 030 FR-009, FR-011, FR-013, FR-014: bar entries in direction
/// remaining. Uses the fixtures of `RunOutMarkerBarLayoutTests` and the
/// configuration of `ThresholdLevelBarLayoutTests`.
@Suite struct DirectionBarLayoutTests {
    typealias F = RunOutMarkerBarLayoutTests
    typealias T = ThresholdLevelBarLayoutTests

    static func config(_ direction: DisplayDirection, thresholds: [Int] = [80, 90]) -> Configuration {
        var c = T.config(thresholds)
        c.displayDirection = direction
        return c
    }

    @Test func valuesFlipInRemaining() {
        let items = T.items(Self.config(.remaining), sub: F.sub(seven: 70), own: F.budget(40, members: ["own"]), team: F.budget(40),
                            codex: F.codex(weekly: 60))
        #expect(items["sub"]?.value == "30%")
        #expect(items["sub"]?.accessibilityValue == "30% left")
        #expect(items["codex"]?.value == "40%")
        #expect(items["codex"]?.accessibilityValue == "40% left")
        #expect(items["own"]?.value == "60%")
        #expect(items["own"]?.accessibilityValue == "60% left")
        #expect(items["team"]?.value == "60%")
        // FR-013: a member's share is not a level value and never flips.
        #expect(items["team/m1"]?.value == "40%")
        #expect(items["team/m1"]?.accessibilityValue == "40%")
    }

    /// Direction used keeps today's values; the accessibility value is the
    /// value.
    @Test func usedKeepsTodaysValues() {
        let items = T.items(Self.config(.used), sub: F.sub(seven: 70), own: F.budget(40, members: ["own"]))
        #expect(items["sub"]?.value == "70%")
        #expect(items["sub"]?.accessibilityValue == "70%")
        #expect(items["own"]?.value == "40%")
    }

    /// "…" and "--" have nothing to flip; stale keeps "~" before the value.
    @Test func placeholdersAndStaleInRemaining() {
        let c = Self.config(.remaining)
        #expect(T.items(c)["sub"]?.value == "…")
        #expect(T.items(c, sub: SubscriptionEntry(status: nil, state: .notSignedIn))["sub"]?.value == "--")
        #expect(T.items(c, codex: CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline")))["codex"]?.value == "--")
        let stale = T.items(c, sub: F.sub(seven: 70, state: .stale(lastGoodAt: F.now, error: "offline")))["sub"]
        let entry = BarPresentation.entries([stale].compactMap { $0 }, settings: .default).first
        #expect(entry?.valueText == "~30%")
        #expect(entry?.accessibilityText == "Max ~30% left")
    }

    /// FR-014: the levels are the same in both directions.
    @Test func levelsAreTheSameInBothDirections() {
        for seven in [10.0, 79, 85, 91, 100, 104] {
            for budget in [Decimal(40), 60, 80, 100, 115] {
                let used = T.items(Self.config(.used), sub: F.sub(seven: seven), own: F.budget(budget, members: ["own"]),
                                   codex: F.codex(weekly: seven))
                let remaining = T.items(Self.config(.remaining), sub: F.sub(seven: seven), own: F.budget(budget, members: ["own"]),
                                        codex: F.codex(weekly: seven))
                for id in ["sub", "own", "codex"] {
                    #expect(used[id]?.level == remaining[id]?.level)
                    #expect(used[id]?.overLimit == remaining[id]?.overLimit)
                }
            }
        }
    }

    /// FR-011: the markers point down in remaining.
    @Test func markersFlipInRemaining() {
        var c = F.config()
        c.displayDirection = .remaining
        var s = UsageSnapshot(generatedAt: F.now, window: F.window, windowSource: .fallback)
        s.subscriptions["sub"] = F.sub(seven: 33)
        let slow = BarLayout.segments(snapshot: s, configuration: c).first { $0.id == "sub" }
        #expect(slow?.runOutMarker == true)
        #expect(slow?.runOutGlyph == "↘")
        s.subscriptions["sub"] = F.sub(seven: 50, five: 50)
        let fast = BarLayout.segments(snapshot: s, configuration: c).first { $0.id == "sub" }
        #expect(fast?.burnsFast == true)
        #expect(fast?.runOutGlyph == "↓")
        c.displayDirection = .used
        #expect(BarLayout.segments(snapshot: s, configuration: c).first { $0.id == "sub" }?.runOutGlyph == "↑")
        s.subscriptions["sub"] = F.sub(seven: 33)
        #expect(BarLayout.segments(snapshot: s, configuration: c).first { $0.id == "sub" }?.runOutGlyph == "↗")
    }

    /// The section header follows the direction like the bar entry.
    @Test func headerInRemaining() {
        let sub = F.sub(seven: 70)
        let headline = HeadlineWindow.claude(accountId: "sub", status: sub.status, choice: nil, now: F.now)
        let header = HeadlineWindow.claudeHeader(headline, entry: sub, thresholds: [80, 90], direction: .remaining, now: F.now)
        #expect(header?.value == "30%")
        #expect(header?.accessibilityValue == "30% left")
        let used = HeadlineWindow.claudeHeader(headline, entry: sub, thresholds: [80, 90], direction: .used, now: F.now)
        #expect(used?.value == "70%")
        #expect(used?.accessibilityValue == "70%")
        #expect(used?.level == header?.level)
        let codex = F.codex(weekly: 60)
        let codexHeadline = HeadlineWindow.codex(accountId: "codex", entry: codex, choice: nil, now: F.now)
        let codexHeader = HeadlineWindow.codexHeader(codexHeadline, entry: codex, thresholds: [], direction: .remaining, now: F.now)
        #expect(codexHeader?.value == "40%")
        #expect(codexHeader?.accessibilityValue == "40% left")
        // A chosen fixed window without values keeps "--".
        let noFive = SubscriptionEntry(status: SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 70, resetsAt: F.window.end),
                                                                  fetchedAt: F.now), state: .ok)
        let fiveHeadline = HeadlineWindow.claude(accountId: "sub", status: noFive.status, choice: .claudeFiveHour, now: F.now)
        #expect(HeadlineWindow.claudeHeader(fiveHeadline, entry: noFive, thresholds: [], direction: .remaining, now: F.now)?.value == "--")
    }
}

/// spec 030 US3, FR-012: values above 100% used in direction remaining read
/// negative with the typographic minus, at the critical level of a real
/// limit, and their words name how far over they are.
@Suite struct OverBudgetDirectionTests {
    typealias F = RunOutMarkerBarLayoutTests
    typealias T = ThresholdLevelBarLayoutTests

    static func config(_ direction: DisplayDirection) -> Configuration {
        var c = T.config([80, 100])
        c.displayDirection = direction
        if let index = c.accounts.firstIndex(where: { $0.id == "own" }) {
            c.accounts[index].displayName = "Side project"
        }
        return c
    }

    /// US3 scenario 1: a budget at 115% in remaining reads "−15%", critical
    /// at a real limit, and the full accessibility text names it over budget
    /// (FR-012; the doubled wording "over limit 15% over budget" is accepted).
    @Test func budgetAboveHundredInRemaining() throws {
        let item = try #require(T.items(Self.config(.remaining), own: F.budget(115, members: ["own"]))["own"])
        #expect(item.value == "\u{2212}15%")
        #expect(item.level == .critical)
        #expect(item.overLimit)
        #expect(item.accessibilityValue == "15% over budget")
        let entry = try #require(BarPresentation.entries([item], settings: .default).first)
        #expect(entry.accessibilityText == "Side project over limit 15% over budget")
        #expect(entry.textTone == .overLimit)
        let bar = RowBar.budget(F.budget(115, members: ["own"]), thresholds: [80, 100], direction: .remaining, reading: nil)
        #expect(bar.fill == 0)
        #expect(bar.tone == .overLimit)
    }

    /// A subscription window the provider reports above 100% reads "−4%"
    /// with "4% over the limit".
    @Test func windowAboveHundredInRemaining() throws {
        let item = try #require(T.items(Self.config(.remaining), sub: F.sub(seven: 104))["sub"])
        #expect(item.value == "\u{2212}4%")
        #expect(item.accessibilityValue == "4% over the limit")
        #expect(item.level == .critical)
        let row = RowText.window(name: "7-day", percent: 104, direction: .remaining, resetsAt: nil, observedWithReset: true,
                                 limitReached: false, bar: nil, times: RowTextTests.relative)
        #expect(row.accessibilityLabel == "7-day, 4% over the limit")
    }

    /// US3 scenario 3: in direction used the same values read as today.
    @Test func usedKeepsTodaysValuesAboveHundred() throws {
        let item = try #require(T.items(Self.config(.used), own: F.budget(115, members: ["own"]))["own"])
        #expect(item.value == "115%")
        #expect(item.accessibilityValue == "115%")
        let line = BudgetAmountLine.make(spent: 115, budget: 100, roundedPercent: 115, direction: .used)
        #expect(line.text(amount: { "$\($0)" }, budget: "$100", period: "week") == "$115 of $100/week")
        let remaining = BudgetAmountLine.make(spent: 115, budget: 100, roundedPercent: 115, direction: .remaining)
        #expect(remaining.text(amount: { "$\($0)" }, budget: "$100", period: "week") == "$15 over $100/week")
        #expect(RowBar.budget(F.budget(115, members: ["own"]), thresholds: [80, 100], direction: .used, reading: nil).fill == 1)
    }
}
