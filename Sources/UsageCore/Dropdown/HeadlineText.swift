import Foundation

/// The headline of a token-based account's dropdown section: its text, its
/// tooltip and its accessibility text, for each measure (spec 043 FR-013,
/// FR-016, research R6, contracts/ui-strings.md). Used by the section of an
/// own budget with an amount, of a group and of an own budget without one.
public struct HeadlineText: Equatable, Sendable {
    public let text: String
    public let tooltip: String?
    public let accessibilityText: String

    public init(text: String, tooltip: String?, accessibilityText: String) {
        self.text = text
        self.tooltip = tooltip
        self.accessibilityText = accessibilityText
    }

    /// The used percent as the budget header shows it today, through
    /// `DirectedPercent` (spec 030 FR-009, FR-012); no tooltip.
    public static func percent(usedPercent: Int, direction: DisplayDirection) -> HeadlineText {
        let directed = DirectedPercent(usedPercent: usedPercent, direction: direction)
        return HeadlineText(text: directed.text, tooltip: nil, accessibilityText: directed.accessibilityText(.budget))
    }

    /// The token total in the format of spec 041 FR-011 ("48.2M") and the
    /// compact count spelled with its scale word as accessibility text
    /// ("48.2 million tokens this month"). The tooltip uses the same scale
    /// word from a million on, and the exact count below ("950,000 tokens
    /// this week"): eight digits say nothing more than "48.2 million"
    /// (spec 043 FR-013, walkthrough step 4). Always the tokens used, also
    /// in remaining mode.
    public static func tokens(_ total: Int, period: BudgetPeriod) -> HeadlineText {
        let locale = DisplayLocale.numbers
        let compact = CompactFormat.tokens(total, locale: locale)
        let thisPeriod = Self.thisPeriod(period)
        let count = total >= 1_000_000 ? spoken(compact) : total.formatted(.number.locale(locale))
        return HeadlineText(text: compact,
                            tooltip: "\(count) tokens \(thisPeriod)",
                            accessibilityText: "\(spoken(compact)) tokens \(thisPeriod)")
    }

    /// The real spend in whole US dollars rounded half up ("$37", "$0",
    /// "<$1"), with the exact amount and the period as tooltip and spoken
    /// text ("$37.42 spent this month"). Never "≈" (FR-013).
    public static func spent(_ amount: Decimal, period: BudgetPeriod) -> HeadlineText {
        let exact = "\(cents(amount)) spent \(thisPeriod(period))"
        return HeadlineText(text: whole(amount), tooltip: exact, accessibilityText: exact)
    }

    /// The Money headline of an account with an amount: the spend in
    /// direction used; in remaining mode the amount left ("$63") or over
    /// ("−$12", typographic minus), decided as the amount line decides it
    /// (spec 030 FR-012), with the tooltip and spoken text worded like the
    /// amount line ("$62.58 left of $100/month", "$12.40 over $100/month").
    public static func money(spent: Decimal, budget: Decimal, roundedPercent: Int, period: BudgetPeriod,
                             direction: DisplayDirection) -> HeadlineText {
        let line = BudgetAmountLine.make(spent: spent, budget: budget, roundedPercent: roundedPercent, direction: direction)
        let ofBudget = "\(BudgetAmountFormatter.amount(budget))/\(BudgetAmountFormatter.unit(period))"
        switch line {
        case .of:
            return Self.spent(spent, period: period)
        case .left(let left):
            let exact = "\(cents(left)) left of \(ofBudget)"
            return HeadlineText(text: whole(left), tooltip: exact, accessibilityText: exact)
        case .over(let over):
            let exact = "\(cents(over)) over \(ofBudget)"
            return HeadlineText(text: "\u{2212}\(whole(over))", tooltip: exact, accessibilityText: exact)
        }
    }

    /// The headline of a budget section (spec 043 FR-013, FR-014): an own
    /// budget passes its account's Show setting, a group `.automatic`. With
    /// an amount Automatic and Percent show the percent; Tokens the entry's
    /// token total; Money the spend, or what is left or over in remaining
    /// mode.
    public static func budget(entry: GroupEntry, show: DropdownShow, direction: DisplayDirection) -> HeadlineText {
        switch show.resolve(hasAmount: true, hasPricedUsage: true) {
        case .percent:
            return percent(usedPercent: entry.percent, direction: direction)
        case .tokens:
            return tokens(entry.breakdown.totalTokens, period: entry.period)
        case .money:
            return money(spent: entry.spentUSD, budget: entry.budgetUSD, roundedPercent: entry.percent,
                         period: entry.period, direction: direction)
        }
    }

    /// "this week" or "this month".
    static func thisPeriod(_ period: BudgetPeriod) -> String {
        "this \(BudgetAmountFormatter.unit(period))"
    }

    /// Whole US dollars rounded half up: "$0" for exactly 0, "<$1" above 0
    /// and below one dollar (spec 043 FR-013, the rounding of spec 041's
    /// value line).
    static func whole(_ amount: Decimal) -> String {
        BudgetAmountFormatter.wholeDollars(amount).visible
    }

    /// The exact amount with cents: "$37.42", "$12.40", "$0.00". Rounded
    /// half up to the cent first, as `BudgetAmountFormatter.amount` rounds,
    /// never to even (SC-004).
    static func cents(_ amount: Decimal) -> String {
        var input = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded.formatted(Decimal.FormatStyle.Currency(code: "USD", locale: DisplayLocale.numbers).precision(.fractionLength(2)))
    }

    /// A compact count with its scale spelled out: "48.2M" reads "48.2
    /// million", "950K" "950 thousand", "1.2B" "1.2 billion".
    static func spoken(_ compact: String) -> String {
        let words: [Character: String] = ["K": "thousand", "M": "million", "B": "billion", "T": "trillion"]
        guard let last = compact.last, let word = words[last] else { return compact }
        return "\(compact.dropLast()) \(word)"
    }
}
