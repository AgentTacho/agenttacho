import Foundation

/// A Claude subscription window that has a pace (spec 017 Key Entities).
public enum ClaudeWindow: Hashable, Sendable {
    case fiveHour
    case sevenDay
    /// A model-scoped weekly limit, by model name.
    case model(String)
}

/// Identifies one window or budget across refreshes (spec 017 Key Entities,
/// research R2): the account and Claude window, the account and Codex window
/// name, or the budget owner: a group by group id, an account with its own
/// budget by account id. A group and an account may share an id (spec 008),
/// so the two budget owners are separate cases.
public enum BurnWindowKey: Hashable, Sendable {
    case claude(String, ClaudeWindow)
    case codex(String, String)
    case group(String)
    case accountBudget(String)
}

/// One observed value of one window or budget (spec 017 FR-003): the
/// observation time, the unrounded used percent and the reset time.
struct RateObservation: Equatable, Sendable {
    var observedAt: Date
    var usedPercent: Double
    var resetsAt: Date

    init(observedAt: Date, usedPercent: Double, resetsAt: Date) {
        self.observedAt = observedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// The recent rate of one window (spec 017 FR-004): percentage points per
/// hour between the oldest and the newest observation within the lookback,
/// with the newest observation's time and used percent.
struct RecentRate: Equatable, Sendable {
    var perHour: Double
    var observedAt: Date
    var usedPercent: Double

    init(perHour: Double, observedAt: Date, usedPercent: Double) {
        self.perHour = perHour
        self.observedAt = observedAt
        self.usedPercent = usedPercent
    }
}

/// The observations of every window and budget with a pace, kept in memory
/// only and never written (spec 017 FR-003, FR-013, research R1).
struct ObservationLog: Equatable, Sendable {
    /// Observations per window, oldest first, none older than the lookback
    /// before the last snapshot.
    private(set) var entries: [BurnWindowKey: [RateObservation]] = [:]
    /// What a budget's percent depends on besides its spend, per budget
    /// key; a change discards its observations (spec 017 FR-003).
    private var budgetFingerprints: [BurnWindowKey: BudgetFingerprint] = [:]

    /// Reset times less than this many seconds apart count as the same
    /// reset: Codex reports raw epochs that differ by seconds between a live
    /// result and a session log (spec 017 research R4).
    static let resetTolerance: TimeInterval = 60
    /// Kept observations more than this many seconds after the snapshot time
    /// are dropped: the clock moved backwards, and otherwise they would
    /// block every new observation and freeze the recent rate until it caught
    /// up. A fetch inside the refresh is seconds after the snapshot time, so
    /// it stays well within the tolerance. After a smaller step back, kept
    /// observations inside the tolerance still count for at most that long.
    static let futureTolerance: TimeInterval = 600

    init() {}

    /// The log after `snapshot` (spec 017 FR-003, research R3, R4): every
    /// window and budget with a pace records its observation when it is
    /// later than the newest kept one; a moved reset, a lower used percent, a
    /// changed budget amount, period or member list, or changed prices for
    /// budgets (`budgetPricesChanged`) discard the earlier observations; a
    /// stale budget adds nothing; a key without a pace is removed; and
    /// observations older than the lookback before the snapshot time, or
    /// after it beyond `futureTolerance`, are dropped.
    func updated(with snapshot: UsageSnapshot, budgetPricesChanged: Bool) -> ObservationLog {
        let now = snapshot.generatedAt
        let oldest = now.addingTimeInterval(-BurnRate.lookback)
        let latest = now.addingTimeInterval(Self.futureTolerance)
        var next = ObservationLog()
        for key in snapshot.paceKeys {
            guard let inputs = snapshot.burnInputs(for: key) else { continue }
            var kept = (entries[key] ?? []).filter { $0.observedAt <= latest }
            var adds = true
            if let entry = snapshot.budgetEntry(for: key) {
                let fingerprint = BudgetFingerprint(entry)
                if budgetPricesChanged || budgetFingerprints[key] != fingerprint { kept = [] }
                next.budgetFingerprints[key] = fingerprint
                // Carried-over values with a fresh snapshot time (research R3).
                if entry.stale { adds = false }
            }
            let observation = RateObservation(observedAt: inputs.values.observedAt, usedPercent: inputs.values.usedPercent,
                                              resetsAt: inputs.values.resetsAt)
            if !adds, let newest = kept.last {
                // A stale budget adds nothing, but a moved window still
                // discards the earlier observations (spec 017 FR-003).
                if abs(observation.resetsAt.timeIntervalSince(newest.resetsAt)) >= Self.resetTolerance { kept = [] }
            } else if let newest = kept.last {
                if observation.observedAt <= newest.observedAt {
                    adds = false
                } else if abs(observation.resetsAt.timeIntervalSince(newest.resetsAt)) >= Self.resetTolerance
                            || kept.contains(where: { observation.usedPercent < $0.usedPercent }) {
                    kept = []
                }
            }
            if adds { kept.append(observation) }
            kept.removeAll { $0.observedAt < oldest }
            if !kept.isEmpty { next.entries[key] = kept }
        }
        return next
    }

    /// The recent rate of `key` at the snapshot time `now` (spec 017 FR-004,
    /// research R6): the change between the oldest and the newest
    /// observation within the lookback over the time between them; nil when
    /// they are less than the minimum span apart or the change is below the
    /// minimum.
    func recentRate(for key: BurnWindowKey, now: Date) -> RecentRate? {
        let oldest = now.addingTimeInterval(-BurnRate.lookback)
        guard let list = entries[key]?.filter({ $0.observedAt >= oldest }),
              let first = list.first, let last = list.last else { return nil }
        let span = last.observedAt.timeIntervalSince(first.observedAt)
        let change = last.usedPercent - first.usedPercent
        guard span >= BurnRate.minimumSpan, change >= BurnRate.minimumChange else { return nil }
        return RecentRate(perHour: change / (span / BurnRate.secondsPerHour), observedAt: last.observedAt, usedPercent: last.usedPercent)
    }
}

/// A budget's amount, period and sorted members (spec 017 FR-003).
private struct BudgetFingerprint: Equatable, Sendable {
    let budgetUSD: Decimal
    let period: BudgetPeriod
    let members: [String]

    init(_ entry: GroupEntry) {
        budgetUSD = entry.budgetUSD
        period = entry.period
        members = entry.members.sorted()
    }
}
