import Foundation

/// How fast one window or budget burns at one snapshot (spec 017 Key
/// Entities, research R7): the sustainable rate, the average rate since the
/// window start, the recent rate if it exists, and the fast run-out. All
/// rates are in percentage points per hour. Computed from snapshot values
/// and in-memory observations only, never stored.
public struct BurnRate: Equatable, Sendable {
    /// The remaining percent over the time left until the reset, at the
    /// observation time (spec 017 FR-001).
    public let sustainablePerHour: Double
    /// The used percent over the time elapsed since the window start; nil
    /// when no time has elapsed (spec 017 FR-002).
    public let averagePerHour: Double?
    /// The recent rate from the observation log, whether it qualifies or not
    /// (spec 017 FR-004).
    public let recentPerHour: Double?
    /// The run-out at the earlier qualifying rate; set exactly when the entry
    /// burns fast (spec 017 FR-005 to FR-007).
    public let fastRunOut: Date?

    /// The entry burns at least `factor` times its sustainable rate (spec 017 FR-005).
    public var burnsFast: Bool { fastRunOut != nil }

    /// The escalation factor k (spec 017 FR-005).
    public static let factor = 2.0
    /// How far back observations count, in seconds (spec 017 FR-003, FR-004).
    public static let lookback: TimeInterval = 3600
    /// The minimum time between the oldest and newest observation for a
    /// recent rate, in seconds (spec 017 FR-004).
    public static let minimumSpan: TimeInterval = 900
    /// The minimum change in used percent for a recent rate, in points (spec 017 FR-004).
    public static let minimumChange = 2.0

    static let secondsPerHour: TimeInterval = 3600

    init(sustainablePerHour: Double, averagePerHour: Double?, recentPerHour: Double?, fastRunOut: Date?) {
        self.sustainablePerHour = sustainablePerHour
        self.averagePerHour = averagePerHour
        self.recentPerHour = recentPerHour
        self.fastRunOut = fastRunOut
    }

    /// The burn rate of a value `usedPercent` observed at `observedAt` in the
    /// window from `windowStart` to `resetsAt`, with the entry's spec 011
    /// `pace` and the `recent` rate from the observation log, at the snapshot
    /// time `now` (spec 017 FR-001, FR-002, FR-005 to FR-007).
    ///
    /// The average rate qualifies only when spec 011 counts a run-out
    /// (`pace.runOut`); the recent rate qualifies whenever it is at least
    /// `factor` times the sustainable rate at its own observation, also on
    /// pace, behind or inside the hold back (FR-006). A rate whose run-out is
    /// at or before `now` does not qualify; the earlier run-out of the
    /// qualifying rates is the fast run-out (FR-007). Nil when the
    /// observation is at or after the reset, which leaves the sustainable
    /// rate undefined.
    static func compute(pace: Pace, usedPercent: Double, windowStart: Date, resetsAt: Date,
                               observedAt: Date, now: Date, recent: RecentRate?) -> BurnRate? {
        let left = resetsAt.timeIntervalSince(observedAt)
        guard left > 0, usedPercent.isFinite else { return nil }
        let remaining = 100 - usedPercent
        let sustainable = remaining / (left / secondsPerHour)

        let elapsed = observedAt.timeIntervalSince(windowStart)
        let average: Double? = elapsed > 0 ? usedPercent / (elapsed / secondsPerHour) : nil

        var runOuts: [Date] = []
        // At the average rate the run-out is spec 011's linear run-out,
        // which `pace.runOut` holds only when it counts (FR-006); a pace
        // computed for an earlier snapshot time may hold one that has passed.
        if let runOut = pace.runOut, runOut > now, let average, average >= factor * sustainable {
            runOuts.append(runOut)
        }
        if let recent, recent.perHour > 0, recent.perHour.isFinite {
            let recentLeft = resetsAt.timeIntervalSince(recent.observedAt)
            let recentRemaining = 100 - recent.usedPercent
            if recentLeft > 0, recent.perHour >= factor * (recentRemaining / (recentLeft / secondsPerHour)) {
                let runOut = recent.observedAt.addingTimeInterval(recentRemaining / recent.perHour * secondsPerHour)
                if runOut > now { runOuts.append(runOut) }
            }
        }
        return BurnRate(sustainablePerHour: sustainable, averagePerHour: average,
                        recentPerHour: recent?.perHour, fastRunOut: runOuts.min())
    }
}

/// The pace of one window or budget with the values it was computed from
/// (spec 011 FR-001, FR-002, spec 017 FR-001 to FR-003).
struct BurnInputs: Equatable, Sendable {
    let pace: Pace
    let values: PaceInputs
}

extension UsageSnapshot {
    /// The burn rate of the window or budget `key` at the snapshot time,
    /// with the recent rate from `observations` (spec 017 FR-001 to FR-007,
    /// research R10). Nil when the key is unknown or its window has no pace
    /// (spec 011 FR-007). The bar and the dropdown both use this accessor,
    /// so they cannot disagree on a window's inputs.
    public func burnRate(for key: BurnWindowKey) -> BurnRate? {
        guard let inputs = burnInputs(for: key) else { return nil }
        let values = inputs.values
        return BurnRate.compute(pace: inputs.pace, usedPercent: values.usedPercent, windowStart: values.windowStart,
                                resetsAt: values.resetsAt, observedAt: values.observedAt, now: generatedAt,
                                recent: observations.recentRate(for: key, now: generatedAt))
    }

    /// Every window and budget key of this snapshot that may have a pace:
    /// the Claude 5-hour, 7-day and model limits, every effective Codex
    /// window by name, every group and own budget (spec 017 Key Entities).
    var burnWindowKeys: [BurnWindowKey] {
        var keys: [BurnWindowKey] = []
        for (id, entry) in subscriptions {
            guard let status = entry.status else { continue }
            keys.append(.claude(id, .fiveHour))
            keys.append(.claude(id, .sevenDay))
            keys += status.modelLimits.map { .claude(id, .model($0.modelName)) }
        }
        for (id, entry) in codexLimits {
            keys += entry.windows(now: generatedAt).map { .codex(id, $0.name) }
        }
        keys += groups.keys.map { .group($0) }
        keys += accountBudgets.keys.map { .accountBudget($0) }
        return keys
    }

    /// The budget entry of a group or own-budget key; nil for other keys.
    func budgetEntry(for key: BurnWindowKey) -> GroupEntry? {
        switch key {
        case .group(let id): groups[id]
        case .accountBudget(let id): accountBudgets[id]
        case .claude, .codex: nil
        }
    }

    /// The pace of `key` with its inputs, from the same accessors the
    /// dropdown and the bar use: Claude windows observed at the fetch time
    /// with the unrounded utilization, Codex windows of `windows(now:)`
    /// observed at the observation time, budgets observed at the snapshot
    /// time with the unrounded spend share. Nil without a pace (spec 011 FR-007).
    func burnInputs(for key: BurnWindowKey) -> BurnInputs? {
        let now = generatedAt
        let values: PaceInputs?
        switch key {
        case .claude(let id, let window):
            guard let status = subscriptions[id]?.status else { return nil }
            switch window {
            case .fiveHour: values = status.fiveHourPaceInputs
            case .sevenDay: values = status.sevenDayPaceInputs
            case .model(let name): values = status.modelLimits.first { $0.modelName == name }.flatMap { status.paceInputs(of: $0) }
            }
        case .codex(let id, let name):
            guard let entry = codexLimits[id] else { return nil }
            // The last of a name, like the bar's longest window.
            values = entry.windows(now: now).last { $0.name == name }.flatMap { entry.paceInputs(of: $0) }
        case .group, .accountBudget:
            values = budgetEntry(for: key)?.paceInputs(now: now)
        }
        guard let values, let pace = values.pace(now: now) else { return nil }
        return BurnInputs(pace: pace, values: values)
    }
}
