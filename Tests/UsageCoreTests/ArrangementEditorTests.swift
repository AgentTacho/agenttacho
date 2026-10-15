import Foundation
import Testing
@testable import UsageCore

/// Spec 008 FR-009, FR-010, FR-010a and research R4: the flat rows of the
/// Menu Bar tab, drag moves in `onMove` coordinates, and Move Up/Move Down.
@Suite struct ArrangementEditorTests {
    /// Arranged as: a (subscription), g (members m1, m2, m3), b (own
    /// budget), h (member n1). Rows:
    /// 0 a, 1 g, 2 m1, 3 m2, 4 m3, 5 b, 6 h, 7 n1.
    static func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "a", displayName: "Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "m1", displayName: "Member one", kind: .tokenBased(TokenBasedSettings(groupId: "g"))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "g"))),
            Account(id: "b", displayName: "Own", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
            Account(id: "m3", displayName: "Member three", kind: .tokenBased(TokenBasedSettings(groupId: "g"))),
            Account(id: "n1", displayName: "Only member", kind: .tokenBased(TokenBasedSettings(groupId: "h"))),
        ]
        c.groups = [BudgetGroup(id: "g", name: "Vertex", budgetUSD: 10), BudgetGroup(id: "h", name: "Other", budgetUSD: 10)]
        c.arrangement = Arrangement(entries: [EntryRef(kind: .account, id: "a"), EntryRef(kind: .group, id: "g"),
                                              EntryRef(kind: .account, id: "b"), EntryRef(kind: .group, id: "h")])
        return c
    }

    static let a = ArrangementRow.entry(EntryRef(kind: .account, id: "a"))
    static let g = ArrangementRow.entry(EntryRef(kind: .group, id: "g"))
    static let b = ArrangementRow.entry(EntryRef(kind: .account, id: "b"))
    static let h = ArrangementRow.entry(EntryRef(kind: .group, id: "h"))
    static let m1 = ArrangementRow.member(groupId: "g", accountId: "m1")
    static let m2 = ArrangementRow.member(groupId: "g", accountId: "m2")
    static let m3 = ArrangementRow.member(groupId: "g", accountId: "m3")
    static let n1 = ArrangementRow.member(groupId: "h", accountId: "n1")

    static func entries(_ arrangement: Arrangement?) -> [String]? { arrangement?.entries.map(\.id) }

    static func move(_ source: Int, _ destination: Int) -> Arrangement? {
        ArrangementEditor.move(config(), from: IndexSet(integer: source), to: destination)
    }

    @Test func rowsListEntriesWithTheirMembers() {
        #expect(ArrangementEditor.rows(Self.config()) == [Self.a, Self.g, Self.m1, Self.m2, Self.m3, Self.b, Self.h, Self.n1])
        #expect(Self.m1.id == "member:m1")
        #expect(Self.g.id == "group:g")
        #expect(Self.a.id == "account:a")
    }

    /// Every returned arrangement is complete: all entries, all members.
    @Test func movedEntryReturnsTheFullArrangement() {
        let moved = Self.move(0, 5)
        #expect(Self.entries(moved) == ["g", "a", "b", "h"])
        #expect(moved?.members == ["g": ["m1", "m2", "m3"], "h": ["n1"]])
    }

    @Test func entryMoves() {
        #expect(Self.entries(Self.move(0, 8)) == ["g", "b", "h", "a"])
        #expect(Self.entries(Self.move(0, 6)) == ["g", "b", "a", "h"])
        #expect(Self.entries(Self.move(5, 0)) == ["b", "a", "g", "h"])
        #expect(Self.entries(Self.move(5, 1)) == ["a", "b", "g", "h"])
        #expect(Self.entries(Self.move(6, 0)) == ["h", "a", "g", "b"])
    }

    /// A group's member rows move along with it.
    @Test func groupMovesWithItsMembers() {
        let up = Self.move(1, 0)
        #expect(Self.entries(up) == ["g", "a", "b", "h"])
        #expect(up?.members["g"] == ["m1", "m2", "m3"])
        #expect(Self.entries(Self.move(1, 6)) == ["a", "b", "g", "h"])
        #expect(Self.entries(Self.move(1, 8)) == ["a", "b", "h", "g"])
        let config = Self.config()
        var applied = config
        applied.arrangement = Self.move(1, 8)
        #expect(ArrangementEditor.rows(applied) == [Self.a, Self.b, Self.h, Self.n1, Self.g, Self.m1, Self.m2, Self.m3])
    }

    @Test func memberMovesWithinItsGroup() {
        #expect(Self.move(2, 4)?.members["g"] == ["m2", "m1", "m3"])
        #expect(Self.move(2, 5)?.members["g"] == ["m2", "m3", "m1"])
        #expect(Self.move(4, 2)?.members["g"] == ["m3", "m1", "m2"])
        #expect(Self.move(4, 3)?.members["g"] == ["m1", "m3", "m2"])
        #expect(Self.entries(Self.move(4, 2)) == ["a", "g", "b", "h"])
    }

    /// FR-010: a member never leaves its group, an entry never enters a
    /// member block.
    @Test func dropsAcrossLevelsAreRejected() {
        for destination in [0, 1, 6, 7, 8] {
            #expect(Self.move(2, destination) == nil)   // m1 out of g
        }
        #expect(Self.move(7, 0) == nil)                 // n1 out of h
        #expect(Self.move(7, 5) == nil)                 // n1 into g
        for destination in [2, 3, 4, 7] {
            #expect(Self.move(0, destination) == nil)   // a into a member block
        }
        #expect(Self.move(5, 2) == nil)                 // b at the start of g's members
    }

    /// Research R4: destinations that leave everything in place return nil.
    @Test func noOpDestinationsReturnNil() {
        #expect(Self.move(0, 0) == nil)
        #expect(Self.move(0, 1) == nil)
        for destination in 1...5 {
            #expect(Self.move(1, destination) == nil)   // inside the moved group block
        }
        #expect(Self.move(6, 6) == nil)
        #expect(Self.move(6, 7) == nil)
        #expect(Self.move(6, 8) == nil)
        #expect(Self.move(2, 2) == nil)
        #expect(Self.move(2, 3) == nil)
        #expect(Self.move(7, 7) == nil)                 // a group's only member
        #expect(Self.move(7, 8) == nil)
    }

    @Test func invalidSourcesReturnNil() {
        #expect(ArrangementEditor.move(Self.config(), from: IndexSet([0, 5]), to: 8) == nil)
        #expect(ArrangementEditor.move(Self.config(), from: IndexSet(), to: 8) == nil)
        #expect(ArrangementEditor.move(Self.config(), from: IndexSet(integer: 9), to: 0) == nil)
        #expect(ArrangementEditor.move(Self.config(), from: IndexSet(integer: 0), to: 9) == nil)
    }

    /// FR-010a: one position within the row's level.
    @Test func moveUpAndDown() {
        let c = Self.config()
        let groupUp = ArrangementEditor.moveUp(c, row: Self.g)
        #expect(Self.entries(groupUp) == ["g", "a", "b", "h"])
        #expect(groupUp?.members["g"] == ["m1", "m2", "m3"])
        #expect(Self.entries(ArrangementEditor.moveDown(c, row: Self.g)) == ["a", "b", "g", "h"])
        #expect(Self.entries(ArrangementEditor.moveDown(c, row: Self.a)) == ["g", "a", "b", "h"])
        #expect(ArrangementEditor.moveUp(c, row: Self.a) == nil)
        #expect(ArrangementEditor.moveDown(c, row: Self.h) == nil)
        #expect(ArrangementEditor.moveUp(c, row: Self.m2)?.members["g"] == ["m2", "m1", "m3"])
        #expect(ArrangementEditor.moveDown(c, row: Self.m2)?.members["g"] == ["m1", "m3", "m2"])
        #expect(ArrangementEditor.moveUp(c, row: Self.m1) == nil)
        #expect(ArrangementEditor.moveDown(c, row: Self.m3) == nil)
        #expect(ArrangementEditor.moveUp(c, row: Self.n1) == nil)
        #expect(ArrangementEditor.moveDown(c, row: Self.n1) == nil)
        #expect(ArrangementEditor.moveUp(c, row: .entry(EntryRef(kind: .group, id: "gone"))) == nil)
    }

    @Test func canMoveUpAndDown() {
        let c = Self.config()
        #expect(!ArrangementEditor.canMoveUp(c, row: nil))
        #expect(!ArrangementEditor.canMoveDown(c, row: nil))
        #expect(!ArrangementEditor.canMoveUp(c, row: Self.a))
        #expect(ArrangementEditor.canMoveDown(c, row: Self.a))
        #expect(ArrangementEditor.canMoveUp(c, row: Self.h))
        #expect(!ArrangementEditor.canMoveDown(c, row: Self.h))
        #expect(!ArrangementEditor.canMoveUp(c, row: Self.m1))
        #expect(ArrangementEditor.canMoveDown(c, row: Self.m1))
        #expect(ArrangementEditor.canMoveUp(c, row: Self.m3))
        #expect(!ArrangementEditor.canMoveDown(c, row: Self.m3))
        #expect(!ArrangementEditor.canMoveUp(c, row: Self.n1))
        #expect(!ArrangementEditor.canMoveDown(c, row: Self.n1))
        #expect(!ArrangementEditor.canMoveUp(c, row: .member(groupId: "g", accountId: "gone")))
    }

    /// Research R1: row ids stay unique when a group and an account share an id.
    @Test func rowIdsAreUniqueForSharedIds() {
        var c = Configuration()
        c.accounts = [
            Account(id: "x", displayName: "Own x", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
            Account(id: "m", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
        ]
        c.groups = [BudgetGroup(id: "x", name: "Group x", budgetUSD: 10)]
        let rows = ArrangementEditor.rows(c)
        #expect(rows.map(\.id) == ["account:x", "group:x", "member:m"])
        #expect(ArrangementEditor.move(c, from: IndexSet(integer: 1), to: 0)?.entries
                == [EntryRef(kind: .group, id: "x"), EntryRef(kind: .account, id: "x")])
    }

    /// Ids joined from a group id and an account id cannot collide: group
    /// "a/b" with member "c" and group "a" with member "b/c".
    @Test func memberRowIdsDoNotCollideForIdsWithSeparators() {
        var c = Configuration()
        c.accounts = [
            Account(id: "c", displayName: "c", kind: .tokenBased(TokenBasedSettings(groupId: "a/b"))),
            Account(id: "b/c", displayName: "b/c", kind: .tokenBased(TokenBasedSettings(groupId: "a"))),
        ]
        c.groups = [BudgetGroup(id: "a/b", name: "a/b", budgetUSD: 1), BudgetGroup(id: "a", name: "a", budgetUSD: 1)]
        let ids = ArrangementEditor.rows(c).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// US1 scenario 5: with a group and an account sharing an id among other
    /// entries, a drag or a Move command acts on the named kind only.
    /// Rows: 0 sub, 1 account:x, 2 group:x, 3 m, 4 m2.
    @Test func sharedIdMovesActOnTheNamedKindOnly() {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub", displayName: "Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "x", displayName: "Own x", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
            Account(id: "m", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
        ]
        c.groups = [BudgetGroup(id: "x", name: "Group x", budgetUSD: 10)]
        let account = EntryRef(kind: .account, id: "x")
        let group = EntryRef(kind: .group, id: "x")
        let sub = EntryRef(kind: .account, id: "sub")
        #expect(ArrangementEditor.rows(c).map(\.id) == ["account:sub", "account:x", "group:x", "member:m", "member:m2"])

        #expect(ArrangementEditor.move(c, from: IndexSet(integer: 1), to: 0)?.entries == [account, sub, group])
        #expect(ArrangementEditor.move(c, from: IndexSet(integer: 2), to: 0)?.entries == [group, sub, account])
        #expect(ArrangementEditor.moveUp(c, row: .entry(account))?.entries == [account, sub, group])
        #expect(ArrangementEditor.moveUp(c, row: .entry(group))?.entries == [sub, group, account])
        #expect(ArrangementEditor.moveDown(c, row: .entry(account))?.entries == [sub, group, account])
        #expect(ArrangementEditor.moveDown(c, row: .entry(group)) == nil)

        // A member leaving group x for its own budget follows the group,
        // not the account that shares its id (FR-006).
        var previous = c
        previous.arrangement = Arrangement(entries: [group, sub, account])
        let result = previous.movingAccountToOwnBudget(accountId: "m").reconcilingArrangement(previous: previous)
        #expect(result.arrangedEntries.map(\.ref) == [group, EntryRef(kind: .account, id: "m"), sub, account])
    }
}

/// Spec 008 FR-012, research R6: the "Show in bar" checkbox of a row
/// changes the same setting as the editor toggles.
@Suite struct ShownInBarTests {
    /// sub (subscription), codex (Codex plan), x (own budget), m (member of
    /// group x, which shares its id with the account x).
    static func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub", displayName: "Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "codex", displayName: "ChatGPT", harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings())),
            Account(id: "x", displayName: "Own x", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
            Account(id: "m", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
        ]
        c.groups = [BudgetGroup(id: "x", name: "Group x", budgetUSD: 10)]
        c.arrangement = Arrangement(entries: [EntryRef(kind: .group, id: "x"), EntryRef(kind: .account, id: "sub")])
        return c
    }

    static let sub = ArrangementRow.entry(EntryRef(kind: .account, id: "sub"))
    static let codex = ArrangementRow.entry(EntryRef(kind: .account, id: "codex"))
    static let own = ArrangementRow.entry(EntryRef(kind: .account, id: "x"))
    static let group = ArrangementRow.entry(EntryRef(kind: .group, id: "x"))
    static let member = ArrangementRow.member(groupId: "x", accountId: "m")

    @Test func readsTheExistingSettings() {
        let c = Self.config()
        #expect(c.isShownInBar(Self.sub))
        #expect(c.isShownInBar(Self.codex))
        #expect(c.isShownInBar(Self.own))
        #expect(c.isShownInBar(Self.group))
        #expect(!c.isShownInBar(Self.member))   // a member's share starts hidden
        #expect(!c.isShownInBar(.entry(EntryRef(kind: .account, id: "gone"))))
    }

    @Test func writesTheSameSettingAsTheEditors() {
        let c = Self.config()
        #expect(c.settingShownInBar(Self.sub, false).account(id: "sub")?.kind.subscription?.shownInBar == false)
        #expect(c.settingShownInBar(Self.codex, false).account(id: "codex")?.kind.codexSubscription?.shownInBar == false)
        #expect(c.settingShownInBar(Self.own, false).account(id: "x")?.kind.tokenBased?.ownBudget?.shownInBar == false)
        #expect(c.settingShownInBar(Self.group, false).group(id: "x")?.shownInBar == false)
        let member = c.settingShownInBar(Self.member, true)
        #expect(member.account(id: "m")?.kind.tokenBased?.membership == .group(id: "x", shownInBar: true))
        #expect(member.isShownInBar(Self.member))
        // The getter reads the hidden state too, for every kind (FR-012).
        for row in [Self.sub, Self.codex, Self.own, Self.group] {
            #expect(!c.settingShownInBar(row, false).isShownInBar(row))
        }
        #expect(!member.settingShownInBar(Self.member, false).isShownInBar(Self.member))
    }

    /// A setting changed in an editor shows in the checkbox (US3 scenario 2).
    @Test func readsAHiddenSettingFromTheEditors() {
        var c = Self.config()
        c.accounts[0].kind = .subscription(SubscriptionSettings(shownInBar: false))
        c.accounts[1].kind = .codexSubscription(CodexSubscriptionSettings(shownInBar: false))
        #expect(!c.isShownInBar(Self.sub))
        #expect(!c.isShownInBar(Self.codex))
    }

    /// A group and an account sharing an id are toggled independently, and
    /// toggling never touches the order.
    @Test func togglesAreIndependentAndKeepTheOrder() {
        let c = Self.config()
        let groupOff = c.settingShownInBar(Self.group, false)
        #expect(!groupOff.isShownInBar(Self.group))
        #expect(groupOff.isShownInBar(Self.own))
        let ownOff = c.settingShownInBar(Self.own, false)
        #expect(!ownOff.isShownInBar(Self.own))
        #expect(ownOff.isShownInBar(Self.group))
        for row in [Self.sub, Self.codex, Self.own, Self.group, Self.member] {
            #expect(c.settingShownInBar(row, !c.isShownInBar(row)).arrangement == c.arrangement)
        }
        #expect(c.settingShownInBar(.entry(EntryRef(kind: .group, id: "gone")), false) == c)
    }
}
