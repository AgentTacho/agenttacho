import Foundation
import Testing
@testable import UsageCore

/// spec 026 FR-009, FR-009a, research R2, R3: the Σ column of a day row, its
/// value, its tooltip and the row it sits on.
@Suite struct DayRowTotalTests {
    static let locale = Locale(identifier: "en_US")
    static let monday = isoDate("2026-10-19T00:00:00Z")

    static func day(_ offset: Int, tokens: Int = 0, cost: Decimal? = nil) -> DayUsage {
        DayUsage(day: monday.addingTimeInterval(Double(offset) * 86_400), inputTokens: tokens, costUSD: cost)
    }

    // MARK: Value and tooltip

    @Test func tokenRowSumsAllShownDays() {
        let days = [Self.day(0, tokens: 100_000_000), Self.day(1, tokens: 88_712_345), Self.day(2)]
        let total = DayRowTotal.make(days: days, showsCost: false, incomplete: false, locale: Self.locale)
        #expect(total.text == "189")
        #expect(total.tooltip == "Total: 188.7M tokens")
    }

    /// Σ adds all four token kinds, like a day column's value.
    @Test func tokenRowSumsAllFourKinds() {
        let day = DayUsage(day: Self.monday, inputTokens: 1_000_000, outputTokens: 2_000_000,
                           cacheWriteTokens: 3_000_000, cacheReadTokens: 4_000_000)
        let total = DayRowTotal.make(days: [day], showsCost: false, incomplete: false, locale: Self.locale)
        #expect(total.text == "10")
        #expect(total.tooltip == "Total: 10M tokens")
    }

    @Test func smallTokenSumReadsLessThanOne() {
        let total = DayRowTotal.make(days: [Self.day(0, tokens: 120_000)], showsCost: false, incomplete: false, locale: Self.locale)
        #expect(total.text == "<1")
        #expect(total.tooltip == "Total: 0.1M tokens")
    }

    @Test func costRowSumsTheDaysCost() {
        let days = [Self.day(0, tokens: 5, cost: Decimal(string: "1000.40")!), Self.day(1, cost: 596), Self.day(2, cost: nil)]
        let total = DayRowTotal.make(days: days, showsCost: true, incomplete: false, locale: Self.locale)
        #expect(total.text == "1.6K")
        #expect(total.tooltip == "Total: $1,596.40")
    }

    @Test func costBelowAThousandIsWholeDollars() {
        let days = [Self.day(0, cost: Decimal(string: "180.30")!), Self.day(1, cost: Decimal(string: "249.82")!)]
        let total = DayRowTotal.make(days: days, showsCost: true, incomplete: false, locale: Self.locale)
        #expect(total.text == "430")
        #expect(total.tooltip == "Total: $430.12")
    }

    @Test func rowWithoutUsageReadsZero() {
        #expect(DayRowTotal.make(days: [], showsCost: false, incomplete: false, locale: Self.locale).text == "0")
        #expect(DayRowTotal.make(days: [], showsCost: true, incomplete: false, locale: Self.locale).text == "0")
        let zeros = [Self.day(0, cost: 0), Self.day(1, cost: 0)]
        #expect(DayRowTotal.make(days: zeros, showsCost: true, incomplete: false, locale: Self.locale).text == "0")
        #expect(DayRowTotal.make(days: zeros, showsCost: false, incomplete: false, locale: Self.locale).text == "0")
        #expect(DayRowTotal.make(days: zeros, showsCost: false, incomplete: false, locale: Self.locale).tooltip == "Total: 0M tokens")
    }

    @Test func incompleteBudgetAddsTheUnpricedNote() {
        let days = [Self.day(0, cost: Decimal(string: "430.12")!)]
        let total = DayRowTotal.make(days: days, showsCost: true, incomplete: true, locale: Self.locale)
        #expect(total.text == "430")
        #expect(total.tooltip == "Total: $430.12\nincomplete: some usage is unpriced")
    }

    // MARK: Layout

    @Test func weeklyRowIsOneRowWithTheSum() {
        #expect(DayRowLayout.rows(dayCount: 7, monthly: false) == [0..<7])
        #expect(DayRowLayout.sumRowIndex(dayCount: 7, monthly: false) == 0)
        #expect(DayRowLayout.rows(dayCount: 8, monthly: false) == [0..<8])
        #expect(DayRowLayout.sumRowIndex(dayCount: 8, monthly: false) == 0)
    }

    @Test func monthlyRowsWrapAfterSevenDaysWithTheSumOnTheLastRow() {
        #expect(DayRowLayout.rows(dayCount: 28, monthly: true) == [0..<7, 7..<14, 14..<21, 21..<28])
        #expect(DayRowLayout.sumRowIndex(dayCount: 28, monthly: true) == 3)
        #expect(DayRowLayout.rows(dayCount: 30, monthly: true) == [0..<7, 7..<14, 14..<21, 21..<28, 28..<30])
        #expect(DayRowLayout.sumRowIndex(dayCount: 30, monthly: true) == 4)
        #expect(DayRowLayout.rows(dayCount: 31, monthly: true) == [0..<7, 7..<14, 14..<21, 21..<28, 28..<31])
        #expect(DayRowLayout.sumRowIndex(dayCount: 31, monthly: true) == 4)
    }

    @Test func rowWithoutDaysStillHoldsTheSum() {
        #expect(DayRowLayout.rows(dayCount: 0, monthly: false) == [0..<0])
        #expect(DayRowLayout.sumRowIndex(dayCount: 0, monthly: true) == 0)
    }

    // MARK: - Header column and day tooltips (spec 026 FR-009b, FR-009c)

    /// The header column in front of a day row: "Day" over the unit, with
    /// the unit spelled out as tooltip.
    @Test func headerNamesTheUnit() {
        #expect(DayRowHeader.make(showsCost: false) == DayRowHeader(top: "Day", bottom: "Tok", tooltip: "Tokens per day, in millions"))
        #expect(DayRowHeader.make(showsCost: true) == DayRowHeader(top: "Day", bottom: "$", tooltip: "Cost per day, in US$"))
    }

    /// A day's tooltip gives tokens in millions with one decimal, or the
    /// exact cost.
    @Test func dayTooltipUsesMillions() {
        let day = Self.day(0, tokens: 42_345_678)
        let date = day.day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Self.locale, timeZone: TimeZone(identifier: "UTC")!))
        #expect(DayRowHeader.dayTooltip(day, showsCost: false, locale: Self.locale, timeZone: TimeZone(identifier: "UTC")!) == "\(date): 42.3M tokens")
        var priced = day
        priced.costUSD = Decimal(string: "12.5")!
        #expect(DayRowHeader.dayTooltip(priced, showsCost: true, locale: Self.locale, timeZone: TimeZone(identifier: "UTC")!) == "\(date): $12.50")
    }
}
