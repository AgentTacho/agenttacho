import Foundation
import Testing
@testable import UsageCore

@Suite struct WindowResolverTests {
    let resolver = WindowResolver()
    let berlin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    let monday = WeekFallback(weekday: 2, hour: 0)

    @Test func alignedWindowEndsAtResetAndStartsSevenDaysEarlier() {
        let reset = isoDate("2026-10-16T06:59:59.706Z")
        let now = isoDate("2026-10-13T08:00:00Z")
        let (window, source) = resolver.resolve(now: now, alignmentReset: AlignmentReset(accountId: "acc-max", resetsAt: reset),
                                                fallback: monday, calendar: berlin)
        #expect(window.end == reset)
        #expect(window.start == reset.addingTimeInterval(-7 * 24 * 3600))
        #expect(source == .aligned(accountId: "acc-max"))
    }

    @Test func fallbackUsesMostRecentMondayMidnightLocal() {
        // Tuesday 2026-10-13 10:00 Berlin (CEST, UTC+2)
        let now = isoDate("2026-10-13T08:00:00Z")
        let (window, source) = resolver.resolve(now: now, alignmentReset: nil, fallback: monday, calendar: berlin)
        #expect(source == .fallback)
        #expect(window.start == isoDate("2026-10-11T22:00:00Z"))   // Monday 2026-10-12 00:00 CEST
        #expect(window.end == isoDate("2026-10-18T22:00:00Z"))     // Monday 2026-10-19 00:00 CEST
    }

    @Test func fallbackRollsOverAtTheBoundary() {
        let justBefore = isoDate("2026-10-18T21:59:59Z")
        let atBoundary = isoDate("2026-10-18T22:00:00Z")
        let (before, _) = resolver.resolve(now: justBefore, alignmentReset: nil, fallback: monday, calendar: berlin)
        let (after, _) = resolver.resolve(now: atBoundary, alignmentReset: nil, fallback: monday, calendar: berlin)
        #expect(before.start == isoDate("2026-10-11T22:00:00Z"))
        #expect(after.start == isoDate("2026-10-18T22:00:00Z"))
        #expect(after.end == isoDate("2026-10-25T23:00:00Z"))      // CET after the DST change on Oct 25
    }

    @Test func fallbackHonorsWeekdayAndHour() {
        // Friday 2026-10-16 15:00 Berlin, fallback Wednesday 09:00
        let now = isoDate("2026-10-16T13:00:00Z")
        let (window, _) = resolver.resolve(now: now, alignmentReset: nil, fallback: WeekFallback(weekday: 4, hour: 9), calendar: berlin)
        #expect(window.start == isoDate("2026-10-14T07:00:00Z"))
        #expect(window.end == isoDate("2026-10-21T07:00:00Z"))
    }

    @Test func alignedWindowMovesWithNewReset() {
        let first = AlignmentReset(accountId: "a", resetsAt: isoDate("2026-10-16T07:00:00Z"))
        let second = AlignmentReset(accountId: "a", resetsAt: isoDate("2026-10-23T07:00:00Z"))
        let (w1, _) = resolver.resolve(now: isoDate("2026-10-15T08:00:00Z"), alignmentReset: first, fallback: monday, calendar: berlin)
        let (w2, _) = resolver.resolve(now: isoDate("2026-10-17T08:00:00Z"), alignmentReset: second, fallback: monday, calendar: berlin)
        #expect(w2.end == second.resetsAt)
        #expect(w2.start == w1.end)
    }

    @Test func pastResetWhileUnreachableRollsForwardInSevenDaySteps() {
        // The provider was unreachable; the last fetched reset is in the past.
        let now = isoDate("2026-10-17T08:00:00Z")
        let stale = AlignmentReset(accountId: "a", resetsAt: isoDate("2026-10-16T07:00:00Z"))
        let (window, source) = resolver.resolve(now: now, alignmentReset: stale, fallback: monday, calendar: berlin)
        #expect(source == .aligned(accountId: "a"))
        #expect(window.start == stale.resetsAt)
        #expect(window.end == isoDate("2026-10-23T07:00:00Z"))
        #expect(window.contains(now))
    }

    @Test func fallbackWindowSpanningDSTChangeHasSevenCalendarDays() {
        // Window starting Monday 2026-10-19 00:00 CEST ends Monday 2026-10-26 00:00 CET: 7 days + 1 hour in seconds.
        let now = isoDate("2026-10-24T12:00:00Z")
        let (window, _) = resolver.resolve(now: now, alignmentReset: nil, fallback: monday, calendar: berlin)
        #expect(window.start == isoDate("2026-10-18T22:00:00Z"))
        #expect(window.end == isoDate("2026-10-25T23:00:00Z"))
        let days = berlin.dateComponents([.day], from: window.start, to: window.end).day
        #expect(days == 7)
        #expect(window.duration == 7 * 24 * 3600 + 3600)
    }

    // MARK: Monthly window (spec 003 FR-005, FR-016, research R1)

    func calendar(_ identifier: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: identifier)!
        return c
    }

    @Test func monthWindowMidMonthSpansTheLocalCalendarMonth() {
        // Tuesday 2026-10-13 10:00 Berlin; October contains the DST change on Oct 25.
        let window = resolver.monthWindow(now: isoDate("2026-10-13T08:00:00Z"), calendar: berlin)
        #expect(window.start == isoDate("2026-09-30T22:00:00Z"))   // 2026-10-01 00:00 CEST
        #expect(window.end == isoDate("2026-10-31T23:00:00Z"))     // 2026-11-01 00:00 CET
        // Not a fixed number of hours: 31 days plus the hour gained at the DST change.
        #expect(window.duration == 31 * 24 * 3600 + 3600)
        #expect(window.duration != 31 * 24 * 3600)
    }

    @Test func monthWindowBoundariesAreStartInclusive() {
        let atStart = resolver.monthWindow(now: isoDate("2026-09-30T22:00:00Z"), calendar: berlin)
        #expect(atStart.start == isoDate("2026-09-30T22:00:00Z"))
        #expect(atStart.end == isoDate("2026-10-31T23:00:00Z"))

        let lastSecond = resolver.monthWindow(now: isoDate("2026-10-31T22:59:59Z"), calendar: berlin)
        #expect(lastSecond.start == isoDate("2026-09-30T22:00:00Z"))
        #expect(lastSecond.end == isoDate("2026-10-31T23:00:00Z"))

        let nextMonth = resolver.monthWindow(now: isoDate("2026-10-31T23:00:00Z"), calendar: berlin)
        #expect(nextMonth.start == isoDate("2026-10-31T23:00:00Z"))
    }

    @Test func monthWindowHandlesEveryMonthLength() {
        func days(_ window: DateInterval) -> Int? {
            berlin.dateComponents([.day], from: window.start, to: window.end).day
        }
        // February in a leap year (2028) and a non-leap year (2027).
        let leap = resolver.monthWindow(now: isoDate("2028-02-15T12:00:00Z"), calendar: berlin)
        #expect(leap.start == isoDate("2028-01-31T23:00:00Z"))
        #expect(leap.end == isoDate("2028-02-29T23:00:00Z"))
        #expect(days(leap) == 29)
        let nonLeap = resolver.monthWindow(now: isoDate("2027-02-15T12:00:00Z"), calendar: berlin)
        #expect(nonLeap.end == isoDate("2027-02-28T23:00:00Z"))
        #expect(days(nonLeap) == 28)
        // A 30-day and a 31-day month without DST change.
        let november = resolver.monthWindow(now: isoDate("2026-11-10T12:00:00Z"), calendar: berlin)
        #expect(november.start == isoDate("2026-10-31T23:00:00Z"))
        #expect(november.end == isoDate("2026-11-30T23:00:00Z"))
        #expect(november.duration == 30 * 24 * 3600)
        let december = resolver.monthWindow(now: isoDate("2026-12-31T12:00:00Z"), calendar: berlin)
        #expect(december.end == isoDate("2026-12-31T23:00:00Z"))
        #expect(days(december) == 31)
    }

    @Test func monthWindowFollowsTheCalendarTimeZone() {
        // 2026-10-31 12:00 UTC is already November 1 in Auckland (UTC+13)
        // but still October 31 in Los Angeles (UTC-7).
        let instant = isoDate("2026-10-31T12:00:00Z")
        let auckland = resolver.monthWindow(now: instant, calendar: calendar("Pacific/Auckland"))
        let losAngeles = resolver.monthWindow(now: instant, calendar: calendar("America/Los_Angeles"))
        #expect(auckland.start == isoDate("2026-10-31T11:00:00Z"))    // 2026-11-01 00:00 NZDT
        #expect(losAngeles.start == isoDate("2026-10-01T07:00:00Z"))  // 2026-10-01 00:00 PDT
        #expect(auckland.start != losAngeles.start)
        #expect(auckland.contains(instant))
        #expect(losAngeles.contains(instant))
    }

    // MARK: Collection window (spec 003 research R2)

    func configuration(periods: [BudgetPeriod]) -> Configuration {
        var c = Configuration()
        c.groups = periods.enumerated().map { i, period in
            BudgetGroup(id: "g\(i)", name: "G\(i)", label: "G\(i)", period: period, budgetUSD: 10)
        }
        return c
    }

    @Test func collectionWindowEqualsWeeklyWindowWithoutMonthlyGroups() {
        let weekly = DateInterval(start: isoDate("2026-10-09T07:00:00Z"), end: isoDate("2026-10-16T07:00:00Z"))
        let now = isoDate("2026-10-13T08:00:00Z")
        for periods in [[], [BudgetPeriod.weekly], [.weekly, .weekly]] {
            let window = resolver.collectionWindow(weekly: weekly, now: now, configuration: configuration(periods: periods), calendar: berlin)
            #expect(window == weekly)
        }
    }

    @Test func collectionWindowSpansWeeklyAndMonthlyWindows() {
        // Weekly window inside the month: the month dominates.
        let weekly = DateInterval(start: isoDate("2026-10-09T07:00:00Z"), end: isoDate("2026-10-16T07:00:00Z"))
        let inside = resolver.collectionWindow(weekly: weekly, now: isoDate("2026-10-13T08:00:00Z"),
                                               configuration: configuration(periods: [.weekly, .monthly]), calendar: berlin)
        #expect(inside == DateInterval(start: isoDate("2026-09-30T22:00:00Z"), end: isoDate("2026-10-31T23:00:00Z")))

        // Weekly window starting in the previous month: earliest start, latest end.
        let straddling = DateInterval(start: isoDate("2026-10-29T07:00:00Z"), end: isoDate("2026-11-05T07:00:00Z"))
        let union = resolver.collectionWindow(weekly: straddling, now: isoDate("2026-11-02T08:00:00Z"),
                                              configuration: configuration(periods: [.monthly]), calendar: berlin)
        #expect(union.start == straddling.start)
        #expect(union.end == isoDate("2026-11-30T23:00:00Z"))
    }
}
