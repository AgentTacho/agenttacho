import Foundation

/// The group editor's draft of a group's budget: period, an optional
/// amount, thresholds and shown-in-bar (spec 044 FR-016, FR-017, research
/// R6). It converts them to and from `OwnBudgetForm`, so the group editor
/// shows the own budget editor's fields with their enabling rules and help
/// texts, not copies (FR-015). The amount decides whether the group has a
/// limit; period, thresholds and shown-in-bar are kept in both directions
/// (FR-002).
public struct GroupBudgetForm: Equatable, Sendable {
    public var period: BudgetPeriod
    /// Nil means no amount, so no limit. 0 or less stays an amount, which
    /// saving refuses (spec 003 FR-019).
    public var amount: Decimal?
    public var thresholds: [Int]
    public var shownInBar: Bool

    public init(_ group: BudgetGroup) {
        period = group.period
        amount = group.budgetUSD
        thresholds = group.thresholds
        shownInBar = group.shownInBar
    }

    /// `group` with this form's period, amount, thresholds and shown-in-bar;
    /// name, icon, Price tokens as, Show and the time format stay.
    public func applied(to group: BudgetGroup) -> BudgetGroup {
        var copy = group
        copy.period = period
        copy.budgetUSD = amount
        copy.thresholds = thresholds
        copy.shownInBar = shownInBar
        return copy
    }

    /// The own budget form with the same values, whose rules and strings
    /// this form shares. The group editor shows the own budget editor's
    /// fields through it; setting it takes back period, amount, thresholds
    /// and shown-in-bar (spec 044 FR-016).
    public var ownForm: OwnBudgetForm {
        get {
            var form = OwnBudgetForm(.noLimit(NoLimitSettings(period: period, thresholds: thresholds, shownInBar: shownInBar)))
            form.amount = amount
            return form
        }
        set {
            period = newValue.period
            amount = newValue.amount
            thresholds = newValue.thresholds
            shownInBar = newValue.shownInBar
        }
    }
}
