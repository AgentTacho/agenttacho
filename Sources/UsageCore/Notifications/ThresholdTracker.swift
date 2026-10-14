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
    /// Account `displayName` or group `name`.
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
/// State is keyed by `(entityId, windowKind)`; the first observation of a key
/// (or the first after its window end changed) only records a baseline.
/// Groups use their period's window kind (spec 003 FR-015 to FR-017).
public struct ThresholdTracker: Sendable {
    private struct Key: Hashable {
        let entityId: String
        let windowKind: WindowKind
    }

    private struct State {
        /// Known only for groups; subscriptions report a reset time only.
        var windowStart: Date?
        var windowEnd: Date
        var lastPercent: Int?
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
                liveKeys.insert(Key(entityId: account.id, windowKind: kind))
            }
            guard let entry = snapshot.subscriptions[account.id], entry.state.isOk, let status = entry.status else { continue }
            for kind in kinds {
                let window = kind == .fiveHour ? status.fiveHour : status.sevenDay
                guard let window, let windowEnd = window.resetsAt else { continue }
                crossings += evaluate(key: Key(entityId: account.id, windowKind: kind), entityName: account.displayName,
                                      windowEnd: windowEnd, percent: PercentFormatter.rounded(window.utilizationPercent),
                                      thresholds: thresholds)
            }
        }

        // Keyed by the group's period: a period switch drops the old key and
        // starts the new one with a baseline (spec 003 FR-017). A month
        // rollover or a time zone change moving the month changes `resetAt`,
        // which resets the state as for a weekly window (FR-015, FR-016); a
        // moved window start alone also counts as a reset. A snapshot computed
        // for the other period (a refresh that ran while the period was
        // switched) is skipped, so the new key's baseline comes from a
        // snapshot of the new period (FR-017).
        for group in configuration.groups {
            let key = Key(entityId: group.id, windowKind: group.period.windowKind)
            liveKeys.insert(key)
            guard let entry = snapshot.groups[group.id], !entry.stale, entry.period == group.period else { continue }
            crossings += evaluate(key: key, entityName: group.name, windowStart: entry.window.start, windowEnd: entry.resetAt,
                                  percent: entry.percent, thresholds: Self.normalized(group.thresholds))
        }

        // Entities no longer configured lose their state.
        states = states.filter { liveKeys.contains($0.key) }
        return crossings
    }

    private mutating func evaluate(key: Key, entityName: String, windowStart: Date? = nil, windowEnd: Date, percent: Int,
                                   thresholds: [Int]) -> [ThresholdCrossing] {
        var state = states[key] ?? State(windowStart: windowStart, windowEnd: windowEnd, lastPercent: nil)
        if state.windowEnd != windowEnd || state.windowStart != windowStart {
            state = State(windowStart: windowStart, windowEnd: windowEnd, lastPercent: nil)   // window reset (FR-029)
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
