import Foundation

public enum WindowKind: String, Sendable, CaseIterable {
    case fiveHour
    case sevenDay
    case weekly
    /// Window of a monthly budget group (spec 003 FR-015).
    case monthly

    public var displayName: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .sevenDay: return "7-day"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        }
    }
}

public struct ThresholdCrossing: Equatable, Sendable {
    public let entityId: String
    /// Account `displayName` or group `name`, never an icon name, so
    /// entries sharing an icon stay distinguishable (spec 004 FR-004).
    public let entityName: String
    public let windowKind: WindowKind
    public let threshold: Int
    public let percent: Int

    public init(entityId: String, entityName: String, windowKind: WindowKind, threshold: Int, percent: Int) {
        self.entityId = entityId
        self.entityName = entityName
        self.windowKind = windowKind
        self.threshold = threshold
        self.percent = percent
    }
}

/// Pure crossing detection (FR-028, FR-029, data-model.md ThresholdState).
/// State is keyed by `(scope, entityId, windowKind)`; the first observation of a key
/// (or the first after its window end changed) only records a baseline.
/// Groups and accounts with their own budget (budget owners) use their
/// period's window kind (spec 003 FR-015 to FR-017, spec 004 FR-012).
public struct ThresholdTracker: Sendable {
    /// Keeps a group and an own-budget account apart even if a hand-edited
    /// file gives them the same id (spec 004 research R4).
    private enum Scope: Hashable {
        case subscription
        case group
        case account
    }

    private struct Key: Hashable {
        let scope: Scope
        let entityId: String
        let windowKind: WindowKind
    }

    private struct State {
        /// Known only for groups; subscriptions report a reset time only.
        var windowStart: Date?
        var windowEnd: Date
        var lastPercent: Int?
        /// Budget owners only: the member accounts the state was recorded
        /// for. A different member set resets the state (spec 004 FR-015).
        var memberIds: [String]?
    }

    private var states: [Key: State] = [:]

    public init() {}

    /// Sorted ids with at least one tracked window.
    public var trackedEntityIds: [String] {
        Array(Set(states.keys.map(\.entityId))).sorted()
    }

    public mutating func observe(snapshot: UsageSnapshot, configuration: Configuration) -> [ThresholdCrossing] {
        var crossings: [ThresholdCrossing] = []
        var liveKeys = Set<Key>()

        for account in configuration.accounts {
            guard let settings = account.kind.subscription else { continue }
            let thresholds = Self.normalized(settings.thresholds)
            let kinds: [WindowKind] = [.fiveHour, .sevenDay]
            for kind in kinds {
                liveKeys.insert(Key(scope: .subscription, entityId: account.id, windowKind: kind))
            }
            guard let entry = snapshot.subscriptions[account.id], entry.state.isOk, let status = entry.status else { continue }
            for kind in kinds {
                let window = kind == .fiveHour ? status.fiveHour : status.sevenDay
                guard let window, let windowEnd = window.resetsAt else { continue }
                crossings += evaluate(key: Key(scope: .subscription, entityId: account.id, windowKind: kind), entityName: account.displayName,
                                      windowEnd: windowEnd, percent: PercentFormatter.rounded(window.utilizationPercent),
                                      thresholds: thresholds)
            }
        }

        // Budget owners (groups, then accounts with their own budget), keyed
        // by the owner's period: a period switch drops the old key and
        // starts the new one with a baseline (spec 003 FR-017). A month
        // rollover or a time zone change moving the month changes `resetAt`,
        // which resets the state as for a weekly window (FR-015, FR-016); a
        // moved window start alone also counts as a reset. A snapshot computed
        // for the other period (a refresh that ran while the period was
        // switched) is skipped, so the new key's baseline comes from a
        // snapshot of the new period (FR-017). An account moving between its
        // own budget and a group drops its own key and changes the group's
        // member set, which re-baselines the group (spec 004 FR-015). As with
        // a period switch, a snapshot computed for the old member set (a
        // refresh that ran while the account moved) is skipped, so the new
        // baseline already includes the moved account's spend.
        for owner in configuration.budgetOwners {
            let budget = owner.budget
            let key = Key(scope: owner.kind == .group ? .group : .account, entityId: owner.id, windowKind: budget.period.windowKind)
            liveKeys.insert(key)
            let entries = owner.kind == .group ? snapshot.groups : snapshot.accountBudgets
            guard let entry = entries[owner.id], !entry.stale, entry.period == budget.period,
                  entry.members == owner.memberIds else { continue }
            crossings += evaluate(key: key, entityName: owner.name, windowStart: entry.window.start, windowEnd: entry.resetAt,
                                  percent: entry.percent, thresholds: Self.normalized(budget.thresholds), memberIds: owner.memberIds)
        }

        // Entities no longer configured lose their state.
        states = states.filter { liveKeys.contains($0.key) }
        return crossings
    }

    private mutating func evaluate(key: Key, entityName: String, windowStart: Date? = nil, windowEnd: Date, percent: Int,
                                   thresholds: [Int], memberIds: [String]? = nil) -> [ThresholdCrossing] {
        let fresh = State(windowStart: windowStart, windowEnd: windowEnd, lastPercent: nil, memberIds: memberIds)
        var state = states[key] ?? fresh
        if state.windowEnd != windowEnd || state.windowStart != windowStart {
            state = fresh   // window reset (FR-029)
        } else if state.memberIds != memberIds {
            state = fresh   // member set changed (spec 004 FR-015)
        }
        var result: [ThresholdCrossing] = []
        if let last = state.lastPercent {
            for threshold in thresholds where last < threshold && percent >= threshold {
                result.append(ThresholdCrossing(entityId: key.entityId, entityName: entityName, windowKind: key.windowKind,
                                                threshold: threshold, percent: percent))
            }
        }
        state.lastPercent = percent
        states[key] = state
        return result
    }

    /// Whole-number percents greater than 0, deduplicated, ascending.
    static func normalized(_ thresholds: [Int]) -> [Int] {
        Array(Set(thresholds.filter { $0 > 0 })).sorted()
    }
}
