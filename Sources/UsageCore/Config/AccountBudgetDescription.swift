import Foundation

/// Budget amounts in the Settings lists: "$400 / month", "$99.50 / week"
/// (spec 018 FR-003). Shared by the Accounts and Groups lists, so both show
/// the same amount text for the same budget (SC-004).
public enum BudgetAmountFormatter {
    /// A US dollar amount in en_US currency style by default
    /// (DisplayLocale), rounded to cents
    /// with plain rounding (half away from zero), without decimals when the
    /// rounded amount is whole and with exactly two otherwise (spec 018
    /// FR-003, research R1). Zero and negative amounts are shown as entered.
    public static func amount(_ value: Decimal, locale: Locale = DisplayLocale.numbers) -> String {
        let cents = rounded(value, scale: 2)
        let isWhole = rounded(cents, scale: 0) == cents
        let style = Decimal.FormatStyle.Currency(code: "USD", locale: locale)
            .precision(.fractionLength(isWhole ? 0 : 2))
        return cents.formatted(style)
    }

    /// A US dollar amount in whole units in en_US currency style by
    /// default (DisplayLocale),
    /// rounded half up, never to even ("$412" for 411.50), for the value
    /// line and Money headline of an own budget without an amount (spec 043
    /// FR-013, spec 041 FR-012).
    public static func wholeAmount(_ value: Decimal, locale: Locale = DisplayLocale.numbers) -> String {
        rounded(value, scale: 0).formatted(Decimal.FormatStyle.Currency(code: "USD", locale: locale).precision(.fractionLength(0)))
    }

    /// Whole US dollars for a member line of a group with an amount ("$181",
    /// spec 004 FR-018a, spec 044 FR-013): the currency style's own
    /// rounding, half to even ("$180" for 180.50), as these lines have
    /// always rounded, unlike `wholeAmount`; and without "<$1", so a spend
    /// below one dollar reads "$0" or "$1".
    public static func memberSpend(_ value: Decimal, locale: Locale = DisplayLocale.numbers) -> String {
        value.formatted(Decimal.FormatStyle.Currency(code: "USD", locale: locale).precision(.fractionLength(0)))
    }

    /// Whole US dollars for the dropdown (spec 041 FR-012, clarification 1,
    /// spec 043 FR-013): "$0" for exactly 0, "<$1" above 0 and below one
    /// dollar, otherwise rounded half up ("$412"), never to even. The
    /// spoken form reads "about $412" or "less than $1". Shared by the
    /// Money headline and the value line.
    public static func wholeDollars(_ value: Decimal, locale: Locale = DisplayLocale.numbers) -> (visible: String, spoken: String) {
        if value > 0 && value < 1 {
            let one = wholeAmount(1, locale: locale)
            return ("<\(one)", "less than \(one)")
        }
        let text = wholeAmount(value, locale: locale)
        return (text, "about \(text)")
    }

    /// The amount followed by " / month" or " / week" (spec 018 FR-003).
    public static func text(_ value: Decimal, period: BudgetPeriod, locale: Locale = DisplayLocale.numbers) -> String {
        "\(amount(value, locale: locale)) / \(unit(period))"
    }

    /// "no limit / month" or "no limit / week", in place of the amount of
    /// a budget without one (spec 041 FR-020, spec 043 FR-021, spec 044
    /// FR-018).
    public static func noLimitText(period: BudgetPeriod) -> String {
        "no limit / \(unit(period))"
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
        /// `amount` is nil for a group without an amount (spec 044 FR-018).
        case group(iconId: String, name: String, amount: Decimal?, period: BudgetPeriod)
        case ownBudget(amount: Decimal, period: BudgetPeriod)
        /// The account's group id names no existing group (FR-002).
        case missingGroup
        /// An own budget without an amount (spec 043 FR-021, spec 041
        /// FR-020).
        case noLimit(period: BudgetPeriod)
    }

    /// The session kind's short name, for example "Vertex" or "Other
    /// provider" (spec 038 FR-012).
    public let source: String
    public let budget: Kind
    /// "Vertex · " for a group member; the full visible text otherwise,
    /// such as "Other provider · no limit / month" (spec 041 FR-020).
    public let visiblePrefix: String
    /// The group's icon (FR-007); nil for an own budget with or without an
    /// amount (spec 043 FR-021) and a missing group.
    public let iconId: String?
    /// "Vertex, $400 / month" for a group member; empty otherwise. The view
    /// puts a space between the icon and this text.
    public let visibleSuffix: String
    /// The full visible text without the icon (FR-001, FR-002).
    public let visibleText: String
    /// The VoiceOver text, without the icon glyph (FR-007a).
    public let accessibilityText: String

    init(source: String, budget: Kind, locale: Locale) {
        self.source = source
        self.budget = budget
        let lead = "\(source) · "
        switch budget {
        case .group(let iconId, let name, let amount, let period):
            // A group without an amount reads "no limit / month" in place
            // of the amount (spec 044 FR-018).
            let amountText = amount.map { BudgetAmountFormatter.text($0, period: period, locale: locale) }
                ?? BudgetAmountFormatter.noLimitText(period: period)
            let suffix = "\(name), \(amountText)"
            visiblePrefix = lead
            self.iconId = iconId
            visibleSuffix = suffix
            visibleText = lead + suffix
            let spokenAmount = amount.map { BudgetAmountFormatter.amount($0, locale: locale) } ?? "no limit,"
            accessibilityText = "\(source), group \(name), \(spokenAmount) \(period.perUnit)"
        case .ownBudget(let amount, let period):
            let text = "\(lead)own budget, \(BudgetAmountFormatter.text(amount, period: period, locale: locale))"
            visiblePrefix = text
            iconId = nil
            visibleSuffix = ""
            visibleText = text
            accessibilityText = "\(source), own budget, \(BudgetAmountFormatter.amount(amount, locale: locale)) \(period.perUnit)"
        case .missingGroup:
            let text = "\(lead)no group"
            visiblePrefix = text
            iconId = nil
            visibleSuffix = ""
            visibleText = text
            accessibilityText = "\(source), no group"
        case .noLimit(let period):
            let text = lead + BudgetAmountFormatter.noLimitText(period: period)
            visiblePrefix = text
            iconId = nil
            visibleSuffix = ""
            visibleText = text
            accessibilityText = "\(source), no limit, \(period.perUnit)"
        }
    }

    /// The description of `account` as the `configuration` draft has it, so
    /// unsaved edits show at once (spec 018 FR-005). Nil for subscription
    /// and Codex subscription accounts, whose subtitles stay unchanged
    /// (FR-006).
    public static func make(for account: Account, in configuration: Configuration, locale: Locale = DisplayLocale.numbers) -> AccountBudgetDescription? {
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
        case .noLimit(let settings):
            kind = .noLimit(period: settings.period)
        }
        return AccountBudgetDescription(source: sourceName(settings), budget: kind, locale: locale)
    }

    /// The kind's short name, such as "Other provider" (spec 038 FR-012).
    static func sourceName(_ settings: TokenBasedSettings) -> String {
        settings.sessionKind.displayName
    }
}

/// The subtitle of a row in Settings > Groups (spec 018 FR-004).
public enum GroupListSubtitle {
    /// "$400 / month, 2 member(s)", in the amount style of FR-003; "no limit
    /// / month, 2 member(s)" for a group without an amount (spec 044 FR-018).
    public static func text(group: BudgetGroup, memberCount: Int, locale: Locale = DisplayLocale.numbers) -> String {
        let amount = group.budgetUSD.map { BudgetAmountFormatter.text($0, period: group.period, locale: locale) }
            ?? BudgetAmountFormatter.noLimitText(period: group.period)
        return "\(amount), \(memberCount) member(s)"
    }

    /// The VoiceOver text: the visible text with an amount, "No limit,
    /// monthly, 2 members" without one (spec 044 FR-018,
    /// contracts/ui-strings.md "Settings: Groups tab list").
    public static func accessibilityText(group: BudgetGroup, memberCount: Int, locale: Locale = DisplayLocale.numbers) -> String {
        guard !group.hasAmount else { return text(group: group, memberCount: memberCount, locale: locale) }
        return "No limit, \(group.period.adjective), \(memberCount) \(memberCount == 1 ? "member" : "members")"
    }
}
