import Foundation
import Testing
@testable import UsageCore

/// Spec 008 FR-004, FR-004a, FR-005 to FR-008 and research R3: placement
/// rules applied when Settings applies a change.
@Suite struct ArrangementReconcileTests {
    /// Accounts list: a (subscription), m1 (g), m2 (g), b (own budget),
    /// n1 (h). Groups list: g, h. Default order: a, b, g, h.
    static func config(arrangement: Arrangement? = nil) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "a", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.a"))),
            Account(id: "m1", displayName: "Member one", kind: .tokenBased(TokenBasedSettings(groupId: "g"))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "g"))),
            Account(id: "b", displayName: "Own", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
            Account(id: "n1", displayName: "Only member", kind: .tokenBased(TokenBasedSettings(groupId: "h"))),
        ]
        c.groups = [BudgetGroup(id: "g", name: "Vertex", budgetUSD: 10), BudgetGroup(id: "h", name: "Other", budgetUSD: 10)]
        c.arrangement = arrangement
        return c
    }

    static func ref(_ value: String) -> EntryRef {
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        return EntryRef(kind: parts[0] == "g" ? .group : .account, id: parts[1])
    }

    /// `"a:<id>"` for an account, `"g:<id>"` for a group.
    static func arrangement(_ entries: [String], members: [String: [String]] = [:]) -> Arrangement {
        Arrangement(entries: entries.map(ref), members: members)
    }

    static func order(_ c: Configuration) -> [String] {
        c.arrangedEntries.map { ($0.ref.kind == .group ? "g:" : "a:") + $0.ref.id }
    }

    static func members(_ c: Configuration, _ groupId: String) -> [String]? {
        c.arrangedEntries.lazy.compactMap { entry -> [String]? in
            if case .group(let group, let members) = entry, group.id == groupId { return members.map(\.id) }
            return nil
        }.first
    }

    static func newSubscription(_ id: String) -> Account {
        Account(id: id, displayName: id, kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.\(id)")))
    }

    /// FR-004: a change that does not affect the order stores nothing.
    @Test func unrelatedChangeKeepsNothingStored() {
        let previous = Self.config()
        var next = previous
        next.refreshIntervalSeconds = 600
        next.accounts[0].icon = "solid:robot"
        next.groups[0].shownInBar = false
        let result = next.reconcilingArrangement(previous: previous)
        #expect(result == next)
        #expect(result.arrangement == nil)
    }

    /// FR-004a, FR-005: the new entry goes last, so the order is stored.
    @Test func newEntryGoesLastAndIsStored() {
        let previous = Self.config()
        var next = previous
        next.accounts.append(Self.newSubscription("c"))
        let result = next.reconcilingArrangement(previous: previous)
        #expect(result.arrangement != nil)
        #expect(Self.order(result) == ["a:a", "a:b", "g:g", "g:h", "a:c"])
        #expect(Self.order(next) == ["a:a", "a:b", "a:c", "g:g", "g:h"])   // the default would differ
    }

    /// FR-004: an addition that lands last in default order anyway needs no
    /// stored order.
    @Test func additionMatchingTheDefaultKeepsNothingStored() {
        let previous = Self.config()
        var next = previous
        next.accounts.append(Account(id: "k1", displayName: "k1", kind: .tokenBased(TokenBasedSettings(groupId: "k"))))
        next.groups.append(BudgetGroup(id: "k", name: "New group", budgetUSD: 1))
        let result = next.reconcilingArrangement(previous: previous)
        #expect(result.arrangement == nil)
        #expect(Self.order(result) == ["a:a", "a:b", "g:g", "g:h", "g:k"])
    }

    /// FR-005: a new member is last in its group.
    @Test func newMemberGoesLastInItsGroup() {
        let previous = Self.config()
        var next = previous
        next.accounts.insert(Account(id: "m0", displayName: "m0", kind: .tokenBased(TokenBasedSettings(groupId: "g"))), at: 1)
        let result = next.reconcilingArrangement(previous: previous)
        #expect(Self.members(result, "g") == ["m1", "m2", "m0"])
        #expect(result.arrangement != nil)
    }

    /// FR-006: an account leaving its group for its own budget follows the group.
    @Test func ownBudgetFollowsItsFormerGroup() {
        let previous = Self.config()
        let next = previous.movingAccountToOwnBudget(accountId: "m1")
        let result = next.reconcilingArrangement(previous: previous)
        #expect(Self.order(result) == ["a:a", "a:b", "g:g", "a:m1", "g:h"])
        #expect(Self.members(result, "g") == ["m2"])
        #expect(result.arrangement != nil)
    }

    /// FR-006: when the former group is deleted, the account takes its place.
    @Test func ownBudgetTakesThePlaceOfAPrunedGroup() {
        let previous = Self.config(arrangement: Self.arrangement(["g:h", "a:a", "a:b", "g:g"]))
        let next = previous.movingAccountToOwnBudget(accountId: "n1").pruningEmptyGroups()
        #expect(next.group(id: "h") == nil)
        let result = next.reconcilingArrangement(previous: previous)
        #expect(Self.order(result) == ["a:n1", "a:a", "a:b", "g:g"])

        let unstored = Self.config()
        let moved = unstored.movingAccountToOwnBudget(accountId: "n1").reconcilingArrangement(previous: unstored)
        #expect(Self.order(moved) == ["a:a", "a:b", "g:g", "a:n1"])
    }

    /// FR-007: own budget to group, and group to group, land last in the
    /// new group; the rest keeps its order.
    @Test func joiningAGroupGoesLast() {
        let previous = Self.config(arrangement: Self.arrangement(["a:b", "g:h", "a:a", "g:g"], members: ["g": ["m2", "m1"]]))
        let ownToGroup = previous.movingAccountToGroup(accountId: "b", groupId: "g").reconcilingArrangement(previous: previous)
        #expect(Self.order(ownToGroup) == ["g:h", "a:a", "g:g"])
        #expect(Self.members(ownToGroup, "g") == ["m2", "m1", "b"])

        let groupToGroup = previous.movingAccountToGroup(accountId: "m2", groupId: "h").reconcilingArrangement(previous: previous)
        #expect(Self.order(groupToGroup) == ["a:b", "g:h", "a:a", "g:g"])
        #expect(Self.members(groupToGroup, "h") == ["n1", "m2"])
        #expect(Self.members(groupToGroup, "g") == ["m1"])

        // Nothing stored before: the new member still goes last.
        let unstored = Self.config()
        let moved = unstored.movingAccountToGroup(accountId: "m1", groupId: "h").reconcilingArrangement(previous: unstored)
        #expect(Self.members(moved, "h") == ["n1", "m1"])
        #expect(moved.arrangement != nil)
    }

    /// FR-008: removals keep the relative order of the rest.
    @Test func removalKeepsTheRelativeOrder() {
        let previous = Self.config(arrangement: Self.arrangement(["g:h", "a:b", "g:g", "a:a"], members: ["g": ["m2", "m1"]]))
        let account = previous.removingAccount(id: "b").reconcilingArrangement(previous: previous)
        #expect(Self.order(account) == ["g:h", "g:g", "a:a"])
        let member = previous.removingAccount(id: "m2").reconcilingArrangement(previous: previous)
        #expect(Self.members(member, "g") == ["m1"])
        let group = previous.removingAccount(id: "n1").reconcilingArrangement(previous: previous)
        #expect(Self.order(group) == ["a:b", "g:g", "a:a"])
        #expect(group.arrangement?.entries.contains(Self.ref("g:h")) == false)
    }

    /// A reorder from the Menu Bar tab is stored, with the placement rules
    /// on top when a structural change lands in the same apply (FR-006).
    @Test func reorderIsStoredWithPlacementRulesOnTop() {
        let previous = Self.config()
        var reordered = previous
        reordered.arrangement = Self.arrangement(["a:b", "a:a", "g:g", "g:h"], members: ["g": ["m2", "m1"], "h": ["n1"]])
        let plain = reordered.reconcilingArrangement(previous: previous)
        #expect(plain.arrangement == reordered.arrangement)

        let combined = reordered.movingAccountToOwnBudget(accountId: "m1").reconcilingArrangement(previous: previous)
        #expect(Self.order(combined) == ["a:b", "a:a", "g:g", "a:m1", "g:h"])
        #expect(Self.members(combined, "g") == ["m2"])
    }

    /// FR-004a: a reorder that ends at the default order (Move Up, then Move
    /// Down within one debounce) stores nothing while nothing was stored;
    /// with an order stored before, the result stays stored.
    @Test func reorderBackToTheDefaultKeepsNothingStored() {
        let unstored = Self.config()
        var reordered = unstored
        reordered.arrangement = unstored.defaultArrangement
        let result = reordered.reconcilingArrangement(previous: unstored)
        #expect(result.arrangement == nil)
        #expect(result == unstored)

        let stored = Self.config(arrangement: Self.arrangement(["a:b", "a:a", "g:g", "g:h"]))
        var back = stored
        back.arrangement = stored.defaultArrangement
        #expect(back.reconcilingArrangement(previous: stored).arrangement == stored.defaultArrangement)
    }

    /// FR-014: an undo back to no stored order, followed by another edit in
    /// the same debounce, keeps the default order instead of bringing the
    /// undone reorder back.
    @Test func undoneReorderDoesNotReturnWithALaterEdit() {
        let applied = Self.config(arrangement: Self.arrangement(["g:h", "a:b", "g:g", "a:a"]))
        var next = Self.config()
        next.refreshIntervalSeconds = 600
        let result = next.reconcilingArrangement(previous: applied)
        #expect(Self.order(result) == ["a:a", "a:b", "g:g", "g:h"])
        #expect(result.refreshIntervalSeconds == 600)
    }

    /// FR-005 to FR-008 keep a stored order stored.
    @Test func storedOrderStaysStored() {
        let previous = Self.config(arrangement: Self.arrangement(["g:h", "a:a", "g:g", "a:b"]))
        var next = previous
        next.accounts.append(Self.newSubscription("c"))
        let result = next.reconcilingArrangement(previous: previous)
        #expect(Self.order(result) == ["g:h", "a:a", "g:g", "a:b", "a:c"])
        #expect(result.arrangement?.entries.count == 5)
    }

    /// Two accounts leaving the same group follow it in accounts-list order.
    @Test func severalAccountsLeavingAGroup() {
        var previous = Self.config(arrangement: Self.arrangement(["a:a", "g:g", "a:b", "g:h"], members: ["g": ["m3", "m2", "m1"]]))
        previous.accounts.append(Account(id: "m3", displayName: "m3", kind: .tokenBased(TokenBasedSettings(groupId: "g"))))
        let next = previous.movingAccountToOwnBudget(accountId: "m3").movingAccountToOwnBudget(accountId: "m1")
        let result = next.reconcilingArrangement(previous: previous)
        #expect(Self.order(result) == ["a:a", "g:g", "a:m1", "a:m3", "a:b", "g:h"])
        #expect(Self.members(result, "g") == ["m2"])
    }

    /// Research R3 step 2.2: a reorder base that already holds the moved
    /// account, with its group pruned, places it at the anchor exactly once.
    @Test func reorderBaseWithMovedAccountAndPrunedGroup() {
        let previous = Self.config(arrangement: Self.arrangement(["a:a", "g:h", "a:b", "g:g"]))
        var next = previous.movingAccountToOwnBudget(accountId: "n1").pruningEmptyGroups()
        next.arrangement = Self.arrangement(["a:b", "a:n1", "a:a", "g:g"])
        let result = next.reconcilingArrangement(previous: previous)
        #expect(Self.order(result) == ["a:b", "a:a", "a:n1", "g:g"])
        #expect(result.arrangement?.entries.filter { $0.id == "n1" }.count == 1)
    }

    /// FR-007, FR-008: the members left in a group keep their stored order,
    /// which differs from the accounts-list order here.
    @Test func remainingMembersKeepTheirStoredOrder() {
        var previous = Self.config(arrangement: Self.arrangement(["a:a", "a:b", "g:g", "g:h"], members: ["g": ["m3", "m2", "m1"]]))
        previous.accounts.append(Account(id: "m3", displayName: "m3", kind: .tokenBased(TokenBasedSettings(groupId: "g"))))
        #expect(Self.members(previous, "g") == ["m3", "m2", "m1"])

        let removed = previous.removingAccount(id: "m2").reconcilingArrangement(previous: previous)
        #expect(Self.members(removed, "g") == ["m3", "m1"])

        let moved = previous.movingAccountToGroup(accountId: "m2", groupId: "h").reconcilingArrangement(previous: previous)
        #expect(Self.members(moved, "g") == ["m3", "m1"])
        #expect(Self.members(moved, "h") == ["n1", "m2"])
    }

    /// FR-005: every kind of new entry goes last, also where the default
    /// order would put it elsewhere.
    @Test func everyKindOfNewEntryGoesLast() {
        let unstored = Self.config()
        let newEntries: [Account] = [
            Self.newSubscription("c"),
            Account(id: "cx", displayName: "cx", harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings())),
            Account(id: "o", displayName: "o", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
        ]
        for account in newEntries {
            var next = unstored
            next.accounts.append(account)
            let result = next.reconcilingArrangement(previous: unstored)
            #expect(Self.order(result).last == "a:\(account.id)")
            #expect(result.arrangement != nil)
        }

        let stored = Self.config(arrangement: Self.arrangement(["g:h", "a:a", "g:g", "a:b"]))
        var withGroup = stored
        withGroup.groups.append(BudgetGroup(id: "k", name: "New group", budgetUSD: 1))
        withGroup.accounts.append(Account(id: "k1", displayName: "k1", kind: .tokenBased(TokenBasedSettings(groupId: "k"))))
        #expect(Self.order(withGroup.reconcilingArrangement(previous: stored)) == ["g:h", "a:a", "g:g", "a:b", "g:k"])
    }

    /// FR-014: an edit made right after an undo is judged against the
    /// restored state, not against the undone one. Undone change: b moved
    /// from its own budget into g.
    @Test func editAfterUndoKeepsTheRestoredOrder() {
        let restored = Self.config(arrangement: Self.arrangement(["a:b", "a:a", "g:g", "g:h"]))
        let undone = restored.movingAccountToGroup(accountId: "b", groupId: "g").reconcilingArrangement(previous: restored)
        #expect(Self.order(undone) == ["a:a", "g:g", "g:h"])

        // Applied again unchanged: the undo target passes through.
        #expect(restored.settingsCandidate(applied: undone, undoTarget: restored) == restored)

        // Another edit inside the same debounce keeps the restored order.
        var edited = restored
        edited.refreshIntervalSeconds = 600
        let candidate = edited.settingsCandidate(applied: undone, undoTarget: restored)
        #expect(Self.order(candidate) == ["a:b", "a:a", "g:g", "g:h"])
        #expect(candidate.refreshIntervalSeconds == 600)

        // A structural edit after the undo follows the placement rules
        // against the restored state.
        let removed = restored.removingAccount(id: "a").settingsCandidate(applied: undone, undoTarget: restored)
        #expect(Self.order(removed) == ["a:b", "g:g", "g:h"])

        // Without an undo the last applied configuration is the baseline.
        var plain = undone
        plain.refreshIntervalSeconds = 600
        #expect(Self.order(plain.settingsCandidate(applied: undone, undoTarget: nil)) == ["a:a", "g:g", "g:h"])
    }

    /// Settings prunes groups left without members before the placement
    /// rules run (spec 004 FR-014, FR-006 of this spec).
    @Test func settingsCandidatePrunesEmptyGroups() {
        let applied = Self.config(arrangement: Self.arrangement(["g:h", "a:a", "a:b", "g:g"]))
        let draft = applied.movingAccountToOwnBudget(accountId: "n1")
        let candidate = draft.settingsCandidate(applied: applied, undoTarget: nil)
        #expect(candidate.group(id: "h") == nil)
        #expect(Self.order(candidate) == ["a:n1", "a:a", "a:b", "g:g"])
    }

    /// Research R3 step 0: nothing changed, nothing rewritten, not even a
    /// hand-edited stale order.
    @Test func reconcilingAgainstItselfIsANoOp() {
        let unstored = Self.config()
        #expect(unstored.reconcilingArrangement(previous: unstored) == unstored)
        let stale = Self.config(arrangement: Arrangement(entries: [Self.ref("g:gone"), Self.ref("a:m1"), Self.ref("g:h")],
                                                         members: ["g": ["ghost"]]))
        #expect(stale.reconcilingArrangement(previous: stale) == stale)
        var renamed = stale
        renamed.groups[0].name = "Renamed"
        #expect(renamed.reconcilingArrangement(previous: stale) == renamed)
    }
}
