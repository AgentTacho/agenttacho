import Foundation

/// The last fetched 7-day reset of the designated alignment account.
public struct AlignmentReset: Equatable, Sendable {
    public var accountId: String
    public var resetsAt: Date

    public init(accountId: String, resetsAt: Date) {
        self.accountId = accountId
        self.resetsAt = resetsAt
    }
}

/// Computes the weekly window (FR-021, FR-022, research R9) and the monthly
/// window of monthly groups (spec 003 FR-005).
public struct WindowResolver: Sendable {
    public static let weekSeconds: TimeInterval = 7 * 24 * 60 * 60

    public init() {}

    /// Aligned: `[resets_at - 7d, resets_at)`, rolled forward in 7-day steps
    /// when the last fetched reset is already in the past. Fallback: from the
    /// most recent occurrence of the configured weekday and hour (local time)
    /// to the same local time 7 calendar days later.
    public func resolve(now: Date, alignmentReset: AlignmentReset?, fallback: WeekFallback, calendar: Calendar) -> (DateInterval, WindowSource) {
        if let reset = alignmentReset {
            var end = reset.resetsAt
            while end <= now {
                end = end.addingTimeInterval(WindowResolver.weekSeconds)
            }
            let start = end.addingTimeInterval(-WindowResolver.weekSeconds)
            return (DateInterval(start: start, end: end), .aligned(accountId: reset.accountId))
        }

        var components = DateComponents()
        components.weekday = fallback.weekday
        components.hour = fallback.hour
        components.minute = 0
        components.second = 0
        // `nextDate(after:direction:.backward)` is strict, so search from one
        // second after `now` to include a boundary that is exactly `now`.
        let start = calendar.nextDate(after: now.addingTimeInterval(1), matching: components,
                                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .backward)
            ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(WindowResolver.weekSeconds)
        return (DateInterval(start: start, end: end), .fallback)
    }

    /// The window of a monthly group: `[1st 00:00, next 1st 00:00)` in the
    /// calendar's time zone (spec 003 FR-005, research R1). Calendar
    /// arithmetic covers 28 to 31 day months and DST changes. It never looks
    /// at a subscription reset or the week fallback (FR-006).
    public func monthWindow(now: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: .month, for: now) {
            return interval
        }
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(31 * 24 * 3600))
    }

    /// The window record sources collect over: the weekly window, widened to
    /// span the monthly window when at least one budget, a group's or an
    /// account's own (spec 004 FR-009), is monthly (spec 003 research R2).
    /// Budget owners then filter to their own window in the aggregator.
    public func collectionWindow(weekly: DateInterval, now: Date, configuration: Configuration, calendar: Calendar) -> DateInterval {
        guard configuration.budgetOwners.contains(where: { $0.budget.period == .monthly }) else { return weekly }
        let month = monthWindow(now: now, calendar: calendar)
        return DateInterval(start: min(weekly.start, month.start), end: max(weekly.end, month.end))
    }
}
