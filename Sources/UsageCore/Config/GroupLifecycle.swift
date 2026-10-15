import Foundation

// MARK: - Explicit group lifecycle (spec 009)

extension Configuration {
    /// Appends a group with the defaults of a group created in the
    /// new-account sheet and no members (spec 009 FR-007, research R2). The
    /// id is passed in so tests are deterministic; the app passes a fresh
    /// UUID. Names need not be unique. The arrangement needs no explicit
    /// step: reconciliation places the new group last (spec 008 FR-005).
    public func addingGroup(id: String) -> Configuration {
        var copy = self
        copy.groups.append(BudgetGroup(id: id, name: "Budget group", icon: IconDefaults.group, period: .weekly,
                                       budgetUSD: 60, shownInBar: true, thresholds: [80, 100]))
        return copy
    }
}

/// Where the members of a removed group go: all to their own budgets, or
/// all into one other existing group (spec 009 FR-010, data-model.md).
public enum GroupRemovalDestination: Equatable, Hashable, Sendable {
    /// Each member gets its own budget with the group's budget settings.
    case ownBudgets
    /// Each member joins this group, its share hidden from the bar.
    case group(id: String)
}

extension Configuration {
    /// Removes a group and moves its members to `destination` (spec 009
    /// FR-010, research R3):
    /// - `.ownBudgets`: each member gets its own budget with the group's
    ///   period, amount, thresholds and shown-in-bar setting, the values
    ///   moving out of a group starts with (spec 004 FR-014);
    /// - `.group(id:)`: each member becomes a member of that group with its
    ///   share hidden from the bar (spec 004 FR-016).
    /// A destination equal to the removed group, or naming no existing
    /// group, falls back to `.ownBudgets`, so no member is left without a
    /// budget (SC-003). An unknown group id changes nothing. The
    /// arrangement is left to `reconcilingArrangement` (FR-011).
    public func removingGroup(id: String, destination: GroupRemovalDestination) -> Configuration {
        guard let removed = group(id: id) else { return self }
        var target: String?
        if case .group(let targetId) = destination, targetId != id, group(id: targetId) != nil {
            target = targetId
        }
        var copy = self
        for index in copy.accounts.indices {
            guard var settings = copy.accounts[index].kind.tokenBased, settings.groupId == id else { continue }
            settings.membership = target.map { .group(id: $0, shownInBar: false) } ?? .ownBudget(removed.budget)
            copy.accounts[index].kind = .tokenBased(settings)
        }
        copy.groups.removeAll { $0.id == id }
        return copy
    }
}
