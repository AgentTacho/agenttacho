import Foundation
import Testing
@testable import UsageCore

/// Spec 009 FR-007, FR-010: adding and removing budget groups explicitly.
@Suite struct GroupLifecycleTests {
    /// Accounts list: a (subscription), m1 (g), m2 (g), b (own budget),
    /// n1 (h). Groups list: g, h.
    static func config() -> Configuration {
        ArrangementReconcileTests.config()
    }

    // MARK: Adding (FR-007)

    /// Add appends a group with the defaults of the new-account sheet.
    @Test func addingAGroupAppendsTheDefaults() throws {
        let before = Self.config()
        let added = before.addingGroup(id: "new")
        #expect(added.groups.map(\.id) == ["g", "h", "new"])
        let group = try #require(added.group(id: "new"))
        #expect(group.name == "Budget group")
        #expect(group.icon == IconDefaults.group)
        #expect(group.period == .weekly)
        #expect(group.budgetUSD == 60)
        #expect(group.shownInBar)
        #expect(group.thresholds == [80, 100])
        #expect(added.members(of: "new").isEmpty)
        #expect(added.accounts == before.accounts)
        try added.validate()
    }

    /// Group names need not be unique: each Add creates another group.
    @Test func repeatedAddsCreateDistinctGroupsWithTheSameName() throws {
        let added = Self.config().addingGroup(id: "x1").addingGroup(id: "x2")
        #expect(added.groups.map(\.id) == ["g", "h", "x1", "x2"])
        #expect(added.group(id: "x1")?.name == "Budget group")
        #expect(added.group(id: "x2")?.name == "Budget group")
        try added.validate()
    }

    /// The new group is last in the arrangement once reconciled (spec 008
    /// FR-005), also when an order is stored.
    @Test func addedGroupIsLastInTheArrangement() {
        let unstored = Self.config()
        let added = unstored.addingGroup(id: "new").reconcilingArrangement(previous: unstored)
        #expect(ArrangementReconcileTests.order(added).last == "g:new")

        let stored = ArrangementReconcileTests.config(arrangement: ArrangementReconcileTests.arrangement(["g:h", "a:a", "g:g", "a:b"]))
        let addedStored = stored.addingGroup(id: "new").reconcilingArrangement(previous: stored)
        #expect(ArrangementReconcileTests.order(addedStored) == ["g:h", "a:a", "g:g", "a:b", "g:new"])
        #expect(ArrangementReconcileTests.members(addedStored, "new") == [])
    }

    // MARK: Removing (FR-010)

    /// g with distinctive budget settings, and m1's share shown in the bar.
    static func removalConfig() -> Configuration {
        var c = config()
        c.groups[0] = BudgetGroup(id: "g", name: "Vertex", icon: "solid:cloud", period: .monthly, budgetUSD: 300,
                                  shownInBar: false, thresholds: [70, 95])
        c.accounts[1].kind = .tokenBased(TokenBasedSettings(membership: .group(id: "g", shownInBar: true), harness: .claudeCode))
        return c
    }

    /// An empty group is simply removed.
    @Test func removingAnEmptyGroup() throws {
        let emptied = Self.config().removingAccount(id: "n1")
        let removed = emptied.removingGroup(id: "h", destination: .ownBudgets)
        #expect(removed.groups.map(\.id) == ["g"])
        #expect(removed.accounts == emptied.accounts)
        try removed.validate()
        #expect(emptied.removingGroup(id: "h", destination: .group(id: "g")) == removed)
    }

    /// "Own budgets": each member gets its own budget with the group's
    /// period, amount, thresholds and shown-in-bar setting.
    @Test func ownBudgetsCopyTheGroupBudget() throws {
        let before = Self.removalConfig()
        let removed = before.removingGroup(id: "g", destination: .ownBudgets)
        #expect(removed.group(id: "g") == nil)
        #expect(removed.groups.map(\.id) == ["h"])
        let budget = BudgetSettings(period: .monthly, budgetUSD: 300, shownInBar: false, thresholds: [70, 95])
        for id in ["m1", "m2"] {
            #expect(removed.account(id: id)?.kind.tokenBased?.membership == .ownBudget(budget))
        }
        // The provider of a member is kept.
        #expect(removed.account(id: "m1")?.kind.tokenBased?.harness == .claudeCode)
        try removed.validate()
    }

    /// Another group: each member joins it with its share hidden.
    @Test func anotherGroupTakesTheMembersWithSharesHidden() throws {
        let before = Self.removalConfig()
        let removed = before.removingGroup(id: "g", destination: .group(id: "h"))
        #expect(removed.groups.map(\.id) == ["h"])
        #expect(removed.group(id: "h") == before.group(id: "h"))
        for id in ["m1", "m2"] {
            #expect(removed.account(id: id)?.kind.tokenBased?.membership == .group(id: "h", shownInBar: false))
        }
        #expect(removed.members(of: "h").map(\.id) == ["m1", "m2", "n1"])
        try removed.validate()
    }

    /// A destination equal to the removed group, or an unknown group, falls
    /// back to own budgets (research R3; the dialog never offers either).
    @Test func invalidDestinationsFallBackToOwnBudgets() {
        let before = Self.removalConfig()
        let own = before.removingGroup(id: "g", destination: .ownBudgets)
        #expect(before.removingGroup(id: "g", destination: .group(id: "g")) == own)
        #expect(before.removingGroup(id: "g", destination: .group(id: "missing")) == own)
    }

    /// Accounts and groups that are not involved stay as they are, and an
    /// unknown group id changes nothing.
    @Test func unrelatedAccountsAndGroupsAreUnchanged() {
        let before = Self.removalConfig()
        for destination in [GroupRemovalDestination.ownBudgets, .group(id: "h")] {
            let removed = before.removingGroup(id: "g", destination: destination)
            for id in ["a", "b", "n1"] {
                #expect(removed.account(id: id) == before.account(id: id))
            }
            #expect(removed.accounts.map(\.id) == before.accounts.map(\.id))
        }
        #expect(before.removingGroup(id: "missing", destination: .ownBudgets) == before)
    }

    // MARK: Groups without an amount (spec 044 FR-017, FR-021, R7)

    /// Add keeps spec 009's defaults plus no Price tokens as model and
    /// Automatic (FR-017).
    @Test func addingAGroupKeepsTheAmountDefaults() throws {
        let group = try #require(Self.config().addingGroup(id: "new").group(id: "new"))
        #expect(group.budgetUSD == 60)
        #expect(group.period == .weekly)
        #expect(group.thresholds == [80, 100])
        #expect(group.shownInBar)
        #expect(group.valueAs == nil)
        #expect(group.show == .automatic)
    }

    static func noAmountConfig() -> Configuration {
        var c = removalConfig()
        c.groups[0].budgetUSD = nil
        return c
    }

    @Test func ownBudgetsFromAGroupWithoutAnAmountHaveNoAmount() throws {
        let removed = Self.noAmountConfig().removingGroup(id: "g", destination: .ownBudgets)
        let expected = TokenMembership.noLimit(NoLimitSettings(period: .monthly, thresholds: [70, 95], shownInBar: false))
        for id in ["m1", "m2"] {
            #expect(removed.account(id: id)?.kind.tokenBased?.membership == expected)
        }
        try removed.validate()
        // Another group as destination is unchanged.
        let joined = Self.noAmountConfig().removingGroup(id: "g", destination: .group(id: "h"))
        #expect(joined.account(id: "m1")?.kind.tokenBased?.membership == .group(id: "h", shownInBar: false))
    }

    /// The remove sheet's note for "each to its own budget" (contracts/ui-strings.md).
    @Test func destinationNoteNamesTheMissingAmount() throws {
        let with = try #require(Self.removalConfig().group(id: "g"))
        let without = try #require(Self.noAmountConfig().group(id: "g"))
        #expect(GroupRemovalDestination.ownBudgets.note(removing: with)
                == "Each account gets its own budget with this group's period, amount, thresholds and menu bar setting. You can undo this with \u{2318}Z.")
        #expect(GroupRemovalDestination.ownBudgets.note(removing: without)
                == "Each account gets its own budget with this group's period and settings, without an amount. You can undo this with \u{2318}Z.")
        for group in [with, without] {
            #expect(GroupRemovalDestination.group(id: "h").note(removing: group)
                    == "The accounts join that group, their shares hidden from the menu bar. You can undo this with \u{2318}Z.")
        }
    }
}
