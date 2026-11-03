import Foundation

/// What the headline of a token-based account's dropdown section shows
/// (spec 043 FR-010, research R3). Stored per account under `show`; absent
/// means Automatic. Presentation only: the menu bar never changes with it.
public enum DropdownShow: String, Codable, CaseIterable, Sendable {
    case automatic, percent, tokens, money

    /// The label of the account editor's pop-up (spec 043 FR-018,
    /// contracts/ui-strings.md).
    public static let popUpLabel = "Dropdown shows"

    /// The pop-up item (contracts/ui-strings.md).
    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .percent: return "Percent"
        case .tokens: return "Tokens"
        case .money: return "Money"
        }
    }
}

/// The measure a dropdown headline shows after Automatic and the amount rule
/// are applied (spec 043 "Resolved headline").
public enum HeadlineMeasure: Equatable, Sendable {
    case percent, tokens, money
}

extension DropdownShow {
    /// The measure of the headline (spec 043 FR-011, FR-012, data-model.md):
    /// Automatic is Percent with an amount, otherwise Money when the
    /// current window has a priced record and Tokens when not. A stored
    /// Percent without an amount shows what Automatic would.
    public func resolve(hasAmount: Bool, hasPricedUsage: Bool) -> HeadlineMeasure {
        switch self {
        case .tokens: return .tokens
        case .money: return .money
        case .automatic, .percent:
            if hasAmount { return .percent }
            return hasPricedUsage ? .money : .tokens
        }
    }

    /// Whether `choice` can be picked in the pop-up: Percent needs an amount
    /// (spec 043 FR-018). A stored Percent stays selected while disabled.
    public static func isEnabled(_ choice: DropdownShow, hasAmount: Bool) -> Bool {
        choice != .percent || hasAmount
    }

    /// The help text of a disabled pop-up item, nil for an enabled one
    /// (contracts/ui-strings.md).
    public static func help(_ choice: DropdownShow, hasAmount: Bool, period: BudgetPeriod) -> String? {
        isEnabled(choice, hasAmount: hasAmount) ? nil : "Percent needs a \(period.adjective) budget. The headline follows Automatic."
    }
}
