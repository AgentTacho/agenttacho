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

/// spec 006 FR-017: no bar entry for Codex subscription accounts.
@Suite struct CodexPlanBarLayoutTests {
    @Test func codexSubscriptionNeverYieldsABarItem() {
        let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
        let configuration = Configuration(accounts: [
            Account(id: "acc-codex", displayName: "ChatGPT", kind: .codexSubscription(CodexSubscriptionSettings())),
        ])
        var snapshot = UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback)
        snapshot.planAccounts["acc-codex"] = TokenAccountEntry()
        #expect(BarLayout.segments(snapshot: snapshot, configuration: configuration).isEmpty)
        #expect(BarLayout.segments(snapshot: nil, configuration: configuration).isEmpty)
    }
}
