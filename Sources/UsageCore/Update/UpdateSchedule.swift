import Foundation

/// When the automatic update check is due (spec 013 FR-001, research R9).
/// Wall-clock time; nothing is stored on disk, so every launch checks once
/// after `firstCheckDelay`.
public enum UpdateSchedule {
    /// 5 minutes after launch, not at launch itself.
    public static let firstCheckDelay: TimeInterval = 300
    /// 24 hours between checks while running.
    public static let interval: TimeInterval = 86_400

    /// True when no check ran yet and `firstCheckDelay` has passed since
    /// launch, when `interval` has passed since the last check attempt, or
    /// when the clock moved back before the last check.
    public static func isDue(now: Date, launchedAt: Date, lastCheck: Date?) -> Bool {
        if let lastCheck, lastCheck > now { return true }
        return now >= nextDue(launchedAt: launchedAt, lastCheck: lastCheck)
    }

    /// When the next automatic check is due: `firstCheckDelay` after launch
    /// before the first check, then `interval` after the last check attempt.
    /// The schedule loop sleeps until this time.
    public static func nextDue(launchedAt: Date, lastCheck: Date?) -> Date {
        lastCheck.map { $0.addingTimeInterval(interval) } ?? launchedAt.addingTimeInterval(firstCheckDelay)
    }
}
