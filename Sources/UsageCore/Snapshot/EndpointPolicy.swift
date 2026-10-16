import Foundation

/// Why a refresh runs. Decides, through `EndpointPolicy`, whether the
/// refresh may call the usage endpoint.
public enum RefreshTrigger: String, Sendable, CaseIterable {
    case scheduled, launch, wake, manual, settings, retry, local
    /// The single quick retry 30 s after a transport failure (spec 010
    /// FR-004, FR-008, research R2).
    case quickRetry

    /// While a refresh runs, one pending trigger is kept: the one with the
    /// highest rank.
    public var rank: Int {
        switch self {
        case .scheduled, .retry, .quickRetry: return 2
        case .launch, .wake, .manual, .settings: return 1
        case .local: return 0
        }
    }
}

/// Result of one usage endpoint request for an account.
public enum FetchOutcome: Equatable, Sendable {
    case success
    case rateLimited(retryAfter: TimeInterval?)
    case otherError

    public var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    /// One outcome for all accounts of a refresh: any rate limit wins (with
    /// the longest known wait), all successes are a success, anything else
    /// is an other error. Nil when no request was made.
    public static func combined(_ outcomes: [FetchOutcome]) -> FetchOutcome? {
        guard !outcomes.isEmpty else { return nil }
        var limited = false
        var longest: TimeInterval?
        for case .rateLimited(let wait) in outcomes {
            limited = true
            if let wait { longest = max(longest ?? wait, wait) }
        }
        if limited { return .rateLimited(retryAfter: longest) }
        return outcomes.allSatisfy { $0 == .success } ? .success : .otherError
    }
}

/// Decides whether a refresh calls the usage endpoint or reuses the last
/// network result, and tracks rate-limit blocks and the single retry
/// (docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md).
/// A plain value with no clock of its own: callers pass `now`.
public struct EndpointPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case fetch
        /// `retryAt` asks the caller to schedule one retry at that time.
        case reuse(reason: String, retryAt: Date?)
    }

    /// Minimum time between endpoint calls for `manual`, `wake` and `settings`.
    public static let minimumSpacing: TimeInterval = 60
    /// First backoff after a 429 without `Retry-After`; doubles per consecutive 429.
    public static let defaultBackoff: TimeInterval = 60

    /// Caps the backoff; the coordinator updates it from the configuration.
    public var refreshInterval: TimeInterval
    public private(set) var lastAttemptAt: Date?
    public private(set) var lastOutcome: FetchOutcome?
    public private(set) var blockedUntil: Date?
    public private(set) var consecutiveRateLimits = 0
    public private(set) var retryUsed = false

    public init(refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
    }

    public mutating func decide(_ trigger: RefreshTrigger, now: Date) -> Decision {
        if trigger == .scheduled { retryUsed = false }
        if trigger == .local { return .reuse(reason: "local change", retryAt: nil) }
        guard let last = lastAttemptAt else { return .fetch }
        if let until = blockedUntil {
            if now < last {
                // The clock moved backwards; never stay blocked because of it.
                blockedUntil = nil
            } else if now < until {
                var retryAt: Date?
                if trigger == .scheduled && !retryUsed {
                    retryUsed = true
                    retryAt = until
                }
                return .reuse(reason: "rate limited until \(until.formatted(date: .omitted, time: .shortened))", retryAt: retryAt)
            }
        }
        // The quick retry fetches unless a rate-limit block is active: no
        // spacing and no "already fresh" reuse (spec 010 FR-007, FR-008).
        if trigger == .quickRetry { return .fetch }
        if trigger == .retry, let outcome = lastOutcome, !outcome.isRateLimited {
            return .reuse(reason: "already fresh", retryAt: nil)
        }
        let elapsed = now.timeIntervalSince(last)
        if [.manual, .wake, .settings].contains(trigger), elapsed < Self.minimumSpacing {
            // A spaced subscription edit still needs fresh data: ask for a
            // follow-up as soon as the spacing allows a fetch.
            let followUp = trigger == .settings ? last.addingTimeInterval(Self.minimumSpacing) : nil
            return .reuse(reason: "last fetch \(Int(elapsed)) s ago", retryAt: followUp)
        }
        return .fetch
    }

    /// Records the outcome of a fetch. Returns the time of the single retry
    /// to schedule, or nil.
    public mutating func record(_ outcome: FetchOutcome, now: Date) -> Date? {
        lastAttemptAt = now
        lastOutcome = outcome
        switch outcome {
        case .success:
            blockedUntil = nil
            consecutiveRateLimits = 0
            return nil
        case .otherError:
            return nil
        case .rateLimited(let retryAfter):
            let cap = max(refreshInterval, Self.defaultBackoff)
            let backoff = min(Self.defaultBackoff * pow(2, Double(consecutiveRateLimits)), cap)
            consecutiveRateLimits += 1
            let until = now.addingTimeInterval(retryAfter ?? backoff)
            blockedUntil = until
            guard !retryUsed else { return nil }
            retryUsed = true
            return until
        }
    }
}
