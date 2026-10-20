import Foundation
import Testing
@testable import UsageCore

/// The budget row the screenshot capture crops (spec 024 FR-019, tasks
/// T026): the first budget owner at warning or critical, else the first.
@Suite struct ShotTargetTests {
    static let window = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 7 * 86_400)

    static func configuration() -> Configuration {
        Configuration(
            accounts: [
                Account(id: "acc-a", displayName: "A", kind: .tokenBased(TokenBasedSettings(groupId: "grp-1", provider: .openai))),
                Account(id: "acc-own", displayName: "Own", kind: .tokenBased(TokenBasedSettings(
                    membership: .ownBudget(BudgetSettings(budgetUSD: 10, thresholds: [80])), provider: .openai))),
            ],
            groups: [
                BudgetGroup(id: "grp-1", name: "One", budgetUSD: 100, thresholds: [80]),
                BudgetGroup(id: "grp-2", name: "Two", budgetUSD: 100, thresholds: [50]),
            ])
    }

    static func entry(_ percent: Int) -> GroupEntry {
        GroupEntry(spentUSD: Decimal(percent), budgetUSD: 100, percent: percent, incomplete: false, window: window,
                   breakdown: .empty, members: [])
    }

    static func snapshot(groups: [String: GroupEntry], accountBudgets: [String: GroupEntry] = [:]) -> UsageSnapshot {
        UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback, groups: groups, accountBudgets: accountBudgets)
    }

    @Test func firstOwnerAtWarningOrCritical() {
        let snapshot = Self.snapshot(groups: ["grp-1": Self.entry(20), "grp-2": Self.entry(60)], accountBudgets: ["acc-own": Self.entry(120)])
        let owner = BarLayout.shotBudgetOwner(snapshot: snapshot, configuration: Self.configuration())
        #expect(owner?.id == "grp-2")
        #expect(owner?.kind == .group)
    }

    @Test func ownBudgetCountsToo() {
        let snapshot = Self.snapshot(groups: ["grp-1": Self.entry(20), "grp-2": Self.entry(10)], accountBudgets: ["acc-own": Self.entry(120)])
        let owner = BarLayout.shotBudgetOwner(snapshot: snapshot, configuration: Self.configuration())
        #expect(owner?.id == "acc-own")
        #expect(owner?.kind == .account)
    }

    @Test func fallsBackToTheFirstOwner() {
        let snapshot = Self.snapshot(groups: ["grp-1": Self.entry(20), "grp-2": Self.entry(10)])
        #expect(BarLayout.shotBudgetOwner(snapshot: snapshot, configuration: Self.configuration())?.id == "grp-1")
        #expect(BarLayout.shotBudgetOwner(snapshot: nil, configuration: Self.configuration())?.id == "grp-1")
    }

    @Test func noneWithoutBudgets() {
        #expect(BarLayout.shotBudgetOwner(snapshot: nil, configuration: Configuration()) == nil)
    }
}

/// The Claude Max sections the `glance` and `same-provider` shots crop
/// (spec 031 FR-010a, research R2): the first two Claude subscription
/// accounts in arrangement order.
@Suite struct ShotClaudeAccountsTests {
    static func claude(_ id: String) -> Account {
        Account(id: id, displayName: id, kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.\(id)")))
    }

    static func codex(_ id: String) -> Account {
        Account(id: id, displayName: id, harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings()))
    }

    static func token(_ id: String, groupId: String? = nil) -> Account {
        let settings = groupId.map { TokenBasedSettings(groupId: $0, provider: .openai) }
            ?? TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 10, thresholds: [80])), provider: .openai)
        return Account(id: id, displayName: id, kind: .tokenBased(settings))
    }

    @Test func firstTwoInArrangementOrder() {
        let configuration = Configuration(
            accounts: [Self.claude("c1"), Self.claude("c2"), Self.claude("c3")],
            arrangement: Arrangement(entries: [EntryRef(kind: .account, id: "c3"), EntryRef(kind: .account, id: "c1")]))
        #expect(BarLayout.shotClaudeAccountIds(configuration: configuration) == ["c3", "c1"])
    }

    @Test func oneWhenOnlyOneExists() {
        let configuration = Configuration(accounts: [Self.codex("x"), Self.claude("c1")])
        #expect(BarLayout.shotClaudeAccountIds(configuration: configuration) == ["c1"])
    }

    @Test func emptyWithoutClaudeSubscriptions() {
        #expect(BarLayout.shotClaudeAccountIds(configuration: Configuration()) == [])
        let configuration = Configuration(accounts: [Self.codex("x"), Self.token("t")])
        #expect(BarLayout.shotClaudeAccountIds(configuration: configuration) == [])
    }

    @Test func ignoresCodexAndTokenAccounts() {
        let configuration = Configuration(
            accounts: [Self.codex("x"), Self.token("t"), Self.claude("c1"), Self.token("m", groupId: "g"), Self.claude("c2")],
            groups: [BudgetGroup(id: "g", name: "G", budgetUSD: 100, thresholds: [80])])
        #expect(BarLayout.shotClaudeAccountIds(configuration: configuration) == ["c1", "c2"])
    }

    @Test func keepsOrderAcrossAGroupOrCodexBetween() {
        let configuration = Configuration(
            accounts: [Self.claude("c1"), Self.codex("x"), Self.claude("c2"), Self.token("m", groupId: "g")],
            groups: [BudgetGroup(id: "g", name: "G", budgetUSD: 100, thresholds: [80])],
            arrangement: Arrangement(entries: [
                EntryRef(kind: .account, id: "c2"), EntryRef(kind: .group, id: "g"),
                EntryRef(kind: .account, id: "x"), EntryRef(kind: .account, id: "c1"),
            ]))
        #expect(BarLayout.shotClaudeAccountIds(configuration: configuration) == ["c2", "c1"])
    }
}
