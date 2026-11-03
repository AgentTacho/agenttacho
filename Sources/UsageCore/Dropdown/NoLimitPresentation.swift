import Foundation

/// The texts of the dropdown section of an own budget without an amount,
/// decided here; the view only renders them (spec 043 FR-007, FR-011 to
/// FR-016, spec 041 FR-011 to FR-015b, contracts/ui-strings.md).
public struct NoLimitPresentation: Equatable, Sendable {
    /// The measure of the headline after Automatic and the amount rule are
    /// applied (spec 043 FR-011, FR-012); nil without an entry.
    public let measure: HeadlineMeasure?
    /// The token total ("48.2M", "0") or the real spend in whole dollars
    /// ("$37", "<$1"), without a unit; nil without an entry (FR-013).
    public let headline: String?
    /// The count with unit and period ("48.2 million tokens this month",
    /// the exact count below a million) or the exact spend ("$37.42 spent
    /// this month"), the headline's tooltip; nil without an entry (FR-013).
    public let headlineTooltip: String?
    /// "this week" / "this month" under a Tokens headline, "spent this
    /// week" / "spent this month" under a Money headline, left of the reset
    /// text when there is no value line; nil with a value line or without
    /// an entry (FR-014).
    public let periodLine: String?
    /// The reset time in the section's time format, and its other form as
    /// tooltip (spec 025 FR-016, FR-019).
    public let resetText: String?
    public let resetTooltip: String?
    /// The missing-model note, the "incomplete, unpriced" note under a
    /// Money headline without a valuing Value as model (FR-007), and the
    /// stale and no-data notes of an own budget's section (spec 041 FR-015b).
    public let notes: [SectionNote]
    /// True when the "incomplete, unpriced" note is shown, so the Details'
    /// Σ tooltip matches it (FR-007, FR-014).
    public let incomplete: Bool
    /// True when the period has usage; a section without usage has no
    /// Details (spec 041 FR-014).
    public let showsDetails: Bool
    /// True when the Details show the cost per model, under a Money
    /// headline; tokens under a Tokens headline (FR-014).
    public let showsCost: Bool
    /// "≈ $412 at claude-opus-5-5 prices", nil without a value (FR-014,
    /// FR-015, spec 041 FR-012).
    public let valueLine: String?
    /// What the value means, nil without a value line (FR-015).
    public let valueTooltip: String?
    /// Name, the headline's spoken text, the reset time and the value or
    /// the missing-model note (FR-016).
    public let accessibilityLabel: String

    /// The presentation of `entry` with the account's Show setting, nil
    /// headline before the first result of a refresh. The notes follow an
    /// own budget's section: stale since the last successful refresh, or
    /// "No data" / "Refreshing…" without an entry (spec 025 FR-029). `value`
    /// adds the value line, or the neutral missing-model note in its place
    /// (spec 041 FR-012, FR-013).
    public static func make(name: String, entry: NoLimitEntry?, show: DropdownShow = .automatic, value: ReferenceValue = .none,
                            times: TimeText, lastSuccessfulRefreshAt: Date?, isPreliminary: Bool,
                            dates: NoteDates) -> NoLimitPresentation {
        guard let entry else {
            let notes = [SectionNote.noData(isPreliminary: isPreliminary)]
            return NoLimitPresentation(measure: nil, headline: nil, headlineTooltip: nil, periodLine: nil, resetText: nil, resetTooltip: nil,
                                       notes: notes, incomplete: false, showsDetails: false, showsCost: false, valueLine: nil,
                                       valueTooltip: nil, accessibilityLabel: ([name] + notes.map(\.text)).joined(separator: ", "))
        }
        // A stored Percent shows what Automatic would (FR-012).
        let measure = show.resolve(hasAmount: false, hasPricedUsage: entry.hasPricedUsage)
        let headline = measure == .money ? HeadlineText.spent(entry.spentUSD, period: entry.period)
                                         : HeadlineText.tokens(entry.totalTokens, period: entry.period)
        let thisPeriod = HeadlineText.thisPeriod(entry.period)
        let resetText = times.reset(entry.resetAt)
        var notes: [SectionNote] = []
        var spoken = "\(name), \(headline.accessibilityText), \(resetText)"
        var valueLine: String?
        var valueTooltip: String?
        // The unpriced records are incomplete spend under Money, unless a
        // Value as model with a price values them (FR-007).
        var valued = false
        switch value {
        case .none:
            break
        case .missing(let model):
            let note = SectionNote.valueAsMissing(model: model)
            notes.append(note)
            spoken += ", \(note.text)"
        case .value(let amount, let model):
            valued = true
            let shown = BudgetAmountFormatter.wholeDollars(amount)
            valueLine = "\u{2248} \(shown.visible) at \(model) prices"
            valueTooltip = entry.hasPricedUsage
                ? "What the tokens of models without a price would have cost at \(model) prices. Nothing was spent for them."
                : "What these tokens would have cost at \(model) prices. Nothing was spent."
            spoken += ", \(shown.spoken) at \(model) prices"
        }
        let incomplete = measure == .money && !valued && !entry.unpricedModels.isEmpty
        if incomplete { notes.append(.budgetIncomplete(unpricedModels: entry.unpricedModels)) }
        if entry.stale { notes.append(.budgetStale(since: lastSuccessfulRefreshAt, dates: dates)) }
        // The value line sits left of the reset text; without it the period
        // does (spec 041 walkthrough step 4: one line instead of two).
        let periodLine = measure == .money ? "spent \(thisPeriod)" : thisPeriod
        return NoLimitPresentation(measure: measure, headline: headline.text, headlineTooltip: headline.tooltip,
                                   periodLine: valueLine == nil ? periodLine : nil, resetText: resetText,
                                   resetTooltip: times.resetTooltip(entry.resetAt), notes: notes, incomplete: incomplete,
                                   showsDetails: !entry.breakdown.isEmpty, showsCost: measure == .money,
                                   valueLine: valueLine, valueTooltip: valueTooltip, accessibilityLabel: spoken)
    }

    /// The section of the own budget without an amount `account` in
    /// `snapshot`, as the dropdown and the demo coverage test build it: the
    /// account's entry and Show setting, its unpriced records valued at the
    /// Value as model's prices in `prices`, the effective price table of
    /// the Prices tab (spec 041 research R4, spec 043 R5), and the notes of
    /// the snapshot, "Refreshing…" without one. Nil for an account with an
    /// amount or in a group.
    public static func make(account: Account, snapshot: UsageSnapshot?, prices: PriceTable, times: TimeText,
                            dates: NoteDates) -> NoLimitPresentation? {
        guard let settings = account.kind.tokenBased, settings.noLimit != nil else { return nil }
        let entry = snapshot?.noLimitAccounts[account.id]
        return make(name: account.displayName, entry: entry, show: settings.show,
                    value: ReferenceValue.make(unpricedUsage: entry?.unpricedUsage ?? [], valueAs: settings.valueAs, prices: prices),
                    times: times, lastSuccessfulRefreshAt: snapshot?.lastSuccessfulRefreshAt,
                    isPreliminary: snapshot?.isPreliminary ?? true, dates: dates)
    }
}
