import Foundation

/// The own budget editor's draft: one form for an own budget with or
/// without an amount, whose amount decides the membership case (spec 043
/// FR-002, FR-003, FR-018, FR-019, research R7). Period, thresholds and
/// shown-in-bar are carried over in both directions.
public struct OwnBudgetForm: Equatable, Sendable {
    public var period: BudgetPeriod
    /// Nil means no amount, so no limit. 0 or less stays an amount, which
    /// saving refuses (spec 003 FR-019).
    public var amount: Decimal?
    public var thresholds: [Int]
    public var shownInBar: Bool

    /// The form of an own budget (`.ownBudget` or `.noLimit`); a group
    /// membership gives a new account's form without an amount.
    public init(_ membership: TokenMembership) {
        switch membership {
        case .ownBudget(let budget):
            period = budget.period
            amount = budget.budgetUSD
            thresholds = budget.thresholds
            shownInBar = budget.shownInBar
        case .noLimit(let settings):
            period = settings.period
            amount = nil
            thresholds = settings.thresholds
            shownInBar = settings.shownInBar
        case .group:
            let fresh = NoLimitSettings()
            period = fresh.period
            amount = nil
            thresholds = fresh.thresholds
            shownInBar = fresh.shownInBar
        }
    }

    /// `.ownBudget` when an amount is set, `.noLimit` otherwise.
    public var membership: TokenMembership {
        if let amount {
            return .ownBudget(BudgetSettings(period: period, budgetUSD: amount, shownInBar: shownInBar, thresholds: thresholds))
        }
        return .noLimit(NoLimitSettings(period: period, thresholds: thresholds, shownInBar: shownInBar))
    }

    /// True when the form has an amount, so thresholds and the menu bar
    /// apply (spec 043 FR-018).
    public var hasAmount: Bool { amount != nil }

    /// What the editor's disabled "Show in menu bar" toggle shows: unchecked
    /// without an amount, as the Menu Bar tab shows it (spec 043 FR-018,
    /// FR-020). The kept `shownInBar` stays stored and applies again once
    /// an amount is entered.
    public var shownInBarDisplayed: Bool { hasAmount && shownInBar }

    /// The thresholds and "Show in menu bar" apply only with an amount;
    /// without one they are disabled, not hidden (spec 043 FR-018, spec 044
    /// FR-016).
    public var budgetControlsEnabled: Bool { hasAmount }
    /// The help text of the disabled thresholds and "Show in menu bar", nil
    /// while they are enabled.
    public var budgetControlsHelp: String? { budgetControlsEnabled ? nil : needsBudgetHelp }
    /// "Price tokens as" values unpriced records only without an amount;
    /// with one it is disabled (spec 043 FR-018, spec 044 FR-008, FR-016).
    public var valueAsEnabled: Bool { !hasAmount }
    /// The help text of the disabled "Price tokens as" pop-up, nil while it
    /// is enabled.
    public var valueAsHelp: String? { valueAsEnabled ? nil : valueAsDisabledHelp }

    /// The inline error below the Amount field: only an entered amount of 0
    /// or less is one, an empty amount is no limit (spec 043 FR-002).
    public var amountError: String? { period.amountError(for: amount) }

    /// The help text of the disabled thresholds and "Show in menu bar"
    /// without an amount, naming the period's budget rather than "an
    /// amount" (contracts/ui-strings.md, walkthrough step 6).
    public var needsBudgetHelp: String { "Set a \(period.adjective) budget to use thresholds and the menu bar." }
    /// The help text of the disabled "Price tokens as" pop-up with an amount.
    public var valueAsDisabledHelp: String { "\(Self.valueAsLabel) applies only without a \(period.adjective) budget." }
    /// The label of the pop-up that prices unpriced tokens at a reference
    /// model (spec 041 "Value as", renamed in walkthrough step 6).
    public static let valueAsLabel = "Price tokens as"
    /// The caption under the "Price tokens as" pop-up.
    public static let valueAsCaption = "Shows what the tokens of models without a price would cost at this model's prices."
    /// The Amount field's placeholder.
    public static let amountPlaceholder = "No limit"
    /// The new account sheet's caption below the budget pop-up
    /// (contracts/ui-strings.md "Settings: new account sheet"): for an own
    /// budget with an empty amount, with an amount, or for a group (nil).
    public static func newAccountCaption(ownBudget: OwnBudgetForm?) -> String {
        guard let ownBudget else { return groupCaption }
        return ownBudget.hasAmount ? "Shown in the menu bar, with notifications at 80% and 100%. " + groupCaption
            : "Without a \(ownBudget.period.adjective) budget the account has no limit and is not shown in the menu bar."
    }

    private static let groupCaption = "To share a budget with other accounts, create a budget group in the Groups tab first."
}
