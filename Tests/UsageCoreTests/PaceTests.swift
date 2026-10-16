import Foundation
import Testing
@testable import UsageCore

/// spec 011 FR-001 to FR-008, research R5: the pace computation, the
/// tolerance band, the hold back and the summary text.
@Suite struct PaceTests {
    static let start = isoDate("2026-10-11T09:00:00Z")
    static let week = WindowResolver.weekSeconds
    static let reset = start.addingTimeInterval(week)

    /// A pace in a 7-day window starting at `start`, observed after
    /// `elapsedShare` of the window, evaluated at the observation time.
    static func weekly(_ used: Double, elapsedShare: Double) -> Pace? {
        let observed = start.addingTimeInterval(week * elapsedShare)
        return Pace.compute(usedPercent: used, windowStart: start, resetsAt: reset, observedAt: observed, now: observed)
    }

    // MARK: - Expected percent (FR-001)

    @Test func expectedPercentIsTheElapsedShare() throws {
        #expect(try #require(Self.weekly(0, elapsedShare: 0)).expectedPercent == 0)
        #expect(try #require(Self.weekly(0, elapsedShare: 0.5)).expectedPercent == 50)
        let quarter = try #require(Self.weekly(0, elapsedShare: 0.25))
        #expect(abs(quarter.expectedPercent - 25) < 1e-9)
    }

    @Test func expectedPercentIsClampedToTheWindow() throws {
        let before = Pace.compute(usedPercent: 10, windowStart: Self.start, resetsAt: Self.reset,
                                  observedAt: Self.start.addingTimeInterval(-3600), now: Self.start)
        #expect(try #require(before).expectedPercent == 0)
        let after = Pace.compute(usedPercent: 10, windowStart: Self.start, resetsAt: Self.reset,
                                 observedAt: Self.reset.addingTimeInterval(3600), now: Self.start)
        #expect(try #require(after).expectedPercent == 100)
    }

    // MARK: - Delta (FR-003)

    /// The unrounded used percent minus the expected percent (3/7 = 42.857),
    /// rounded to the nearest whole number.
    @Test func deltaUsesTheUnroundedUsedPercent() throws {
        #expect(try #require(Self.weekly(47.6, elapsedShare: 3.0 / 7)).delta == 5)
        #expect(try #require(Self.weekly(47.4, elapsedShare: 3.0 / 7)).delta == 5)
        #expect(try #require(Self.weekly(48.0, elapsedShare: 3.0 / 7)).delta == 5)
        #expect(try #require(Self.weekly(48.4, elapsedShare: 3.0 / 7)).delta == 6)
    }

    // MARK: - Band (FR-008)

    @Test func bandLimitsAreInclusive() throws {
        #expect(try #require(Self.weekly(55, elapsedShare: 0.5)).status == .onPace)
        #expect(try #require(Self.weekly(45, elapsedShare: 0.5)).status == .onPace)
        #expect(try #require(Self.weekly(56, elapsedShare: 0.5)).status == .ahead(6))
        #expect(try #require(Self.weekly(44, elapsedShare: 0.5)).status == .behind(6))
    }

    /// FR-003 on the negative side: -5.5 rounds away from zero to -6.
    @Test func negativeFractionalDeltasRoundAwayFromZero() throws {
        let edge = try #require(Self.weekly(44.6, elapsedShare: 0.5))
        #expect(edge.delta == -5)
        #expect(edge.status == .onPace)
        #expect(try #require(Self.weekly(44.5, elapsedShare: 0.5)).status == .behind(6))
        #expect(try #require(Self.weekly(44.1, elapsedShare: 0.5)).status == .behind(6))
    }

    /// FR-005: the first delta beyond the band (+6, also from an unrounded
    /// +5.5) already has a run-out before the reset.
    @Test func firstAheadDeltaHasARunOut() throws {
        for used in [56.0, 55.5] {
            let pace = try #require(Self.weekly(used, elapsedShare: 0.5))
            #expect(pace.status == .ahead(6))
            let runOut = try #require(pace.runOut)
            #expect(runOut < Self.reset)
        }
    }

    // MARK: - Run-out (FR-004 to FR-006)

    @Test func noRunOutWhenOnPaceOrBehind() throws {
        // +5 is on pace, so no run-out although the projection reaches 100%
        // shortly before the reset (spec edge case "slightly ahead").
        #expect(try #require(Self.weekly(55, elapsedShare: 0.5)).runOut == nil)
        #expect(try #require(Self.weekly(20, elapsedShare: 0.6)).runOut == nil)
    }

    @Test func runOutIsWithheldDuringTheHoldBack() throws {
        // Far ahead, but only 5% (and 9.9%) of the window has elapsed.
        let early = try #require(Self.weekly(80, elapsedShare: 0.05))
        #expect(early.status == .ahead(75))
        #expect(early.runOut == nil)
        let almost = try #require(Self.weekly(80, elapsedShare: 0.099))
        #expect(almost.runOut == nil)
    }

    @Test func runOutStartsAtExactlyTenPercent() throws {
        // A 10-hour window observed after exactly 1 hour: elapsed share 0.1.
        let start = Self.start
        let reset = start.addingTimeInterval(36_000)
        let observed = start.addingTimeInterval(3_600)
        let pace = try #require(Pace.compute(usedPercent: 50, windowStart: start, resetsAt: reset, observedAt: observed, now: observed))
        #expect(pace.status == .ahead(40))
        #expect(pace.runOut == observed.addingTimeInterval(3_600))
    }

    @Test func noRunOutAtZeroUsage() throws {
        let early = try #require(Self.weekly(0, elapsedShare: 0.02))
        #expect(early.status == .onPace)
        #expect(early.runOut == nil)
        let later = try #require(Self.weekly(0, elapsedShare: 0.6))
        #expect(later.status == .behind(60))
        #expect(later.runOut == nil)
    }

    @Test func negativeUsedPercentIsBehindWithoutRunOut() throws {
        let pace = try #require(Self.weekly(-3, elapsedShare: 0.2))
        #expect(pace.status == .behind(23))
        #expect(pace.delta == -23)
        #expect(pace.runOut == nil)
    }

    @Test func runOutIsTheLinearExtrapolation() throws {
        let observed = Self.start.addingTimeInterval(Self.week * 0.25)
        let pace = try #require(Self.weekly(40, elapsedShare: 0.25))
        let elapsed = observed.timeIntervalSince(Self.start)
        let expected = observed.addingTimeInterval((100 - 40) * elapsed / 40)
        let runOut = try #require(pace.runOut)
        #expect(abs(runOut.timeIntervalSince(expected)) < 0.001)
        #expect(runOut < Self.reset)
    }

    /// FR-005: a run-out at or before the snapshot time does not count (an
    /// old observation that is not marked stale); the delta still shows.
    /// 40% at 25% elapsed runs out at 62.5% of the window.
    @Test func runOutAtOrBeforeTheSnapshotTimeDoesNotCount() throws {
        let observed = Self.start.addingTimeInterval(Self.week * 0.25)
        let runOutAt = Self.start.addingTimeInterval(Self.week * 0.625)
        func pace(now: Date) throws -> Pace {
            try #require(Pace.compute(usedPercent: 40, windowStart: Self.start, resetsAt: Self.reset,
                                      observedAt: observed, now: now))
        }
        let later = try pace(now: Self.start.addingTimeInterval(Self.week * 0.7))
        #expect(later.status == .ahead(15))
        #expect(later.runOut == nil)
        #expect(try pace(now: runOutAt).runOut == nil)
        #expect(try pace(now: runOutAt.addingTimeInterval(-60)).runOut != nil)
    }

    // MARK: - Exclusions (FR-007)

    @Test func noPaceForExcludedValues() {
        #expect(Self.weekly(100, elapsedShare: 0.5) == nil)
        #expect(Self.weekly(104, elapsedShare: 0.5) == nil)
        // Shown as 100% (rounded), so the over-limit styling covers it.
        #expect(Self.weekly(99.6, elapsedShare: 0.5) == nil)
        #expect(Self.weekly(99.5, elapsedShare: 0.5) == nil)
        #expect(Self.weekly(99.4, elapsedShare: 0.5) != nil)
        #expect(Self.weekly(.nan, elapsedShare: 0.5) == nil)
        #expect(Self.weekly(.infinity, elapsedShare: 0.5) == nil)
        #expect(Self.weekly(-.infinity, elapsedShare: 0.5) == nil)
        // A window of length 0 or less.
        #expect(Pace.compute(usedPercent: 10, windowStart: Self.reset, resetsAt: Self.reset,
                             observedAt: Self.start, now: Self.start) == nil)
        #expect(Pace.compute(usedPercent: 10, windowStart: Self.reset, resetsAt: Self.start,
                             observedAt: Self.start, now: Self.start) == nil)
    }

    @Test func noPaceWhenTheWindowHasResetAtTheSnapshotTime() {
        let observed = Self.start.addingTimeInterval(Self.week * 0.5)
        #expect(Pace.compute(usedPercent: 40, windowStart: Self.start, resetsAt: Self.reset,
                             observedAt: observed, now: Self.reset) == nil)
        #expect(Pace.compute(usedPercent: 40, windowStart: Self.start, resetsAt: Self.reset,
                             observedAt: observed, now: Self.reset.addingTimeInterval(1)) == nil)
        #expect(Pace.compute(usedPercent: 40, windowStart: Self.start, resetsAt: Self.reset,
                             observedAt: observed, now: Self.reset.addingTimeInterval(-1)) != nil)
    }

    // MARK: - Spec examples

    /// Story 1 intro: 145 of 300 dollars at the start of 10 October in a
    /// window from 1 October to 1 November gives 19% ahead and a run-out on
    /// Mon 19 Oct 14:53 (local time, Europe/Berlin).
    @Test func monthlyBudgetExample() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        func local(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        let observed = local(10, 10)
        let pace = try #require(Pace.compute(usedPercent: 145.0 / 300 * 100, windowStart: local(10, 1), resetsAt: local(11, 1),
                                             observedAt: observed, now: observed))
        #expect(pace.delta == 19)
        #expect(pace.status == .ahead(19))
        let runOut = try #require(pace.runOut)
        let minute = calendar.dateInterval(of: .minute, for: runOut)?.start
        #expect(minute == local(10, 19, 14, 53))
    }

    /// Story 2 intro: 7-day window at 62% three days in gives 19% ahead and
    /// a run-out 44 h 07 min after the observation.
    @Test func sevenDayExample() throws {
        let observed = Self.start.addingTimeInterval(3 * 24 * 3600)
        let pace = try #require(Self.weekly(62, elapsedShare: 3.0 / 7))
        #expect(pace.delta == 19)
        let runOut = try #require(pace.runOut)
        let minutes = Int(runOut.timeIntervalSince(observed) / 60)
        #expect(minutes == 44 * 60 + 7)
    }

    /// Story 1 acceptance scenarios 1 to 3 and Story 3 scenario 3.
    @Test func storyScenarios() throws {
        let ahead = try #require(Self.weekly(48, elapsedShare: 0.33))
        #expect(ahead.status == .ahead(15))
        let runOut = try #require(ahead.runOut)
        #expect(runOut < Self.reset)

        let even = try #require(Self.weekly(50, elapsedShare: 0.5))
        #expect(even.status == .onPace)
        #expect(even.runOut == nil)

        let behind = try #require(Self.weekly(20, elapsedShare: 0.6))
        #expect(behind.status == .behind(40))
        #expect(behind.runOut == nil)

        let held = try #require(Self.weekly(60, elapsedShare: 0.05))
        #expect(held.runOut == nil)
    }

    // MARK: - Summary text (FR-008)

    @Test func summaryText() {
        let runOut = Self.reset
        let text: (Date) -> String = { $0 == runOut ? "X" : "?" }
        #expect(Pace(expectedPercent: 50, delta: 3, status: .onPace, runOut: nil).summary(runOutText: text) == "on pace")
        #expect(Pace(expectedPercent: 50, delta: 12, status: .ahead(12), runOut: nil).summary(runOutText: text) == "12% ahead")
        #expect(Pace(expectedPercent: 50, delta: -8, status: .behind(8), runOut: nil).summary(runOutText: text) == "8% behind")
        #expect(Pace(expectedPercent: 50, delta: 12, status: .ahead(12), runOut: runOut).summary(runOutText: text)
                == "12% ahead \u{00B7} runs out X")
    }

    /// spec 017 FR-012, US3 AS1: the meter is orange with a spec 011
    /// run-out or a fast burn, also while behind.
    @Test func attentionColorWithARunOutOrAFastBurn() {
        let behind = Pace(expectedPercent: 50, delta: -8, status: .behind(8), runOut: nil)
        let fast = BurnRate(sustainablePerHour: 1, averagePerHour: nil, recentPerHour: 7.2, fastRunOut: Self.reset)
        let slow = BurnRate(sustainablePerHour: 1, averagePerHour: nil, recentPerHour: 1.5, fastRunOut: nil)
        #expect(behind.usesAttentionColor(burn: fast))
        #expect(!behind.usesAttentionColor(burn: slow))
        #expect(!behind.usesAttentionColor(burn: nil))
        #expect(Pace(expectedPercent: 50, delta: 19, status: .ahead(19), runOut: Self.reset).usesAttentionColor(burn: nil))
    }

    /// spec 017 FR-012, contracts/burn-rate-display.md: a fast burn names
    /// itself and replaces the spec 011 run-out with the fast run-out.
    @Test func summaryTextWithAFastBurn() {
        let runOut = Self.reset
        let fast = Self.reset.addingTimeInterval(-86_400)
        let text: (Date) -> String = { $0 == runOut ? "X" : $0 == fast ? "Y" : "?" }
        // US3 AS1: behind, no spec 011 run-out.
        #expect(Pace(expectedPercent: 50, delta: -8, status: .behind(8), runOut: nil).summary(runOutText: text, fastRunOut: fast)
                == "8% behind \u{00B7} burning fast \u{00B7} runs out Y")
        // US3 AS2: ahead with a spec 011 run-out, which the fast run-out replaces.
        #expect(Pace(expectedPercent: 50, delta: 19, status: .ahead(19), runOut: runOut).summary(runOutText: text, fastRunOut: fast)
                == "19% ahead \u{00B7} burning fast \u{00B7} runs out Y")
        #expect(Pace(expectedPercent: 50, delta: 2, status: .onPace, runOut: nil).summary(runOutText: text, fastRunOut: fast)
                == "on pace \u{00B7} burning fast \u{00B7} runs out Y")
        // Without a fast run-out the spec 011 texts stay.
        #expect(Pace(expectedPercent: 50, delta: 19, status: .ahead(19), runOut: runOut).summary(runOutText: text, fastRunOut: nil)
                == "19% ahead \u{00B7} runs out X")
        #expect(Pace(expectedPercent: 50, delta: -8, status: .behind(8), runOut: nil).summary(runOutText: text, fastRunOut: nil)
                == "8% behind")
    }

    // MARK: - Meter (FR-008)

    /// The bar of the pace meter as a share of its half track: 0 within the
    /// band (tick only), positive ahead, negative behind, proportional to
    /// the delta and full (+/-1) at 50 points or more.
    @Test func meterOffset() {
        func offset(_ delta: Int, _ status: PaceStatus) -> Double {
            Pace(expectedPercent: 50, delta: delta, status: status, runOut: nil).meterOffset
        }
        #expect(offset(0, .onPace) == 0)
        #expect(offset(5, .onPace) == 0)
        #expect(offset(-5, .onPace) == 0)
        #expect(offset(6, .ahead(6)) == 6.0 / 50)
        #expect(offset(-18, .behind(18)) == -18.0 / 50)
        #expect(offset(25, .ahead(25)) == 0.5)
        #expect(offset(50, .ahead(50)) == 1)
        #expect(offset(80, .ahead(80)) == 1)
        #expect(offset(-120, .behind(120)) == -1)
    }
}

/// spec 011 FR-001, FR-002, FR-007: the pace of a budget (group or own
/// budget), observed at the snapshot time.
@Suite struct GroupPaceTests {
    static let weekly = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    static let monthly = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    static func entry(spent: Decimal, budget: Decimal = 100, percent: Int = 0, window: DateInterval = weekly,
                      period: BudgetPeriod = .weekly, members: [String] = ["a"]) -> GroupEntry {
        GroupEntry(spentUSD: spent, budgetUSD: budget, percent: percent, incomplete: false, period: period,
                   window: window, breakdown: .empty, members: members)
    }

    /// The used percent is `spentUSD / budgetUSD * 100` unrounded, not the
    /// rounded `percent` field.
    @Test func usesTheUnroundedSpendShare() throws {
        let halfway = Self.weekly.start.addingTimeInterval(Self.weekly.duration / 2)
        let pace = try #require(Self.entry(spent: Decimal(string: "55.6")!, percent: 0).pace(now: halfway))
        #expect(pace.status == .ahead(6))
        let below = try #require(Self.entry(spent: Decimal(string: "55.4")!, percent: 99).pace(now: halfway))
        #expect(below.status == .onPace)
    }

    /// The snapshot time is the observation time (FR-002).
    @Test func observedAtTheSnapshotTime() throws {
        let now = Self.weekly.start.addingTimeInterval(Self.weekly.duration / 4)
        let pace = try #require(Self.entry(spent: 40).pace(now: now))
        #expect(pace.status == .ahead(15))
        let elapsed = now.timeIntervalSince(Self.weekly.start)
        let runOut = try #require(pace.runOut)
        #expect(abs(runOut.timeIntervalSince(now.addingTimeInterval(60 * elapsed / 40))) < 0.001)
    }

    /// A 31-day month is the window length (FR-001).
    @Test func monthlyWindow() throws {
        let halfway = Self.monthly.start.addingTimeInterval(15.5 * 24 * 3600)
        let pace = try #require(Self.entry(spent: 150, budget: 300, window: Self.monthly, period: .monthly).pace(now: halfway))
        #expect(abs(pace.expectedPercent - 50) < 1e-9)
        #expect(pace.status == .onPace)
        let early = try #require(Self.entry(spent: 145, budget: 300, window: Self.monthly, period: .monthly)
            .pace(now: Self.monthly.start.addingTimeInterval(9 * 24 * 3600)))
        #expect(early.delta == 19)
        #expect(early.runOut != nil)
    }

    @Test func noPaceForExcludedBudgets() {
        let now = Self.weekly.start.addingTimeInterval(3600 * 24)
        // Empty group (spec 009 FR-005).
        #expect(Self.entry(spent: 0, members: []).pace(now: now) == nil)
        // No budget.
        #expect(Self.entry(spent: 10, budget: 0).pace(now: now) == nil)
        // At or above 100%.
        #expect(Self.entry(spent: 100).pace(now: now) == nil)
        #expect(Self.entry(spent: 104).pace(now: now) == nil)
        #expect(Self.entry(spent: Decimal(string: "99.6")!).pace(now: now) == nil)
        // Window already over at the snapshot time.
        #expect(Self.entry(spent: 10).pace(now: Self.weekly.end) == nil)
        #expect(Self.entry(spent: 10).pace(now: Self.weekly.end.addingTimeInterval(60)) == nil)
    }
}

/// spec 011 FR-001, FR-002, FR-007, research R3, R4: the pace of Claude
/// windows, model-scoped weekly limits and Codex plan windows.
@Suite struct WindowPaceTests {
    static let now = isoDate("2026-10-14T12:00:00Z")

    @Test func limitWindowStartsOneLengthBeforeTheReset() throws {
        // 5-hour window resetting in 2.5 h: half elapsed.
        let five = LimitWindow(utilizationPercent: 70, resetsAt: Self.now.addingTimeInterval(2.5 * 3600))
        let fivePace = try #require(five.pace(length: Pace.fiveHourSeconds, observedAt: Self.now, now: Self.now))
        #expect(abs(fivePace.expectedPercent - 50) < 1e-9)
        #expect(fivePace.status == .ahead(20))
        // 7-day window resetting in 4 days: 3/7 elapsed (Story 2 intro).
        let seven = LimitWindow(utilizationPercent: 62, resetsAt: Self.now.addingTimeInterval(4 * 24 * 3600))
        let sevenPace = try #require(seven.pace(length: WindowResolver.weekSeconds, observedAt: Self.now, now: Self.now))
        #expect(sevenPace.delta == 19)
        #expect(sevenPace.runOut != nil)
    }

    /// Story 2 scenario 2: a window that has not started has no pace.
    @Test func limitWindowWithoutResetHasNoPace() {
        let notStarted = LimitWindow(utilizationPercent: 0, resetsAt: nil)
        #expect(notStarted.pace(length: Pace.fiveHourSeconds, observedAt: Self.now, now: Self.now) == nil)
    }

    /// The observation time is the fetch time, not the snapshot time.
    @Test func limitWindowUsesTheObservationTime() throws {
        let reset = Self.now.addingTimeInterval(2.5 * 3600)
        let window = LimitWindow(utilizationPercent: 50, resetsAt: reset)
        let earlier = Self.now.addingTimeInterval(-3600)
        let pace = try #require(window.pace(length: Pace.fiveHourSeconds, observedAt: earlier, now: Self.now))
        #expect(abs(pace.expectedPercent - 30) < 1e-9)
    }

    /// A stale Claude value whose 7-day reset is before the snapshot time.
    @Test func staleWindowPastItsResetHasNoPace() {
        let fetched = Self.now.addingTimeInterval(-3 * 24 * 3600)
        let window = LimitWindow(utilizationPercent: 40, resetsAt: Self.now.addingTimeInterval(-60))
        #expect(window.pace(length: WindowResolver.weekSeconds, observedAt: fetched, now: Self.now) == nil)
    }

    /// Story 2 scenario 3: model limit at 30% with half its week elapsed.
    @Test func modelLimitUsesASevenDayLength() throws {
        let limit = ModelLimit(modelName: "Fable", utilizationPercent: 30, resetsAt: Self.now.addingTimeInterval(3.5 * 24 * 3600))
        let pace = try #require(limit.pace(observedAt: Self.now, now: Self.now))
        #expect(abs(pace.expectedPercent - 50) < 1e-9)
        #expect(pace.status == .behind(20))
    }

    @Test func codexWindowUsesItsReportedLength() throws {
        // 300-minute window resetting in 4 hours: 20% elapsed.
        let window = CodexLimitWindow(lengthMinutes: 300, usedPercent: 50, resetsAt: Self.now.addingTimeInterval(4 * 3600))
        let pace = try #require(window.pace(observedAt: Self.now, now: Self.now))
        #expect(abs(pace.expectedPercent - 20) < 1e-9)
        #expect(pace.status == .ahead(30))
        #expect(pace.runOut != nil)
    }

    @Test func codexWindowWithoutResetOrReachedHasNoPace() {
        let noReset = CodexLimitWindow(lengthMinutes: 300, usedPercent: 50, resetsAt: nil)
        #expect(noReset.pace(observedAt: Self.now, now: Self.now) == nil)
        let reached = CodexLimitWindow(lengthMinutes: 300, usedPercent: 60, resetsAt: Self.now.addingTimeInterval(3600), limitReached: true)
        #expect(reached.pace(observedAt: Self.now, now: Self.now) == nil)
    }

    /// Research R3: a Codex window past its reset becomes 0% without a reset
    /// time in the effective windows, so it has no pace; the other window
    /// keeps its own.
    @Test func codexWindowPastItsResetHasNoPace() throws {
        let observed = Self.now.addingTimeInterval(-6 * 3600)
        let observation = CodexLimitObservation(planType: "plus", observedAt: observed, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 80, resetsAt: Self.now.addingTimeInterval(-3600)),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 40, resetsAt: Self.now.addingTimeInterval(3 * 24 * 3600)),
        ])
        let entry = CodexLimitsEntry(observation: observation, state: .live)
        let windows = entry.windows(now: Self.now)
        #expect(windows.count == 2)
        #expect(windows[0].pace(observedAt: observed, now: Self.now) == nil)
        #expect(entry.pace(of: windows[0], now: Self.now) == nil)
        // Weekly window: 4 days elapsed minus 6 hours at the observation.
        let weekly = try #require(entry.pace(of: windows[1], now: Self.now))
        let elapsed = 4 * 24 * 3600 - 6 * 3600.0
        #expect(abs(weekly.expectedPercent - elapsed / WindowResolver.weekSeconds * 100) < 1e-9)
        #expect(entry.barPace(now: Self.now) == weekly)
    }

    /// The subscription accessors pick the 5-hour and 7-day lengths and the
    /// fetch time, so the dropdown and the bar cannot disagree (FR-001, FR-002).
    @Test func subscriptionAccessorsUseTheWindowLengthsAndFetchTime() throws {
        let fetched = Self.now.addingTimeInterval(-3600)
        // Both windows reset 2.5 h after `now`: 3.5 h before the reset at the fetch.
        let reset = Self.now.addingTimeInterval(2.5 * 3600)
        let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 50, resetsAt: reset),
                                        sevenDay: LimitWindow(utilizationPercent: 50, resetsAt: reset),
                                        modelLimits: [ModelLimit(modelName: "Fable", utilizationPercent: 50, resetsAt: reset)],
                                        fetchedAt: fetched)
        let five = try #require(status.fiveHourPace(now: Self.now))
        #expect(abs(five.expectedPercent - 30) < 1e-9)
        let weekShare = (WindowResolver.weekSeconds - 3.5 * 3600) / WindowResolver.weekSeconds * 100
        let seven = try #require(status.sevenDayPace(now: Self.now))
        #expect(abs(seven.expectedPercent - weekShare) < 1e-9)
        let model = try #require(status.pace(of: status.modelLimits[0], now: Self.now))
        #expect(abs(model.expectedPercent - weekShare) < 1e-9)
    }

    /// Without an observation a Codex entry has no pace, also for a window
    /// passed in directly (FR-002).
    @Test func codexEntryWithoutObservationHasNoPace() {
        let empty = CodexLimitsEntry(observation: nil, state: .unavailable(reason: "x"))
        #expect(empty.barPace(now: Self.now) == nil)
        let window = CodexLimitWindow(lengthMinutes: 300, usedPercent: 50, resetsAt: Self.now.addingTimeInterval(3600))
        #expect(window.pace(observedAt: Self.now, now: Self.now) != nil)
        #expect(empty.pace(of: window, now: Self.now) == nil)
    }
}
