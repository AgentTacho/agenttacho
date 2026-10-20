import Foundation
import Testing
@testable import UsageCore

/// spec 025 FR-002 to FR-004, FR-006, FR-007, FR-009, FR-032, research R2:
/// the bar of a window row or budget (fill, tick, tone) and its note, all
/// from one `PaceReading`.
@Suite struct RowBarTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    static let locale = Locale(identifier: "en_US")
    /// Thu 22 Oct 2026, 14:54 UTC.
    static let now = isoDate("2026-10-22T14:54:00Z")
    static let hour: TimeInterval = 3600
    static let relative = TimeText(format: .relative, now: now, calendar: calendar, locale: locale)
    static let absolute = TimeText(format: .absolute, now: now, calendar: calendar, locale: locale)

    static let runOut = now.addingTimeInterval(36 * hour)
    static let fastRunOut = now.addingTimeInterval(3 * hour + 10 * 60)
    static let ahead = Pace(expectedPercent: 40, delta: 20, status: .ahead(20), runOut: runOut)
    static let aheadNoRunOut = Pace(expectedPercent: 5, delta: 7, status: .ahead(7), runOut: nil)
    static let onPace = Pace(expectedPercent: 38, delta: 0, status: .onPace, runOut: nil)
    static let behind = Pace(expectedPercent: 50, delta: -8, status: .behind(8), runOut: nil)
    static let fast = BurnRate(sustainablePerHour: 1, averagePerHour: 3, recentPerHour: nil, fastRunOut: fastRunOut)
    static let calm = BurnRate(sustainablePerHour: 1, averagePerHour: 0.5, recentPerHour: nil, fastRunOut: nil)

    static func long(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    // MARK: - Fill (FR-002, FR-009)

    @Test func fillIsTheUsedShareCappedAtAFullBar() {
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: nil).fill == 0.38)
        #expect(RowBar.make(usedPercent: 0, limitReached: false, thresholds: [], direction: .used, reading: nil).fill == 0)
        #expect(RowBar.make(usedPercent: 100, limitReached: false, thresholds: [], direction: .used, reading: nil).fill == 1)
        #expect(RowBar.make(usedPercent: 532, limitReached: false, thresholds: [], direction: .used, reading: nil).fill == 1)
        #expect(RowBar.make(usedPercent: -4, limitReached: false, thresholds: [], direction: .used, reading: nil).fill == 0)
    }

    @Test func nonFiniteUsedPercentIsAnEmptyNeutralBar() {
        for value in [Double.nan, .infinity, -.infinity] {
            let bar = RowBar.make(usedPercent: value, limitReached: false, thresholds: [], direction: .used, reading: nil)
            #expect(bar.fill == 0)
            #expect(bar.tone == .neutral)
            #expect(bar.note == nil)
        }
    }

    /// spec 030 FR-003: a reached Codex limit is critical even when its
    /// used percent is not finite; the bar stays empty in both directions.
    @Test func reachedLimitWithoutAFinitePercentIsCritical() {
        for direction in DisplayDirection.allCases {
            let bar = RowBar.make(usedPercent: .nan, limitReached: true, thresholds: [80, 90], direction: direction, reading: nil)
            #expect(bar.level == .critical)
            #expect(bar.tone == .overLimit)
            #expect(bar.percentTone == .critical)
            #expect(bar.fill == 0)
        }
    }

    // MARK: - Tick (FR-002)

    @Test func tickIsClampedToTheBar() {
        let over = Pace(expectedPercent: 130, delta: 0, status: .onPace, runOut: nil)
        let under = Pace(expectedPercent: -20, delta: 0, status: .onPace, runOut: nil)
        #expect(RowBar.make(usedPercent: 10, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: over, burn: nil)).tick == 1)
        #expect(RowBar.make(usedPercent: 10, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: under, burn: nil)).tick == 0)
    }

    @Test func tickIsTheExpectedPercent() {
        let bar = RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.onPace, burn: nil))
        #expect(bar.tick == 0.38)
        let ahead = RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: nil))
        #expect(ahead.tick == 0.4)
    }

    @Test func noTickWithoutAPace() {
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: nil).tick == nil)
    }

    // MARK: - Tone (FR-003, FR-007)

    @Test func overLimitAtARoundedHundredOrAReachedLimit() {
        #expect(RowBar.make(usedPercent: 99.6, limitReached: false, thresholds: [], direction: .used, reading: nil).tone == .overLimit)
        #expect(RowBar.make(usedPercent: 100, limitReached: false, thresholds: [], direction: .used, reading: nil).tone == .overLimit)
        #expect(RowBar.make(usedPercent: 532, limitReached: false, thresholds: [], direction: .used, reading: nil).tone == .overLimit)
        #expect(RowBar.make(usedPercent: 99.4, limitReached: false, thresholds: [], direction: .used, reading: nil).tone == .neutral)
        #expect(RowBar.make(usedPercent: 10, limitReached: true, thresholds: [], direction: .used, reading: nil).tone == .overLimit)
    }

    /// Over the limit wins over attention, and an over-limit bar has no note.
    @Test func overLimitWinsOverAttention() {
        let bar = RowBar.make(usedPercent: 10, limitReached: true, thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: Self.fast))
        #expect(bar.tone == .overLimit)
        #expect(bar.note == nil)
    }

    @Test func attentionWithARunOutOrAFastBurn() {
        #expect(RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: nil)).tone == .attention)
        #expect(RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: Self.calm)).tone == .attention)
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.onPace, burn: Self.fast)).tone == .attention)
        #expect(RowBar.make(usedPercent: 42, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.behind, burn: Self.fast)).tone == .attention)
    }

    /// On pace, behind, or ahead without a counted run-out (the hold back)
    /// and without a fast burn: neutral, whatever the warning threshold.
    @Test func neutralOtherwise() {
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.onPace, burn: Self.calm)).tone == .neutral)
        #expect(RowBar.make(usedPercent: 42, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.behind, burn: nil)).tone == .neutral)
        #expect(RowBar.make(usedPercent: 12, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.aheadNoRunOut, burn: nil)).tone == .neutral)
        #expect(RowBar.make(usedPercent: 92, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.onPace, burn: nil)).tone == .neutral)
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: nil).tone == .neutral)
    }

    // MARK: - Note (FR-004)

    @Test func noteExactlyOnAttention() throws {
        let attention = RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: Self.fast))
        let note = try #require(attention.note)
        #expect(note.pace == Self.ahead)
        #expect(note.fastRunOut == Self.fastRunOut)
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.onPace, burn: nil)).note == nil)
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: nil).note == nil)
    }

    @Test func noteTextInTheSectionsFormat() throws {
        let runOut = try #require(RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used,
                                              reading: PaceReading(pace: Self.ahead, burn: Self.calm)).note)
        #expect(runOut.text(times: Self.relative) == "20% ahead \u{00B7} runs out in 1d 12h")
        let fast = try #require(RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used,
                                            reading: PaceReading(pace: Self.ahead, burn: Self.fast)).note)
        #expect(fast.text(times: Self.relative) == "20% ahead \u{00B7} burning fast \u{00B7} runs out in 3h 10m")
        let onPace = try #require(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used,
                                              reading: PaceReading(pace: Self.onPace, burn: Self.fast)).note)
        #expect(onPace.text(times: Self.relative) == "on pace \u{00B7} burning fast \u{00B7} runs out in 3h 10m")
        #expect(runOut.text(times: Self.absolute) == "20% ahead \u{00B7} runs out \(Self.absolute.runOut(Self.runOut))")
    }

    /// The note's tooltip is only the run-out time in the other form, the
    /// fast run-out when the row burns fast (spec 025 FR-019, amended by
    /// spec 026 FR-019b).
    @Test func noteTooltipIsTheRunOutInTheOtherForm() throws {
        let note = try #require(RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used,
                                            reading: PaceReading(pace: Self.ahead, burn: nil)).note)
        #expect(note.tooltip(times: Self.relative) == Self.long(Self.runOut))
        #expect(note.tooltip(times: Self.absolute) == "in 1d 12h")
        let fast = try #require(RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used,
                                            reading: PaceReading(pace: Self.ahead, burn: Self.fast)).note)
        #expect(fast.tooltip(times: Self.relative) == Self.long(Self.fastRunOut))
        #expect(fast.tooltip(times: Self.absolute) == "in 3h 10m")
    }

    // MARK: - Accessibility (FR-006)

    @Test func accessibilitySummaryAlsoWithoutANote() {
        let onPace = RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.onPace, burn: nil))
        #expect(onPace.note == nil)
        #expect(onPace.accessibilitySummary(times: Self.relative) == "on pace")
        let behind = RowBar.make(usedPercent: 42, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.behind, burn: Self.calm))
        #expect(behind.accessibilitySummary(times: Self.relative) == "8% behind")
        let ahead = RowBar.make(usedPercent: 60, limitReached: false, thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: nil))
        #expect(ahead.accessibilitySummary(times: Self.relative) == "20% ahead \u{00B7} runs out in 1d 12h")
        #expect(RowBar.make(usedPercent: 38, limitReached: false, thresholds: [], direction: .used, reading: nil).accessibilitySummary(times: Self.relative) == nil)
    }

    // MARK: - One pace source (FR-030)

    /// The tick, the tone, the note and the accessibility summary all come
    /// from the one reading: a note shows exactly on attention, its text is
    /// the summary VoiceOver reads, and without a reading there is no tick,
    /// note or summary.
    @Test func tickToneNoteAndSummaryShareOneReading() {
        let readings: [PaceReading?] = [
            nil,
            PaceReading(pace: Self.onPace, burn: Self.calm),
            PaceReading(pace: Self.onPace, burn: Self.fast),
            PaceReading(pace: Self.ahead, burn: nil),
            PaceReading(pace: Self.ahead, burn: Self.fast),
            PaceReading(pace: Self.aheadNoRunOut, burn: nil),
            PaceReading(pace: Self.behind, burn: Self.fast),
        ]
        var bars: [RowBar] = []
        for reading in readings {
            for used in [10.0, 60, 100] {
                bars.append(RowBar.make(usedPercent: used, limitReached: false, thresholds: [], direction: .used, reading: reading))
                bars.append(RowBar.make(usedPercent: used, limitReached: true, thresholds: [], direction: .used, reading: reading))
                bars.append(RowBar.budget(Self.budget(Decimal(used), 100), thresholds: [], direction: .used, reading: reading))
            }
        }
        for bar in bars {
            #expect((bar.note != nil) == (bar.tone == .attention))
            #expect((bar.tick != nil) == (bar.accessibilitySummary(times: Self.relative) != nil))
            if let note = bar.note {
                for times in [Self.relative, Self.absolute] {
                    #expect(bar.accessibilitySummary(times: times) == note.text(times: times))
                }
            }
        }
        #expect(bars.contains { $0.tone == .attention })
        #expect(bars.contains { $0.tone == .neutral && $0.tick != nil })
        #expect(bars.contains { $0.tone == .overLimit && $0.tick != nil })
    }

    // MARK: - Budget (FR-003, FR-009)

    static let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    /// A budget entry whose percent is the header's rounding of the spend
    /// share, as the aggregator computes it, unless `percent` is given.
    static func budget(_ spent: Decimal, _ budget: Decimal, percent: Int? = nil) -> GroupEntry {
        GroupEntry(spentUSD: spent, budgetUSD: budget, percent: percent ?? PercentFormatter.rounded(spent: spent, budget: budget),
                   incomplete: false, period: .monthly, window: month, breakdown: .empty, members: ["a"])
    }

    @Test func groupEntryUsedPercentIsTheUnroundedShare() {
        #expect(Self.budget(1596, 300).usedPercent == 532)
        #expect(abs(Self.budget(1, 3).usedPercent - 100.0 / 3) < 1e-9)
        #expect(Self.budget(0, 300).usedPercent == 0)
        #expect(Self.budget(40, 0).usedPercent == 0)
        // A budget far over its limit: a full red bar.
        let bar = RowBar.budget(Self.budget(1596, 300), thresholds: [], direction: .used, reading: nil)
        #expect(bar.fill == 1)
        #expect(bar.tone == .overLimit)
    }

    /// At the .5 boundary the bar is red exactly when the header shows 100%:
    /// a spend share of 99.5% reads 100% and draws a red bar, 99.4% reads
    /// 99% and does not. The fill keeps the unrounded share.
    @Test func budgetToneAtTheHalfPercentBoundary() {
        let half = Self.budget(995, 1000)
        #expect(half.percent == 100)
        let red = RowBar.budget(half, thresholds: [], direction: .used, reading: nil)
        #expect(red.tone == .overLimit)
        #expect(abs(red.fill - 0.995) < 1e-12)
        let below = Self.budget(994, 1000)
        #expect(below.percent == 99)
        let neutral = RowBar.budget(below, thresholds: [], direction: .used, reading: nil)
        #expect(neutral.tone == .neutral)
        #expect(abs(neutral.fill - 0.994) < 1e-12)
    }

    /// The tone comes from the header's percent (`GroupEntry.percent`), not
    /// from a second rounding of the spend share, so 99% never sits next to
    /// a red bar and 100% always does.
    @Test func budgetToneFollowsTheHeaderPercent() {
        #expect(RowBar.budget(Self.budget(995, 1000, percent: 99), thresholds: [], direction: .used, reading: nil).tone == .neutral)
        #expect(RowBar.budget(Self.budget(994, 1000, percent: 100), thresholds: [], direction: .used, reading: nil).tone == .overLimit)
    }

    /// Below the limit a budget's bar calls for attention like a window's;
    /// over it, red wins and no note shows (FR-003, FR-004).
    @Test func budgetAttentionAndNote() throws {
        let attention = RowBar.budget(Self.budget(60, 100), thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: Self.fast))
        #expect(attention.tone == .attention)
        #expect(attention.tick == 0.4)
        let note = try #require(attention.note)
        #expect(note.pace == Self.ahead)
        let over = RowBar.budget(Self.budget(300, 300), thresholds: [], direction: .used, reading: PaceReading(pace: Self.ahead, burn: Self.fast))
        #expect(over.tone == .overLimit)
        #expect(over.note == nil)
    }

    // MARK: - Levels from thresholds (spec 030 FR-005, FR-006)

    /// Thresholds 80 and 90: at 85% the row is warning and the bar keeps its
    /// pace tone; at 91% the row and the bar are critical and red.
    @Test func windowLevelFromThresholds() {
        let warning = RowBar.make(usedPercent: 85, limitReached: false, thresholds: [80, 90], direction: .used, reading: nil)
        #expect(warning.level == .warning)
        #expect(warning.percentTone == .warning)
        #expect(warning.tone == .neutral)
        let attention = RowBar.make(usedPercent: 85, limitReached: false, thresholds: [80, 90], direction: .used,
                                    reading: PaceReading(pace: Self.ahead, burn: nil))
        #expect(attention.level == .warning)
        #expect(attention.tone == .attention)
        #expect(attention.note != nil)
        let critical = RowBar.make(usedPercent: 91, limitReached: false, thresholds: [80, 90], direction: .used,
                                   reading: PaceReading(pace: Self.ahead, burn: nil))
        #expect(critical.level == .critical)
        #expect(critical.percentTone == .critical)
        #expect(critical.tone == .overLimit)
        #expect(critical.note == nil)
        let normal = RowBar.make(usedPercent: 79, limitReached: false, thresholds: [80, 90], direction: .used, reading: nil)
        #expect(normal.level == .normal)
        #expect(normal.percentTone == .primary)
    }

    /// A row's own reached limit is critical at any percent (FR-003, FR-005).
    @Test func ownReachedLimitIsCritical() {
        let bar = RowBar.make(usedPercent: 40, limitReached: true, thresholds: [80, 90], direction: .used, reading: nil)
        #expect(bar.level == .critical)
        #expect(bar.percentTone == .critical)
        #expect(bar.tone == .overLimit)
    }

    /// The level uses the rounded percent the row shows: 89.6% reads 90%
    /// and is critical at a threshold of 90.
    @Test func windowLevelUsesTheRoundedPercent() {
        #expect(RowBar.make(usedPercent: 89.6, limitReached: false, thresholds: [80, 90], direction: .used, reading: nil).level == .critical)
        #expect(RowBar.make(usedPercent: 89.4, limitReached: false, thresholds: [80, 90], direction: .used, reading: nil).level == .warning)
        #expect(RowBar.make(usedPercent: .nan, limitReached: false, thresholds: [80, 90], direction: .used, reading: nil).level == .normal)
    }

    /// Thresholds 50 and 75: a budget at 60% is warning with a neutral bar,
    /// at 80% critical and red (US1 scenario 4).
    @Test func budgetLevelFromThresholds() {
        let warning = RowBar.budget(Self.budget(60, 100), thresholds: [50, 75], direction: .used, reading: nil)
        #expect(warning.level == .warning)
        #expect(warning.percentTone == .warning)
        #expect(warning.tone == .neutral)
        let critical = RowBar.budget(Self.budget(80, 100), thresholds: [50, 75], direction: .used, reading: nil)
        #expect(critical.level == .critical)
        #expect(critical.tone == .overLimit)
    }

    /// Without thresholds the old behavior holds: red exactly at a rounded
    /// 100, warning from 80, which never colors the bar.
    @Test func noThresholdsKeepTheOldBehavior() {
        #expect(RowBar.budget(Self.budget(995, 1000), thresholds: [], direction: .used, reading: nil).tone == .overLimit)
        #expect(RowBar.budget(Self.budget(994, 1000), thresholds: [], direction: .used, reading: nil).tone == .neutral)
        #expect(RowBar.budget(Self.budget(994, 1000), thresholds: [], direction: .used, reading: nil).level == .warning)
        #expect(RowBar.make(usedPercent: 92, limitReached: false, thresholds: [], direction: .used, reading: nil).tone == .neutral)
        #expect(RowBar.make(usedPercent: 92, limitReached: false, thresholds: [], direction: .used, reading: nil).level == .warning)
    }

    /// FR-006: the bar is red exactly when the level is critical.
    @Test func redBarExactlyAtCritical() {
        for used in stride(from: 0.0, through: 120, by: 2.5) {
            for thresholds in [[], [80, 90], [50, 75], [90, 90], [80, 120]] {
                for reached in [false, true] {
                    let bar = RowBar.make(usedPercent: used, limitReached: reached, thresholds: thresholds, direction: .used,
                                          reading: PaceReading(pace: Self.ahead, burn: nil))
                    #expect((bar.tone == .overLimit) == (bar.level == .critical))
                    #expect(bar.percentTone == PercentTone(bar.level))
                }
            }
        }
    }

    // MARK: - Direction (spec 030 FR-010, FR-014)

    /// In direction remaining the fill is the remaining share and the tick
    /// the expected remaining share; level, tone and note stay as in used.
    @Test func remainingFillAndTick() {
        let reading = PaceReading(pace: Self.ahead, burn: nil)
        let used = RowBar.make(usedPercent: 60, limitReached: false, thresholds: [80, 90], direction: .used, reading: reading)
        let remaining = RowBar.make(usedPercent: 60, limitReached: false, thresholds: [80, 90], direction: .remaining, reading: reading)
        #expect(used.fill == 0.6)
        #expect(abs(remaining.fill - 0.4) < 1e-12)
        #expect(used.tick == 0.4)
        #expect(abs((remaining.tick ?? -1) - 0.6) < 1e-12)
        #expect(remaining.level == used.level)
        #expect(remaining.tone == used.tone)
        #expect(remaining.note == used.note)
        #expect(remaining.percentTone == used.percentTone)
    }

    /// Spec Edge Cases: 99.6% used reads 0% left, is critical in both
    /// directions, and fills about 0.004 of the bar.
    @Test func nearlyFullRowInRemaining() {
        let bar = RowBar.make(usedPercent: 99.6, limitReached: false, thresholds: [], direction: .remaining, reading: nil)
        #expect(DirectedPercent(usedPercent: PercentFormatter.rounded(99.6), direction: .remaining).text == "0%")
        #expect(bar.level == .critical)
        #expect(bar.tone == .overLimit)
        #expect(abs(bar.fill - 0.004) < 1e-9)
    }

    /// A budget above 100% has an empty bar in remaining and a full one in
    /// used; both are red.
    @Test func budgetFillInBothDirections() {
        let over = Self.budget(115, 100)
        let remaining = RowBar.budget(over, thresholds: [], direction: .remaining, reading: nil)
        let used = RowBar.budget(over, thresholds: [], direction: .used, reading: nil)
        #expect(remaining.fill == 0)
        #expect(used.fill == 1)
        #expect(remaining.tone == .overLimit)
        #expect(used.tone == .overLimit)
        #expect(abs(RowBar.budget(Self.budget(40, 100), thresholds: [], direction: .remaining, reading: nil).fill - 0.6) < 1e-12)
    }

    /// FR-014: levels and tones never depend on the direction.
    @Test func levelsAreTheSameInBothDirections() {
        for used in stride(from: 0.0, through: 120, by: 5) {
            for thresholds in [[], [80, 90], [50, 75]] {
                let reading = PaceReading(pace: Self.ahead, burn: Self.fast)
                let a = RowBar.make(usedPercent: used, limitReached: false, thresholds: thresholds, direction: .used, reading: reading)
                let b = RowBar.make(usedPercent: used, limitReached: false, thresholds: thresholds, direction: .remaining, reading: reading)
                #expect(a.level == b.level)
                #expect(a.tone == b.tone)
            }
        }
    }
}
