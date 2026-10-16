import Foundation

/// The one pace line of the dropdown, shown under "Last refreshed" while a
/// pace is slower than the base (spec 016 FR-016, research R11). Built by
/// `AdaptivePace.status(now:)`; the app only renders `text(now:calendar:)`,
/// and its accessibility text is the same string (spec 019 FR-005).
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
    /// The plans the line is about: the slowed plans for "no agent
    /// activity", in the order Claude, Codex; empty for a timer reason
    /// (spec 019 FR-001 to FR-003).
    public let plans: [PacedEndpoint]

    public init(reason: PaceReason, nextAt: Date, kind: Kind, plans: [PacedEndpoint] = []) {
        self.reason = reason
        self.nextAt = nextAt
        self.kind = kind
        self.plans = plans
    }

    /// `Codex limits next checked at 14:35 (no Codex activity)` for one
    /// slowed plan, `Claude and Codex limits next checked at 14:35 (no agent
    /// activity)` for both (spec 019 FR-001, FR-002); for a timer reason
    /// `Plan limits next checked at 14:35 (away)` or `Next refresh at 14:20
    /// (Low Power Mode)` (spec 019 FR-003). The time stands alone when it is
    /// on the same day as `now`, otherwise it carries the abbreviated
    /// weekday (`Fri 09:05`). `locale` defaults to the user's, so the time
    /// follows the 12 or 24 hour setting like the rest of the dropdown
    /// (spec 019 FR-006).
    public func text(now: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        if !calendar.isDate(nextAt, inSameDayAs: now) {
            style = style.weekday(.abbreviated)
        }
        let time = nextAt.formatted(style)
        switch kind {
        case .planLimits:
            if reason == .noAgentActivity, !plans.isEmpty {
                let subject = plans.map(\.planName).joined(separator: " and ")
                let why = plans.count == 1 ? "no \(plans[0].agentName) activity" : reason.displayName
                return "\(subject) limits next checked at \(time) (\(why))"
            }
            return "Plan limits next checked at \(time) (\(reason.displayName))"
        case .refresh: return "Next refresh at \(time) (\(reason.displayName))"
        }
    }
}
