import Foundation
import Testing
@testable import UsageCore

/// Spec 044 FR-013, research R5, contracts/ui-strings.md "Dropdown: member
/// lines": a member line's trailing text, tooltip and accessibility text,
/// with the share for a group with an amount and without it for a group
/// without one.
@Suite struct MemberLineTextTests {
    static let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A member's priced entry, as the aggregator builds it for a group member.
    static func member(_ records: [UsageRecord]) -> TokenAccountEntry {
        let breakdown = Aggregator().breakdown(of: records, priced: true, window: month,
                                               lastDay: isoDate("2026-10-13T00:00:00Z"), calendar: utc)
        return TokenAccountEntry(breakdown: breakdown, incomplete: records.contains { !$0.isPriced },
                                 unpricedTokens: records.filter { !$0.isPriced }.reduce(0) { $0 + $1.totalTokens })
    }

    static func priced(_ cost: String, tokens: Int = 1_000) -> UsageRecord {
        makeRecord(id: "p-\(cost)", accountId: "m", model: "claude-opus-5-5", timestamp: isoDate("2026-10-05T10:00:00Z"),
                   input: tokens, cost: Decimal(string: cost)!)
    }

    static func unpriced(_ tokens: Int) -> UsageRecord {
        makeRecord(id: "u-\(tokens)", accountId: "m", model: "gateway-a/open-model-7b", timestamp: isoDate("2026-10-06T10:00:00Z"),
                   input: tokens, cost: nil)
    }

    /// A group with an amount; the recorded spend is the member's own.
    static func share(_ member: TokenAccountEntry, budget: Decimal) -> MemberLineText {
        MemberLineText.withAmount(member: member, budgetUSD: budget, recordedSpendUSD: member.breakdown.spentUSD, period: .monthly)
    }

    /// A group without an amount, monthly.
    static func make(_ member: TokenAccountEntry, _ measure: HeadlineMeasure) -> MemberLineText {
        MemberLineText.withoutAmount(member: member, measure: measure, period: .monthly)
    }

    // MARK: With an amount (unchanged)

    /// Spend and share, whatever the Show setting and the direction: the
    /// rule takes neither (spec 004 FR-018a, spec 030).
    @Test func withAnAmountTheShareStays() {
        let line = Self.share(Self.member([Self.priced("181.40")]), budget: 500)
        #expect(line.text == "$181 (36%)")
        #expect(line.tooltip == "$181.40 spent this month, 36% of the $500 budget")
        #expect(line.accessibility == line.tooltip)
    }

    /// The whole dollars keep the line's rounding, half to even, as before
    /// this feature (spec 004 FR-018a).
    @Test func withAnAmountTheWholeDollarsRoundAsBefore() {
        #expect(Self.share(Self.member([Self.priced("180.50")]), budget: 500).text == "$180 (36%)")
        #expect(Self.share(Self.member([Self.priced("0.62")]), budget: 500).text == "$1 (0%)")
    }

    /// The share comes from the spend the group's entry records, as the
    /// bar's share does (`GroupEntry.memberPercent`), not from the member's
    /// own breakdown (spec 004 FR-018a).
    @Test func withAnAmountTheShareUsesTheRecordedSpend() {
        let line = MemberLineText.withAmount(member: Self.member([Self.priced("181.40")]), budgetUSD: 500,
                                             recordedSpendUSD: 250, period: .monthly)
        #expect(line.text == "$181 (50%)")
        #expect(line.tooltip == "$181.40 spent this month, 50% of the $500 budget")
    }

    /// Group values computed before the member joined: no share, as the
    /// bar shows a placeholder (spec 004 FR-018).
    @Test func withAnAmountButNoRecordedSpendThereIsNoShare() {
        let line = MemberLineText.withAmount(member: Self.member([Self.priced("181.40")]), budgetUSD: 500,
                                             recordedSpendUSD: nil, period: .monthly)
        #expect(line.text == "$181")
        #expect(line.tooltip == "$181.40 spent this month")
    }

    /// A model with priced and unpriced records counts with its full priced
    /// spend: the line reads every priced record, not only the models whose
    /// records are all priced (spec 044 FR-013, review-code decision
    /// 2026-11-10).
    @Test func withAnAmountAModelWithUnpricedRecordsCountsItsPricedSpend() {
        let unpricedSameModel = makeRecord(id: "same", accountId: "m", model: "claude-opus-5-5",
                                           timestamp: isoDate("2026-10-07T10:00:00Z"), input: 2_000, cost: nil)
        let member = Self.member([Self.priced("181.40"), unpricedSameModel])
        // The per-model cost leaves the mixed model out; the line must not.
        #expect(member.breakdown.pricedCostUSD == 0)
        let line = Self.share(member, budget: 500)
        #expect(line.text == "$181 (36%)")
        #expect(line.tooltip == "$181.40 spent this month, 36% of the $500 budget")
    }

    // MARK: Without an amount, Money

    @Test func moneyShowsTheSpendWithoutAShare() {
        let line = Self.make(Self.member([Self.priced("92.84")]), .money)
        #expect(line.text == "$93")
        #expect(line.tooltip == "$92.84 spent this month")
        #expect(line.accessibility == line.tooltip)
        #expect(Self.make(Self.member([Self.priced("0.62")]), .money).text == "<$1")
        #expect(Self.make(Self.member([]), .money).text == "$0")
        #expect(Self.make(Self.member([]), .money).tooltip == "$0 spent this month")
    }

    /// FR-013: a member with only unpriced records reads its real spend,
    /// and the tooltip names the tokens without a price.
    @Test func onlyUnpricedRecordsReadZeroWithTheirTokens() {
        let line = Self.make(Self.member([Self.unpriced(48_200_000)]), .money)
        #expect(line.text == "$0")
        #expect(line.tooltip == "$0 spent this month, 48.2 million tokens without a price")
        #expect(line.accessibility == line.tooltip)
        let mixed = Self.make(Self.member([Self.priced("92.84"), Self.unpriced(950_000)]), .money)
        #expect(mixed.text == "$93")
        #expect(mixed.tooltip == "$92.84 spent this month, 950,000 tokens without a price")
        // A model with priced and unpriced records: only the unpriced
        // records' tokens count, as the group's unpriced usage counts them.
        let sameModel = makeRecord(id: "same", accountId: "m", model: "claude-opus-5-5", timestamp: isoDate("2026-10-07T10:00:00Z"),
                                   input: 2_000, cost: nil)
        let split = Self.make(Self.member([Self.priced("92.84", tokens: 1_000_000), sameModel]), .money)
        #expect(split.tooltip == "$92.84 spent this month, 2,000 tokens without a price")
    }

    // MARK: Without an amount, Tokens

    @Test func tokensShowTheTokenCount() {
        let line = Self.make(Self.member([Self.unpriced(48_200_000)]), .tokens)
        #expect(line.text == "48.2M")
        #expect(line.tooltip == "48.2 million tokens this month")
        #expect(line.accessibility == line.tooltip)
        let weekly = MemberLineText.withoutAmount(member: Self.member([Self.priced("3", tokens: 950_000)]), measure: .tokens,
                                                  period: .weekly)
        #expect(weekly.text == "950K")
        #expect(weekly.tooltip == "950,000 tokens this week")
    }

    /// Member lines never show "≈", and no share without an amount.
    @Test func noApproximationAndNoShareWithoutAnAmount() {
        let members = [Self.member([Self.unpriced(48_200_000)]), Self.member([Self.priced("92.84"), Self.unpriced(10)]), Self.member([])]
        for member in members {
            for measure in [HeadlineMeasure.money, .tokens] {
                let line = Self.make(member, measure)
                for text in [line.text, line.tooltip, line.accessibility] {
                    #expect(!text.contains("\u{2248}"))
                    #expect(!text.contains("%"))
                }
            }
        }
    }

    // MARK: All lines of a section

    /// The lines follow `MemberDisplay` in member order and each takes the
    /// section's rule (spec 044 FR-013, FR-024).
    @Test func linesFollowTheDisplayRuleAndTheSectionRule() {
        let a = Self.member([Self.priced("181.40")])
        let b = Self.member([Self.unpriced(48_200_000)])
        let usage = ["a": a, "b": b]
        let noLimit = MemberLineText.lines(memberIds: ["b", "x", "a"], usage: usage, rule: .measure(.money), period: .monthly)
        #expect(noLimit.map(\.id) == ["b", "a"])
        #expect(noLimit.map(\.text) == [Self.make(b, .money), Self.make(a, .money)])
        let share = MemberLineText.lines(memberIds: ["a", "b"], usage: usage,
                                         rule: .share(budgetUSD: 500, recordedSpendUSD: ["a": 250]), period: .monthly)
        #expect(share.map(\.text.text) == ["$181 (50%)", "$0"])
        // A single member has no line (spec 025 FR-010).
        #expect(MemberLineText.lines(memberIds: ["a"], usage: usage, rule: .measure(.tokens), period: .monthly).isEmpty)
    }
}
