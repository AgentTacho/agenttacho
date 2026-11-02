import Foundation
import Testing
@testable import UsageCore

/// spec 026 FR-009, research R2: the compact formats of the day row, moved
/// from the app's `UsageFormat` into core with today's outputs.
@Suite struct CompactFormatTests {
    static let locale = Locale(identifier: "en_US")

    @Test func millionsKeepTodaysOutputs() {
        #expect(CompactFormat.millions(0, locale: Self.locale) == "0")
        #expect(CompactFormat.millions(1, locale: Self.locale) == "<1")
        #expect(CompactFormat.millions(499_999, locale: Self.locale) == "<1")
        #expect(CompactFormat.millions(500_000, locale: Self.locale) == "1")
        #expect(CompactFormat.millions(188_400_000, locale: Self.locale) == "188")
        #expect(CompactFormat.millions(1_000_000_000, locale: Self.locale) == "1,000")
    }

    @Test func usdKeepsTodaysOutputs() {
        #expect(CompactFormat.usd(0, locale: Self.locale) == "0")
        #expect(CompactFormat.usd(Decimal(string: "0.4")!, locale: Self.locale) == "<1")
        #expect(CompactFormat.usd(409, locale: Self.locale) == "409")
        #expect(CompactFormat.usd(Decimal(string: "999.4")!, locale: Self.locale) == "999")
        #expect(CompactFormat.usd(1_596, locale: Self.locale) == "1.6K")
    }

    /// The edges FR-009 names: an amount that rounds to 0 reads "<1", never
    /// "0" like a day without usage, and an amount that rounds to 1,000
    /// already reads "1K", never "1,000".
    @Test func usdBoundariesFollowTheRoundedValue() {
        #expect(CompactFormat.usd(Decimal(string: "0.49")!, locale: Self.locale) == "<1")
        #expect(CompactFormat.usd(Decimal(string: "0.5")!, locale: Self.locale) == "<1")
        #expect(CompactFormat.usd(Decimal(string: "0.51")!, locale: Self.locale) == "1")
        #expect(CompactFormat.usd(Decimal(string: "999.5")!, locale: Self.locale) == "1K")
        #expect(CompactFormat.usd(Decimal(string: "999.99")!, locale: Self.locale) == "1K")
        #expect(CompactFormat.usd(1_000, locale: Self.locale) == "1K")
    }

    /// The passed locale decides the grouping separator.
    @Test func formatsFollowThePassedLocale() {
        let german = Locale(identifier: "de_DE")
        #expect(CompactFormat.millions(1_000_000_000, locale: german) == "1.000")
        #expect(CompactFormat.usd(Decimal(string: "999.4")!, locale: german) == "999")
        #expect(CompactFormat.usd(1_596, locale: german) != CompactFormat.usd(1_596, locale: Self.locale))
    }
}

/// Spec 041 research R7: the token total of the dropdown, moved from the
/// app's `UsageFormat.tokens` into core with today's outputs.
@Suite struct CompactTokensFormatTests {
    static let locale = Locale(identifier: "en_US")

    @Test func tokensInCompactNotation() {
        #expect(CompactFormat.tokens(48_200_000, locale: Self.locale) == "48.2M")
        #expect(CompactFormat.tokens(950_000, locale: Self.locale) == "950K")
        #expect(CompactFormat.tokens(0, locale: Self.locale) == "0")
        #expect(CompactFormat.tokens(1_200_000_000, locale: Self.locale) == "1.2B")
    }

    /// The same output as the formatting `UsageFormat.tokens` used before.
    @Test(arguments: [0, 7, 999, 1_000, 1_049, 12_345, 950_000, 999_999, 1_000_000, 48_200_000, 48_260_000, 1_200_000_000])
    func sameAsTheFormerAppFormat(value: Int) {
        let former = value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Self.locale))
        #expect(CompactFormat.tokens(value, locale: Self.locale) == former)
    }
}
