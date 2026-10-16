import Foundation

/// One limit of a ChatGPT plan: its length, the used percent, the reset time
/// and whether the limit was reached (spec 007 Key Entities, FR-001).
public struct CodexLimitWindow: Equatable, Sendable {
    /// Window length in minutes, greater than 0.
    public var lengthMinutes: Int
    /// The raw percent the source reports, uncapped.
    public var usedPercent: Double
    public var resetsAt: Date?
    public var limitReached: Bool

    public init(lengthMinutes: Int, usedPercent: Double, resetsAt: Date?, limitReached: Bool = false) {
        self.lengthMinutes = lengthMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.limitReached = limitReached
    }

    /// A window from untrusted source values (the usage service or a session
    /// log), or nil when it does not count: a missing or non-finite percent,
    /// or a length that is missing, not finite, 0 or less, or too large. The
    /// length is rounded up to whole minutes, the mapping Codex uses for its
    /// rollout snapshots; a non-finite reset time counts as none.
    public init?(minutes: Double?, usedPercent: Double?, resetEpoch: Double?) {
        guard let usedPercent, usedPercent.isFinite,
              let minutes, minutes.isFinite, minutes > 0, minutes < Double(Int32.max) else { return nil }
        let reset = resetEpoch.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        self.init(lengthMinutes: Int(minutes.rounded(.up)), usedPercent: usedPercent, resetsAt: reset)
    }

    /// The window's name and identity (FR-009, research R7): under one day
    /// "N-hour", a length that rounds to 7 days "weekly", otherwise "N-day",
    /// with N rounded to the nearest whole unit.
    public var name: String {
        let minutes = Double(lengthMinutes)
        if lengthMinutes < 24 * 60 {
            return "\(max(1, PercentFormatter.rounded(minutes / 60)))-hour"
        }
        let days = PercentFormatter.rounded(minutes / (24 * 60))
        return days == 7 ? "weekly" : "\(days)-day"
    }

    /// Applies the limit-reached rule of research R2: a window is reached
    /// when its percent is at least 100, or when the source reports a reached
    /// limit and the window has the highest percent of the observation (the
    /// source does not name the window; the highest one is the one that
    /// blocks).
    public static func applyingReachedRule(_ windows: [CodexLimitWindow], sourceReportsReached: Bool) -> [CodexLimitWindow] {
        let highest = windows.map(\.usedPercent).max()
        return windows.map { window in
            var copy = window
            copy.limitReached = window.usedPercent >= 100 || (sourceReportsReached && window.usedPercent == highest)
            return copy
        }
    }
}

/// The plan's limits at one moment (spec 007 Key Entities). The observation
/// time is the fetch time for a live result and the event timestamp for a
/// snapshot (FR-001).
public struct CodexLimitObservation: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        /// Fetched from the plan's usage service (FR-002).
        case live
        /// Read from a Codex session log (FR-004).
        case snapshot
    }

    /// The raw plan type, for example `"plus"`.
    public var planType: String?
    public var observedAt: Date
    public var origin: Origin
    /// Unique by name; a later window with the same name is dropped (FR-009).
    public let windows: [CodexLimitWindow]

    public init(planType: String?, observedAt: Date, origin: Origin, windows: [CodexLimitWindow]) {
        self.planType = planType
        self.observedAt = observedAt
        self.origin = origin
        var seen = Set<String>()
        self.windows = windows.filter { seen.insert($0.name).inserted }
    }

    /// The windows as shown at `now`, shortest first. A window whose reset
    /// time has passed shows 0%, no reset time and no limit-reached note
    /// until a newer observation arrives (FR-010).
    public func effectiveWindows(now: Date) -> [CodexLimitWindow] {
        windows.map { window in
            guard let resetsAt = window.resetsAt, resetsAt <= now else { return window }
            return CodexLimitWindow(lengthMinutes: window.lengthMinutes, usedPercent: 0, resetsAt: nil, limitReached: false)
        }
        .sorted { $0.lengthMinutes < $1.lengthMinutes }
    }
}

/// Where the shown values of a Codex subscription account come from
/// (spec 007 FR-005, FR-006, data-model.md).
public enum CodexLimitsState: Equatable, Sendable {
    /// Fetched in this refresh, or the kept live result when no request was
    /// due and no snapshot is newer (FR-006 exception).
    case live
    /// Live limits are on, no request was due and the last request did not
    /// fail, but a snapshot newer than the kept live result exists: the
    /// snapshot is shown with its observation time, not as a failure
    /// (FR-005, FR-006 exception).
    case newerSnapshot
    /// Live limits are off: a snapshot, shown as local data, not a failure.
    case localOnly
    /// Live limits are on, but the values come from an earlier live result
    /// or a snapshot; `reason` says why the live values are missing.
    case stale(reason: String)
    /// No observation at all.
    case unavailable(reason: String)
    /// A transport failure inside a grace period: the shown observation
    /// stays unmarked until the quick retry at `retryAt` (spec 010 FR-005).
    case retrying(reason: String, retryAt: Date)

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    /// The live-limits setting a refresh producing this state had:
    /// `.localOnly` comes only with live limits off, `.live`,
    /// `.newerSnapshot` and `.stale` only with them on. Nil for
    /// `.unavailable`, which either setting produces.
    public var impliedLiveLimits: Bool? {
        switch self {
        case .live, .newerSnapshot, .stale, .retrying: return true
        case .localOnly: return false
        case .unavailable: return nil
        }
    }
}

/// Why a Codex sign-in could not be used before a request was sent, carried
/// as a typed value so credential notifications never match reason strings;
/// the only string match left is the lookup's keychain reason, in
/// `CodexLimitsSource.live` (spec 014 FR-001, FR-005, FR-009).
public enum CodexCredentialProblem: Equatable, Sendable {
    /// The token's expiry time passed; `at` is its JWT expiry.
    case expired(at: Date)
    /// No plan sign-in in the Codex home.
    case notSignedIn
    /// Codex keeps its sign-in in the keychain, which AgentMeter cannot read.
    case keychain
}

/// The plan limits of one Codex subscription account in a snapshot
/// (spec 007 FR-001, FR-011, FR-012).
public struct CodexLimitsEntry: Equatable, Sendable {
    /// Nil only for `.unavailable`.
    public var observation: CodexLimitObservation?
    public var state: CodexLimitsState
    /// Set only for an unreadable answer or a rejected sign-in; the
    /// coordinator turns it into a `SourceError` (FR-006).
    public var sourceError: String?
    /// Time of the account's pending quick retry, also when the shown values
    /// are stale or absent (spec 010 FR-004, plan Design Note 2).
    public var quickRetryAt: Date?
    /// True when the shown reason is a rejected sign-in, from a 401 or 403
    /// answer or a token already rejected; drawn in the attention style
    /// (spec 010 FR-012).
    public var signInRejected: Bool
    /// Set for entries built from a failure before a request (missing or
    /// expired sign-in); nil otherwise. Kept by `markedStale` (spec 014
    /// FR-001).
    public var credentialProblem: CodexCredentialProblem?

    /// True when this refresh sent a request for the account's Codex home
    /// and got an answer that is not a transport failure (spec 016 FR-005,
    /// FR-013, research R5). Transient: never saved, false when carried
    /// over, and not part of equality.
    public var reachedService: Bool {
        get { reachedServiceFlag.value }
        set { reachedServiceFlag.value = newValue }
    }
    private var reachedServiceFlag = TransientFlag()
    /// True when this refresh tried the account's Codex home: it sent a
    /// request (whatever the answer) or found that no request was possible
    /// because of the sign-in (spec 016 FR-012, FR-014). Transient like
    /// `reachedService`; implied by it.
    public var attempted: Bool {
        get { attemptedFlag.value || reachedService }
        set { attemptedFlag.value = newValue }
    }
    private var attemptedFlag = TransientFlag()

    public init(observation: CodexLimitObservation?, state: CodexLimitsState, sourceError: String? = nil,
                quickRetryAt: Date? = nil, signInRejected: Bool = false, credentialProblem: CodexCredentialProblem? = nil,
                reachedService: Bool = false, attempted: Bool = false) {
        self.observation = observation
        self.state = state
        self.sourceError = sourceError
        self.quickRetryAt = quickRetryAt
        self.signInRejected = signInRejected
        self.credentialProblem = credentialProblem
        self.reachedServiceFlag = TransientFlag(reachedService)
        self.attemptedFlag = TransientFlag(attempted)
    }

    /// The entry carried over a failed refresh: live values and values in a
    /// grace period become stale with `reason`, local and already stale or
    /// unavailable values keep their state, and the source error is not
    /// repeated (FR-005, FR-021, spec 010 FR-005).
    public func markedStale(reason: String) -> CodexLimitsEntry {
        var copy = self
        copy.sourceError = nil
        copy.quickRetryAt = nil
        copy.reachedService = false
        copy.attempted = false
        switch state {
        case .live, .newerSnapshot, .retrying: copy.state = .stale(reason: reason)
        case .localOnly, .stale, .unavailable: break
        }
        return copy
    }

    /// The effective windows at `now`, shortest first (FR-010).
    public func windows(now: Date) -> [CodexLimitWindow] {
        observation?.effectiveWindows(now: now) ?? []
    }

    /// The rounded percent of the longest effective window (FR-012, spec
    /// 001 FR-009a); nil without an observation.
    public func barPercent(now: Date) -> Int? {
        windows(now: now).last.map { PercentFormatter.rounded($0.usedPercent) }
    }

    /// True when any effective window carries the limit-reached note (FR-012).
    public func anyLimitReached(now: Date) -> Bool {
        windows(now: now).contains { $0.limitReached }
    }

    /// The plan type as a capitalized name, for example "Plus" (FR-011).
    public static func planDisplayName(_ planType: String?) -> String? {
        guard let planType, let first = planType.first else { return nil }
        return first.uppercased() + planType.dropFirst()
    }
}
