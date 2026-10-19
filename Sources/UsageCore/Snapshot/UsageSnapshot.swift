import Foundation

// MARK: - Subscription fetch result

public struct LimitWindow: Equatable, Sendable {
    public var utilizationPercent: Double
    /// Nil while the window has not started (no usage yet, reported as 0 %).
    public var resetsAt: Date?

    public init(utilizationPercent: Double, resetsAt: Date?) {
        self.utilizationPercent = utilizationPercent
        self.resetsAt = resetsAt
    }
}

/// A weekly limit that applies to one model only (for example Fable), on top
/// of the account-wide 7-day limit. Reported by the usage endpoint as a
/// `weekly_scoped` entry in `limits`.
public struct ModelLimit: Equatable, Sendable {
    /// Model name as the provider displays it, for example "Fable".
    public var modelName: String
    public var utilizationPercent: Double
    /// Nil once the reset time has passed (spec 010 FR-016).
    public var resetsAt: Date?
    /// Share of the account-wide weekly limit this model may use, when reported.
    public var allowancePercentOfWeekly: Int?

    public init(modelName: String, utilizationPercent: Double, resetsAt: Date?, allowancePercentOfWeekly: Int? = nil) {
        self.modelName = modelName
        self.utilizationPercent = utilizationPercent
        self.resetsAt = resetsAt
        self.allowancePercentOfWeekly = allowancePercentOfWeekly
    }
}

public struct SubscriptionStatus: Equatable, Sendable {
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    /// Model-scoped weekly limits; empty when the account has none.
    public var modelLimits: [ModelLimit]
    public var subscriptionType: String?
    public var fetchedAt: Date

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?, modelLimits: [ModelLimit] = [],
                subscriptionType: String? = nil, fetchedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.modelLimits = modelLimits
        self.subscriptionType = subscriptionType
        self.fetchedAt = fetchedAt
    }

    /// The 7-day window, or nil when it is unavailable (FR-005). It is the
    /// default headline window and decides the at-or-above-100% style
    /// whichever window is the headline; another window is shown in the bar
    /// only when the user chose it, never as a stand-in (spec 027 FR-007).
    public var barPercent: Int? {
        sevenDay.map { PercentFormatter.rounded($0.utilizationPercent) }
    }

    /// The status as shown at `now`: every window (5-hour, 7-day, model
    /// limits) whose reset time is at or before `now` shows 0% without a
    /// reset time; the others are unchanged (spec 010 FR-016, research R7).
    public func effective(now: Date) -> SubscriptionStatus {
        func reset(_ window: LimitWindow?) -> LimitWindow? {
            guard let window, let resetsAt = window.resetsAt, resetsAt <= now else { return window }
            return LimitWindow(utilizationPercent: 0, resetsAt: nil)
        }
        var copy = self
        copy.fiveHour = reset(fiveHour)
        copy.sevenDay = reset(sevenDay)
        copy.modelLimits = modelLimits.map { limit in
            guard let resetsAt = limit.resetsAt, resetsAt <= now else { return limit }
            var zeroed = limit
            zeroed.utilizationPercent = 0
            zeroed.resetsAt = nil
            return zeroed
        }
        return copy
    }
}

public enum SubscriptionState: Equatable, Sendable {
    case ok
    /// `lastGoodAt` is nil when no fetch has succeeded yet in this run.
    case stale(lastGoodAt: Date?, error: String)
    case notSignedIn
    case credentialsExpired
    /// A transport failure inside a grace period: the values of the last
    /// successful request stay unmarked until the quick retry at `retryAt`
    /// (spec 010 FR-005). `error` is the failure's text.
    case retrying(lastGoodAt: Date?, error: String, retryAt: Date)
    /// The usage service rejected the sign-in with HTTP 401 or 403 (spec 010
    /// FR-010); `lastGoodAt` is nil without last good values.
    case signInRejected(lastGoodAt: Date?)

    public var isOk: Bool {
        if case .ok = self { return true }
        return false
    }

    /// True for the states whose values are marked stale when shown:
    /// `.stale`, `.signInRejected` and `.credentialsExpired` (spec 010
    /// FR-010, FR-015). `.retrying` is not stale (FR-005).
    public var isStale: Bool {
        switch self {
        case .stale, .signInRejected, .credentialsExpired: return true
        case .ok, .notSignedIn, .retrying: return false
        }
    }
}

// MARK: - Breakdown

public struct ModelUsage: Equatable, Sendable, Identifiable {
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int
    /// nil when the model is unpriced or cost is not applicable (subscription accounts).
    public var costUSD: Decimal?
    public var priced: Bool
    /// Reasoning tokens, already included in `outputTokens` (spec 006 FR-008).
    public var reasoningTokens: Int

    public var id: String { model }
    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }

    public init(model: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheWrite5mTokens: Int = 0, cacheWrite1hTokens: Int = 0, cacheReadTokens: Int = 0, costUSD: Decimal? = nil, priced: Bool = true,
                reasoningTokens: Int = 0) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.priced = priced
        self.reasoningTokens = reasoningTokens
    }
}

public struct DayUsage: Equatable, Sendable, Identifiable {
    /// Start of the local calendar day.
    public var day: Date
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheWriteTokens: Int
    public var cacheReadTokens: Int
    /// nil for token-only breakdowns (subscription accounts, Unassigned).
    public var costUSD: Decimal?

    public var id: Date { day }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }

    public init(day: Date, inputTokens: Int = 0, outputTokens: Int = 0, cacheWriteTokens: Int = 0, cacheReadTokens: Int = 0, costUSD: Decimal? = nil) {
        self.day = day
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
    }
}

/// Usage of one project (git repository) within a breakdown.
public struct ProjectUsage: Equatable, Sendable, Identifiable {
    /// nil = Unknown (log lines without a working directory).
    public var project: Project?
    /// The project name, `name (parent)` when another root in the same
    /// breakdown has the same name, or "Unknown".
    public var displayName: String
    public var totalTokens: Int
    /// nil when any record is unpriced, or cost is not applicable (token-only breakdowns).
    public var costUSD: Decimal?
    /// Sum of the priced records only; ranks and shares priced breakdowns.
    public var pricedCostUSD: Decimal
    public var priced: Bool

    public var id: String { project?.rootPath ?? "" }

    public init(project: Project?, displayName: String, totalTokens: Int = 0, costUSD: Decimal? = nil,
                pricedCostUSD: Decimal = 0, priced: Bool = true) {
        self.project = project
        self.displayName = displayName
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.pricedCostUSD = pricedCostUSD
        self.priced = priced
    }
}

/// Usage of one harness within a breakdown (spec 006 FR-021).
public struct HarnessUsage: Equatable, Sendable, Identifiable {
    public var harness: Harness
    public var totalTokens: Int
    /// nil when any record is unpriced, or cost is not applicable (token-only breakdowns).
    public var costUSD: Decimal?
    public var priced: Bool

    public var id: Harness { harness }

    public init(harness: Harness, totalTokens: Int = 0, costUSD: Decimal? = nil, priced: Bool = true) {
        self.harness = harness
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.priced = priced
    }
}

/// The Projects view of a breakdown: the top rows and the rest combined.
public struct ProjectRanking: Equatable, Sendable {
    public var top: [ProjectRanked]
    /// nil when no project is beyond the top rows.
    public var other: OtherProjects?
}

public struct ProjectRanked: Equatable, Sendable, Identifiable {
    public var usage: ProjectUsage
    /// Whole percent of the breakdown total; nil when the total is 0.
    public var sharePercent: Int?
    public var id: String { usage.id }
}

public struct OtherProjects: Equatable, Sendable {
    public var count: Int
    public var totalTokens: Int
    /// nil when any of the projects is unpriced, or cost is not applicable.
    public var costUSD: Decimal?
    public var sharePercent: Int?
}

public struct UsageBreakdown: Equatable, Sendable {
    public var perModel: [ModelUsage]
    public var perDay: [DayUsage]
    /// All projects, ranked (cost in priced breakdowns, tokens otherwise).
    public var perProject: [ProjectUsage]
    public var unpricedModels: [String]
    /// Per-harness split, sorted by cost, then tokens (spec 006 FR-021).
    public var perHarness: [HarnessUsage]

    public init(perModel: [ModelUsage] = [], perDay: [DayUsage] = [], perProject: [ProjectUsage] = [],
                unpricedModels: [String] = [], perHarness: [HarnessUsage] = []) {
        self.perModel = perModel
        self.perDay = perDay
        self.perProject = perProject
        self.unpricedModels = unpricedModels
        self.perHarness = perHarness
    }

    public static let empty = UsageBreakdown()

    public var totalTokens: Int { perModel.reduce(0) { $0 + $1.totalTokens } }
    public var inputTokens: Int { perModel.reduce(0) { $0 + $1.inputTokens } }
    public var outputTokens: Int { perModel.reduce(0) { $0 + $1.outputTokens } }
    public var cacheWriteTokens: Int { perModel.reduce(0) { $0 + $1.cacheWriteTokens } }
    public var cacheReadTokens: Int { perModel.reduce(0) { $0 + $1.cacheReadTokens } }
    public var pricedCostUSD: Decimal { perModel.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) } }
    public var isEmpty: Bool { perModel.isEmpty }

    /// The first `limit` projects plus the rest as one Other entry. Shares
    /// use cost when `byCost` (priced breakdowns), tokens otherwise.
    public func topProjects(limit: Int = 5, byCost: Bool) -> ProjectRanking {
        let top = Array(perProject.prefix(limit))
        let rest = Array(perProject.dropFirst(limit))
        let value: (ProjectUsage) -> Decimal = { byCost ? $0.pricedCostUSD : Decimal($0.totalTokens) }
        var values = top.map(value)
        if !rest.isEmpty { values.append(rest.map(value).reduce(0, +)) }
        let shares = Self.shares(values)

        let ranked = top.enumerated().map { i, usage in ProjectRanked(usage: usage, sharePercent: shares?[i]) }
        guard !rest.isEmpty else { return ProjectRanking(top: ranked, other: nil) }
        let restCost: Decimal? = byCost && rest.allSatisfy(\.priced) ? rest.reduce(0) { $0 + $1.pricedCostUSD } : nil
        let other = OtherProjects(count: rest.count, totalTokens: rest.reduce(0) { $0 + $1.totalTokens },
                                  costUSD: restCost, sharePercent: shares?.last)
        return ProjectRanking(top: ranked, other: other)
    }

    /// Whole percents that add up to exactly 100 (largest remainder); nil
    /// when the total is 0.
    static func shares(_ values: [Decimal]) -> [Int]? {
        let total = values.reduce(0, +)
        guard total > 0 else { return nil }
        let exact = values.map { NSDecimalNumber(decimal: $0 * 100 / total).doubleValue }
        var result = exact.map { Int($0.rounded(.down)) }
        let order = exact.indices.sorted { a, b in
            let ra = exact[a] - Double(result[a]), rb = exact[b] - Double(result[b])
            return ra != rb ? ra > rb : a < b
        }
        for i in order.prefix(max(0, 100 - result.reduce(0, +))) { result[i] += 1 }
        return result
    }
}

// MARK: - Entries

/// A per-refresh fact carried on an entry that never takes part in
/// equality, so entries still compare by what they show (spec 016
/// research R5).
public struct TransientFlag: Equatable, Sendable {
    public var value: Bool

    public init(_ value: Bool = false) {
        self.value = value
    }

    public static func == (lhs: TransientFlag, rhs: TransientFlag) -> Bool { true }
}

public struct SubscriptionEntry: Equatable, Sendable {
    public var status: SubscriptionStatus?
    public var state: SubscriptionState
    public var breakdown: UsageBreakdown
    /// Outcome of this refresh's endpoint request; nil when no request was
    /// made (not signed in, credentials expired or unreadable).
    public var fetchOutcome: FetchOutcome?
    /// Time of the account's pending quick retry, also when the shown values
    /// are stale or absent; the coordinator schedules its timer from it
    /// (spec 010 FR-004, plan Design Note 2).
    public var quickRetryAt: Date?
    /// The expiry time recorded in the credential, set only with
    /// `.credentialsExpired`; the credential notification delay counts from
    /// it (spec 014 FR-005).
    public var credentialExpiresAt: Date?

    /// True when this refresh sent a request for the account and got an
    /// answer that is not a transport failure (spec 016 FR-005, FR-013,
    /// research R5). Transient: never saved, false on a reused entry, and
    /// not part of equality.
    public var reachedService: Bool {
        get { reachedServiceFlag.value }
        set { reachedServiceFlag.value = newValue }
    }
    private var reachedServiceFlag = TransientFlag()

    public init(status: SubscriptionStatus?, state: SubscriptionState, breakdown: UsageBreakdown = .empty,
                fetchOutcome: FetchOutcome? = nil, quickRetryAt: Date? = nil, credentialExpiresAt: Date? = nil,
                reachedService: Bool = false) {
        self.status = status
        self.state = state
        self.breakdown = breakdown
        self.fetchOutcome = fetchOutcome
        self.quickRetryAt = quickRetryAt
        self.credentialExpiresAt = credentialExpiresAt
        self.reachedServiceFlag = TransientFlag(reachedService)
    }

    /// The entry once its grace period has ended without a request: a
    /// `.retrying` entry whose retry time is at or before `now` becomes
    /// `.stale` with the same error and last good time, and its quick retry
    /// time is cleared so a reused entry never sets the timer again; every
    /// other entry is returned unchanged (spec 010 FR-007, research R3).
    public func endingGrace(now: Date) -> SubscriptionEntry {
        guard case .retrying(let lastGoodAt, let error, let retryAt) = state, retryAt <= now else { return self }
        var copy = self
        copy.state = .stale(lastGoodAt: lastGoodAt, error: error)
        copy.quickRetryAt = nil
        return copy
    }

    /// The entry as a refresh without a request reuses it (a reprice, or a
    /// manual, wake or settings refresh held back by the spacing or a
    /// rate-limit wait). Its quick retry has not been attempted yet (a
    /// suppressed one is ended in the stored result), so the entry stays as
    /// it is, `.retrying` included, while the retry's due window
    /// (`retryAt + RetryEpisodes.delay`) is open; the timer fires 1 s after
    /// `retryAt`, inside that window. Once the window passed without the
    /// retry, the grace period ends stale and the retry time is cleared, so
    /// the timer is not set again (spec 010 FR-005, FR-007, FR-008). A
    /// reused entry made no request, so it never reached the service
    /// (spec 016 research R5).
    public func reused(now: Date) -> SubscriptionEntry {
        var unsent = self
        unsent.reachedService = false
        let retryAt: Date?
        if case .retrying(_, _, let at) = state { retryAt = at } else { retryAt = quickRetryAt }
        guard let retryAt, retryAt.addingTimeInterval(RetryEpisodes.delay) <= now else { return unsent }
        var copy = unsent.endingGrace(now: now)
        copy.quickRetryAt = nil
        return copy
    }
}

/// One budget's values: a budget group, or a token-based account with its
/// own budget (spec 004 FR-010, research R4).
public struct GroupEntry: Equatable, Sendable {
    public var spentUSD: Decimal
    public var budgetUSD: Decimal
    /// Rounded, uncapped (FR-009a).
    public var percent: Int
    public var incomplete: Bool
    /// The group's period, copied from the configuration (spec 003 FR-014).
    public var period: BudgetPeriod
    /// The group's own window: the weekly window or the local calendar
    /// month (spec 003 FR-005, FR-008).
    public var window: DateInterval
    /// End of `window`.
    public var resetAt: Date { window.end }
    public var breakdown: UsageBreakdown
    public var members: [String]
    /// Each member's spend in `window`, from the same records as `spentUSD`
    /// (spec 004 FR-017, FR-018a).
    public var memberSpendUSD: [String: Decimal]
    public var stale: Bool

    public init(spentUSD: Decimal, budgetUSD: Decimal, percent: Int, incomplete: Bool, period: BudgetPeriod = .weekly, window: DateInterval,
                breakdown: UsageBreakdown, members: [String], memberSpendUSD: [String: Decimal] = [:], stale: Bool = false) {
        self.spentUSD = spentUSD
        self.budgetUSD = budgetUSD
        self.percent = percent
        self.incomplete = incomplete
        self.period = period
        self.window = window
        self.breakdown = breakdown
        self.members = members
        self.memberSpendUSD = memberSpendUSD
        self.stale = stale
    }

    /// A member's spend as a percent of the whole budget: rounded, uncapped
    /// (spec 004 FR-017, FR-018a, spec 001 FR-009a). Nil when this entry was
    /// not computed for the account, for example a snapshot from before the
    /// account joined the group, so callers show a placeholder, not 0%.
    public func memberPercent(_ accountId: String) -> Int? {
        guard let spent = memberSpendUSD[accountId] else { return nil }
        return PercentFormatter.rounded(spent: spent, budget: budgetUSD)
    }
}

public struct TokenAccountEntry: Equatable, Sendable {
    public var breakdown: UsageBreakdown
    public var incomplete: Bool
    public var stale: Bool

    public init(breakdown: UsageBreakdown = .empty, incomplete: Bool = false, stale: Bool = false) {
        self.breakdown = breakdown
        self.incomplete = incomplete
        self.stale = stale
    }

    public static let empty = TokenAccountEntry()
}

/// Output of a record source that reports per-location problems without
/// failing as a whole (spec 006 FR-005, FR-006, research R7).
public struct RecordBatch: Sendable {
    /// All records with timestamp >= window.start.
    public var records: [UsageRecord]
    /// One message per failed or skipped location; each becomes a `SourceError`.
    public var issues: [String]
    /// Harnesses whose records are carried over from an earlier read; the
    /// entries containing their records are marked stale.
    public var staleHarnesses: Set<Harness>

    public init(records: [UsageRecord] = [], issues: [String] = [], staleHarnesses: Set<Harness> = []) {
        self.records = records
        self.issues = issues
        self.staleHarnesses = staleHarnesses
    }
}

public struct SourceError: Equatable, Sendable {
    public var sourceName: String
    public var message: String
    public var at: Date

    public init(sourceName: String, message: String, at: Date) {
        self.sourceName = sourceName
        self.message = message
        self.at = at
    }
}

public enum WindowSource: Equatable, Sendable {
    case aligned(accountId: String)
    case fallback
}

// MARK: - Snapshot

public struct UsageSnapshot: Equatable, Sendable {
    public var generatedAt: Date
    public var window: DateInterval
    public var windowSource: WindowSource
    public var subscriptions: [String: SubscriptionEntry]
    public var groups: [String: GroupEntry]
    /// Entries of token-based accounts with their own budget, keyed by
    /// account id (spec 004 FR-010).
    public var accountBudgets: [String: GroupEntry]
    public var tokenAccounts: [String: TokenAccountEntry]
    /// Token breakdowns of Codex subscription accounts, keyed by account id:
    /// weekly window, token counts only (spec 006 FR-017, spec 007 FR-013).
    public var codexPlanTokens: [String: TokenAccountEntry]
    /// Plan limits of Codex subscription accounts, keyed by account id
    /// (spec 007 FR-001).
    public var codexLimits: [String: CodexLimitsEntry]
    public var unassigned: TokenAccountEntry
    public var sourceErrors: [SourceError]
    public var configError: String?
    public var lastSuccessfulRefreshAt: Date?
    /// End of an active rate-limit block on the usage endpoint, if any.
    public var endpointBlockedUntil: Date?
    /// Time of the scheduled retry after a rate limit, if any.
    public var nextRetryAt: Date?
    /// True only for the early result built from saved values at launch,
    /// before the first refresh finishes (spec 010 FR-015, research R6).
    public var isPreliminary: Bool
    /// The observations kept in memory by the coordinator up to this
    /// snapshot, for the recent rate (spec 017 FR-003, research R1). Never
    /// encoded or written; the app reads only `burnRate(for:)`.
    var observations = ObservationLog()

    public init(generatedAt: Date,
                window: DateInterval,
                windowSource: WindowSource,
                subscriptions: [String: SubscriptionEntry] = [:],
                groups: [String: GroupEntry] = [:],
                accountBudgets: [String: GroupEntry] = [:],
                tokenAccounts: [String: TokenAccountEntry] = [:],
                codexPlanTokens: [String: TokenAccountEntry] = [:],
                codexLimits: [String: CodexLimitsEntry] = [:],
                unassigned: TokenAccountEntry = .empty,
                sourceErrors: [SourceError] = [],
                configError: String? = nil,
                lastSuccessfulRefreshAt: Date? = nil,
                endpointBlockedUntil: Date? = nil,
                nextRetryAt: Date? = nil,
                isPreliminary: Bool = false) {
        self.generatedAt = generatedAt
        self.window = window
        self.windowSource = windowSource
        self.subscriptions = subscriptions
        self.groups = groups
        self.accountBudgets = accountBudgets
        self.tokenAccounts = tokenAccounts
        self.codexPlanTokens = codexPlanTokens
        self.codexLimits = codexLimits
        self.unassigned = unassigned
        self.sourceErrors = sourceErrors
        self.configError = configError
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.endpointBlockedUntil = endpointBlockedUntil
        self.nextRetryAt = nextRetryAt
        self.isPreliminary = isPreliminary
    }

    public var isStale: Bool { !sourceErrors.isEmpty }

    /// Canonical ids of the models in every breakdown of this snapshot:
    /// subscription accounts, groups, own budgets, token accounts, Codex
    /// subscription accounts (unpriced, spec 006 FR-017) and Unassigned.
    /// Drives the Prices tab's "Used in this window" filter (spec 002
    /// FR-030, research R9).
    public var usedModels: Set<String> {
        var breakdowns = subscriptions.values.map(\.breakdown)
        breakdowns += groups.values.map(\.breakdown)
        breakdowns += accountBudgets.values.map(\.breakdown)
        breakdowns += tokenAccounts.values.map(\.breakdown)
        breakdowns += codexPlanTokens.values.map(\.breakdown)
        breakdowns.append(unassigned.breakdown)
        var models = Set<String>()
        for breakdown in breakdowns {
            for usage in breakdown.perModel { models.insert(PriceTable.canonicalModel(usage.model)) }
            for model in breakdown.unpricedModels { models.insert(PriceTable.canonicalModel(model)) }
        }
        return models
    }
}

// MARK: - Percent formatting (FR-009a)

public enum PercentFormatter {
    /// Nearest whole number, not capped at 100. Values from untrusted
    /// sources (a Codex snapshot or usage answer) can be absurdly large;
    /// they are clamped to +/- one billion so the conversion never traps.
    public static func rounded(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, -1_000_000_000), 1_000_000_000).rounded(.toNearestOrAwayFromZero))
    }

    public static func rounded(spent: Decimal, budget: Decimal) -> Int {
        guard budget > 0 else { return 0 }
        var ratio = spent / budget * 100
        var result = Decimal()
        NSDecimalRound(&result, &ratio, 0, .plain)
        return NSDecimalNumber(decimal: result).intValue
    }

    public static func text(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? "--"
    }
}

extension UsageSnapshot {
    /// The snapshot without group and own-budget entries computed for
    /// another period than the owner's configured one (spec 015 FR-004,
    /// FR-005, research R2). Such entries are carried over from before a
    /// period switch while the record source fails; without an entry the
    /// owner shows its waiting-for-data presentation (no amount, percent,
    /// period line or level), and the threshold tracker skips it.
    public func droppingBudgetPeriodMismatches(configuration: Configuration) -> UsageSnapshot {
        var copy = self
        for owner in configuration.budgetOwners {
            switch owner.kind {
            case .group:
                if let entry = copy.groups[owner.id], entry.period != owner.budget.period { copy.groups[owner.id] = nil }
            case .account:
                if let entry = copy.accountBudgets[owner.id], entry.period != owner.budget.period { copy.accountBudgets[owner.id] = nil }
            }
        }
        return copy
    }
}
