import Foundation
import Testing
@testable import UsageCore

/// Spec 041 FR-011, FR-014, FR-015, FR-015a, FR-015b, contracts/ui-strings.md:
/// the texts of a No limit section, decided in core.
@Suite struct NoLimitPresentationTests {
    static let locale = Locale(identifier: "en_US")
    static let utc = TimeZone(identifier: "UTC")!
    static let dates = NoteDates(locale: locale, timeZone: utc)
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }
    /// Tuesday 2026-10-13 12:00 UTC.
    static let now = isoDate("2026-10-13T12:00:00Z")
    static let week = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    static let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
    static let lastRefresh = isoDate("2026-10-13T11:00:00Z")

    static func times(_ format: TimeFormat = .relative) -> TimeText {
        TimeText(format: format, now: now, calendar: calendar, locale: locale)
    }

    static func entry(tokens: Int = 48_200_000, period: BudgetPeriod = .monthly, stale: Bool = false) -> NoLimitEntry {
        let perModel = tokens == 0 ? [] : [ModelUsage(model: "gateway-a/open-model-7b", inputTokens: tokens - 200_000, cacheReadTokens: 200_000)]
        return NoLimitEntry(period: period, window: period == .monthly ? month : week, breakdown: UsageBreakdown(perModel: perModel), stale: stale)
    }

    static func make(_ entry: NoLimitEntry?, format: TimeFormat = .relative, isPreliminary: Bool = false) -> NoLimitPresentation {
        NoLimitPresentation.make(name: "Free models", entry: entry, times: times(format), lastSuccessfulRefreshAt: lastRefresh,
                                 isPreliminary: isPreliminary, dates: dates)
    }

    @Test func headlineIsTheTokenTotal() {
        let p = Self.make(Self.entry())
        #expect(p.headline == "48.2M")
        #expect(p.showsDetails)
        #expect(Self.make(Self.entry(tokens: 950_000)).headline == "950K")
    }

    /// Without a value line the second line names the period on the left
    /// of the reset text (spec 041 FR-011, walkthrough step 4).
    @Test func periodLine() {
        #expect(Self.make(Self.entry(period: .monthly)).periodLine == "this month")
        #expect(Self.make(Self.entry(period: .weekly)).periodLine == "this week")
    }

    /// The headline has no unit; its tooltip gives the exact count with the
    /// unit and the period (FR-011).
    @Test func headlineTooltipGivesTheExactCount() {
        #expect(Self.make(Self.entry()).headlineTooltip == "48,200,000 tokens this month")
        #expect(Self.make(Self.entry(tokens: 0, period: .weekly)).headlineTooltip == "0 tokens this week")
        #expect(Self.make(nil).headlineTooltip == nil)
    }

    /// The reset text and its tooltip in both time formats (spec 025 FR-016).
    @Test(arguments: [TimeFormat.relative, .absolute])
    func resetTextFollowsTheTimeFormat(format: TimeFormat) {
        let p = Self.make(Self.entry(), format: format)
        #expect(p.resetText == Self.times(format).reset(Self.month.end))
        #expect(p.resetTooltip == Self.times(format).resetTooltip(Self.month.end))
        #expect(p.resetText?.hasPrefix("resets ") == true)
    }

    /// The stale and no-data notes equal those of an own budget's section
    /// for the same state (FR-015b), never "incomplete, unpriced" (FR-008).
    @Test func notesMatchAnOwnBudget() {
        #expect(Self.make(Self.entry()).notes.isEmpty)
        #expect(Self.make(Self.entry(stale: true)).notes == [.budgetStale(since: Self.lastRefresh, dates: Self.dates)])
        #expect(Self.make(nil).notes == [.noData(isPreliminary: false)])
        #expect(Self.make(nil, isPreliminary: true).notes == [.noData(isPreliminary: true)])
        let all = [Self.make(Self.entry()), Self.make(Self.entry(stale: true)), Self.make(nil)].flatMap(\.notes)
        #expect(!all.contains { $0.text.contains("incomplete") })
    }

    @Test func withoutAnEntryThereIsNoHeadlineOrDetails() {
        let p = Self.make(nil)
        #expect(p.headline == nil)
        #expect(p.periodLine == nil)
        #expect(p.resetText == nil)
        #expect(!p.showsDetails)
        #expect(p.accessibilityLabel == "Free models, No data")
    }

    @Test func accessibilityLabelWithoutValue() {
        let p = Self.make(Self.entry())
        #expect(p.accessibilityLabel == "Free models, 48.2M tokens this month, \(Self.times().reset(Self.month.end))")
    }

    /// A section without usage shows "0" and no Details (spec 041 edge case).
    @Test func zeroTokens() {
        let p = Self.make(Self.entry(tokens: 0, period: .weekly))
        #expect(p.headline == "0")
        #expect(p.periodLine == "this week")
        #expect(!p.showsDetails)
    }
}

/// Spec 041 FR-012, FR-013, FR-015, contracts/ui-strings.md: the value line,
/// its tooltip, the missing-model note and the accessibility text.
@Suite struct NoLimitValuePresentationTests {
    static func make(_ value: ReferenceValue) -> NoLimitPresentation {
        NoLimitPresentation.make(name: "Free models", entry: NoLimitPresentationTests.entry(), value: value,
                                 times: NoLimitPresentationTests.times(), lastSuccessfulRefreshAt: nil, isPreliminary: false,
                                 dates: NoLimitPresentationTests.dates)
    }

    static func line(_ amount: String) -> String? {
        make(.value(Decimal(string: amount)!, model: "claude-opus-5-5")).valueLine
    }

    static let reset = NoLimitPresentationTests.times().reset(NoLimitPresentationTests.month.end)

    @Test func valueLineRoundsHalfUpToWholeDollars() {
        #expect(Self.line("30.20") == "≈ $30 at claude-opus-5-5 prices")
        #expect(Self.line("411.50") == "≈ $412 at claude-opus-5-5 prices")
        #expect(Self.line("410.50") == "≈ $411 at claude-opus-5-5 prices")
        #expect(Self.line("1.00") == "≈ $1 at claude-opus-5-5 prices")
        #expect(Self.line("1234.49") == "≈ $1,234 at claude-opus-5-5 prices")
    }

    @Test func smallAndZeroValues() {
        #expect(Self.line("0.40") == "≈ <$1 at claude-opus-5-5 prices")
        #expect(Self.line("0.99") == "≈ <$1 at claude-opus-5-5 prices")
        #expect(Self.line("0") == "≈ $0 at claude-opus-5-5 prices")
    }

    @Test func tooltipSaysNothingWasSpent() throws {
        let p = Self.make(.value(Decimal(string: "30.20")!, model: "claude-opus-5-5"))
        #expect(p.valueTooltip == "What these tokens would have cost at claude-opus-5-5 prices. Nothing was spent.")
        // The value line takes the period line's place, left of the reset
        // text (FR-011).
        #expect(p.periodLine == nil)
        let line = try #require(p.valueLine)
        #expect(!line.contains("spent"))
        #expect(!line.contains(" of "))
        #expect(p.notes.isEmpty)
    }

    @Test func missingModelGivesTheNeutralNote() {
        let p = Self.make(.missing(model: "gateway-x/unknown"))
        #expect(p.valueLine == nil)
        #expect(p.valueTooltip == nil)
        #expect(p.periodLine == "this month")
        #expect(p.notes == [SectionNote(text: "Value as model gateway-x/unknown has no price", style: .neutral)])
        #expect(p.notes == [.valueAsMissing(model: "gateway-x/unknown")])
        #expect(p.accessibilityLabel == "Free models, 48.2M tokens this month, \(Self.reset), Value as model gateway-x/unknown has no price")
    }

    @Test func withoutValueAsThereIsNoValueLine() {
        let p = Self.make(.none)
        #expect(p.valueLine == nil)
        #expect(p.notes.isEmpty)
        #expect(p.accessibilityLabel == "Free models, 48.2M tokens this month, \(Self.reset)")
    }

    /// Another locale: its currency format in whole units, with the same
    /// rounding and small-value rules (FR-012).
    /// A German region keeps English numbers and dollar amounts (idea
    /// inbox english-number-format, amends spec 018 FR-003).
    @Test func valueLineInAnotherLocale() {
        let de = Locale(identifier: "en_DE")
        let times = TimeText(format: .relative, now: NoLimitPresentationTests.now, calendar: NoLimitPresentationTests.calendar, locale: de)
        func line(_ amount: String) -> String? {
            NoLimitPresentation.make(name: "Free models", entry: NoLimitPresentationTests.entry(),
                                     value: .value(Decimal(string: amount)!, model: "claude-opus-5-5"), times: times,
                                     lastSuccessfulRefreshAt: nil, isPreliminary: false,
                                     dates: NoteDates(locale: de, timeZone: NoLimitPresentationTests.utc)).valueLine
        }
        #expect(line("1234.50") == "\u{2248} $1,235 at claude-opus-5-5 prices")
        #expect(line("410.50") == "\u{2248} $411 at claude-opus-5-5 prices")
        #expect(line("0.40") == "\u{2248} <$1 at claude-opus-5-5 prices")
        #expect(line("0") == "\u{2248} $0 at claude-opus-5-5 prices")
    }

    @Test func accessibilityLabelReadsTheValue() {
        #expect(Self.make(.value(Decimal(string: "30.20")!, model: "claude-opus-5-5")).accessibilityLabel
                == "Free models, 48.2M tokens this month, \(Self.reset), about $30 at claude-opus-5-5 prices")
        #expect(Self.make(.value(Decimal(string: "0.40")!, model: "claude-opus-5-5")).accessibilityLabel
                == "Free models, 48.2M tokens this month, \(Self.reset), less than $1 at claude-opus-5-5 prices")
    }
}

/// Spec 041 FR-011 to FR-013, FR-022: the section as the dropdown and the
/// demo coverage test assemble it, from the account, the snapshot and the
/// effective price table.
@Suite struct NoLimitSectionAssemblyTests {
    static func account(valueAs: String?, membership: TokenMembership = .noLimit(NoLimitSettings(period: .weekly))) -> Account {
        Account(id: "free", displayName: "Free models", kind: .tokenBased(TokenBasedSettings(membership: membership, valueAs: valueAs)))
    }

    /// 33.5M tokens this week, worth 30.20 at claude-opus-5-5 prices.
    static var snapshot: UsageSnapshot {
        var s = UsageSnapshot(generatedAt: NoLimitPresentationTests.now, window: NoLimitPresentationTests.week, windowSource: .fallback)
        s.noLimitAccounts["free"] = NoLimitEntry(period: .weekly, window: NoLimitPresentationTests.week,
                                                 breakdown: UsageBreakdown(perModel: ReferenceValueTests.breakdown))
        return s
    }

    static func make(_ account: Account, _ snapshot: UsageSnapshot?) -> NoLimitPresentation? {
        NoLimitPresentation.make(account: account, snapshot: snapshot, prices: ReferenceValueTests.prices,
                                 times: NoLimitPresentationTests.times(), dates: NoLimitPresentationTests.dates)
    }

    @Test func valuesTheEntryAtTheValueAsModelsPrice() throws {
        let p = try #require(Self.make(Self.account(valueAs: "claude-opus-5-5"), Self.snapshot))
        #expect(p.headline == "33.5M")
        #expect(p.periodLine == nil)
        #expect(p.valueLine == "\u{2248} $30 at claude-opus-5-5 prices")
        #expect(p.showsDetails)
        #expect(p.notes.isEmpty)
    }

    @Test func missingValueAsModelGivesTheNote() throws {
        let p = try #require(Self.make(Self.account(valueAs: "gateway-x/unknown"), Self.snapshot))
        #expect(p.valueLine == nil)
        #expect(p.notes == [.valueAsMissing(model: "gateway-x/unknown")])
    }

    @Test func withoutValueAsThereIsNoValueLine() throws {
        let p = try #require(Self.make(Self.account(valueAs: nil), Self.snapshot))
        #expect(p.headline == "33.5M")
        #expect(p.valueLine == nil)
    }

    /// Before the first result, the no-data note of an early result.
    @Test func withoutSnapshotTheSectionIsRefreshing() throws {
        let p = try #require(Self.make(Self.account(valueAs: "claude-opus-5-5"), nil))
        #expect(p.headline == nil)
        #expect(p.notes == [.noData(isPreliminary: true)])
    }

    @Test func staleEntryShowsTheStaleNote() throws {
        var s = Self.snapshot
        s.noLimitAccounts["free"]?.stale = true
        s.lastSuccessfulRefreshAt = NoLimitPresentationTests.lastRefresh
        let p = try #require(Self.make(Self.account(valueAs: nil), s))
        #expect(p.notes == [.budgetStale(since: NoLimitPresentationTests.lastRefresh, dates: NoLimitPresentationTests.dates)])
    }

    @Test func otherAccountsHaveNoNoLimitSection() {
        let own = Self.account(valueAs: "claude-opus-5-5", membership: .ownBudget(BudgetSettings(budgetUSD: 10)))
        #expect(Self.make(own, Self.snapshot) == nil)
    }
}
