import Foundation

/// A rate-limited usage endpoint whose calls follow the agent activity
/// (spec 016 FR-004): the Claude usage endpoint and the Codex usage
/// endpoint. All Codex homes share one pace (FR-003a).
public enum PacedEndpoint: String, CaseIterable, Sendable {
    case claude, codex

    /// The harnesses whose records count as activity for this endpoint.
    /// OpenCode can use either subscription, so it counts for both (FR-004).
    public var harnesses: Set<Harness> {
        switch self {
        case .claude: return [.claudeCode, .openCode]
        case .codex: return [.codex, .openCode]
        }
    }

    /// Whether a refresh would call this endpoint: Claude with at least one
    /// Claude subscription account, Codex with at least one Codex
    /// subscription account that has live limits on (FR-003a).
    public func isInUse(_ configuration: Configuration) -> Bool {
        switch self {
        case .claude:
            return !configuration.subscriptionAccounts.isEmpty
        case .codex:
            return configuration.codexSubscriptionAccounts.contains { $0.kind.codexSubscription?.liveLimits == true }
        }
    }

    /// The plan as the pace line names it: "Claude" or "Codex", not an
    /// account name (spec 019 FR-001).
    public var planName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// The plan's main agent as the pace line names it, "Claude Code" or
    /// "Codex" (spec 019 FR-001). OpenCode also counts for both plans but is
    /// not named: a plan slowed for lack of activity had neither agent
    /// active, so naming the main one is still true.
    public var agentName: String {
        switch self {
        case .claude: return Harness.claudeCode.displayName
        case .codex: return Harness.codex.displayName
        }
    }
}

/// The system state that slows the whole refresh timer (spec 016 FR-008,
/// FR-009), read by the app without permissions (research R8).
public struct SystemConditions: Equatable, Sendable {
    /// No input for 10 minutes, the screen locked, or the displays asleep.
    public var idle: Bool
    public var lowPowerMode: Bool
    /// The thermal state is serious or critical.
    public var thermalPressure: Bool

    public init(idle: Bool = false, lowPowerMode: Bool = false, thermalPressure: Bool = false) {
        self.idle = idle
        self.lowPowerMode = lowPowerMode
        self.thermalPressure = thermalPressure
    }
}

/// Why a pace is slower than the base, ranked for the pace line: idle,
/// then Low Power Mode, then high temperature, then no agent activity
/// (spec 016 FR-016).
public enum PaceReason: Int, Comparable, Sendable {
    case idle, lowPowerMode, highTemperature, noAgentActivity

    public static func < (lhs: PaceReason, rhs: PaceReason) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The reason as the pace line and the diagnostic log name it.
    public var displayName: String {
        switch self {
        case .idle: return "away"
        case .lowPowerMode: return "Low Power Mode"
        case .highTemperature: return "high temperature"
        case .noAgentActivity: return "no agent activity"
        }
    }
}

/// A change of an endpoint's interval, for the diagnostic log (spec 016
/// FR-017). `reason` is `.noAgentActivity` when the interval grew and nil
/// when it returned to the base.
public struct IntervalChange: Equatable, Sendable {
    public let endpoint: PacedEndpoint
    public let from: TimeInterval
    public let to: TimeInterval
    public let reason: PaceReason?

    public init(endpoint: PacedEndpoint, from: TimeInterval, to: TimeInterval, reason: PaceReason?) {
        self.endpoint = endpoint
        self.from = from
        self.to = to
        self.reason = reason
    }
}

/// The pace of one usage endpoint (spec 016 FR-005, FR-013).
public struct EndpointPace: Equatable, Sendable {
    /// The last call that reached the service, of any trigger.
    public var lastCallAt: Date?
    /// The start of the last refresh that tried the endpoint: it sent a
    /// request (whatever the answer, transport failures included) or found
    /// that no request was possible (expired or missing sign-in). Never
    /// earlier than `lastCallAt`.
    public var lastTriedAt: Date?
    /// The current interval between scheduled calls; starts at the base.
    public var interval: TimeInterval

    public init(lastCallAt: Date? = nil, lastTriedAt: Date? = nil, interval: TimeInterval) {
        self.lastCallAt = lastCallAt
        self.lastTriedAt = lastTriedAt ?? lastCallAt
        self.interval = interval
    }
}

/// What a change of the system conditions means for a refresh on the
/// return from idle (spec 016 FR-011).
public enum IdleReturn: Equatable, Sendable {
    /// No return from idle, or adaptive refresh is off.
    case none
    /// The user returned: start a refresh.
    case refresh
    /// The user returned within 60 s after a wake refresh: no further refresh.
    case afterWake
}

/// The adaptive refresh pace (spec 016 FR-003 to FR-013, FR-016, FR-019,
/// data-model.md). A plain value with no clock of its own: callers pass
/// `now`. Owned by `RefreshCoordinator` next to `EndpointPolicy`, which
/// keeps the rate-limit rules; this value only adds "not due yet" for
/// scheduled refreshes and computes the timer.
public struct AdaptivePace: Equatable, Sendable {
    /// The slowest adaptive pace, unless the base is longer (FR-003).
    public static let cap: TimeInterval = 1800
    /// A tick this early before a due time counts as due (FR-006).
    public static let tickTolerance: TimeInterval = 5
    /// The minimum age of an endpoint's last call for a refresh on opening
    /// the dropdown (FR-012).
    public static let openSpacing: TimeInterval = 60
    /// A return from idle this soon after a wake refresh starts no further
    /// refresh (FR-011).
    public static let wakeQuietPeriod: TimeInterval = 60

    /// From `adaptiveRefresh` (FR-001, FR-002).
    public private(set) var enabled: Bool
    /// The configured refresh interval, the fastest regular pace (FR-003).
    public private(set) var base: TimeInterval
    public private(set) var conditions = SystemConditions()
    public private(set) var inUse: Set<PacedEndpoint>
    /// Start of the last completed refresh of any trigger (FR-003a).
    public private(set) var lastRefreshAt: Date?
    /// Start of the last completed scheduled refresh.
    public private(set) var lastScheduledAt: Date?
    /// When the last wake refresh was requested (FR-011).
    public private(set) var lastWakeAt: Date?
    private var endpoints: [PacedEndpoint: EndpointPace]

    public init(enabled: Bool = true, base: TimeInterval, inUse: Set<PacedEndpoint> = []) {
        self.enabled = enabled
        self.base = base
        self.inUse = inUse
        endpoints = Dictionary(uniqueKeysWithValues: PacedEndpoint.allCases.map { ($0, EndpointPace(interval: base)) })
    }

    /// The pace of `endpoint`.
    public func pace(of endpoint: PacedEndpoint) -> EndpointPace {
        endpoints[endpoint] ?? EndpointPace(interval: base)
    }

    public func lastCallAt(_ endpoint: PacedEndpoint) -> Date? { pace(of: endpoint).lastCallAt }
    public func lastTriedAt(_ endpoint: PacedEndpoint) -> Date? { pace(of: endpoint).lastTriedAt }
    public func interval(_ endpoint: PacedEndpoint) -> TimeInterval { pace(of: endpoint).interval }

    /// A base above the cap is never stretched (FR-003).
    private var bound: TimeInterval { max(base, Self.cap) }

    // MARK: Configuration and conditions

    /// Takes the toggle, the base and the endpoints in use from the
    /// configuration. A changed base or toggle starts every interval at the
    /// base again (spec edge case "Toggle switched while slowed").
    public mutating func update(configuration: Configuration) {
        let newEnabled = configuration.adaptiveRefresh
        let newBase = TimeInterval(configuration.refreshIntervalSeconds)
        if newEnabled != enabled || newBase != base {
            for endpoint in PacedEndpoint.allCases {
                endpoints[endpoint, default: EndpointPace(interval: newBase)].interval = newBase
            }
        }
        enabled = newEnabled
        base = newBase
        inUse = Set(PacedEndpoint.allCases.filter { $0.isInUse(configuration) })
    }

    /// Stores the conditions and returns whether the timer interval or its
    /// reason changed (for the log and for re-arming the timer, FR-017).
    /// Always false while disabled: the conditions are kept but do nothing.
    public mutating func update(conditions: SystemConditions) -> Bool {
        let before = (timerInterval, timerReason)
        self.conditions = conditions
        return before.0 != timerInterval || before.1 != timerReason
    }

    /// A wake refresh was requested at `at` (FR-011).
    public mutating func wakeRequested(at: Date) {
        lastWakeAt = at
    }

    /// Whether the change from `previous` to the current conditions is a
    /// return from idle that starts a refresh (FR-011): only with adaptive
    /// refresh on (FR-002), and not within 60 s after a wake refresh.
    public func idleReturn(from previous: SystemConditions, now: Date) -> IdleReturn {
        guard enabled, previous.idle, !conditions.idle else { return .none }
        if let wake = lastWakeAt, now >= wake, now.timeIntervalSince(wake) < Self.wakeQuietPeriod {
            return .afterWake
        }
        return .refresh
    }

    // MARK: Timer pace (FR-008 to FR-010)

    /// The time between scheduled refreshes. Idle: 30 minutes; Low Power
    /// Mode or thermal pressure: twice the base, capped at 30 minutes; the
    /// longest applicable interval wins, and it is never shorter than the
    /// base nor (unless the base is longer) longer than 30 minutes.
    public var timerInterval: TimeInterval {
        guard enabled else { return base }
        var interval = base
        if conditions.idle { interval = max(interval, bound) }
        if conditions.lowPowerMode || conditions.thermalPressure { interval = max(interval, min(2 * base, bound)) }
        return interval
    }

    /// The highest-ranked condition that slows the timer; nil while
    /// disabled or when the timer runs at the base.
    public var timerReason: PaceReason? {
        guard enabled, timerInterval > base else { return nil }
        let holding: [PaceReason?] = [conditions.idle ? .idle : nil,
                                      conditions.lowPowerMode ? .lowPowerMode : nil,
                                      conditions.thermalPressure ? .highTemperature : nil]
        return holding.compactMap { $0 }.min()
    }

    // MARK: Endpoint pace (FR-004 to FR-007, FR-010a, FR-013)

    /// The newest timestamp among `records` from the harnesses that count
    /// for `endpoint`, of any account including Unassigned (FR-004).
    public func newestActivity(_ endpoint: PacedEndpoint, in records: [UsageRecord]) -> Date? {
        let harnesses = endpoint.harnesses
        return records.lazy.filter { harnesses.contains($0.harness) }.map(\.timestamp).max()
    }

    /// The endpoint's last call plus the longer of its own interval and the
    /// timer interval; nil before its first call (FR-010a).
    public func dueAt(_ endpoint: PacedEndpoint) -> Date? {
        let pace = pace(of: endpoint)
        return pace.lastCallAt?.addingTimeInterval(max(pace.interval, timerInterval))
    }

    /// Whether a scheduled refresh calls `endpoint`: always while disabled
    /// or before its first call; otherwise when its due time has come (with
    /// the tick tolerance), or when there is activity newer than its last
    /// call and at least the timer interval has passed since then (FR-006).
    /// Rate-limit blocks are not decided here (`EndpointPolicy`, FR-014).
    public func shouldCall(_ endpoint: PacedEndpoint, newestActivity: Date?, now: Date) -> Bool {
        guard enabled, let last = lastCallAt(endpoint), let due = dueAt(endpoint) else { return true }
        if now >= due.addingTimeInterval(-Self.tickTolerance) { return true }
        if let activity = newestActivity, activity > last,
           now.timeIntervalSince(last) >= timerInterval - Self.tickTolerance {
            return true
        }
        return false
    }

    /// Records a call that reached the service and was not reused (FR-005,
    /// FR-013). Activity newer than the previous call returns the interval
    /// to the base, whatever triggered the call; a quiet scheduled call
    /// doubles it up to the cap; a quiet unscheduled call keeps it. Returns
    /// the change for the log, or nil. While disabled only the last call
    /// moves.
    @discardableResult
    public mutating func recordCall(_ endpoint: PacedEndpoint, at: Date, scheduled: Bool, newestActivity: Date?) -> IntervalChange? {
        var pace = pace(of: endpoint)
        let old = pace.interval
        defer { endpoints[endpoint] = pace }
        let previous = pace.lastCallAt
        pace.lastCallAt = at
        pace.lastTriedAt = max(pace.lastTriedAt ?? at, at)
        guard enabled else {
            pace.interval = base
            return nil
        }
        if previous == nil || (newestActivity.map { $0 > previous! } ?? false) {
            pace.interval = base
        } else if scheduled {
            pace.interval = min(pace.interval * 2, bound)
        }
        guard pace.interval != old else { return nil }
        return IntervalChange(endpoint: endpoint, from: old, to: pace.interval,
                              reason: pace.interval > old ? .noAgentActivity : nil)
    }

    /// A refresh that started at `at` tried `endpoint` without reaching the
    /// service: a transport failure, or no request possible because of the
    /// sign-in. The last call and the interval stay (FR-005, FR-013); the
    /// try counts for scheduling and the dropdown-open spacing.
    public mutating func recordTry(_ endpoint: PacedEndpoint, at: Date) {
        var pace = pace(of: endpoint)
        pace.lastTriedAt = max(pace.lastTriedAt ?? at, at)
        endpoints[endpoint] = pace
    }

    /// A refresh of any trigger completed; it started at `at` (FR-003a).
    public mutating func refreshCompleted(at: Date, scheduled: Bool) {
        lastRefreshAt = at
        if scheduled { lastScheduledAt = at }
    }

    /// A clock moved backwards never blocks a refresh: any stored time
    /// later than `now` becomes `now`, so a call is at most `max(interval,
    /// timerInterval)` away (spec edge case "Clock moved backwards").
    public mutating func normalize(now: Date) {
        for endpoint in PacedEndpoint.allCases {
            if let last = endpoints[endpoint]?.lastCallAt, last > now {
                endpoints[endpoint]?.lastCallAt = now
            }
            if let last = endpoints[endpoint]?.lastTriedAt, last > now {
                endpoints[endpoint]?.lastTriedAt = now
            }
        }
        if let last = lastRefreshAt, last > now { lastRefreshAt = now }
        if let last = lastScheduledAt, last > now { lastScheduledAt = now }
        if let last = lastWakeAt, last > now { lastWakeAt = now }
    }

    // MARK: Schedule (FR-010, FR-010a, research R7)

    /// When the next scheduled refresh runs: the earlier of the last
    /// refresh plus the timer interval and the earliest due time of an
    /// endpoint in use, never before `now`. A due time that a scheduled
    /// refresh already handled, or that a refresh of any trigger already
    /// tried (within the tick tolerance of it or earlier), is ignored, so an
    /// endpoint whose last call cannot move (transport failures, a block, no
    /// request) never makes the timer spin, and a failed wake or
    /// return-from-idle call is not followed by a scheduled call at once,
    /// which would use up the quick retry (FR-014, spec 010 FR-008).
    /// Without a completed refresh it is one timer interval from `now`, so
    /// the timer never adds a request at launch.
    public func nextScheduledRefresh(now: Date) -> Date {
        guard let lastRefresh = lastRefreshAt else { return now.addingTimeInterval(timerInterval) }
        guard enabled else { return max(now, lastRefresh.addingTimeInterval(base)) }
        var next = lastRefresh.addingTimeInterval(timerInterval)
        for endpoint in inUse {
            guard let due = dueAt(endpoint) else { continue }
            let handled = [lastScheduledAt, lastTriedAt(endpoint)].compactMap { $0 }.max()
            if let handled, due <= handled.addingTimeInterval(Self.tickTolerance) { continue }
            next = min(next, due)
        }
        return max(now, next)
    }

    /// Whether opening the dropdown starts a refresh: when an endpoint in
    /// use was neither called nor tried in the last 60 s, or, with no
    /// endpoint in use, when the last refresh is at least 60 s old. Never
    /// while disabled (FR-002, FR-012). A try that did not reach the
    /// service counts too: within 60 s of it the refresh could not call the
    /// endpoint (spacing) or would only read the sign-in again (FR-020).
    public func shouldRefreshOnOpen(now: Date) -> Bool {
        guard enabled else { return false }
        func old(_ date: Date?) -> Bool {
            guard let date else { return true }
            return now.timeIntervalSince(date) >= Self.openSpacing
        }
        if inUse.isEmpty { return old(lastRefreshAt) }
        return inUse.contains { old(lastTriedAt($0)) }
    }

    // MARK: Pace line (FR-016)

    /// The dropdown's pace line, or nil when every pace equals the base. A
    /// timer reason wins over "no agent activity". For "no agent activity"
    /// the time is the earliest next call of the stretched endpoints; for a
    /// timer reason the earliest next call of any endpoint in use, or the
    /// next scheduled refresh without one. An endpoint's next call is never
    /// before the next scheduled refresh, so the time is never in the past.
    /// For "no agent activity" the status carries the stretched endpoints in
    /// the fixed order Claude, Codex; a timer reason names none (spec 019
    /// FR-001 to FR-004).
    public func status(now: Date) -> RefreshPaceStatus? {
        guard enabled else { return nil }
        let next = nextScheduledRefresh(now: now)
        func nextCall(_ endpoint: PacedEndpoint) -> Date {
            max(dueAt(endpoint) ?? next, next)
        }
        if let reason = timerReason {
            guard let earliest = inUse.map(nextCall).min() else {
                return RefreshPaceStatus(reason: reason, nextAt: next, kind: .refresh)
            }
            return RefreshPaceStatus(reason: reason, nextAt: earliest, kind: .planLimits)
        }
        let stretched = inUse.filter { interval($0) > base }
        guard let earliest = stretched.map(nextCall).min() else { return nil }
        return RefreshPaceStatus(reason: .noAgentActivity, nextAt: earliest, kind: .planLimits,
                                 plans: PacedEndpoint.allCases.filter { stretched.contains($0) })
    }
}
