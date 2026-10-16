import Foundation

/// Budget amounts in the Settings lists: "$400 / month", "$99.50 / week"
/// (spec 018 FR-003). Shared by the Accounts and Groups lists, so both show
/// the same amount text for the same budget (SC-004).
public enum BudgetAmountFormatter {
    /// A US dollar amount in the locale's currency style, rounded to cents
    /// with plain rounding (half away from zero), without decimals when the
    /// rounded amount is whole and with exactly two otherwise (spec 018
    /// FR-003, research R1). Zero and negative amounts are shown as entered.
    public static func amount(_ value: Decimal, locale: Locale = .current) -> String {
        let cents = rounded(value, scale: 2)
        let isWhole = rounded(cents, scale: 0) == cents
        let style = Decimal.FormatStyle.Currency(code: "USD", locale: locale)
            .precision(.fractionLength(isWhole ? 0 : 2))
        return cents.formatted(style)
    }

    /// The amount followed by " / month" or " / week" (spec 018 FR-003).
    public static func text(_ value: Decimal, period: BudgetPeriod, locale: Locale = .current) -> String {
        "\(amount(value, locale: locale)) / \(unit(period))"
    }

    static func unit(_ period: BudgetPeriod) -> String {
        switch period {
        case .weekly: return "week"
        case .monthly: return "month"
        }
    }

    private static func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}

/// Where a token-based account's spend counts, for its subtitle in
/// Settings > Accounts (spec 018 FR-001, FR-002, FR-007a, FR-008). All text
/// is built here; the view only draws the group icon between
/// `visiblePrefix` and `visibleSuffix`.
public struct AccountBudgetDescription: Equatable, Sendable {
    /// The budget the account's spend counts against (spec 018 Key Entities).
    public enum Kind: Equatable, Sendable {
        case group(iconId: String, name: String, amount: Decimal, period: BudgetPeriod)
        case ownBudget(amount: Decimal, period: BudgetPeriod)
        /// The account's group id names no existing group (FR-002).
        case missingGroup
    }

    /// The provider's display name, for example "Vertex".
    public let provider: String
    public let budget: Kind
    /// "Vertex · " for a group member; the full visible text otherwise.
    public let visiblePrefix: String
    /// The group's icon (FR-007); nil for an own budget and a missing group.
    public let iconId: String?
    /// "Vertex, $400 / month" for a group member; empty otherwise. The view
    /// puts a space between the icon and this text.
    public let visibleSuffix: String
    /// The full visible text without the icon (FR-001, FR-002).
    public let visibleText: String
    /// The VoiceOver text, without the icon glyph (FR-007a).
    public let accessibilityText: String

    init(provider: String, budget: Kind, locale: Locale) {
        self.provider = provider
        self.budget = budget
        let lead = "\(provider) · "
        switch budget {
        case .group(let iconId, let name, let amount, let period):
            let suffix = "\(name), \(BudgetAmountFormatter.text(amount, period: period, locale: locale))"
            visiblePrefix = lead
            self.iconId = iconId
            visibleSuffix = suffix
            visibleText = lead + suffix
            accessibilityText = "\(provider), group \(name), \(BudgetAmountFormatter.amount(amount, locale: locale)) \(period.perUnit)"
        case .ownBudget(let amount, let period):
            let text = "\(lead)own budget, \(BudgetAmountFormatter.text(amount, period: period, locale: locale))"
            visiblePrefix = text
            iconId = nil
            visibleSuffix = ""
            visibleText = text
            accessibilityText = "\(provider), own budget, \(BudgetAmountFormatter.amount(amount, locale: locale)) \(period.perUnit)"
        case .missingGroup:
            let text = "\(lead)no group"
            visiblePrefix = text
            iconId = nil
            visibleSuffix = ""
            visibleText = text
            accessibilityText = "\(provider), no group"
        }
    }

    /// The description of `account` as the `configuration` draft has it, so
    /// unsaved edits show at once (spec 018 FR-005). Nil for subscription
    /// and Codex subscription accounts, whose subtitles stay unchanged
    /// (FR-006).
    public static func make(for account: Account, in configuration: Configuration, locale: Locale = .current) -> AccountBudgetDescription? {
        guard let settings = account.kind.tokenBased else { return nil }
        let kind: Kind
        switch settings.membership {
        case .group(let id, _):
            if let group = configuration.group(id: id) {
                kind = .group(iconId: group.icon, name: group.name, amount: group.budgetUSD, period: group.period)
            } else {
                kind = .missingGroup
            }
        case .ownBudget(let budget):
            kind = .ownBudget(amount: budget.budgetUSD, period: budget.period)
        }
        return AccountBudgetDescription(provider: settings.provider.displayName, budget: kind, locale: locale)
    }
}

/// The subtitle of a row in Settings > Groups (spec 018 FR-004).
public enum GroupListSubtitle {
    /// "$400 / month, 2 member(s)", in the amount style of FR-003.
    public static func text(group: BudgetGroup, memberCount: Int, locale: Locale = .current) -> String {
        "\(BudgetAmountFormatter.text(group.budgetUSD, period: group.period, locale: locale)), \(memberCount) member(s)"
    }
}
