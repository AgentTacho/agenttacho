import Foundation
import Testing
@testable import UsageCore

/// spec 025 FR-017 to FR-019, FR-031, SC-006: the relative and absolute
/// forms of reset and run-out times, with a fixed calendar, locale and
/// reference time passed in.
@Suite struct TimeTextTests {
    static let utc: Calendar = calendar("UTC")
    static let berlin: Calendar = calendar("Europe/Berlin")
    static let locale = Locale(identifier: "en_US")
    /// Thu 22 Oct 2026, 14:54 UTC.
    static let now = isoDate("2026-10-22T14:54:00Z")
    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86400

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static func times(_ format: TimeFormat, now: Date = now, calendar: Calendar = utc) -> TimeText {
        TimeText(format: format, now: now, calendar: calendar, locale: locale)
    }

    static func base(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// The expected forms, built with the format styles of FR-018.
    static func time(_ date: Date, _ calendar: Calendar = utc) -> String {
        date.formatted(base(calendar).hour().minute())
    }

    static func weekdayTime(_ date: Date, _ calendar: Calendar = utc) -> String {
        date.formatted(base(calendar).weekday(.abbreviated).hour().minute())
    }

    static func long(_ date: Date, _ calendar: Calendar = utc) -> String {
        date.formatted(base(calendar).weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    static func dayOnly(_ date: Date, _ calendar: Calendar = utc) -> String {
        date.formatted(base(calendar).weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: - Relative (FR-017)

    @Test func relativeBelowOneMinute() {
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(30)) == "in <1m")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(59.9)) == "in <1m")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(60)) == "in 1m")
    }

    @Test func relativeMinutes() {
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(45 * Self.minute)) == "in 45m")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(59 * Self.minute + 59)) == "in 59m")
    }

    @Test func relativeHoursAndMinutes() {
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(2 * Self.hour + 26 * Self.minute)) == "in 2h 26m")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(Self.hour)) == "in 1h")
    }

    @Test func relativeWholeHoursOmitMinutes() {
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(3 * Self.hour)) == "in 3h")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(3 * Self.hour + 59)) == "in 3h")
    }

    @Test func relativeDaysAndHours() {
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(4 * Self.day + 16 * Self.hour)) == "in 4d 16h")
        // Two units only: the minutes of 2d 13h 40m are dropped.
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(2 * Self.day + 13 * Self.hour + 40 * Self.minute)) == "in 2d 13h")
    }

    @Test func relativeWholeDaysOmitHours() {
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(4 * Self.day)) == "in 4d")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(Self.day + 30 * Self.minute)) == "in 1d")
    }

    @Test func relativeRoundsDownToWholeMinutes() {
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(2 * Self.hour + 26 * Self.minute + 59)) == "in 2h 26m")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(Self.day - 1)) == "in 23h 59m")
    }

    @Test func relativeNotInTheFutureIsNow() {
        #expect(TimeText.relative(from: Self.now, to: Self.now) == "now")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(-60)) == "now")
        #expect(TimeText.relative(from: Self.now, to: Self.now.addingTimeInterval(-3 * Self.day)) == "now")
    }

    @Test func relativeResetAndRunOut() {
        let times = Self.times(.relative)
        let date = Self.now.addingTimeInterval(2 * Self.hour + 26 * Self.minute)
        #expect(times.reset(date) == "resets in 2h 26m")
        #expect(times.runOut(date) == "in 2h 26m")
        #expect(times.reset(Self.now.addingTimeInterval(-5)) == "resets now")
        #expect(times.runOut(Self.now) == "now")
    }

    // MARK: - Absolute (FR-018)

    @Test func absoluteSameDayIsTheTime() {
        let times = Self.times(.absolute)
        let date = isoDate("2026-10-22T17:20:00Z")
        #expect(times.runOut(date) == Self.time(date))
        #expect(times.reset(date) == "resets \(Self.time(date))")
        #expect(times.runOut(date).contains("5:20"))
        // A time already past on the same day reads the time as well.
        let earlier = isoDate("2026-10-22T10:00:00Z")
        #expect(times.runOut(earlier) == Self.time(earlier))
    }

    /// The next calendar day, also when it is less than 24 hours away.
    @Test func absoluteNextCalendarDayIsWeekdayAndTime() {
        let times = Self.times(.absolute)
        let tomorrow = isoDate("2026-10-23T09:00:00Z")
        #expect(times.runOut(tomorrow) == Self.weekdayTime(tomorrow))
        #expect(times.reset(tomorrow) == "resets \(Self.weekdayTime(tomorrow))")
        #expect(times.runOut(tomorrow).hasPrefix("Fri"))
        let soon = isoDate("2026-10-23T00:30:00Z")
        #expect(times.runOut(soon) == Self.weekdayTime(soon))
    }

    @Test func absoluteSixCalendarDaysAheadIsWeekdayAndTime() {
        let times = Self.times(.absolute)
        let date = isoDate("2026-10-28T23:59:00Z")
        #expect(times.runOut(date) == Self.weekdayTime(date))
        #expect(times.runOut(date).hasPrefix("Wed"))
    }

    /// A window that resets next week on today's weekday is seven calendar
    /// days away and reads the long form, not the bare weekday.
    @Test func absoluteSevenCalendarDaysAheadIsTheLongForm() {
        let times = Self.times(.absolute)
        let date = isoDate("2026-10-29T09:00:00Z")
        #expect(times.runOut(date) == Self.long(date))
        #expect(times.reset(date) == "resets \(Self.long(date))")
        #expect(times.runOut(date).hasPrefix("Thu"))
        #expect(times.runOut(date).contains("Oct"))
        #expect(times.runOut(date).contains("29"))
        // Seven calendar days, though under seven times 24 hours.
        let early = isoDate("2026-10-29T00:10:00Z")
        #expect(times.runOut(early) == Self.long(early))
    }

    @Test func absoluteEarlierDayIsTheLongForm() {
        let times = Self.times(.absolute)
        let date = isoDate("2026-10-21T09:00:00Z")
        #expect(times.runOut(date) == Self.long(date))
        #expect(times.reset(date) == "resets \(Self.long(date))")
    }

    /// A reset at local midnight that is not on the same day reads weekday,
    /// day and month without a time; a run-out keeps its time (spec 011 FR-009).
    @Test func absoluteMidnightResetOmitsTheTime() {
        let times = Self.times(.absolute)
        let tomorrow = isoDate("2026-10-23T00:00:00Z")
        #expect(times.reset(tomorrow) == "resets \(Self.dayOnly(tomorrow))")
        #expect(times.runOut(tomorrow) == Self.weekdayTime(tomorrow))
        let november = isoDate("2026-11-01T00:00:00Z")
        #expect(times.reset(november) == "resets \(Self.dayOnly(november))")
        #expect(times.reset(november).contains("Nov"))
        #expect(times.runOut(november) == Self.long(november))
        // A midnight reset that just passed today reads the time itself; one
        // on an earlier day reads weekday, day and month (edge case "no
        // longer in the future").
        let todayMidnight = isoDate("2026-10-22T00:00:00Z")
        #expect(times.reset(todayMidnight) == "resets \(Self.time(todayMidnight))")
        let yesterdayMidnight = isoDate("2026-10-21T00:00:00Z")
        #expect(times.reset(yesterdayMidnight) == "resets \(Self.dayOnly(yesterdayMidnight))")
        #expect(times.runOut(yesterdayMidnight) == Self.long(yesterdayMidnight))
    }

    // MARK: - Tooltips (FR-019)

    @Test func relativeTooltipsShowTheLongAbsoluteForm() {
        let times = Self.times(.relative)
        let soon = Self.now.addingTimeInterval(2 * Self.hour + 26 * Self.minute)
        #expect(times.resetTooltip(soon) == Self.long(soon))
        #expect(times.runOutTooltip(soon) == Self.long(soon))
        // A reset at local midnight drops the time; a run-out keeps it.
        let midnight = isoDate("2026-10-24T00:00:00Z")
        #expect(times.resetTooltip(midnight) == Self.dayOnly(midnight))
        #expect(times.runOutTooltip(midnight) == Self.long(midnight))
    }

    @Test func absoluteTooltipsShowTheRelativeForm() {
        let times = Self.times(.absolute)
        let date = Self.now.addingTimeInterval(2 * Self.hour + 26 * Self.minute)
        #expect(times.resetTooltip(date) == "in 2h 26m")
        #expect(times.runOutTooltip(date) == "in 2h 26m")
        #expect(times.resetTooltip(Self.now.addingTimeInterval(-60)) == "now")
    }

    // MARK: - Calendar and time zone (FR-031)

    /// The day boundary comes from the given calendar's time zone: 23:30
    /// UTC is still today in UTC but already Friday in Berlin.
    @Test func dayBoundaryFollowsTheCalendarsTimeZone() {
        let date = isoDate("2026-10-22T23:30:00Z")
        #expect(Self.times(.absolute, calendar: Self.utc).runOut(date) == Self.time(date, Self.utc))
        #expect(Self.times(.absolute, calendar: Self.berlin).runOut(date) == Self.weekdayTime(date, Self.berlin))
    }

    /// Calendar days, not seconds divided by 86400, across the clock change
    /// of Sun 25 Oct 2026 in Berlin: from Thu 22 Oct 23:00 the Thursday
    /// after is seven calendar days away although less than seven times 24
    /// hours have passed.
    @Test func calendarDaysAcrossTheClockChange() {
        let now = isoDate("2026-10-22T21:00:00Z")
        let times = Self.times(.absolute, now: now, calendar: Self.berlin)
        let sunday = isoDate("2026-10-25T10:00:00Z")
        #expect(times.runOut(sunday) == Self.weekdayTime(sunday, Self.berlin))
        #expect(times.runOut(sunday).hasPrefix("Sun"))
        let thursday = isoDate("2026-10-28T23:30:00Z")
        #expect(times.runOut(thursday) == Self.long(thursday, Self.berlin))
        #expect(times.runOut(thursday).hasPrefix("Thu"))
    }

    /// The spring clock change of Sun 28 Mar 2027 in Berlin: the Thursday
    /// after is seven calendar days away, although its start of day is one
    /// hour short of seven times 24 hours later, so seconds divided by 86400
    /// would read six days.
    @Test func calendarDaysAcrossTheSpringClockChange() {
        let now = isoDate("2027-03-25T08:00:00Z")
        let times = Self.times(.absolute, now: now, calendar: Self.berlin)
        let wednesday = isoDate("2027-03-31T07:00:00Z")
        #expect(times.runOut(wednesday) == Self.weekdayTime(wednesday, Self.berlin))
        let thursday = isoDate("2027-04-01T07:00:00Z")
        #expect(times.runOut(thursday) == Self.long(thursday, Self.berlin))
        #expect(times.runOut(thursday).hasPrefix("Thu"))
    }

    /// The reference time is the one passed in, never the current time.
    @Test func referenceTimeIsAnInput() {
        let later = Self.now.addingTimeInterval(Self.hour)
        let date = Self.now.addingTimeInterval(3 * Self.hour)
        #expect(Self.times(.relative).reset(date) == "resets in 3h")
        #expect(Self.times(.relative, now: later).reset(date) == "resets in 2h")
    }
}

/// spec 033 FR-010, FR-015, research R8: the expiry text of a free reset
/// ticket ("in 2d 3h (Thu 14:00)") and the absolute form alone, both with
/// the absolute form of a run-out (a time at local midnight keeps it).
@Suite struct ExpiryTimeTextTests {
    typealias T = TimeTextTests

    @Test func expiryTodayTomorrowAndLater() {
        for format in [TimeFormat.relative, .absolute] {
            let times = T.times(format)
            let today = T.now.addingTimeInterval(3 * T.hour)
            #expect(times.expiry(today) == "in 3h (\(T.time(today)))")
            let tomorrow = T.now.addingTimeInterval(T.day + 3 * T.hour + 6 * T.minute)
            #expect(times.expiry(tomorrow) == "in 1d 3h (\(T.weekdayTime(tomorrow)))")
            let later = T.now.addingTimeInterval(9 * T.day)
            #expect(times.expiry(later) == "in 9d (\(T.long(later)))")
        }
    }

    @Test func absoluteFormKeepsTheTimeAtMidnight() {
        let times = T.times(.relative)
        let midnight = isoDate("2026-10-24T00:00:00Z")
        #expect(times.absolute(midnight) == T.weekdayTime(midnight))
        let today = T.now.addingTimeInterval(T.hour)
        #expect(times.absolute(today) == T.time(today))
        let later = T.now.addingTimeInterval(20 * T.day)
        #expect(times.absolute(later) == T.long(later))
    }

    @Test func absoluteFormUsesTheCalendarsTimeZone() {
        let times = T.times(.absolute, calendar: T.berlin)
        let date = T.now.addingTimeInterval(2 * T.hour)
        #expect(times.absolute(date) == T.time(date, T.berlin))
    }
}
