import Foundation

/// The pace of one window or budget together with its burn rate, both from
/// the same inputs (spec 025 FR-030, research R1, idea inbox
/// single-pace-and-burn-value). A row's bar tick, note and fill color all
/// derive from this one value, so they cannot disagree.
public struct PaceReading: Equatable, Sendable {
    /// The spec 011 pace at the observation time.
    public let pace: Pace
    /// The spec 017 burn rate; nil when it cannot be computed (an
    /// observation at or after the reset).
    public let burn: BurnRate?

    public init(pace: Pace, burn: BurnRate?) {
        self.pace = pace
        self.burn = burn
    }

    /// The row calls for attention: a counted run-out (spec 011 FR-010) or a
    /// fast burn (spec 017 FR-012).
    public var callsForAttention: Bool {
        pace.usesAttentionColor(burn: burn)
    }
}

extension UsageSnapshot {
    /// The pace and burn rate of the window or budget `key` at the snapshot
    /// time, with the recent rate from `observations` (spec 025 FR-030,
    /// spec 017 FR-001 to FR-007). Nil when the key is unknown or has no
    /// pace (spec 011 FR-007).
    public func paceReading(for key: BurnWindowKey) -> PaceReading? {
        guard let inputs = burnInputs(for: key) else { return nil }
        let values = inputs.values
        let burn = BurnRate.compute(pace: inputs.pace, usedPercent: values.usedPercent, windowStart: values.windowStart,
                                    resetsAt: values.resetsAt, observedAt: values.observedAt, now: generatedAt,
                                    recent: observations.recentRate(for: key, now: generatedAt))
        return PaceReading(pace: inputs.pace, burn: burn)
    }

    /// Every window and budget key of this snapshot that may have a pace:
    /// the Claude 5-hour, 7-day and model limits, every effective Codex
    /// window by name, every group and own budget (spec 017 Key Entities,
    /// spec 025 research R11).
    public var paceKeys: [BurnWindowKey] {
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
}
