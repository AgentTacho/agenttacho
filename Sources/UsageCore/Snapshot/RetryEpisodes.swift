import Foundation

/// Per-account failure episodes of a network source (spec 010 FR-004 to
/// FR-009, research R1). An episode starts with the first failed request
/// after a success or after launch and ends with the next success; it has
/// at most one quick retry. A plain value with no clock of its own.
public struct RetryEpisodes: Equatable, Sendable {
    /// Time from a transport failure to its quick retry (spec 010 FR-004).
    public static let delay: TimeInterval = 30

    public enum Phase: Equatable, Sendable {
        /// A quick retry is due at `retryAt`; `unmarked` keeps the shown
        /// values unmarked (spec 010 FR-005).
        case grace(retryAt: Date, unmarked: Bool)
        /// The episode's quick retry was used or is not available.
        case exhausted
    }

    public private(set) var phases: [String: Phase] = [:]

    public init() {}

    /// A successful request ends the account's episode (spec 010 FR-006).
    public mutating func succeeded(_ id: String) {
        phases[id] = nil
    }

    /// Records a failed request and returns the account's phase after it.
    /// Only the first failure of an episode, and only a transport failure,
    /// gets a grace period (spec 010 FR-004, FR-006, FR-007).
    public mutating func failed(_ id: String, category: FailureCategory, now: Date, hasLiveValuesThisRun: Bool) -> Phase {
        let phase: Phase
        if phases[id] == nil, category == .transport {
            phase = .grace(retryAt: now.addingTimeInterval(Self.delay), unmarked: hasLiveValuesThisRun)
        } else {
            phase = .exhausted
        }
        phases[id] = phase
        return phase
    }

    /// The grace period ended without a request (blocked at the retry time):
    /// the episode's quick retry counts as used (spec 010 FR-007).
    public mutating func expire(_ id: String) {
        if case .grace? = phases[id] { phases[id] = .exhausted }
    }

    /// The time of the account's pending quick retry, if any.
    public func retryAt(_ id: String) -> Date? {
        if case .grace(let retryAt, _)? = phases[id] { return retryAt }
        return nil
    }

    /// True when the account is in a grace period whose quick retry is due
    /// at `now`: `retryAt <= now < retryAt + delay` (spec 010 FR-007,
    /// FR-008, plan Design Note 10).
    public func isRetryDue(_ id: String, now: Date) -> Bool {
        guard let retryAt = retryAt(id) else { return false }
        return retryAt <= now && now < retryAt.addingTimeInterval(Self.delay)
    }

    /// True when the account's grace period passed its due window without a
    /// request: its quick retry counts as used (spec 010 FR-007, edge case
    /// "Retry while asleep", plan Design Note 10).
    public func isRetryOverdue(_ id: String, now: Date) -> Bool {
        guard let retryAt = retryAt(id) else { return false }
        return now >= retryAt.addingTimeInterval(Self.delay)
    }

    /// Drops the accounts the configuration no longer has.
    public mutating func forget(except ids: Set<String>) {
        phases = phases.filter { ids.contains($0.key) }
    }
}
