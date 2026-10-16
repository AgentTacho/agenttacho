import Foundation

/// Whether a value is within the tolerance band of even use, or how many
/// percentage points it is ahead or behind (spec 011 FR-008).
public enum PaceStatus: Equatable, Sendable {
    /// The rounded delta is from -5 to +5 inclusive.
    case onPace
    /// Points ahead of even use, greater than 5.
    case ahead(Int)
    /// Points behind even use (absolute value), greater than 5.
    case behind(Int)
}

/// The pace of one window or budget at one observation time (spec 011 Key
/// Entities, research R5). Computed from snapshot values only, never stored.
public struct Pace: Equatable, Sendable {
    /// Elapsed share of the window at the observation time, 0 to 100 (FR-001).
    public let expectedPercent: Double
    /// Unrounded used percent minus `expectedPercent`, rounded (FR-003).
    public let delta: Int
    public let status: PaceStatus
    /// Linear run-out; set only when ahead beyond the band, at least 10% of
    /// the window has elapsed, the used percent is above 0 and the run-out
    /// falls strictly after the snapshot time and strictly before the reset
    /// (FR-004 to FR-006).
    public let runOut: Date?

    /// The "on pace" band in percentage points either side of 0 (FR-008).
    public static let tolerancePoints = 5
    /// Share of the window that must have elapsed before a run-out counts (FR-006).
    public static let holdBackShare = 0.10
    /// Length of the Claude 5-hour window (FR-001, research R4).
    public static let fiveHourSeconds: TimeInterval = 5 * 60 * 60

    /// The pace of a value `usedPercent` observed at `observedAt` in the
    /// window from `windowStart` to `resetsAt`. Nil when there is no pace
    /// (FR-007): a used percent that is not finite or shows as 100% or more
    /// (rounded, like the displayed percent and the bar level), a window of
    /// length 0 or less, or a window that has reset at the snapshot time
    /// `now` (`resetsAt <= now`). Besides that, `now` only drops a run-out
    /// that has already passed (FR-005); the pace is the one at the
    /// observation time (FR-002).
    public static func compute(usedPercent: Double, windowStart: Date, resetsAt: Date, observedAt: Date, now: Date) -> Pace? {
        let length = resetsAt.timeIntervalSince(windowStart)
        guard usedPercent.isFinite, PercentFormatter.rounded(usedPercent) < 100, length > 0, resetsAt > now else { return nil }

        let elapsed = min(max(observedAt.timeIntervalSince(windowStart), 0), length)
        let share = elapsed / length
        let expected = share * 100
        let delta = PercentFormatter.rounded(usedPercent - expected)

        let status: PaceStatus
        if delta > tolerancePoints {
            status = .ahead(delta)
        } else if delta < -tolerancePoints {
            status = .behind(-delta)
        } else {
            status = .onPace
        }

        var runOut: Date?
        if case .ahead = status, share >= holdBackShare, usedPercent > 0 {
            let candidate = observedAt.addingTimeInterval((100 - usedPercent) * elapsed / usedPercent)
            // Ahead means used > expected, which already puts the linear
            // run-out before the reset; the check keeps FR-005 explicit and
            // guards against floating point edge cases. A run-out at or
            // before the snapshot time (an old observation that is not
            // marked stale) does not count either (FR-005).
            if candidate < resetsAt, candidate > now { runOut = candidate }
        }
        return Pace(expectedPercent: expected, delta: delta, status: status, runOut: runOut)
    }

    /// The delta at which the pace meter's bar reaches full length (FR-008).
    public static let meterScalePoints = 50

    /// The pace meter's bar as a share of its half track (FR-008): 0 within
    /// the "on pace" band, so only the tick shows; positive ahead (bar right
    /// of the tick), negative behind (bar left), proportional to the delta
    /// and clamped to +/-1 at `meterScalePoints` or more.
    public var meterOffset: Double {
        if case .onPace = status { return 0 }
        let scale = Double(Self.meterScalePoints)
        return min(max(Double(delta) / scale, -1), 1)
    }

    /// The pace meter's text, shown as its tooltip and accessibility label
    /// (FR-008): "on pace", "N% ahead" or "N% behind", followed by
    /// " · runs out <time>" when `runOut` is set. With a `fastRunOut` the
    /// entry burns fast, and " · burning fast · runs out <fast run-out>"
    /// replaces the spec 011 run-out, so the text names one run-out only
    /// (spec 017 FR-012). The app formats the time (FR-009).
    public func summary(runOutText: (Date) -> String, fastRunOut: Date? = nil) -> String {
        let base: String
        switch status {
        case .onPace: base = "on pace"
        case .ahead(let points): base = "\(points)% ahead"
        case .behind(let points): base = "\(points)% behind"
        }
        if let fastRunOut { return "\(base) \u{00B7} burning fast \u{00B7} runs out \(runOutText(fastRunOut))" }
        guard let runOut else { return base }
        return "\(base) \u{00B7} runs out \(runOutText(runOut))"
    }
}

/// The values a pace and a burn rate are computed from: the unrounded used
/// percent, the window and the observation time (spec 011 FR-001, FR-002,
/// spec 017 FR-001 to FR-003). The per-kind accessors below are the only
/// place that derives them, so the pace and the burn rate of a window
/// cannot drift apart.
struct PaceInputs: Equatable, Sendable {
    let usedPercent: Double
    let windowStart: Date
    let resetsAt: Date
    let observedAt: Date

    /// The pace of these values at the snapshot time `now` (spec 011 FR-007).
    func pace(now: Date) -> Pace? {
        Pace.compute(usedPercent: usedPercent, windowStart: windowStart, resetsAt: resetsAt, observedAt: observedAt, now: now)
    }
}

extension Pace {
    /// The pace meter uses the orange attention color with a counted
    /// run-out (spec 011 FR-010) or when the entry burns fast (spec 017
    /// FR-012); `burn` is the row's burn rate.
    public func usesAttentionColor(burn: BurnRate?) -> Bool {
        runOut != nil || burn?.burnsFast == true
    }
}

extension GroupEntry {
    /// The budget's pace at the snapshot time `now`, which is also its
    /// observation time (spec 011 FR-001, FR-002). The used percent is the
    /// unrounded spend share, not `percent`; the window is the budget's own
    /// week or calendar month. Nil for an empty group (spec 009 FR-005), a
    /// budget of 0 or less, and the exclusions of `Pace.compute` (FR-007).
    public func pace(now: Date) -> Pace? {
        paceInputs(now: now)?.pace(now: now)
    }

    /// The inputs of `pace(now:)`.
    func paceInputs(now: Date) -> PaceInputs? {
        guard !members.isEmpty, budgetUSD > 0 else { return nil }
        let used = NSDecimalNumber(decimal: spentUSD / budgetUSD * 100).doubleValue
        return PaceInputs(usedPercent: used, windowStart: window.start, resetsAt: window.end, observedAt: now)
    }
}

extension LimitWindow {
    /// The pace of a Claude 5-hour or 7-day window of `length`, observed at
    /// the subscription fetch time (spec 011 FR-001, FR-002). The window
    /// starts one length before its reset; nil while it has not started (no
    /// reset time) and for the exclusions of `Pace.compute` (FR-007).
    public func pace(length: TimeInterval, observedAt: Date, now: Date) -> Pace? {
        paceInputs(length: length, observedAt: observedAt)?.pace(now: now)
    }

    /// The inputs of `pace(length:observedAt:now:)`.
    func paceInputs(length: TimeInterval, observedAt: Date) -> PaceInputs? {
        guard let resetsAt else { return nil }
        return PaceInputs(usedPercent: utilizationPercent, windowStart: resetsAt.addingTimeInterval(-length),
                          resetsAt: resetsAt, observedAt: observedAt)
    }
}

extension ModelLimit {
    /// The pace of a model-scoped weekly limit: a 7-day window ending at its
    /// reset, observed at the subscription fetch time (spec 011 FR-001, FR-002).
    /// Nil without a reset time, as after a passed reset (spec 010 FR-016).
    public func pace(observedAt: Date, now: Date) -> Pace? {
        paceInputs(observedAt: observedAt)?.pace(now: now)
    }

    /// The inputs of `pace(observedAt:now:)`.
    func paceInputs(observedAt: Date) -> PaceInputs? {
        guard let resetsAt else { return nil }
        return PaceInputs(usedPercent: utilizationPercent, windowStart: resetsAt.addingTimeInterval(-WindowResolver.weekSeconds),
                          resetsAt: resetsAt, observedAt: observedAt)
    }
}

extension CodexLimitWindow {
    /// The pace of a Codex plan window of its reported length, observed at
    /// the observation time of the limits (spec 011 FR-001, FR-002). Nil
    /// without a reset time, which includes a window past its reset in the
    /// effective windows (spec 007 FR-010, research R3), when the limit is
    /// reported as reached, and for the exclusions of `Pace.compute` (FR-007).
    public func pace(observedAt: Date, now: Date) -> Pace? {
        paceInputs(observedAt: observedAt)?.pace(now: now)
    }

    /// The inputs of `pace(observedAt:now:)`.
    func paceInputs(observedAt: Date) -> PaceInputs? {
        guard let resetsAt, !limitReached else { return nil }
        let length = TimeInterval(lengthMinutes) * 60
        return PaceInputs(usedPercent: usedPercent, windowStart: resetsAt.addingTimeInterval(-length),
                          resetsAt: resetsAt, observedAt: observedAt)
    }
}

extension SubscriptionStatus {
    /// The 5-hour window's pace at the fetch time, the snapshot time `now`
    /// only ruling out a window that has reset since (spec 011 FR-001,
    /// FR-002, FR-007). The dropdown, the bar and the burn rate all use
    /// these accessors, so the window lengths and the observation time live
    /// in one place.
    public func fiveHourPace(now: Date) -> Pace? {
        fiveHourPaceInputs?.pace(now: now)
    }

    /// The 7-day window's pace at the fetch time; the bar marker follows
    /// it (spec 011 FR-001, FR-002, FR-012).
    public func sevenDayPace(now: Date) -> Pace? {
        sevenDayPaceInputs?.pace(now: now)
    }

    /// A model-scoped weekly limit's pace at the fetch time (spec 011
    /// FR-001, FR-002).
    public func pace(of limit: ModelLimit, now: Date) -> Pace? {
        paceInputs(of: limit)?.pace(now: now)
    }

    var fiveHourPaceInputs: PaceInputs? {
        fiveHour?.paceInputs(length: Pace.fiveHourSeconds, observedAt: fetchedAt)
    }

    var sevenDayPaceInputs: PaceInputs? {
        sevenDay?.paceInputs(length: WindowResolver.weekSeconds, observedAt: fetchedAt)
    }

    func paceInputs(of limit: ModelLimit) -> PaceInputs? {
        limit.paceInputs(observedAt: fetchedAt)
    }
}

extension CodexLimitsEntry {
    /// The pace of one of `windows(now:)` at the observation time of the
    /// limits; nil without an observation (spec 011 FR-002, FR-007).
    public func pace(of window: CodexLimitWindow, now: Date) -> Pace? {
        paceInputs(of: window)?.pace(now: now)
    }

    /// The inputs of `pace(of:now:)`.
    func paceInputs(of window: CodexLimitWindow) -> PaceInputs? {
        observation.flatMap { window.paceInputs(observedAt: $0.observedAt) }
    }

    /// The longest effective window, the one `barPercent(now:)` shows; the
    /// bar marker and the fast burn follow it (spec 011 FR-012, spec 017
    /// FR-008, spec 007 FR-012).
    public func barWindow(now: Date) -> CodexLimitWindow? {
        windows(now: now).last
    }

    /// The pace of `barWindow(now:)` (spec 011 FR-012).
    public func barPace(now: Date) -> Pace? {
        barWindow(now: now).flatMap { pace(of: $0, now: now) }
    }
}
