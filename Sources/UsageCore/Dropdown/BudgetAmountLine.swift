import Foundation

/// A budget's dollar line in the chosen direction (spec 030 FR-012): what
/// it says and which amount it shows. The app formats the amounts
/// (`UsageFormat`), so the line keeps today's amount and period formats.
public enum BudgetAmountLine: Equatable, Sendable {
    /// "$S of $B/period", direction used (as today).
    case of(spent: Decimal)
    /// "$X left of $B/period": what is left, floored at 0.
    case left(Decimal)
    /// "$X over $B/period": the spend above the budget.
    case over(Decimal)

    /// "over" exactly when the rounded used percent (the one the header
    /// shows) is above 100, so the line, the percent and the bar never
    /// disagree; a rounded 100% reads "$0 left" (FR-012). A budget of 0 or
    /// less keeps today's line in both directions (spec 030 edge case "a
    /// budget without a positive amount").
    public static func make(spent: Decimal, budget: Decimal, roundedPercent: Int, direction: DisplayDirection) -> BudgetAmountLine {
        guard direction == .remaining, budget > 0 else { return .of(spent: spent) }
        if roundedPercent > 100 { return .over(spent - budget) }
        return .left(max(budget - spent, 0))
    }

    /// The line with `amount` formatting the dollar amount, the formatted
    /// `budget` and its `period` ("week", "month").
    public func text(amount: (Decimal) -> String, budget: String, period: String) -> String {
        switch self {
        case .of(let spent): return "\(amount(spent)) of \(budget)/\(period)"
        case .left(let left): return "\(amount(left)) left of \(budget)/\(period)"
        case .over(let over): return "\(amount(over)) over \(budget)/\(period)"
        }
    }
}
