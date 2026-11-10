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
    @Test func headlineTooltipUsesTheScaleWord() {
        #expect(Self.make(Self.entry()).headlineTooltip == "48.2 million tokens this month")
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
    /// for the same state (FR-015b); a Tokens headline never notes
    /// "incomplete, unpriced" (spec 041 FR-008, spec 043 FR-007).
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
        #expect(p.accessibilityLabel == "Free models, 48.2 million tokens this month, \(Self.times().reset(Self.month.end))")
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
        #expect(p.notes == [SectionNote(text: "Price tokens as: gateway-x/unknown has no price", style: .neutral)])
        #expect(p.notes == [.valueAsMissing(model: "gateway-x/unknown")])
        #expect(p.accessibilityLabel == "Free models, 48.2 million tokens this month, \(Self.reset), Price tokens as: gateway-x/unknown has no price")
    }

    @Test func withoutValueAsThereIsNoValueLine() {
        let p = Self.make(.none)
        #expect(p.valueLine == nil)
        #expect(p.notes.isEmpty)
        #expect(p.accessibilityLabel == "Free models, 48.2 million tokens this month, \(Self.reset)")
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
                == "Free models, 48.2 million tokens this month, \(Self.reset), about $30 at claude-opus-5-5 prices")
        #expect(Self.make(.value(Decimal(string: "0.40")!, model: "claude-opus-5-5")).accessibilityLabel
                == "Free models, 48.2 million tokens this month, \(Self.reset), less than $1 at claude-opus-5-5 prices")
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
                                                 breakdown: UsageBreakdown(perModel: ReferenceValueTests.breakdown),
                                                 unpricedUsage: ReferenceValueTests.breakdown)
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

/// Spec 043 FR-007, FR-011, FR-013 to FR-016, contracts/ui-strings.md: the
/// section of an own budget without an amount with the Show setting, priced
/// usage, the "incomplete, unpriced" note and the value tooltip.
@Suite struct NoLimitShowPresentationTests {
    typealias Base = NoLimitPresentationTests
    static let month = Base.month
    static let reset = Base.times().reset(Base.month.end)

    /// A monthly entry: 37.42 US$ of priced usage when `priced`, plus 1.2M
    /// tokens of `gateway-a/open-model-7b` without a price when `unpriced`.
    static func entry(priced: Bool, unpriced: Bool, stale: Bool = false) -> NoLimitEntry {
        var perModel: [ModelUsage] = []
        var unpricedUsage: [ModelUsage] = []
        if priced {
            perModel.append(ModelUsage(model: "claude-opus-5-5", inputTokens: 2_000_000, outputTokens: 1_000_000,
                                       costUSD: Decimal(string: "37.42")!, priced: true))
        }
        if unpriced {
            let row = ModelUsage(model: "gateway-a/open-model-7b", inputTokens: 1_200_000, costUSD: nil, priced: false)
            perModel.append(row)
            unpricedUsage.append(row)
        }
        return NoLimitEntry(period: .monthly, window: month,
                            breakdown: UsageBreakdown(perModel: perModel, unpricedModels: unpricedUsage.map(\.model)),
                            unpricedUsage: unpricedUsage, spentUSD: priced ? Decimal(string: "37.42")! : 0,
                            hasPricedUsage: priced, stale: stale)
    }

    static func make(_ entry: NoLimitEntry, show: DropdownShow = .automatic, value: ReferenceValue = .none) -> NoLimitPresentation {
        NoLimitPresentation.make(name: "API key", entry: entry, show: show, value: value, times: Base.times(),
                                 lastSuccessfulRefreshAt: Base.lastRefresh, isPreliminary: false, dates: Base.dates)
    }

    /// Story 2 scenario 1: real spend, worded as spend, without "≈".
    @Test func automaticWithPricedUsageShowsMoney() {
        let p = Self.make(Self.entry(priced: true, unpriced: false))
        #expect(p.measure == .money)
        #expect(p.headline == "$37")
        #expect(p.headlineTooltip == "$37.42 spent this month")
        #expect(p.periodLine == "spent this month")
        #expect(p.valueLine == nil)
        #expect(p.notes.isEmpty)
        #expect(!p.incomplete)
        #expect(p.showsCost)
        #expect(p.accessibilityLabel == "API key, $37.42 spent this month, \(Self.reset)")
        let all = [p.headline, p.headlineTooltip, p.periodLine, p.accessibilityLabel].compactMap { $0 }
        #expect(!all.contains { $0.contains("\u{2248}") })
    }

    /// Story 1 scenario 4: only unpriced usage keeps spec 041's section.
    @Test func automaticWithOnlyUnpricedUsageShowsTokens() {
        let p = Self.make(Self.entry(priced: false, unpriced: true))
        #expect(p.measure == .tokens)
        #expect(p.headline == "1.2M")
        #expect(p.headlineTooltip == "1.2 million tokens this month")
        #expect(p.periodLine == "this month")
        #expect(p.notes.isEmpty)
        #expect(!p.showsCost)
        #expect(p.accessibilityLabel == "API key, 1.2 million tokens this month, \(Self.reset)")
    }

    /// Story 2 scenario 2 and FR-007: Money without Value as notes the
    /// unpriced models; Tokens never does.
    @Test func moneyWithUnpricedModelsAddsTheIncompleteNote() {
        let p = Self.make(Self.entry(priced: true, unpriced: true))
        #expect(p.measure == .money)
        #expect(p.notes == [.budgetIncomplete(unpricedModels: ["gateway-a/open-model-7b"])])
        #expect(p.incomplete)
        let tokens = Self.make(Self.entry(priced: true, unpriced: true), show: .tokens)
        #expect(tokens.measure == .tokens)
        #expect(tokens.notes.isEmpty)
        #expect(!tokens.incomplete)
        #expect(!tokens.showsCost)
    }

    /// Story 3 scenario 5: Money with only unpriced records shows "$0" and
    /// the note, unless a Value as model values them.
    @Test func moneyOnlyUnpriced() {
        let p = Self.make(Self.entry(priced: false, unpriced: true), show: .money)
        #expect(p.headline == "$0")
        #expect(p.periodLine == "spent this month")
        #expect(p.notes == [.budgetIncomplete(unpricedModels: ["gateway-a/open-model-7b"])])
        let valued = Self.make(Self.entry(priced: false, unpriced: true), show: .money,
                               value: .value(Decimal(string: "4.8")!, model: "claude-opus-5-5"))
        #expect(valued.headline == "$0")
        #expect(valued.notes.isEmpty)
        #expect(valued.valueLine == "\u{2248} $5 at claude-opus-5-5 prices")
        #expect(valued.periodLine == nil)
    }

    /// A set Value as model always shows its value line, "≈ $0" included
    /// (FR-014).
    @Test func valueLineAlsoForZero() {
        let p = Self.make(Self.entry(priced: true, unpriced: false), value: .value(0, model: "claude-opus-5-5"))
        #expect(p.valueLine == "\u{2248} $0 at claude-opus-5-5 prices")
        #expect(p.periodLine == nil)
        #expect(p.headline == "$37")
    }

    /// A missing Value as model gives the missing-model note and, under
    /// Money, also the incomplete note (FR-007).
    @Test func missingValueAsUnderMoneyAlsoNotesIncomplete() {
        let p = Self.make(Self.entry(priced: true, unpriced: true), value: .missing(model: "gateway-x/unknown"))
        #expect(p.notes == [.valueAsMissing(model: "gateway-x/unknown"), .budgetIncomplete(unpricedModels: ["gateway-a/open-model-7b"])])
        #expect(p.periodLine == "spent this month")
        let tokens = Self.make(Self.entry(priced: false, unpriced: true), value: .missing(model: "gateway-x/unknown"))
        #expect(tokens.notes == [.valueAsMissing(model: "gateway-x/unknown")])
    }

    /// FR-015: the value tooltip names the models without a price when the
    /// account also has priced usage.
    @Test func valueTooltipVariants() {
        let mixed = Self.make(Self.entry(priced: true, unpriced: true), value: .value(Decimal(string: "4.8")!, model: "claude-opus-5-5"))
        #expect(mixed.valueTooltip
                == "What the tokens of models without a price would have cost at claude-opus-5-5 prices. Nothing was spent for them.")
        #expect(mixed.notes.isEmpty)
        let free = Self.make(Self.entry(priced: false, unpriced: true), value: .value(Decimal(string: "4.8")!, model: "claude-opus-5-5"))
        #expect(free.valueTooltip == "What these tokens would have cost at claude-opus-5-5 prices. Nothing was spent.")
    }

    /// Story 3 scenario 6: a stored Percent without an amount shows what
    /// Automatic would.
    @Test func storedPercentFollowsAutomatic() {
        #expect(Self.make(Self.entry(priced: true, unpriced: false), show: .percent).measure == .money)
        #expect(Self.make(Self.entry(priced: false, unpriced: true), show: .percent).measure == .tokens)
        #expect(Self.make(Self.entry(priced: true, unpriced: false), show: .tokens).headline == "3M")
    }

    @Test func staleEntryUnderMoneyKeepsTheStaleNote() {
        let p = Self.make(Self.entry(priced: true, unpriced: false, stale: true))
        #expect(p.notes == [.budgetStale(since: Base.lastRefresh, dates: Base.dates)])
    }

    @Test func withoutAnEntryThereIsNoMeasure() {
        let p = NoLimitPresentation.make(name: "API key", entry: nil, show: .money, times: Base.times(),
                                         lastSuccessfulRefreshAt: nil, isPreliminary: false, dates: Base.dates)
        #expect(p.measure == nil)
        #expect(!p.showsCost)
    }

    /// The assembly reads the account's Show setting and values only the
    /// unpriced usage (R5).
    @Test func assemblyReadsShowAndValuesUnpricedOnly() throws {
        var settings = TokenBasedSettings(membership: .noLimit(NoLimitSettings(period: .monthly)), valueAs: "claude-opus-5-5")
        settings.show = .tokens
        let account = Account(id: "api", displayName: "API key", kind: .tokenBased(settings))
        var snapshot = UsageSnapshot(generatedAt: Base.now, window: Base.week, windowSource: .fallback)
        snapshot.noLimitAccounts["api"] = Self.entry(priced: true, unpriced: true)
        let p = try #require(NoLimitPresentation.make(account: account, snapshot: snapshot, prices: ReferenceValueTests.prices,
                                                      times: Base.times(), dates: Base.dates))
        #expect(p.measure == .tokens)
        // 1.2M input tokens at 4.00 per MTok: 4.80, not the priced model's tokens.
        #expect(p.valueLine == "\u{2248} $5 at claude-opus-5-5 prices")
    }
}

/// Spec 043 story 4, SC-003: a spec 041 configuration with a No limit
/// account whose records are all unpriced loads and shows the section
/// strings of spec 041 contracts/ui-strings.md; only the accessibility label
/// uses the spoken form of spec 043 FR-016.
@Suite struct LegacyNoLimitSectionTests {
    @Test func spec041AccountLooksAsBefore() throws {
        let config = try decodeConfig(NoLimitConfigurationTests.json(NoLimitConfigurationTests.example))
        let account = try #require(config.account(id: "acc-free"))
        #expect(account.kind.tokenBased?.show == .automatic)
        let record = makeRecord(id: "free-1", accountId: "acc-free", model: "gateway-a/open-model-7b",
                                timestamp: isoDate("2026-10-05T10:00:00Z"), input: 48_213_507, cost: nil)
        let snapshot = Aggregator().aggregate(records: [record], subscriptions: [:], configuration: config,
                                              window: NoLimitPresentationTests.week, windowSource: .fallback,
                                              now: NoLimitPresentationTests.now, calendar: NoLimitPresentationTests.calendar)
        let times = NoLimitPresentationTests.times()
        let p = try #require(NoLimitPresentation.make(account: account, snapshot: snapshot, prices: ReferenceValueTests.prices,
                                                      times: times, dates: NoLimitPresentationTests.dates))
        let reset = times.reset(NoLimitPresentationTests.month.end)
        // 48,213,507 input tokens at 4.00 per MTok: 192.85, "≈ $193".
        #expect(p.measure == .tokens)
        #expect(p.headline == "48.2M")
        // Spec 041 showed the exact count; since walkthrough step 4 the tooltip
        // uses the scale word from a million on.
        #expect(p.headlineTooltip == "48.2 million tokens this month")
        #expect(p.periodLine == nil)
        #expect(p.valueLine == "\u{2248} $193 at claude-opus-5-5 prices")
        #expect(p.valueTooltip == "What these tokens would have cost at claude-opus-5-5 prices. Nothing was spent.")
        #expect(p.resetText == reset)
        #expect(p.notes.isEmpty)
        #expect(!p.showsCost)
        #expect(p.accessibilityLabel == "Free models, 48.2 million tokens this month, \(reset), about $193 at claude-opus-5-5 prices")
        let subtitle = try #require(AccountBudgetDescription.make(for: account, in: config, locale: Locale(identifier: "en_US")))
        #expect(subtitle.visibleText == "Other provider \u{00B7} no limit / month")
    }
}

/// Spec 043 FR-005 to FR-007, FR-011, FR-013, FR-014, review finding 12:
/// the Money headline end to end, from usage records through the
/// aggregator to the section text. Priced records of last month count for
/// neither the spend nor the Automatic choice.
@Suite struct NoLimitEndToEndTests {
    typealias Base = NoLimitPresentationTests
    static let week = Base.week

    static func account(valueAs: String? = nil) -> Account {
        Account(id: "api", displayName: "API key", kind: .tokenBased(TokenBasedSettings(
            membership: .noLimit(NoLimitSettings(period: .monthly)), valueAs: valueAs)))
    }

    /// Last month: a priced record of 500 US$. This month: priced records
    /// of 37.40 and 0.02 US$ (1M input tokens each) when `pricedThisMonth`,
    /// and 2M unpriced input tokens of `gateway-a/open-model-7b`.
    static func records(pricedThisMonth: Bool) -> [UsageRecord] {
        var records = [
            makeRecord(id: "september", accountId: "api", model: "claude-opus-5-5", timestamp: isoDate("2026-09-28T10:00:00Z"),
                       input: 1_000_000, cost: 500),
            makeRecord(id: "free", accountId: "api", model: "gateway-a/open-model-7b", timestamp: isoDate("2026-10-13T10:00:00Z"),
                       input: 2_000_000, cost: nil),
        ]
        if pricedThisMonth {
            records += [
                makeRecord(id: "paid-1", accountId: "api", model: "claude-opus-5-5", timestamp: isoDate("2026-10-05T10:00:00Z"),
                           input: 1_000_000, cost: Decimal(string: "37.40")!),
                makeRecord(id: "paid-2", accountId: "api", model: "claude-opus-5-5", timestamp: isoDate("2026-10-12T10:00:00Z"),
                           input: 1_000_000, cost: Decimal(string: "0.02")!),
            ]
        }
        return records
    }

    static func make(_ account: Account, pricedThisMonth: Bool) throws -> NoLimitPresentation {
        let config = Configuration(accounts: [account])
        var snapshot = Aggregator().aggregate(records: records(pricedThisMonth: pricedThisMonth), subscriptions: [:], configuration: config,
                                              window: week, windowSource: .fallback, now: Base.now, calendar: Base.calendar)
        snapshot.isPreliminary = false
        return try #require(NoLimitPresentation.make(account: account, snapshot: snapshot, prices: ReferenceValueTests.prices,
                                                     times: Base.times(), dates: Base.dates))
    }

    @Test func pricedRecordsOfThisMonthGiveTheMoneyHeadline() throws {
        let p = try Self.make(Self.account(), pricedThisMonth: true)
        #expect(p.measure == .money)
        #expect(p.headline == "$37")
        #expect(p.headlineTooltip == "$37.42 spent this month")
        #expect(p.periodLine == "spent this month")
        #expect(p.notes == [.budgetIncomplete(unpricedModels: ["gateway-a/open-model-7b"])])
        #expect(p.incomplete)
        #expect(p.showsCost)
    }

    /// With a Value as model only the 2M unpriced tokens are valued
    /// (2M x 4 US$/MTok = 8 US$), never the priced ones, and the note goes.
    @Test func valueAsValuesOnlyTheUnpricedRecords() throws {
        let p = try Self.make(Self.account(valueAs: "claude-opus-5-5"), pricedThisMonth: true)
        #expect(p.headline == "$37")
        #expect(p.valueLine == "\u{2248} $8 at claude-opus-5-5 prices")
        #expect(p.notes.isEmpty)
    }

    /// Only last month has priced records: Automatic shows tokens (FR-011
    /// looks at the current window only), without the incomplete note.
    @Test func pricedRecordsOfLastMonthDoNotCount() throws {
        let p = try Self.make(Self.account(), pricedThisMonth: false)
        #expect(p.measure == .tokens)
        #expect(p.headline == "2M")
        #expect(p.periodLine == "this month")
        #expect(p.notes.isEmpty)
        #expect(!p.showsCost)
    }
}

/// Spec 044 FR-008, FR-009, FR-011, FR-012, FR-014, research R4: the section
/// of a group without an amount, built from the group's entry, Show setting
/// and Price tokens as model with spec 043's rules.
@Suite struct GroupNoLimitPresentationTests {
    typealias Base = NoLimitPresentationTests
    typealias Agg = GroupNoLimitAggregationTests

    static let prices = PriceTable(entries: [
        PriceEntry(model: "claude-opus-5-5", inputPerMTok: 4, outputPerMTok: 20, cacheWrite5mPerMTok: 5, cacheWrite1hPerMTok: 8,
                   cacheReadPerMTok: Decimal(string: "0.2")!, source: .builtIn),
    ])

    /// Only unpriced records: 34.5M input tokens of the Claude Code member
    /// and 13.7M output tokens of the Codex member, 48.2M in all.
    static let unpricedRecords = [
        makeRecord(id: "u1", accountId: "acc-claude", model: "gateway-a/open-model-7b", timestamp: isoDate("2026-10-05T10:00:00Z"),
                   input: 34_500_000, cost: nil),
        makeRecord(id: "u2", accountId: "acc-codex", model: "gateway-a/open-model-7b", timestamp: isoDate("2026-10-06T10:00:00Z"),
                   output: 13_700_000, cost: nil, harness: .codex),
    ]

    static func group(_ config: Configuration = Agg.config(), valueAs: String? = nil, show: DropdownShow = .automatic,
                      id: String = "grp-free") -> BudgetGroup {
        var group = config.group(id: id)!
        group.valueAs = valueAs
        group.show = show
        return group
    }

    static func make(_ group: BudgetGroup, _ snapshot: UsageSnapshot?) -> NoLimitPresentation? {
        NoLimitPresentation.make(group: group, snapshot: snapshot, prices: prices, times: Base.times(), dates: Base.dates)
    }

    @Test func moneyHeadlineForPricedRecords() throws {
        let p = try #require(Self.make(Self.group(), Agg.aggregate()))
        #expect(p.measure == .money)
        #expect(p.headline == "$93")
        #expect(p.headlineTooltip == "$93.46 spent this month")
        #expect(p.periodLine == "spent this month")
        #expect(p.showsCost)
        #expect(p.showsDetails)
        #expect(p.accessibilityLabel.hasPrefix("Free models, $93.46 spent this month, "))
    }

    /// FR-009: under Money the unpriced records give the "incomplete,
    /// unpriced" note, unless a Price tokens as model values them.
    @Test func moneyWithUnpricedRecordsIsIncomplete() throws {
        let p = try #require(Self.make(Self.group(), Agg.aggregate()))
        #expect(p.incomplete)
        #expect(p.notes == [.budgetIncomplete(unpricedModels: ["gateway-a/open-model-7b"])])
        let valued = try #require(Self.make(Self.group(valueAs: "claude-opus-5-5"), Agg.aggregate()))
        #expect(!valued.incomplete)
        #expect(valued.notes.isEmpty)
    }

    @Test func onlyUnpricedRecordsShowTokens() throws {
        let p = try #require(Self.make(Self.group(), Agg.aggregate(Self.unpricedRecords)))
        #expect(p.measure == .tokens)
        #expect(p.headline == "48.2M")
        #expect(p.headlineTooltip == "48.2 million tokens this month")
        #expect(p.periodLine == "this month")
        #expect(p.notes.isEmpty)
        #expect(!p.showsCost)
        #expect(p.accessibilityLabel.hasPrefix("Free models, 48.2 million tokens this month, "))
    }

    /// 34,500,000 input tokens at 4.00 per MTok are 138.00 US$, 13,700,000
    /// output tokens at 20.00 per MTok are 274.00 US$: 412.00 in all.
    @Test func priceTokensAsValuesTheUnpricedRecords() throws {
        let p = try #require(Self.make(Self.group(valueAs: "claude-opus-5-5"), Agg.aggregate(Self.unpricedRecords)))
        #expect(p.valueLine == "\u{2248} $412 at claude-opus-5-5 prices")
        #expect(p.periodLine == nil)
        #expect(p.headline == "48.2M")
    }

    @Test func priceTokensAsWithoutAPriceGivesTheMissingNote() throws {
        let p = try #require(Self.make(Self.group(valueAs: "gateway-x/unknown"), Agg.aggregate(Self.unpricedRecords)))
        #expect(p.valueLine == nil)
        #expect(p.notes == [.valueAsMissing(model: "gateway-x/unknown")])
    }

    @Test func storedPercentDisplaysAsAutomatic() throws {
        #expect(try #require(Self.make(Self.group(show: .percent), Agg.aggregate())).measure == .money)
        #expect(try #require(Self.make(Self.group(show: .percent), Agg.aggregate(Self.unpricedRecords))).measure == .tokens)
        let tokens = try #require(Self.make(Self.group(show: .tokens), Agg.aggregate()))
        #expect(tokens.measure == .tokens)
        #expect(!tokens.showsCost)
        #expect(tokens.notes.isEmpty)
        let money = try #require(Self.make(Self.group(show: .money), Agg.aggregate(Self.unpricedRecords)))
        #expect(money.headline == "$0")
        #expect(money.showsCost)
    }

    /// FR-008: a member's own Price tokens as model and Show setting do not
    /// change the group's section.
    @Test func membersOwnSettingsDoNotChangeTheSection() throws {
        var config = Agg.config()
        for index in config.accounts.indices {
            guard var settings = config.accounts[index].kind.tokenBased else { continue }
            settings.valueAs = "claude-opus-5-5"
            settings.show = .tokens
            config.accounts[index].kind = .tokenBased(settings)
        }
        let snapshot = Agg.aggregate(config: config)
        #expect(Self.make(Self.group(config), snapshot) == Self.make(Self.group(), Agg.aggregate()))
        #expect(Self.make(Self.group(config), snapshot)?.measure == .money)
    }

    @Test func emptyGroupAndGroupWithoutUsageShowZero() throws {
        var config = Agg.config()
        config.groups[1].period = .monthly
        let snapshot = Agg.aggregate([], config: config)
        for id in ["grp-free", "grp-empty"] {
            let p = try #require(Self.make(Self.group(config, id: id), snapshot))
            #expect(p.headline == "0")
            #expect(p.periodLine == "this month")
            #expect(!p.showsDetails)
            let money = try #require(Self.make(Self.group(config, show: .money, id: id), snapshot))
            #expect(money.headline == "$0")
        }
    }

    @Test func groupWithAnAmountHasNoNoLimitSection() {
        var group = Self.group()
        group.budgetUSD = 500
        #expect(Self.make(group, Agg.aggregate()) == nil)
    }

    @Test func withoutSnapshotTheSectionIsRefreshing() throws {
        let p = try #require(Self.make(Self.group(), nil))
        #expect(p.headline == nil)
        #expect(p.notes == [.noData(isPreliminary: true)])
    }
}
