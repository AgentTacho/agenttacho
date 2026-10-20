import Foundation
import Testing
@testable import UsageCore

/// spec 030 FR-012: a budget's dollar line
/// in the chosen direction.
@Suite struct BudgetAmountLineTests {
    static func text(_ line: BudgetAmountLine) -> String {
        line.text(amount: { "$\($0)" }, budget: "$100", period: "week")
    }

    static func line(_ spent: Decimal, budget: Decimal = 100, rounded: Int? = nil, _ direction: DisplayDirection) -> BudgetAmountLine {
        BudgetAmountLine.make(spent: spent, budget: budget,
                              roundedPercent: rounded ?? PercentFormatter.rounded(spent: spent, budget: budget), direction: direction)
    }

    /// The contract table.
    @Test func contractTable() {
        #expect(Self.line(40, .used) == .of(spent: 40))
        #expect(Self.text(Self.line(40, .used)) == "$40 of $100/week")
        #expect(Self.line(40, .remaining) == .left(60))
        #expect(Self.text(Self.line(40, .remaining)) == "$60 left of $100/week")
        #expect(Self.text(Self.line(Decimal(string: "100.4")!, .used)) == "$100.4 of $100/week")
        #expect(Self.line(Decimal(string: "100.4")!, .remaining) == .left(0))
        #expect(Self.text(Self.line(Decimal(string: "100.4")!, .remaining)) == "$0 left of $100/week")
        #expect(Self.text(Self.line(115, .used)) == "$115 of $100/week")
        #expect(Self.line(115, .remaining) == .over(15))
        #expect(Self.text(Self.line(115, .remaining)) == "$15 over $100/week")
    }

    /// "over" exactly when the rounded percent is above 100, so the line,
    /// the percent and the bar never disagree.
    @Test func overStartsAboveARoundedHundred() {
        #expect(Self.line(100, rounded: 100, .remaining) == .left(0))
        #expect(Self.line(Decimal(string: "100.6")!, rounded: 101, .remaining) == .over(Decimal(string: "0.6")!))
    }

    /// A budget of 0 or less keeps today's line in both directions.
    @Test func noPositiveBudgetKeepsTheUsedLine() {
        for direction in DisplayDirection.allCases {
            #expect(Self.line(5, budget: 0, rounded: 0, direction) == .of(spent: 5))
            #expect(BudgetAmountLine.make(spent: 5, budget: 0, roundedPercent: 0, direction: direction)
                .text(amount: { "$\($0)" }, budget: "$0", period: "week") == "$5 of $0/week")
            #expect(Self.line(5, budget: -10, rounded: 0, direction) == .of(spent: 5))
        }
    }
}
