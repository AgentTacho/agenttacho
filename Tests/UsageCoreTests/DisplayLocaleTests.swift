import Foundation
import Testing
@testable import UsageCore

/// Idea inbox english-number-format (amends spec 018 FR-003): the UI is
/// English and every amount is in US dollars, so numbers and dollar amounts
/// use en_US formatting whatever the region; dates and times keep the
/// region.
@Suite struct DisplayLocaleTests {
    /// English language, German region: the setting that showed "48,2M" and
    /// "108 US$" next to English words.
    static let enDE = Locale(identifier: "en_DE")
    static let utc = TimeZone(identifier: "UTC")!

    /// The defaults of the budget amount formatter no longer follow the
    /// current locale. This only catches a regression on a machine with a
    /// non-English region (the maintainer's en_DE); on en_US it passes
    /// either way.
    @Test func budgetAmountsDefaultToEnglish() {
        #expect(BudgetAmountFormatter.amount(Decimal(string: "100.5")!) == "$100.50")
        #expect(BudgetAmountFormatter.amount(1234) == "$1,234")
        #expect(BudgetAmountFormatter.wholeAmount(Decimal(string: "1234.5")!) == "$1,235")
        #expect(BudgetAmountFormatter.text(400, period: .monthly) == "$400 / month")
    }

    /// A day column's tooltip: the date in the region's format, the amount
    /// and the tokens in English.
    @Test func dayTooltipKeepsTheRegionForTheDateOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let date = day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Self.enDE, timeZone: Self.utc))
        let priced = DayUsage(day: day, inputTokens: 42_300_000, outputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0,
                              costUSD: Decimal(string: "1234.5"))
        #expect(DayRowHeader.dayTooltip(priced, showsCost: true, locale: Self.enDE, timeZone: Self.utc) == "\(date): $1,234.50")
        #expect(DayRowHeader.dayTooltip(priced, showsCost: false, locale: Self.enDE, timeZone: Self.utc) == "\(date): 42.3M tokens")
    }

    /// The Σ column and its tooltip in English for a German region.
    @Test func dayRowTotalIsEnglish() {
        let day = Date(timeIntervalSince1970: 0)
        let days = [DayUsage(day: day, inputTokens: 188_700_000, outputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0,
                             costUSD: Decimal(string: "1430.12"))]
        #expect(DayRowTotal.make(days: days, showsCost: true, incomplete: false).tooltip == "Total: $1,430.12")
        #expect(DayRowTotal.make(days: days, showsCost: false, incomplete: false).tooltip == "Total: 188.7M tokens")
    }

    /// The No limit headline and its tooltip in English for a German region.
    @Test func noLimitHeadlineIsEnglish() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let month = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 30 * 86_400)
        let entry = NoLimitEntry(period: .monthly, window: month,
                                 breakdown: UsageBreakdown(perModel: [ModelUsage(model: "gateway-a/open-model-7b", inputTokens: 48_213_507)]))
        let times = TimeText(format: .relative, now: month.start, calendar: calendar, locale: Self.enDE)
        let p = NoLimitPresentation.make(name: "Free models", entry: entry, times: times, lastSuccessfulRefreshAt: nil,
                                         isPreliminary: false, dates: NoteDates(locale: Self.enDE, timeZone: Self.utc))
        #expect(p.headline == "48.2M")
        #expect(p.headlineTooltip == "48,213,507 tokens this month")
    }
}
