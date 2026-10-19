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
