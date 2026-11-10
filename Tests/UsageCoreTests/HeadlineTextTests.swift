import Foundation
import Testing
@testable import UsageCore

/// Spec 043 FR-013, FR-016, research R6, contracts/ui-strings.md: the
/// headline, its tooltip and its accessibility text for each measure.
@Suite struct HeadlineTextTests {
    static func d(_ text: String) -> Decimal { Decimal(string: text)! }

    // MARK: Tokens

    @Test func tokensMonthly() {
        let h = HeadlineText.tokens(48_213_507, period: .monthly)
        #expect(h.text == "48.2M")
        // A million or more reads with its scale word, not 8 digits (walkthrough step 4).
        #expect(h.tooltip == "48.2 million tokens this month")
        #expect(h.accessibilityText == "48.2 million tokens this month")
    }

    @Test func tokensTooltipScale() {
        #expect(HeadlineText.tokens(1_200_000_000, period: .monthly).tooltip == "1.2 billion tokens this month")
        #expect(HeadlineText.tokens(1_000_000, period: .monthly).tooltip == "1 million tokens this month")
        #expect(HeadlineText.tokens(999_999, period: .monthly).tooltip == "999,999 tokens this month")
    }

    @Test func tokensWeekly() {
        let h = HeadlineText.tokens(950_000, period: .weekly)
        #expect(h.text == "950K")
        #expect(h.tooltip == "950,000 tokens this week")
        #expect(h.accessibilityText == "950 thousand tokens this week")
    }

    /// The compact count spelled with its scale word.
    @Test(arguments: [
        (1_200_000_000, "1.2 billion tokens this month"),
        (48_213_507, "48.2 million tokens this month"),
        (1_500, "1.5 thousand tokens this month"),
        (999, "999 tokens this month"),
        (0, "0 tokens this month"),
    ])
    func spokenTokenCounts(total: Int, spoken: String) {
        #expect(HeadlineText.tokens(total, period: .monthly).accessibilityText == spoken)
    }

    @Test func zeroTokens() {
        let h = HeadlineText.tokens(0, period: .weekly)
        #expect(h.text == "0")
        #expect(h.tooltip == "0 tokens this week")
    }

    // MARK: Money, spent

    @Test func moneySpent() {
        let h = HeadlineText.spent(Self.d("37.42"), period: .monthly)
        #expect(h.text == "$37")
        #expect(h.tooltip == "$37.42 spent this month")
        #expect(h.accessibilityText == "$37.42 spent this month")
    }

    @Test(arguments: [("37.50", "$38"), ("37.49", "$37"), ("0", "$0"), ("0.40", "<$1"), ("0.99", "<$1"), ("1", "$1"), ("1234.50", "$1,235")])
    func moneyRoundsHalfUp(amount: String, text: String) {
        #expect(HeadlineText.spent(Self.d(amount), period: .monthly).text == text)
    }

    /// The cents round half up, never to even (SC-004).
    @Test(arguments: [("0.125", "$0.13"), ("0.135", "$0.14"), ("37.425", "$37.43")])
    func centsRoundHalfUp(amount: String, cents: String) {
        #expect(HeadlineText.spent(Self.d(amount), period: .monthly).tooltip == "\(cents) spent this month")
    }

    @Test func moneySpentWeekly() {
        let h = HeadlineText.spent(Self.d("5.1"), period: .weekly)
        #expect(h.text == "$5")
        #expect(h.tooltip == "$5.10 spent this week")
        #expect(h.accessibilityText == "$5.10 spent this week")
    }

    // MARK: Money with an amount (spec 030 FR-012)

    static func money(_ spent: String, budget: Decimal = 100, period: BudgetPeriod = .monthly,
                      direction: DisplayDirection) -> HeadlineText {
        let spentUSD = d(spent)
        return HeadlineText.money(spent: spentUSD, budget: budget,
                                  roundedPercent: PercentFormatter.rounded(spent: spentUSD, budget: budget),
                                  period: period, direction: direction)
    }

    @Test func moneyUsedModeIsTheSpend() {
        let h = Self.money("37.42", direction: .used)
        #expect(h == HeadlineText.spent(Self.d("37.42"), period: .monthly))
    }

    @Test func moneyRemainingLeft() {
        let h = Self.money("37.42", direction: .remaining)
        #expect(h.text == "$63")
        #expect(h.tooltip == "$62.58 left of $100/month")
        #expect(h.accessibilityText == "$62.58 left of $100/month")
    }

    @Test func moneyRemainingOver() {
        let h = Self.money("112.40", direction: .remaining)
        #expect(h.text == "\u{2212}$12")
        #expect(h.tooltip == "$12.40 over $100/month")
        #expect(h.accessibilityText == "$12.40 over $100/month")
    }

    @Test func moneyRemainingBelowOneDollar() {
        #expect(Self.money("99.60", direction: .remaining).text == "<$1")
        #expect(Self.money("99.60", direction: .remaining).tooltip == "$0.40 left of $100/month")
        // Rounded 101% used, so over (spec 030 FR-012).
        #expect(Self.money("100.60", direction: .remaining).text == "\u{2212}<$1")
        #expect(Self.money("100.60", direction: .remaining).tooltip == "$0.60 over $100/month")
    }

    @Test func moneyRemainingWeeklyBudgetWithCents() {
        let h = Self.money("10", budget: Self.d("50.5"), period: .weekly, direction: .remaining)
        #expect(h.text == "$41")
        #expect(h.tooltip == "$40.50 left of $50.50/week")
    }

    /// A Money headline never shows "≈" (FR-013, SC-004).
    @Test func noMoneyOutputContainsApproximately() {
        let outputs = [Self.money("37.42", direction: .used), Self.money("37.42", direction: .remaining),
                       Self.money("112.4", direction: .remaining), HeadlineText.spent(0, period: .weekly),
                       HeadlineText.spent(Self.d("0.4"), period: .monthly)]
        for h in outputs {
            #expect(!h.text.contains("\u{2248}"))
            #expect(!(h.tooltip ?? "").contains("\u{2248}"))
            #expect(!h.accessibilityText.contains("\u{2248}"))
        }
    }

    // MARK: Percent

    /// Percent delegates to `DirectedPercent` unchanged.
    @Test(arguments: [DisplayDirection.used, .remaining])
    func percentIsDirectedPercent(direction: DisplayDirection) {
        for used in [37, 100, 115] {
            let directed = DirectedPercent(usedPercent: used, direction: direction)
            let h = HeadlineText.percent(usedPercent: used, direction: direction)
            #expect(h.text == directed.text)
            #expect(h.tooltip == nil)
            #expect(h.accessibilityText == directed.accessibilityText(.budget))
        }
    }
}

/// Spec 043 FR-013, FR-014, FR-018a, research R6: the headline of a budget
/// section with an amount, from the account's Show setting.
@Suite struct BudgetHeadlineTextTests {
    static let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    /// 37.42 US$ of 100 US$ this month, 3,000,000 tokens.
    static func entry(spent: String = "37.42") -> GroupEntry {
        let spentUSD = Decimal(string: spent)!
        return GroupEntry(spentUSD: spentUSD, budgetUSD: 100, percent: PercentFormatter.rounded(spent: spentUSD, budget: 100),
                          incomplete: false, period: .monthly, window: month,
                          breakdown: UsageBreakdown(perModel: [ModelUsage(model: "claude-opus-5-5", inputTokens: 2_000_000,
                                                                           outputTokens: 1_000_000, costUSD: spentUSD)]),
                          members: ["own"])
    }

    /// Story 3 scenario 2: Automatic and Percent give today's percent.
    @Test(arguments: [DropdownShow.automatic, .percent])
    func automaticAndPercentGiveThePercent(show: DropdownShow) {
        for direction in [DisplayDirection.used, .remaining] {
            #expect(HeadlineText.budget(entry: Self.entry(), show: show, direction: direction)
                    == HeadlineText.percent(usedPercent: 37, direction: direction))
        }
        #expect(HeadlineText.budget(entry: Self.entry(), show: show, direction: .used).text == "37%")
    }

    /// Story 3 scenario 3: Tokens gives the entry's token total, also in
    /// remaining mode.
    @Test(arguments: [DisplayDirection.used, .remaining])
    func tokensGiveTheTokenTotal(direction: DisplayDirection) {
        #expect(HeadlineText.budget(entry: Self.entry(), show: .tokens, direction: direction)
                == HeadlineText.tokens(3_000_000, period: .monthly))
    }

    /// Story 3 scenario 3 and clarification 4: Money gives the spend, or what
    /// is left or over in remaining mode.
    @Test func moneyGivesSpendLeftOrOver() {
        #expect(HeadlineText.budget(entry: Self.entry(), show: .money, direction: .used).text == "$37")
        let left = HeadlineText.budget(entry: Self.entry(), show: .money, direction: .remaining)
        #expect(left.text == "$63")
        #expect(left.tooltip == "$62.58 left of $100/month")
        let over = HeadlineText.budget(entry: Self.entry(spent: "112.40"), show: .money, direction: .remaining)
        #expect(over.text == "\u{2212}$12")
        #expect(over.accessibilityText == "$12.40 over $100/month")
    }

    /// A group with Automatic shows the percent, as before.
    @Test func groupSectionsUsePercent() {
        #expect(HeadlineText.budget(entry: Self.entry(spent: "115"), show: .automatic, direction: .remaining).text == "\u{2212}15%")
    }
}

/// Spec 044 FR-012, FR-013, review-spec decision: a group with an amount and
/// a stored Show setting changes only its headline; member lines keep spend
/// and share, and the Details stay cost tables.
@Suite struct GroupWithAmountShowTests {
    typealias Base = BudgetHeadlineTextTests

    /// 181.40 US$ of a member in a group with 500 US$, as the group entry
    /// records it.
    static let member = MemberLineTextTests.member([MemberLineTextTests.priced("181.40", tokens: 3_000_000)])

    @Test func tokensShowGivesTheTokenHeadline() {
        for direction in DisplayDirection.allCases {
            #expect(HeadlineText.budget(entry: Base.entry(), show: .tokens, direction: direction)
                    == HeadlineText.tokens(3_000_000, period: .monthly))
        }
    }

    /// Money reads the spend, or in remaining mode what is left or over
    /// (spec 043 FR-013).
    @Test func moneyShowGivesSpendOrRemaining() {
        #expect(HeadlineText.budget(entry: Base.entry(), show: .money, direction: .used).text == "$37")
        #expect(HeadlineText.budget(entry: Base.entry(), show: .money, direction: .remaining).text == "$63")
    }

    /// The share rule takes no measure and no direction, so whatever the
    /// Show setting resolves to, member lines keep spend and share.
    @Test func memberLinesStayAsUnderAutomatic() {
        let lines = MemberLineText.lines(memberIds: ["m", "n"], usage: ["m": Self.member],
                                         rule: .share(budgetUSD: 500, recordedSpendUSD: ["m": Decimal(string: "181.40")!]),
                                         period: .monthly)
        #expect(lines.map(\.text.text) == ["$181 (36%)"])
    }
}
