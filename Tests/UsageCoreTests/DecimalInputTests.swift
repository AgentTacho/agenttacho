import Foundation
import Testing
@testable import UsageCore

/// Idea inbox english-number-format: number fields show English numbers but
/// accept a decimal comma, so typing "99,50" or the decimal key of a German
/// keyboard keeps working.
@Suite struct DecimalInputTests {
    static func parse(_ text: String) -> Decimal? {
        try? DecimalInputFormat().parseStrategy.parse(text)
    }

    @Test func englishInput() {
        #expect(Self.parse("99.5") == Decimal(string: "99.5"))
        #expect(Self.parse("1,234.5") == Decimal(string: "1234.5"))
        #expect(Self.parse("1234") == 1234)
        #expect(Self.parse(" 60 ") == 60)
    }

    /// A single comma with one, two, four to six digits after it, or after
    /// a leading 0, is a decimal comma.
    @Test func decimalComma() {
        #expect(Self.parse("99,50") == Decimal(string: "99.5"))
        #expect(Self.parse("3,75") == Decimal(string: "3.75"))
        #expect(Self.parse("0,375") == Decimal(string: "0.375"))
        #expect(Self.parse(",5") == Decimal(string: "0.5"))
        #expect(Self.parse("0,000125") == Decimal(string: "0.000125"))
    }

    /// German grouping with a decimal comma.
    @Test func germanGrouping() {
        #expect(Self.parse("1.234,50") == Decimal(string: "1234.5"))
    }

    /// Three digits after a single comma read as English grouping.
    @Test func threeDigitsAfterACommaAreGrouping() {
        #expect(Self.parse("1,234") == 1234)
    }

    @Test func invalidInputThrows() {
        #expect(Self.parse("abc") == nil)
        #expect(Self.parse("") == nil)
    }

    /// The field shows English numbers.
    @Test func formatsInEnglish() {
        #expect(DecimalInputFormat().format(Decimal(string: "1234.5")!) == "1,234.5")
        #expect(DecimalInputFormat(maxFractionDigits: 2).format(Decimal(string: "99.505")!) == "99.5")
        #expect(DecimalInputFormat().format(Decimal(string: "0.000125")!) == "0.000125")
    }
}
