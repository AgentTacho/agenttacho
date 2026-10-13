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

/// Computes the weekly budget window (FR-021, FR-022, research R9).
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
}
