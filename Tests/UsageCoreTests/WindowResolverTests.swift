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
}
