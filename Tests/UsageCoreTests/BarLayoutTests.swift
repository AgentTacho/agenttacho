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
        let stale = SubscriptionEntry(status: ok(90).status, state: .stale(lastGoodAt: window.start, error: "x"))
        #expect(subA(stale)?.stale == true)
        #expect(subA(stale)?.level == .warning)
        let staleNoData = SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "x"))
        #expect(subA(staleNoData)?.value == "--")
        #expect(subA(staleNoData)?.stale == false)
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
