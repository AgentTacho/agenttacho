import Foundation
import Testing
@testable import UsageCore

/// spec 025 FR-006 to FR-008, FR-019: the reset text, its tooltip and the
/// accessibility label of a window row and a budget's amount line, from one
/// choice of reset text.
@Suite struct RowTextTests {
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
    static let resetsAt = now.addingTimeInterval(2 * hour + 26 * 60)
    static let onPace = RowBar.make(usedPercent: 38, limitReached: false,
                                    reading: PaceReading(pace: Pace(expectedPercent: 38, delta: 0, status: .onPace, runOut: nil), burn: nil))
    static let empty = RowBar.make(usedPercent: 0, limitReached: false, reading: nil)

    static func window(_ name: String = "5-hour", percent: Int?, resetsAt: Date?, observedWithReset: Bool = true,
                       limitReached: Bool = false, bar: RowBar?, times: TimeText = relative) -> RowText {
        RowText.window(name: name, percent: percent, resetsAt: resetsAt, observedWithReset: observedWithReset,
                       limitReached: limitReached, bar: bar, times: times)
    }

    // MARK: - Window rows

    @Test func windowWithAResetTime() {
        let text = Self.window(percent: 38, resetsAt: Self.resetsAt, bar: Self.onPace)
        #expect(text.reset == "resets in 2h 26m")
        #expect(text.resetTooltip == Self.relative.resetTooltip(Self.resetsAt))
        #expect(text.accessibilityLabel == "5-hour, 38%, resets in 2h 26m, on pace")
    }

    /// FR-019: in the absolute format the tooltip is the relative form, and
    /// the label reads the time as shown.
    @Test func absoluteFormatHasTheRelativeTooltip() {
        let text = Self.window(percent: 38, resetsAt: Self.resetsAt, bar: Self.onPace, times: Self.absolute)
        #expect(text.reset == Self.absolute.reset(Self.resetsAt))
        #expect(text.resetTooltip == "in 2h 26m")
        #expect(text.accessibilityLabel == "5-hour, 38%, \(Self.absolute.reset(Self.resetsAt)), on pace")
    }

    /// FR-008: a window observed without a reset time never started.
    @Test func windowObservedWithoutAResetTimeIsNotStarted() {
        let text = Self.window(percent: 0, resetsAt: nil, observedWithReset: false, bar: Self.empty)
        #expect(text.reset == "not started")
        #expect(text.resetTooltip == nil)
        #expect(text.accessibilityLabel == "5-hour, 0%, not started")
    }

    /// FR-008, spec 010 FR-016: a window that reset since the observation
    /// shows no reset text.
    @Test func windowResetSinceTheObservationHasNoResetText() {
        let text = Self.window("7-day", percent: 0, resetsAt: nil, observedWithReset: true, bar: Self.empty)
        #expect(text.reset == nil)
        #expect(text.resetTooltip == nil)
        #expect(text.accessibilityLabel == "7-day, 0%")
    }

    /// FR-008: an unavailable window has no reset text and says so.
    @Test func unavailableWindow() {
        let text = Self.window(percent: nil, resetsAt: Self.resetsAt, bar: nil)
        #expect(text.reset == nil)
        #expect(text.resetTooltip == nil)
        #expect(text.accessibilityLabel == "5-hour, unavailable")
    }

    /// FR-006, FR-007: the pace summary also without a note, and a reached
    /// Codex limit.
    @Test func labelNamesThePaceAndAReachedLimit() {
        let behind = RowBar.make(usedPercent: 42, limitReached: false,
                                 reading: PaceReading(pace: Pace(expectedPercent: 50, delta: -8, status: .behind(8), runOut: nil), burn: nil))
        #expect(behind.note == nil)
        #expect(Self.window("weekly", percent: 42, resetsAt: Self.resetsAt, bar: behind).accessibilityLabel
                == "weekly, 42%, resets in 2h 26m, 8% behind")
        let reached = RowBar.make(usedPercent: 100, limitReached: true, reading: nil)
        #expect(Self.window(percent: 100, resetsAt: Self.resetsAt, limitReached: true, bar: reached).accessibilityLabel
                == "5-hour, 100%, resets in 2h 26m, Limit reached")
    }

    /// spec 027 FR-003: the headline row adds "shown in menu bar" to its
    /// label; other rows stay as they are.
    @Test func headlineRowSaysShownInMenuBar() {
        func label(_ isHeadline: Bool, percent: Int? = 38) -> String {
            RowText.window(name: "5-hour", percent: percent, resetsAt: Self.resetsAt, observedWithReset: true, limitReached: false,
                           bar: Self.onPace, times: Self.relative, isHeadline: isHeadline).accessibilityLabel
        }
        #expect(label(true) == "5-hour, 38%, resets in 2h 26m, on pace, shown in menu bar")
        #expect(label(false) == "5-hour, 38%, resets in 2h 26m, on pace")
        #expect(label(true, percent: nil) == "5-hour, unavailable, shown in menu bar")
        #expect(Self.window(percent: 38, resetsAt: Self.resetsAt, bar: Self.onPace).accessibilityLabel == label(false))
    }

    // MARK: - Budget line (FR-006, FR-009)

    @Test func budgetLine() {
        let reset = isoDate("2026-11-01T00:00:00Z")
        let ahead = RowBar.make(usedPercent: 60, limitReached: false,
                                reading: PaceReading(pace: Pace(expectedPercent: 40, delta: 20, status: .ahead(20),
                                                                runOut: Self.now.addingTimeInterval(36 * Self.hour)), burn: nil))
        let text = RowText.budget(name: "Company budget", amount: "1,596 of 300 US$/month", resetsAt: reset, bar: ahead, times: Self.relative)
        #expect(text.reset == "resets in 9d 9h")
        #expect(text.resetTooltip == Self.relative.resetTooltip(reset))
        #expect(text.accessibilityLabel
                == "Company budget, 1,596 of 300 US$/month, resets in 9d 9h, 20% ahead \u{00B7} runs out in 1d 12h")
    }

    @Test func budgetLineWithoutAPace() {
        let reset = isoDate("2026-11-01T00:00:00Z")
        let text = RowText.budget(name: "Team", amount: "0 of 60 US$/week", resetsAt: reset, bar: Self.empty, times: Self.relative)
        #expect(text.accessibilityLabel == "Team, 0 of 60 US$/week, resets in 9d 9h")
    }

    // MARK: - Codex lookup (FR-008)

    /// The observed window of a name tells "not started" from "reset since".
    @Test func codexWindowObservedWithReset() {
        let observation = CodexLimitObservation(planType: "plus", observedAt: Self.now, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 10, resetsAt: Self.resetsAt),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 0, resetsAt: nil),
        ])
        let entry = CodexLimitsEntry(observation: observation, state: .live)
        #expect(entry.observedWithReset("5-hour"))
        #expect(!entry.observedWithReset("weekly"))
        #expect(!entry.observedWithReset("30-day"))
        #expect(!CodexLimitsEntry(observation: nil, state: .live).observedWithReset("5-hour"))
    }
}
