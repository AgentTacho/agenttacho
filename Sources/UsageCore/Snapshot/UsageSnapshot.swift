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
    public var resetsAt: Date
    /// Share of the account-wide weekly limit this model may use, when reported.
    public var allowancePercentOfWeekly: Int?

    public init(modelName: String, utilizationPercent: Double, resetsAt: Date, allowancePercentOfWeekly: Int? = nil) {
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

    /// The higher of the two windows, or nil when both are unavailable (FR-005).
    public var barPercent: Int? {
        let values = [fiveHour, sevenDay].compactMap { $0?.utilizationPercent }
        guard let max = values.max() else { return nil }
        return PercentFormatter.rounded(max)
    }
}

public enum SubscriptionState: Equatable, Sendable {
    case ok
    /// `lastGoodAt` is nil when no fetch has succeeded yet in this run.
    case stale(lastGoodAt: Date?, error: String)
    case notSignedIn
    case credentialsExpired

    public var isOk: Bool {
        if case .ok = self { return true }
        return false
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

    public var id: String { model }
    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }

    public init(model: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheWrite5mTokens: Int = 0, cacheWrite1hTokens: Int = 0, cacheReadTokens: Int = 0, costUSD: Decimal? = nil, priced: Bool = true) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.priced = priced
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

public struct UsageBreakdown: Equatable, Sendable {
    public var perModel: [ModelUsage]
    public var perDay: [DayUsage]
    /// All projects, ranked (cost in priced breakdowns, tokens otherwise).
    public var perProject: [ProjectUsage]
    public var unpricedModels: [String]

    public init(perModel: [ModelUsage] = [], perDay: [DayUsage] = [], perProject: [ProjectUsage] = [],
                unpricedModels: [String] = []) {
        self.perModel = perModel
        self.perDay = perDay
        self.perProject = perProject
        self.unpricedModels = unpricedModels
    }

    public static let empty = UsageBreakdown()

    public var totalTokens: Int { perModel.reduce(0) { $0 + $1.totalTokens } }
    public var inputTokens: Int { perModel.reduce(0) { $0 + $1.inputTokens } }
    public var outputTokens: Int { perModel.reduce(0) { $0 + $1.outputTokens } }
    public var cacheWriteTokens: Int { perModel.reduce(0) { $0 + $1.cacheWriteTokens } }
    public var cacheReadTokens: Int { perModel.reduce(0) { $0 + $1.cacheReadTokens } }
    public var pricedCostUSD: Decimal { perModel.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) } }
    public var isEmpty: Bool { perModel.isEmpty }
}

// MARK: - Entries

public struct SubscriptionEntry: Equatable, Sendable {
    public var status: SubscriptionStatus?
    public var state: SubscriptionState
    public var breakdown: UsageBreakdown
    /// Outcome of this refresh's endpoint request; nil when no request was
    /// made (not signed in, credentials expired or unreadable).
    public var fetchOutcome: FetchOutcome?

    public init(status: SubscriptionStatus?, state: SubscriptionState, breakdown: UsageBreakdown = .empty,
                fetchOutcome: FetchOutcome? = nil) {
        self.status = status
        self.state = state
        self.breakdown = breakdown
        self.fetchOutcome = fetchOutcome
    }
}

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
    public var stale: Bool

    public init(spentUSD: Decimal, budgetUSD: Decimal, percent: Int, incomplete: Bool, period: BudgetPeriod = .weekly, window: DateInterval,
                breakdown: UsageBreakdown, members: [String], stale: Bool = false) {
        self.spentUSD = spentUSD
        self.budgetUSD = budgetUSD
        self.percent = percent
        self.incomplete = incomplete
        self.period = period
        self.window = window
        self.breakdown = breakdown
        self.members = members
        self.stale = stale
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
    public var tokenAccounts: [String: TokenAccountEntry]
    public var unassigned: TokenAccountEntry
    public var sourceErrors: [SourceError]
    public var configError: String?
    public var lastSuccessfulRefreshAt: Date?
    /// End of an active rate-limit block on the usage endpoint, if any.
    public var endpointBlockedUntil: Date?
    /// Time of the scheduled retry after a rate limit, if any.
    public var nextRetryAt: Date?

    public init(generatedAt: Date,
                window: DateInterval,
                windowSource: WindowSource,
                subscriptions: [String: SubscriptionEntry] = [:],
                groups: [String: GroupEntry] = [:],
                tokenAccounts: [String: TokenAccountEntry] = [:],
                unassigned: TokenAccountEntry = .empty,
                sourceErrors: [SourceError] = [],
                configError: String? = nil,
                lastSuccessfulRefreshAt: Date? = nil,
                endpointBlockedUntil: Date? = nil,
                nextRetryAt: Date? = nil) {
        self.generatedAt = generatedAt
        self.window = window
        self.windowSource = windowSource
        self.subscriptions = subscriptions
        self.groups = groups
        self.tokenAccounts = tokenAccounts
        self.unassigned = unassigned
        self.sourceErrors = sourceErrors
        self.configError = configError
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.endpointBlockedUntil = endpointBlockedUntil
        self.nextRetryAt = nextRetryAt
    }

    public var isStale: Bool { !sourceErrors.isEmpty }
}

// MARK: - Percent formatting (FR-009a)

public enum PercentFormatter {
    /// Nearest whole number, never capped.
    public static func rounded(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(value.rounded(.toNearestOrAwayFromZero))
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
