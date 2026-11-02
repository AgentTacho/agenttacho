import Foundation

/// The texts of a No limit account's dropdown section, decided here; the
/// view only renders them (spec 041 FR-011, FR-014, FR-015, FR-015a,
/// FR-015b, contracts/ui-strings.md).
public struct NoLimitPresentation: Equatable, Sendable {
    /// The token total in place of the percent ("48.2M", "0"), without a
    /// unit; nil without an entry (FR-011).
    public let headline: String?
    /// The exact count with unit and period ("48,213,507 tokens this
    /// month"), the headline's tooltip; nil without an entry (FR-011).
    public let headlineTooltip: String?
    /// "this week" or "this month", left of the reset text when there is no
    /// value line; nil with a value line or without an entry (FR-011).
    public let periodLine: String?
    /// The reset time in the section's time format, and its other form as
    /// tooltip (spec 025 FR-016, FR-019).
    public let resetText: String?
    public let resetTooltip: String?
    /// The stale and no-data notes of an own budget's section; never
    /// "incomplete, unpriced" (FR-008, FR-015b).
    public let notes: [SectionNote]
    /// True when the period has usage; a section without usage has no
    /// Details (FR-014).
    public let showsDetails: Bool
    /// "≈ $412 at claude-opus-5-5 prices", nil without a value (FR-012).
    public let valueLine: String?
    /// What the value means, nil without a value line (FR-012).
    public let valueTooltip: String?
    /// Name, tokens with their period, the reset time and the value or the
    /// missing-model note (FR-015).
    public let accessibilityLabel: String

    /// The presentation of `entry`, nil before the first result of a
    /// refresh. The notes follow an own budget's section: stale since the
    /// last successful refresh, or "No data" / "Refreshing…" without an
    /// entry (spec 025 FR-029). `value` adds the value line, or the
    /// neutral missing-model note in its place (FR-012, FR-013).
    public static func make(name: String, entry: NoLimitEntry?, value: ReferenceValue = .none, times: TimeText,
                            lastSuccessfulRefreshAt: Date?, isPreliminary: Bool, dates: NoteDates) -> NoLimitPresentation {
        guard let entry else {
            let notes = [SectionNote.noData(isPreliminary: isPreliminary)]
            return NoLimitPresentation(headline: nil, headlineTooltip: nil, periodLine: nil, resetText: nil, resetTooltip: nil, notes: notes,
                                       showsDetails: false, valueLine: nil, valueTooltip: nil,
                                       accessibilityLabel: ([name] + notes.map(\.text)).joined(separator: ", "))
        }
        let headline = CompactFormat.tokens(entry.totalTokens, locale: times.locale)
        let period = "this \(BudgetAmountFormatter.unit(entry.period))"
        let headlineTooltip = "\(entry.totalTokens.formatted(.number.locale(times.locale))) tokens \(period)"
        let resetText = times.reset(entry.resetAt)
        var notes: [SectionNote] = []
        var spoken = "\(name), \(headline) tokens \(period), \(resetText)"
        var valueLine: String?
        var valueTooltip: String?
        switch value {
        case .none:
            break
        case .missing(let model):
            let note = SectionNote.valueAsMissing(model: model)
            notes.append(note)
            spoken += ", \(note.text)"
        case .value(let amount, let model):
            let shown = Self.amount(amount, locale: times.locale)
            valueLine = "\u{2248} \(shown.visible) at \(model) prices"
            valueTooltip = "What these tokens would have cost at \(model) prices. Nothing was spent."
            spoken += ", \(shown.spoken) at \(model) prices"
        }
        if entry.stale { notes.append(.budgetStale(since: lastSuccessfulRefreshAt, dates: dates)) }
        // The value line sits left of the reset text; without it the period
        // does (walkthrough step 4: one line instead of two).
        return NoLimitPresentation(headline: headline, headlineTooltip: headlineTooltip,
                                   periodLine: valueLine == nil ? period : nil, resetText: resetText,
                                   resetTooltip: times.resetTooltip(entry.resetAt), notes: notes,
                                   showsDetails: !entry.breakdown.isEmpty, valueLine: valueLine, valueTooltip: valueTooltip,
                                   accessibilityLabel: spoken)
    }

    /// The section of No limit account `account` in `snapshot`, as the
    /// dropdown and the demo coverage test build it: the account's entry,
    /// its tokens valued at the Value as model's prices in `prices`, the
    /// effective price table of the Prices tab (research R4), and the notes
    /// of the snapshot, "Refreshing…" without one (spec 041 FR-011 to
    /// FR-015b, FR-022). Nil for an account without No limit.
    public static func make(account: Account, snapshot: UsageSnapshot?, prices: PriceTable, times: TimeText,
                            dates: NoteDates) -> NoLimitPresentation? {
        guard let settings = account.kind.tokenBased, settings.noLimit != nil else { return nil }
        let entry = snapshot?.noLimitAccounts[account.id]
        return make(name: account.displayName, entry: entry,
                    value: ReferenceValue.make(breakdown: entry?.breakdown.perModel ?? [], valueAs: settings.valueAs, prices: prices),
                    times: times, lastSuccessfulRefreshAt: snapshot?.lastSuccessfulRefreshAt,
                    isPreliminary: snapshot?.isPreliminary ?? true, dates: dates)
    }

    /// Whole US dollars in the locale's currency format: "$0" for exactly
    /// 0, "<$1" above 0 and below one dollar, otherwise rounded half up
    /// ("$412"), never to even (FR-012, clarification 1). The spoken form
    /// reads "about $412" or "less than $1".
    static func amount(_ value: Decimal, locale: Locale) -> (visible: String, spoken: String) {
        if value > 0 && value < 1 {
            let one = BudgetAmountFormatter.wholeAmount(1, locale: locale)
            return ("<\(one)", "less than \(one)")
        }
        let text = BudgetAmountFormatter.wholeAmount(value, locale: locale)
        return (text, "about \(text)")
    }
}
