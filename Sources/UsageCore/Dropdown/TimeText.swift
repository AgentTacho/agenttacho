import Foundation

/// The reset and run-out times of one dropdown section in its time format
/// (spec 025 FR-016 to FR-020, FR-031, research R3). The reference time,
/// the calendar with its time zone and the locale are inputs: the formatter
/// never reads the clock, and "today" is decided against `now` in
/// `calendar`'s time zone. The app passes the current time, re-evaluated at
/// least once a minute while the dropdown is open (FR-020).
public struct TimeText: Sendable {
    public let format: TimeFormat
    /// The reference time of both formats (FR-020, FR-031).
    public let now: Date
    public let calendar: Calendar
    public let locale: Locale

    public init(format: TimeFormat, now: Date, calendar: Calendar, locale: Locale) {
        self.format = format
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    /// "resets in 2h 26m" (relative) or "resets 17:20", "resets Fri 09:00",
    /// "resets Sun 25. Oct 09:00", "resets Sun 1. Nov" for a reset at local
    /// midnight that is not today (absolute) (FR-017, FR-018).
    public func reset(_ date: Date) -> String {
        "resets \(text(date, isReset: true))"
    }

    /// The run-out time that follows "runs out ": "in 2d 13h" (relative) or
    /// "Wed 05:30" (absolute). A run-out keeps its time at local midnight
    /// (spec 011 FR-009, spec 025 FR-018).
    public func runOut(_ date: Date) -> String {
        text(date, isReset: false)
    }

    /// The other form of `reset(_:)` without the "resets" prefix (FR-019):
    /// the long absolute form for a relative section (without the time for
    /// a reset at local midnight), the relative form for an absolute one.
    public func resetTooltip(_ date: Date) -> String {
        switch format {
        case .relative: isLocalMidnight(date) ? dayOnly(date) : long(date)
        case .absolute: Self.relative(from: now, to: date)
        }
    }

    /// The other form of `runOut(_:)` (FR-019): the long absolute form, with
    /// its time, for a relative section; the relative form for an absolute one.
    public func runOutTooltip(_ date: Date) -> String {
        switch format {
        case .relative: long(date)
        case .absolute: Self.relative(from: now, to: date)
        }
    }

    /// The relative form (FR-017): "in" and the two largest units of the
    /// time from `now` to `date`, rounded down to whole minutes; days and
    /// hours from one day on, hours and minutes from one hour on, minutes
    /// below, "in <1m" below one minute. A zero second unit is left out
    /// ("in 4d", "in 3h"); a time not in the future reads "now".
    public static func relative(from now: Date, to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0, seconds.isFinite else { return "now" }
        let totalMinutes = Int(min(seconds / 60, Double(Int32.max)).rounded(.down))
        guard totalMinutes >= 1 else { return "in <1m" }
        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes % (24 * 60) / 60
        let minutes = totalMinutes % 60
        if days >= 1 { return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d" }
        if hours >= 1 { return minutes > 0 ? "in \(hours)h \(minutes)m" : "in \(hours)h" }
        return "in \(minutes)m"
    }

    // MARK: - Absolute form (FR-018)

    private func text(_ date: Date, isReset: Bool) -> String {
        switch format {
        case .relative: return Self.relative(from: now, to: date)
        case .absolute: return absolute(date, isReset: isReset)
        }
    }

    /// Counts calendar days from the start of `now`'s day: the same day
    /// reads the time, the next six days weekday and time, later and
    /// earlier days the long form. A reset at local midnight on another day
    /// reads weekday, day and month only.
    private func absolute(_ date: Date, isReset: Bool) -> String {
        let days = calendarDays(to: date)
        if isReset, days != 0, isLocalMidnight(date) { return dayOnly(date) }
        switch days {
        case 0: return date.formatted(style.hour().minute())
        case 1...6: return date.formatted(style.weekday(.abbreviated).hour().minute())
        default: return long(date)
        }
    }

    private func calendarDays(to date: Date) -> Int {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    private func isLocalMidnight(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) == date
    }

    /// Abbreviated weekday, day, month and time: "Sun 25. Oct 09:00".
    private func long(_ date: Date) -> String {
        date.formatted(style.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// Abbreviated weekday, day and month: "Sun 1. Nov".
    private func dayOnly(_ date: Date) -> String {
        date.formatted(style.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
