import Foundation

/// The window a threshold state belongs to. `rawValue` identifies it in the
/// tracker's keys and in notification identifiers; `displayName` names it in
/// notification text. A struct rather than an enum, so Codex plan windows,
/// whose lengths come from the data, get their own kinds (spec 007 research
/// R8).
public struct WindowKind: Hashable, Sendable {
    public let rawValue: String
    public let displayName: String

    public init(rawValue: String, displayName: String) {
        self.rawValue = rawValue
        self.displayName = displayName
    }

    public static let fiveHour = WindowKind(rawValue: "fiveHour", displayName: "5-hour")
    public static let sevenDay = WindowKind(rawValue: "sevenDay", displayName: "7-day")
    public static let weekly = WindowKind(rawValue: "weekly", displayName: "weekly")
    /// Window of a monthly budget group (spec 003 FR-015).
    public static let monthly = WindowKind(rawValue: "monthly", displayName: "monthly")

    /// A Codex plan window, named by its length (spec 007 FR-009, FR-015).
    /// The live-limits setting is part of the identity, so toggling it
    /// starts a new baseline.
    public static func codex(_ window: CodexLimitWindow, live: Bool) -> WindowKind {
        WindowKind(rawValue: codexPrefix(live: live) + window.name, displayName: window.name)
    }

    /// The raw value prefix of every Codex plan window under one live-limits
    /// setting.
    static func codexPrefix(live: Bool) -> String {
        "codex-\(live ? "live" : "local")-"
    }

    /// Identity is the raw value alone.
    public static func == (lhs: WindowKind, rhs: WindowKind) -> Bool { lhs.rawValue == rhs.rawValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
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
/// Codex subscription accounts use one kind per plan window (spec 007
/// FR-015).
public struct ThresholdTracker: Sendable {
    /// Keeps a group and an own-budget account apart even if a hand-edited
    /// file gives them the same id (spec 004 research R4).
    private enum Scope: Hashable {
        case subscription
        case group
        case account
        /// Windows of a Codex plan (spec 007 FR-015).
        case codexPlan
    }

    /// Live and snapshot reset times of the same Codex window differ by a
    /// few seconds; within this tolerance the window has not reset
    /// (spec 007 research R8).
    static let codexResetTolerance: TimeInterval = 120

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
            // Saved Claude values in the early result neither notify nor set
            // the baseline; the first refresh does (spec 010 FR-019). Saved
            // Codex values count like any observation (spec 007 FR-015).
            guard !snapshot.isPreliminary, let entry = snapshot.subscriptions[account.id], entry.state.isOk,
                  let status = entry.status else { continue }
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

        // Codex plan windows (spec 007 FR-014, FR-015): every window of the
        // shown observation on its own, whatever its source, keyed by its
        // name and the live-limits setting, so a toggle starts a new
        // baseline. A window that disappears (plan change) loses its state;
        // a missing or unavailable entry, or one computed under the other
        // live-limits setting (a refresh that started before the toggle),
        // keeps the state of the current setting for later. State of the
        // other setting is dropped, so turning the setting back on starts a
        // new baseline even while no values are shown (FR-015).
        for account in configuration.codexSubscriptionAccounts {
            guard let settings = account.kind.codexSubscription else { continue }
            guard let entry = snapshot.codexLimits[account.id], let observation = entry.observation,
                  entry.state.impliedLiveLimits == settings.liveLimits else {
                let prefix = WindowKind.codexPrefix(live: settings.liveLimits)
                liveKeys.formUnion(states.keys.filter {
                    $0.scope == .codexPlan && $0.entityId == account.id && $0.windowKind.rawValue.hasPrefix(prefix)
                })
                continue
            }
            let thresholds = Self.normalized(settings.thresholds)
            for window in entry.windows(now: snapshot.generatedAt) {
                let key = Key(scope: .codexPlan, entityId: account.id, windowKind: .codex(window, live: settings.liveLimits))
                liveKeys.insert(key)
                // A window whose reset passed (FR-010) has no reset time and
                // is skipped until a newer observation. A window the source
                // gave no reset time at all is still checked (FR-014): its
                // state never resets on its own.
                let reported = observation.windows.first { $0.name == window.name }
                let windowEnd: Date
                if let resetsAt = window.resetsAt {
                    windowEnd = resetsAt
                } else if reported?.resetsAt == nil {
                    windowEnd = .distantFuture
                } else {
                    continue
                }
                crossings += evaluate(key: key, entityName: account.displayName, windowEnd: windowEnd,
                                      percent: PercentFormatter.rounded(window.usedPercent), thresholds: thresholds,
                                      windowEndTolerance: Self.codexResetTolerance)
            }
        }

        // Entities no longer configured lose their state.
        states = states.filter { liveKeys.contains($0.key) }
        return crossings
    }

    /// `windowEndTolerance` is the largest change of `windowEnd` that is not
    /// a reset; the stored end is kept then.
    private mutating func evaluate(key: Key, entityName: String, windowStart: Date? = nil, windowEnd: Date, percent: Int,
                                   thresholds: [Int], memberIds: [String]? = nil,
                                   windowEndTolerance: TimeInterval = 0) -> [ThresholdCrossing] {
        let fresh = State(windowStart: windowStart, windowEnd: windowEnd, lastPercent: nil, memberIds: memberIds)
        var state = states[key] ?? fresh
        if abs(state.windowEnd.timeIntervalSince(windowEnd)) > windowEndTolerance || state.windowStart != windowStart {
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
