import Foundation

/// The one pace line of the dropdown, shown under "Last refreshed" while a
/// pace is slower than the base (spec 016 FR-016, research R11). Built by
/// `AdaptivePace.status(now:)`; the app only renders `text(now:calendar:)`.
public struct RefreshPaceStatus: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// At least one usage endpoint is in use: the time is its next call.
        case planLimits
        /// No usage endpoint is in use: the time is the next scheduled refresh.
        case refresh
    }

    public let reason: PaceReason
    public let nextAt: Date
    public let kind: Kind

    public init(reason: PaceReason, nextAt: Date, kind: Kind) {
        self.reason = reason
        self.nextAt = nextAt
        self.kind = kind
    }

    /// `Plan limits next checked at 14:35 (no agent activity)` or `Next
    /// refresh at 14:20 (Low Power Mode)`. The time stands alone when it is
    /// on the same day as `now`, otherwise it carries the abbreviated
    /// weekday (`Fri 09:05`). `locale` defaults to the user's, so the time
    /// follows the 12 or 24 hour setting like the rest of the dropdown.
    public func text(now: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        if !calendar.isDate(nextAt, inSameDayAs: now) {
            style = style.weekday(.abbreviated)
        }
        let time = nextAt.formatted(style)
        switch kind {
        case .planLimits: return "Plan limits next checked at \(time) (\(reason.displayName))"
        case .refresh: return "Next refresh at \(time) (\(reason.displayName))"
        }
    }
}
