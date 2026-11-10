import Foundation

/// The trailing text, tooltip and accessibility text of one member line in
/// a group's dropdown section (spec 044 FR-013, FR-015, research R5,
/// contracts/ui-strings.md "Dropdown: member lines"). Which lines appear is
/// `MemberDisplay`'s rule (spec 025 FR-010, spec 026); this decides what
/// each says.
public struct MemberLineText: Equatable, Sendable {
    /// "$181 (36%)" with an amount; "$93", "<$1", "$0" or "48.2M" without.
    public let text: String
    /// The exact amount or token count with the period.
    public let tooltip: String
    /// The same words as the tooltip (FR-013).
    public let accessibility: String

    public init(text: String, tooltip: String, accessibility: String) {
        self.text = text
        self.tooltip = tooltip
        self.accessibility = accessibility
    }

    /// Which of the two member line rules a group section follows (spec 044
    /// FR-013).
    public enum Rule: Equatable, Sendable {
        /// A group with an amount: spend and share of `budgetUSD`, the
        /// share from the spend the group's entry records per member id
        /// (`GroupEntry.memberSpendUSD`).
        case share(budgetUSD: Decimal, recordedSpendUSD: [String: Decimal])
        /// A group without an amount: the group's resolved headline measure.
        case measure(HeadlineMeasure)
    }

    /// One member line of a group section, keyed by the member's id.
    public struct Line: Equatable, Sendable {
        public let id: String
        public let text: MemberLineText
    }

    /// Every member line of a group section in member order: the members
    /// `MemberDisplay` gives a line (spec 004 FR-018a, spec 025 FR-010),
    /// each with its text by `rule` for the group's `period`. The dropdown
    /// and the demo coverage both use it, so the coverage checks what the
    /// dropdown shows (spec 044 FR-013, FR-024).
    public static func lines(memberIds: [String], usage: [String: TokenAccountEntry], rule: Rule,
                             period: BudgetPeriod) -> [Line] {
        MemberDisplay.make(memberIds: memberIds, usage: usage).lines.compactMap { id in
            guard let member = usage[id] else { return nil }
            switch rule {
            case .share(let budget, let recorded):
                return Line(id: id, text: withAmount(member: member, budgetUSD: budget, recordedSpendUSD: recorded[id],
                                                     period: period))
            case .measure(let measure):
                return Line(id: id, text: withoutAmount(member: member, measure: measure, period: period))
            }
        }
    }

    /// The line of `member` in a group with the amount `budgetUSD`: the
    /// member's full priced spend (every priced record, spec 044 FR-013,
    /// review-code decision 2026-11-10) and its share, whatever the Show
    /// setting and the direction, since a share of the budget is not a
    /// remaining value (spec 004 FR-018a, spec 030). The share comes from
    /// `recordedSpendUSD`, the member's spend as the group's entry records
    /// it, as the bar's share does; nil when the entry predates the member,
    /// and the line then has no share.
    static func withAmount(member: TokenAccountEntry, budgetUSD: Decimal, recordedSpendUSD: Decimal?,
                                  period: BudgetPeriod) -> MemberLineText {
        let spent = member.breakdown.spentUSD
        let whole = BudgetAmountFormatter.memberSpend(spent)
        let exact = "\(HeadlineText.cents(spent)) spent \(HeadlineText.thisPeriod(period))"
        guard let recorded = recordedSpendUSD else {
            return MemberLineText(text: whole, tooltip: exact, accessibility: exact)
        }
        let share = PercentFormatter.rounded(spent: recorded, budget: budgetUSD)
        let withShare = "\(exact), \(share)% of the \(BudgetAmountFormatter.amount(budgetUSD)) budget"
        return MemberLineText(text: "\(whole) (\(share)%)", tooltip: withShare, accessibility: withShare)
    }

    /// The line of `member` in a group without an amount, in the group's
    /// resolved `measure` (spec 044 FR-013): the real spend in the Money
    /// headline format, naming the tokens without a price in the tooltip,
    /// or the token count; never a share and never "≈".
    static func withoutAmount(member: TokenAccountEntry, measure: HeadlineMeasure,
                                     period: BudgetPeriod) -> MemberLineText {
        switch measure {
        case .money:
            let spent = member.breakdown.spentUSD
            // Exactly 0 reads "$0", as the line does (contracts/ui-strings.md).
            var exact = "\(spent == 0 ? HeadlineText.whole(0) : HeadlineText.cents(spent)) spent \(HeadlineText.thisPeriod(period))"
            // Counted per record, as the group's unpriced usage is.
            if member.unpricedTokens > 0 {
                exact += ", \(HeadlineText.tokenCount(member.unpricedTokens)) tokens without a price"
            }
            return MemberLineText(text: HeadlineText.whole(spent), tooltip: exact, accessibility: exact)
        case .tokens, .percent:
            // Percent never resolves without an amount (spec 043 FR-012).
            let tokens = HeadlineText.tokens(member.breakdown.totalTokens, period: period)
            let exact = tokens.tooltip ?? tokens.accessibilityText
            return MemberLineText(text: tokens.text, tooltip: exact, accessibility: exact)
        }
    }
}
