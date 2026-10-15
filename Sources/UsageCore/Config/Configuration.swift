import Foundation

// MARK: - Enumerations

/// The harness that produced the usage (spec 001 FR-017, spec 006 FR-001).
public enum Harness: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case openCode

    /// "Claude Code", "Codex" or "OpenCode", for breakdowns and logs.
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .openCode: return "OpenCode"
        }
    }
}

/// Provider behind a token-based account. Selects the built-in detection
/// rule per harness (spec 006 FR-012, FR-016).
public enum Provider: String, Codable, Sendable, CaseIterable {
    case vertex
    case openai

    /// "Vertex" or "OpenAI", for pickers and default names.
    public var displayName: String {
        switch self {
        case .vertex: return "Vertex"
        case .openai: return "OpenAI"
        }
    }

    /// The name a new token-based account gets when none is entered.
    public var defaultAccountName: String {
        switch self {
        case .vertex: return "Claude Code via Vertex"
        case .openai: return "OpenAI API"
        }
    }
}

/// Where an effective price comes from (FR-005).
public enum PriceSource: Equatable, Sendable {
    case builtIn
    case imported(ImportProvenance)
    case override
}

// MARK: - Default icons

/// The icon a new entry starts with, and the icon an entry gets when the
/// configuration file has none (spec 004 FR-002, FR-006, research R1).
public enum IconDefaults {
    /// Subscription accounts: the Claude icon.
    public static let subscription = "brands:claude"
    /// Vertex token-based accounts: the Google icon.
    public static let vertex = "brands:google"
    /// OpenAI token-based accounts and Codex subscription accounts: the
    /// OpenAI icon (spec 006 FR-016, FR-017).
    public static let openai = "brands:openai"
    /// Budget groups: the wallet icon.
    public static let group = "solid:wallet"

    public static func defaultIcon(for kind: AccountKind) -> String {
        switch kind {
        case .subscription: return subscription
        case .tokenBased(let settings): return defaultIcon(for: settings.provider)
        case .codexSubscription: return openai
        }
    }

    public static func defaultIcon(for provider: Provider) -> String {
        switch provider {
        case .vertex: return vertex
        case .openai: return openai
        }
    }
}

// MARK: - Settings per account kind

public struct SubscriptionSettings: Codable, Equatable, Sendable {
    public var credentialDirectory: String
    public var shownInBar: Bool
    public var thresholds: [Int]

    public init(credentialDirectory: String = Paths.defaultClaudeDirectory, shownInBar: Bool = true, thresholds: [Int] = []) {
        self.credentialDirectory = credentialDirectory
        self.shownInBar = shownInBar
        self.thresholds = thresholds
    }
}

/// A budget: period, amount, visibility in the bar and notification
/// thresholds. Held by a budget group or by one token-based account
/// (spec 004 FR-009, research R3).
public struct BudgetSettings: Codable, Equatable, Sendable {
    /// Weekly or monthly; absent in the file means weekly (spec 003 FR-002).
    public var period: BudgetPeriod
    /// Budget in US dollars for one `period` (spec 003 FR-001).
    public var budgetUSD: Decimal
    public var shownInBar: Bool
    public var thresholds: [Int]

    public init(period: BudgetPeriod = .weekly, budgetUSD: Decimal, shownInBar: Bool = true, thresholds: [Int] = []) {
        self.period = period
        self.budgetUSD = budgetUSD
        self.shownInBar = shownInBar
        self.thresholds = thresholds
    }

    private enum CodingKeys: String, CodingKey {
        case period, budgetUSD, shownInBar, thresholds
    }

    /// Applies the period rules of spec 003 (FR-004a): only an absent
    /// `period` means weekly; `null` or an unknown value throws. An absent
    /// `budgetUSD` throws (spec 004 contracts/config-file.md).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = c.contains(.period) ? try c.decode(BudgetPeriod.self, forKey: .period) : .weekly
        guard c.contains(.budgetUSD) else {
            throw DecodingError.keyNotFound(CodingKeys.budgetUSD, DecodingError.Context(
                codingPath: c.codingPath, debugDescription: "Budget has no budgetUSD"))
        }
        budgetUSD = try c.decodeDecimal(forKey: .budgetUSD)
        shownInBar = try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? true
        thresholds = try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(period, forKey: .period)
        try c.encode(budgetUSD, forKey: .budgetUSD)
        try c.encode(shownInBar, forKey: .shownInBar)
        try c.encode(thresholds, forKey: .thresholds)
    }
}

/// How a token-based account is budgeted: as a member of exactly one budget
/// group, or with its own budget (spec 004 FR-008).
public enum TokenMembership: Equatable, Sendable {
    /// Member of the group `id`. `shownInBar` shows the member's share of the
    /// group budget in the bar, off by default (FR-016).
    case group(id: String, shownInBar: Bool)
    case ownBudget(BudgetSettings)
}

/// Encoded and decoded by `Account`, which flattens the membership into the
/// account object (spec 004 contracts/config-file.md).
public struct TokenBasedSettings: Equatable, Sendable {
    public var membership: TokenMembership
    public var provider: Provider

    public init(membership: TokenMembership, provider: Provider = .vertex) {
        self.membership = membership
        self.provider = provider
    }

    /// A group member whose share is not shown in the bar.
    public init(groupId: String, provider: Provider = .vertex) {
        self.init(membership: .group(id: groupId, shownInBar: false), provider: provider)
    }

    /// The group id for members, nil for an own budget.
    public var groupId: String? {
        if case .group(let id, _) = membership { return id }
        return nil
    }

    /// The own budget, nil for group members.
    public var ownBudget: BudgetSettings? {
        if case .ownBudget(let budget) = membership { return budget }
        return nil
    }

    /// True when a group member's share is shown in the bar (FR-016).
    /// Always false for an own budget, which has its own `shownInBar`.
    public var memberShownInBar: Bool {
        if case .group(_, let shown) = membership { return shown }
        return false
    }
}

/// A ChatGPT-plan billing source used through Codex (spec 006 FR-017).
/// `codexHome` separates several Codex subscription accounts (spec 006
/// FR-015). Plan limits add a bar entry, thresholds per window and the
/// live-limits setting, all with defaults so files of the previous version
/// load unchanged (spec 007 FR-016, FR-017).
public struct CodexSubscriptionSettings: Codable, Equatable, Sendable {
    public var codexHome: String = Paths.defaultCodexHome
    /// Shows the longest plan window in the bar (spec 007 FR-012).
    public var shownInBar: Bool = true
    /// Whole-number percents, applied to every plan window (spec 007 FR-014).
    public var thresholds: [Int] = []
    /// Fetches the limits from the plan's usage service; off uses only local
    /// snapshots and never reads the Codex sign-in (spec 007 FR-002, FR-019).
    public var liveLimits: Bool = true

    public init(codexHome: String = Paths.defaultCodexHome, shownInBar: Bool = true, thresholds: [Int] = [], liveLimits: Bool = true) {
        self.codexHome = codexHome
        self.shownInBar = shownInBar
        self.thresholds = thresholds
        self.liveLimits = liveLimits
    }
}

public enum AccountKind: Equatable, Sendable {
    case subscription(SubscriptionSettings)
    case tokenBased(TokenBasedSettings)
    case codexSubscription(CodexSubscriptionSettings)

    public var typeName: String {
        switch self {
        case .subscription: return "subscription"
        case .tokenBased: return "tokenBased"
        case .codexSubscription: return "codexSubscription"
        }
    }

    public var isSubscription: Bool {
        if case .subscription = self { return true }
        return false
    }

    public var subscription: SubscriptionSettings? {
        if case .subscription(let s) = self { return s }
        return nil
    }

    public var tokenBased: TokenBasedSettings? {
        if case .tokenBased(let t) = self { return t }
        return nil
    }

    public var isCodexSubscription: Bool {
        if case .codexSubscription = self { return true }
        return false
    }

    public var codexSubscription: CodexSubscriptionSettings? {
        if case .codexSubscription(let c) = self { return c }
        return nil
    }
}

// MARK: - Account

public struct Account: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// Font Awesome icon as `"style:name"` (for example `"brands:claude"`).
    /// Required, may repeat across entries (spec 004 FR-001, FR-003).
    public var icon: String
    public var displayName: String
    public var harness: Harness
    public var kind: AccountKind
    public var customMarker: String?

    /// A nil `icon` means the default icon for `kind` (FR-002).
    public init(id: String = UUID().uuidString, icon: String? = nil, displayName: String, harness: Harness = .claudeCode, kind: AccountKind, customMarker: String? = nil) {
        self.id = id
        self.icon = icon ?? IconDefaults.defaultIcon(for: kind)
        self.displayName = displayName
        self.harness = harness
        self.kind = kind
        self.customMarker = customMarker
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, icon, displayName, harness, customMarker
        case credentialDirectory, shownInBar, thresholds
        case groupId, provider, budget
        case codexHome, liveLimits
    }

    /// Ignores a legacy `label` key and falls back to the type's default icon
    /// when `icon` is absent, `null`, or empty (spec 004 FR-006). A
    /// token-based account must have exactly one of `groupId` and `budget`
    /// (FR-008); anything else throws a `DecodingError`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        harness = try c.decodeIfPresent(Harness.self, forKey: .harness) ?? .claudeCode
        customMarker = try c.decodeIfPresent(String.self, forKey: .customMarker)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "subscription":
            kind = .subscription(SubscriptionSettings(
                credentialDirectory: try c.decodeIfPresent(String.self, forKey: .credentialDirectory) ?? Paths.defaultClaudeDirectory,
                shownInBar: try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? true,
                thresholds: try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? []))
        case "tokenBased":
            let provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .vertex
            let groupId = try c.decodeIfPresent(String.self, forKey: .groupId)
            let budget = try c.decodeIfPresent(BudgetSettings.self, forKey: .budget)
            let membership: TokenMembership
            switch (groupId, budget) {
            case (let groupId?, nil):
                membership = .group(id: groupId, shownInBar: try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? false)
            case (nil, let budget?):
                membership = .ownBudget(budget)
            case (.some, .some):
                throw DecodingError.dataCorruptedError(forKey: .budget, in: c,
                                                       debugDescription: "Account \"\(displayName)\" has both groupId and its own budget; set exactly one")
            case (nil, nil):
                throw DecodingError.keyNotFound(CodingKeys.groupId, DecodingError.Context(
                    codingPath: c.codingPath, debugDescription: "Account \"\(displayName)\" has neither groupId nor its own budget; set exactly one"))
            }
            kind = .tokenBased(TokenBasedSettings(membership: membership, provider: provider))
        case "codexSubscription":
            // Missing plan-limit keys get the defaults (spec 007 FR-017).
            kind = .codexSubscription(CodexSubscriptionSettings(
                codexHome: try c.decodeIfPresent(String.self, forKey: .codexHome) ?? Paths.defaultCodexHome,
                shownInBar: try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? true,
                thresholds: try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? [],
                liveLimits: try c.decodeIfPresent(Bool.self, forKey: .liveLimits) ?? true))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown account type \"\(type)\"; expected subscription, tokenBased or codexSubscription")
        }
        let storedIcon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        icon = storedIcon.isEmpty ? IconDefaults.defaultIcon(for: kind) : storedIcon
    }

    /// Never writes `label` (spec 004 FR-007).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.typeName, forKey: .type)
        try c.encode(icon, forKey: .icon)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(harness, forKey: .harness)
        try c.encode(customMarker, forKey: .customMarker)
        switch kind {
        case .subscription(let s):
            try c.encode(s.credentialDirectory, forKey: .credentialDirectory)
            try c.encode(s.shownInBar, forKey: .shownInBar)
            try c.encode(s.thresholds, forKey: .thresholds)
        case .tokenBased(let t):
            switch t.membership {
            case .group(let groupId, let shownInBar):
                try c.encode(groupId, forKey: .groupId)
                try c.encode(shownInBar, forKey: .shownInBar)
            case .ownBudget(let budget):
                try c.encode(budget, forKey: .budget)
            }
            try c.encode(t.provider, forKey: .provider)
        case .codexSubscription(let settings):
            try c.encode(settings.codexHome, forKey: .codexHome)
            try c.encode(settings.shownInBar, forKey: .shownInBar)
            try c.encode(settings.thresholds, forKey: .thresholds)
            try c.encode(settings.liveLimits, forKey: .liveLimits)
        }
    }
}

// MARK: - Budget period

/// The period a budget applies to, a group's or an account's own (spec 003
/// FR-001, FR-002, spec 004 FR-009).
/// Weekly windows follow the designated subscription's 7-day reset or the
/// week fallback; monthly windows are the local calendar month (FR-005).
public enum BudgetPeriod: String, Codable, CaseIterable, Sendable {
    case weekly
    case monthly

    /// "weekly" or "monthly", for running text (FR-014).
    public var adjective: String {
        switch self {
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        }
    }

    /// "per week" or "per month", for group summaries (FR-014).
    public var perUnit: String {
        switch self {
        case .weekly: return "per week"
        case .monthly: return "per month"
        }
    }

    /// "Weekly budget" or "Monthly budget", for field labels and validation
    /// messages (FR-014, FR-019).
    public var budgetLabel: String {
        switch self {
        case .weekly: return "Weekly budget"
        case .monthly: return "Monthly budget"
        }
    }

    /// Threshold tracker window kind, so a period switch resets the budget
    /// owner's threshold state (spec 003 FR-017, spec 004 FR-012).
    public var windowKind: WindowKind {
        switch self {
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }
}

// MARK: - Budget group

public struct BudgetGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Font Awesome icon as `"style:name"`. Required, may repeat across
    /// entries (spec 004 FR-001, FR-003).
    public var icon: String
    /// Weekly or monthly; absent in older files means weekly (spec 003 FR-002).
    public var period: BudgetPeriod
    /// Budget in US dollars for one `period` (spec 003 FR-001).
    public var budgetUSD: Decimal
    public var shownInBar: Bool
    public var thresholds: [Int]

    public init(id: String = UUID().uuidString, name: String, icon: String = IconDefaults.group, period: BudgetPeriod = .weekly, budgetUSD: Decimal, shownInBar: Bool = true, thresholds: [Int] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.period = period
        self.budgetUSD = budgetUSD
        self.shownInBar = shownInBar
        self.thresholds = thresholds
    }

    /// The group's budget as one value, so groups and accounts with their own
    /// budget share validation, aggregation and thresholds. The JSON keys stay
    /// flat (spec 004 research R3).
    public var budget: BudgetSettings {
        get { BudgetSettings(period: period, budgetUSD: budgetUSD, shownInBar: shownInBar, thresholds: thresholds) }
        set {
            period = newValue.period
            budgetUSD = newValue.budgetUSD
            shownInBar = newValue.shownInBar
            thresholds = newValue.thresholds
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, period, budgetUSD, shownInBar, thresholds
        /// Legacy amount of files written before spec 003; decoded, never encoded.
        case weeklyBudgetUSD
    }

    /// Implements the decoding table of spec 003 contracts/config-file.md
    /// (FR-002, FR-003, FR-004a, research R5). Every error row throws a
    /// `DecodingError`, which rejects the whole file (spec 001 FR-033).
    /// A legacy `label` is ignored; an absent, `null` or empty `icon` means
    /// the wallet icon (spec 004 FR-006).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let storedIcon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        icon = storedIcon.isEmpty ? IconDefaults.group : storedIcon
        // Only an absent key means weekly; `null`, another string, or a
        // non-string value is a decode error (FR-004a).
        period = c.contains(.period) ? try c.decode(BudgetPeriod.self, forKey: .period) : .weekly
        if c.contains(.budgetUSD) {
            budgetUSD = try c.decodeDecimal(forKey: .budgetUSD)
        } else if c.contains(.weeklyBudgetUSD) {
            guard period == .weekly else {
                throw DecodingError.dataCorruptedError(forKey: .budgetUSD, in: c,
                                                       debugDescription: "Group \"\(name)\" has period \"\(period.rawValue)\" but only the legacy weeklyBudgetUSD; set budgetUSD")
            }
            budgetUSD = try c.decodeDecimal(forKey: .weeklyBudgetUSD)
        } else {
            throw DecodingError.keyNotFound(CodingKeys.budgetUSD, DecodingError.Context(
                codingPath: c.codingPath, debugDescription: "Group \"\(name)\" has no budgetUSD"))
        }
        shownInBar = try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? true
        thresholds = try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? []
    }

    /// Always writes the new form, `period` plus `budgetUSD` (spec 003 FR-004),
    /// and never `label` (spec 004 FR-007).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(period, forKey: .period)
        try c.encode(budgetUSD, forKey: .budgetUSD)
        try c.encode(shownInBar, forKey: .shownInBar)
        try c.encode(thresholds, forKey: .thresholds)
    }
}

// MARK: - Week fallback

public struct WeekFallback: Codable, Equatable, Sendable {
    /// Calendar convention: 1 = Sunday ... 7 = Saturday.
    public var weekday: Int
    /// 0 to 23, local time.
    public var hour: Int

    public init(weekday: Int = 2, hour: Int = 0) {
        self.weekday = weekday
        self.hour = hour
    }

    public static let monday = WeekFallback(weekday: 2, hour: 0)
}

// MARK: - Price entry

public struct PriceEntry: Codable, Equatable, Sendable, Identifiable {
    public var model: String
    public var inputPerMTok: Decimal
    public var outputPerMTok: Decimal
    public var cacheWrite5mPerMTok: Decimal
    public var cacheWrite1hPerMTok: Decimal
    public var cacheReadPerMTok: Decimal
    /// Not persisted; set by the price table when merging.
    public var source: PriceSource

    public var id: String { model }

    public init(model: String, inputPerMTok: Decimal, outputPerMTok: Decimal, cacheWrite5mPerMTok: Decimal, cacheWrite1hPerMTok: Decimal, cacheReadPerMTok: Decimal, source: PriceSource = .override) {
        self.model = model
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cacheWrite5mPerMTok = cacheWrite5mPerMTok
        self.cacheWrite1hPerMTok = cacheWrite1hPerMTok
        self.cacheReadPerMTok = cacheReadPerMTok
        self.source = source
    }

    /// True when all five price fields are equal; `source` is ignored. This
    /// is the price equality used by diffs, Apply enablement and the export
    /// round trip, because synthesized `==` also compares `source`.
    public func samePrices(as other: PriceEntry) -> Bool {
        PriceField.allCases.allSatisfy { self[keyPath: $0.keyPath] == other[keyPath: $0.keyPath] }
    }

    private enum CodingKeys: String, CodingKey {
        case model, inputPerMTok, outputPerMTok, cacheWrite5mPerMTok, cacheWrite1hPerMTok, cacheReadPerMTok
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decode(String.self, forKey: .model)
        inputPerMTok = try c.decodeDecimal(forKey: .inputPerMTok)
        outputPerMTok = try c.decodeDecimal(forKey: .outputPerMTok)
        cacheWrite5mPerMTok = try c.decodeDecimal(forKey: .cacheWrite5mPerMTok)
        cacheWrite1hPerMTok = try c.decodeDecimal(forKey: .cacheWrite1hPerMTok)
        cacheReadPerMTok = try c.decodeDecimal(forKey: .cacheReadPerMTok)
        source = .override
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(inputPerMTok, forKey: .inputPerMTok)
        try c.encode(outputPerMTok, forKey: .outputPerMTok)
        try c.encode(cacheWrite5mPerMTok, forKey: .cacheWrite5mPerMTok)
        try c.encode(cacheWrite1hPerMTok, forKey: .cacheWrite1hPerMTok)
        try c.encode(cacheReadPerMTok, forKey: .cacheReadPerMTok)
    }
}

// MARK: - Configuration

public struct Configuration: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let defaultRefreshIntervalSeconds = 300
    public static let minimumRefreshIntervalSeconds = 60

    public var version: Int
    public var refreshIntervalSeconds: Int
    public var logDirectories: [String]
    /// Extra Codex homes, read in addition to `~/.codex` (spec 006 FR-003).
    public var codexHomes: [String]
    /// Extra OpenCode data directories, read in addition to
    /// `~/.local/share/opencode` (spec 006 FR-003).
    public var openCodeDirectories: [String]
    public var weekFallback: WeekFallback
    public var alignmentAccountId: String?
    public var startAtLogin: Bool
    public var accounts: [Account]
    public var groups: [BudgetGroup]
    public var priceOverrides: [PriceEntry]
    /// The user-defined order of the bar and the dropdown (spec 008 FR-004).
    /// Nil until a change affects the order; the default order is then
    /// derived on every load. Encoded only when set.
    public var arrangement: Arrangement?

    public init(version: Int = Configuration.currentVersion,
                refreshIntervalSeconds: Int = Configuration.defaultRefreshIntervalSeconds,
                logDirectories: [String] = [],
                codexHomes: [String] = [],
                openCodeDirectories: [String] = [],
                weekFallback: WeekFallback = .monday,
                alignmentAccountId: String? = nil,
                startAtLogin: Bool = false,
                accounts: [Account] = [],
                groups: [BudgetGroup] = [],
                priceOverrides: [PriceEntry] = [],
                arrangement: Arrangement? = nil) {
        self.version = version
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.logDirectories = logDirectories
        self.codexHomes = codexHomes
        self.openCodeDirectories = openCodeDirectories
        self.weekFallback = weekFallback
        self.alignmentAccountId = alignmentAccountId
        self.startAtLogin = startAtLogin
        self.accounts = accounts
        self.groups = groups
        self.priceOverrides = priceOverrides
        self.arrangement = arrangement
    }

    public static let `default` = Configuration()

    private enum CodingKeys: String, CodingKey {
        case version, refreshIntervalSeconds, logDirectories, codexHomes, openCodeDirectories, weekFallback, alignmentAccountId, startAtLogin, accounts, groups, priceOverrides
        case arrangement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Configuration.currentVersion
        refreshIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? Configuration.defaultRefreshIntervalSeconds
        logDirectories = try c.decodeIfPresent([String].self, forKey: .logDirectories) ?? []
        codexHomes = try c.decodeIfPresent([String].self, forKey: .codexHomes) ?? []
        openCodeDirectories = try c.decodeIfPresent([String].self, forKey: .openCodeDirectories) ?? []
        weekFallback = try c.decodeIfPresent(WeekFallback.self, forKey: .weekFallback) ?? .monday
        alignmentAccountId = try c.decodeIfPresent(String.self, forKey: .alignmentAccountId)
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        groups = try c.decodeIfPresent([BudgetGroup].self, forKey: .groups) ?? []
        priceOverrides = try c.decodeIfPresent([PriceEntry].self, forKey: .priceOverrides) ?? []
        // An arrangement that cannot be read at all is treated as absent:
        // its problems are never a configuration error (spec 008 FR-011).
        arrangement = (try? c.decodeIfPresent(Arrangement.self, forKey: .arrangement)) ?? nil
    }

    // MARK: Lookups

    /// Anthropic subscription accounts only; Codex subscription accounts
    /// never reach the usage endpoint, alignment or the network fingerprint.
    public var subscriptionAccounts: [Account] { accounts.filter { $0.kind.isSubscription } }
    /// Priced token-based accounts (spec 006 FR-017: Codex subscription
    /// accounts are not among them).
    public var tokenBasedAccounts: [Account] { accounts.filter { $0.kind.tokenBased != nil } }
    /// Accounts of kind `.codexSubscription` (spec 006 FR-017).
    public var codexSubscriptionAccounts: [Account] { accounts.filter { $0.kind.isCodexSubscription } }

    public func account(id: String) -> Account? { accounts.first { $0.id == id } }
    public func group(id: String) -> BudgetGroup? { groups.first { $0.id == id } }

    public func members(of groupId: String) -> [Account] {
        accounts.filter { $0.kind.tokenBased?.groupId == groupId }
    }

    /// The subscription account whose 7-day reset aligns the weekly window (FR-021).
    public var effectiveAlignmentAccountId: String? {
        if let id = alignmentAccountId, let account = account(id: id), account.kind.isSubscription {
            return id
        }
        return subscriptionAccounts.first?.id
    }

    // MARK: Validation

    public func validate() throws {
        if refreshIntervalSeconds < Configuration.minimumRefreshIntervalSeconds {
            throw ConfigurationError(kind: .refreshInterval,
                                     message: "Refresh interval must be at least \(Configuration.minimumRefreshIntervalSeconds) seconds (got \(refreshIntervalSeconds)).")
        }
        if !(1...7).contains(weekFallback.weekday) || !(0...23).contains(weekFallback.hour) {
            throw ConfigurationError(kind: .weekFallback,
                                     message: "Week fallback weekday must be 1 to 7 and hour 0 to 23 (got weekday \(weekFallback.weekday), hour \(weekFallback.hour)).")
        }

        /// The icon must exist in the bundled catalog (spec 004 FR-005).
        /// Several entries may share an icon (FR-003).
        func checkIcon(_ icon: String, owner: String) throws {
            if !IconCatalog.shared.contains(icon) {
                throw ConfigurationError(kind: .unknownIcon,
                                         message: "Icon \"\(icon)\" of \(owner) is not a known Font Awesome icon (expected style:name, for example brands:claude).")
            }
        }

        // Accounts and groups are looked up by id, so ids must be unique
        // within each list. A group and an account may share an id: budget
        // owners keep the two kinds apart (spec 004 BudgetOwner).
        var seenAccountIds = Set<String>()
        for account in accounts where !seenAccountIds.insert(account.id).inserted {
            throw ConfigurationError(kind: .duplicateId,
                                     message: "Account id \"\(account.id)\" is used by more than one account.")
        }
        var seenGroupIds = Set<String>()
        for group in groups where !seenGroupIds.insert(group.id).inserted {
            throw ConfigurationError(kind: .duplicateId,
                                     message: "Group id \"\(group.id)\" is used by more than one budget group.")
        }

        var seenDirectories = Set<String>()
        var seenCodexHomes = Set<String>()
        let paths = Paths()
        for account in accounts {
            let owner = "account \"\(account.displayName)\""
            try checkIcon(account.icon, owner: owner)
            switch account.kind {
            case .subscription(let s):
                let dir = paths.expand(s.credentialDirectory)
                if !seenDirectories.insert(dir).inserted {
                    throw ConfigurationError(kind: .duplicateCredentialDirectory,
                                             message: "Credential directory \"\(s.credentialDirectory)\" is used by more than one subscription account.")
                }
                try checkThresholds(s.thresholds, owner: owner)
            case .tokenBased(let t):
                switch t.membership {
                case .group(let groupId, _):
                    if group(id: groupId) == nil {
                        throw ConfigurationError(kind: .unknownGroup,
                                                 message: "Account \"\(account.displayName)\" references unknown budget group \"\(groupId)\".")
                    }
                case .ownBudget(let budget):
                    // Same rules and messages as a group budget (spec 004 FR-009).
                    try checkBudget(budget, owner: owner)
                }
            case .codexSubscription(let settings):
                // Mirrors the credential directory rule (spec 006 FR-015, research R9).
                // Compared canonically, as the Codex limits source keys its
                // per-sign-in state, so a symlink or `..` alias of a home
                // counts as the same home (spec 007 FR-003, FR-007).
                let home = Attributor.canonical(paths.expand(settings.codexHome))
                if !seenCodexHomes.insert(home).inserted {
                    throw ConfigurationError(kind: .duplicateCodexHome,
                                             message: "Codex home \"\(settings.codexHome)\" is used by more than one Codex subscription account.")
                }
                try checkThresholds(settings.thresholds, owner: owner)
            }
        }
        for group in groups {
            let owner = "group \"\(group.name)\""
            try checkIcon(group.icon, owner: owner)
            // A group without members is valid (spec 009 FR-001).
            try checkBudget(group.budget, owner: owner)
        }
        if let id = alignmentAccountId {
            guard let account = account(id: id), account.kind.isSubscription else {
                throw ConfigurationError(kind: .alignmentAccount,
                                         message: "Alignment account \"\(id)\" must be an existing subscription account.")
            }
        }
    }

    /// The amount must be greater than 0, with a message naming the period
    /// (spec 003 FR-001, FR-019), and thresholds must be whole numbers
    /// greater than 0. Shared by groups and own budgets (spec 004 FR-009).
    private func checkBudget(_ budget: BudgetSettings, owner: String) throws {
        if budget.budgetUSD <= 0 {
            throw ConfigurationError(kind: .budget,
                                     message: "\(budget.period.budgetLabel) of \(owner) must be greater than 0.")
        }
        try checkThresholds(budget.thresholds, owner: owner)
    }

    private func checkThresholds(_ thresholds: [Int], owner: String) throws {
        for t in thresholds where t <= 0 {
            throw ConfigurationError(kind: .threshold,
                                     message: "Thresholds of \(owner) must be whole-number percents greater than 0 (got \(t)).")
        }
    }

    // MARK: Account removal (spec 009 FR-002)

    /// Removes an account and clears `alignmentAccountId` when it named the
    /// removed account. Its group stays, also when it was the last member
    /// (spec 009 FR-002; a group is only deleted by `removingGroup`).
    public func removingAccount(id: String) -> Configuration {
        guard account(id: id) != nil else { return self }
        var copy = self
        copy.accounts.removeAll { $0.id == id }
        if copy.alignmentAccountId == id {
            copy.alignmentAccountId = nil
        }
        return copy
    }

    /// True when going from `old` to this configuration changes what a
    /// refresh computes. Icons, names, visibility in the bar (including a
    /// member's share), notification thresholds and start at login only
    /// change how existing data is shown, so the settings window applies them
    /// without a refresh (and without another request to the usage endpoint).
    public func needsRefresh(comparedTo old: Configuration) -> Bool {
        dataRelevant() != old.dataRelevant()
    }

    /// True when going from `old` to this configuration changes what the
    /// usage endpoint is asked: subscription accounts added or removed, a
    /// credential directory, or the alignment account. Every other
    /// data-relevant edit only needs a local re-price.
    public func needsNetworkRefresh(comparedTo old: Configuration) -> Bool {
        subscriptionFingerprint() != old.subscriptionFingerprint()
    }

    private func subscriptionFingerprint() -> [String] {
        subscriptionAccounts
            .map { "\($0.id)|\($0.kind.subscription?.credentialDirectory ?? "")" }
            .sorted() + ["alignment|\(effectiveAlignmentAccountId ?? "")"]
    }

    private func dataRelevant() -> Configuration {
        var copy = self
        copy.startAtLogin = false
        // The order of the bar and the dropdown is presentation only
        // (spec 008 research R3a).
        copy.arrangement = nil
        for index in copy.accounts.indices {
            copy.accounts[index].icon = ""
            copy.accounts[index].displayName = ""
            switch copy.accounts[index].kind {
            case .subscription(var settings):
                settings.shownInBar = true
                settings.thresholds = []
                copy.accounts[index].kind = .subscription(settings)
            case .tokenBased(var settings):
                // Spec 004 research R8: a member's share in the bar and an own
                // budget's visibility and thresholds are presentation only.
                switch settings.membership {
                case .group(let id, _):
                    settings.membership = .group(id: id, shownInBar: false)
                case .ownBudget(var budget):
                    budget.shownInBar = true
                    budget.thresholds = []
                    settings.membership = .ownBudget(budget)
                }
                copy.accounts[index].kind = .tokenBased(settings)
            case .codexSubscription(var settings):
                // Bar visibility and thresholds are presentation only; the
                // live-limits setting changes what a refresh fetches (spec 007
                // research R9).
                settings.shownInBar = true
                settings.thresholds = []
                copy.accounts[index].kind = .codexSubscription(settings)
            }
        }
        for index in copy.groups.indices {
            copy.groups[index].icon = ""
            copy.groups[index].name = ""
            copy.groups[index].shownInBar = true
            copy.groups[index].thresholds = []
        }
        return copy
    }

    // MARK: Budget owners (spec 004 research R4, R7)

    /// One entry per budget: groups in groups-list order, then token-based
    /// accounts with their own budget in accounts-list order. Aggregation,
    /// thresholds and the bar treat both kinds alike.
    public var budgetOwners: [BudgetOwner] {
        let groupOwners = groups.map { group in
            BudgetOwner(id: group.id, name: group.name, icon: group.icon, budget: group.budget,
                        memberIds: members(of: group.id).map(\.id), kind: .group)
        }
        let accountOwners = accounts.compactMap { account -> BudgetOwner? in
            guard let budget = account.kind.tokenBased?.ownBudget else { return nil }
            return BudgetOwner(id: account.id, name: account.displayName, icon: account.icon, budget: budget,
                               memberIds: [account.id], kind: .account)
        }
        return groupOwners + accountOwners
    }

    /// The owner whose budget and window a token-based account uses: its
    /// group, or the account itself when it has its own budget.
    public func budgetOwner(forAccount id: String) -> BudgetOwner? {
        guard let settings = account(id: id)?.kind.tokenBased else { return nil }
        let ownerId = settings.groupId ?? id
        return budgetOwners.first { $0.id == ownerId && ($0.kind == .account) == (settings.groupId == nil) }
    }

    /// Gives a group member its own budget, prefilled with the group's
    /// period, amount, thresholds and shown-in-bar setting. The member's
    /// share setting is discarded. A group left without members stays
    /// (spec 004 FR-014, spec 009 FR-002).
    public func movingAccountToOwnBudget(accountId: String) -> Configuration {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }),
              var settings = accounts[index].kind.tokenBased,
              let groupId = settings.groupId else { return self }
        let budget = group(id: groupId)?.budget ?? BudgetSettings(budgetUSD: 60, thresholds: [80, 100])
        var copy = self
        settings.membership = .ownBudget(budget)
        copy.accounts[index].kind = .tokenBased(settings)
        return copy
    }

    /// Makes an account a member of `groupId`. Its own budget is discarded,
    /// its share starts hidden in the bar, and a former group left without
    /// members stays (spec 004 FR-016, spec 009 FR-002).
    public func movingAccountToGroup(accountId: String, groupId: String) -> Configuration {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }),
              var settings = accounts[index].kind.tokenBased,
              settings.groupId != groupId else { return self }
        var copy = self
        settings.membership = .group(id: groupId, shownInBar: false)
        copy.accounts[index].kind = .tokenBased(settings)
        return copy
    }
}

// MARK: - Budget owner

/// A budget and who spends from it: a budget group with its members, or a
/// token-based account with its own budget (spec 004 data-model BudgetOwner).
public struct BudgetOwner: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case group
        case account
    }

    /// Group id, or account id for an own budget.
    public let id: String
    /// Group name, or account `displayName` (spec 004 FR-004).
    public let name: String
    public let icon: String
    public let budget: BudgetSettings
    /// Member account ids in accounts-list order; `[id]` for an account.
    public let memberIds: [String]
    public let kind: Kind

    public init(id: String, name: String, icon: String, budget: BudgetSettings, memberIds: [String], kind: Kind) {
        self.id = id
        self.name = name
        self.icon = icon
        self.budget = budget
        self.memberIds = memberIds
        self.kind = kind
    }
}

// MARK: - Error

public struct ConfigurationError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        case decoding
        case io
        /// An icon that is not in the bundled catalog (spec 004 FR-005).
        case unknownIcon
        /// Two accounts, or two groups, with the same id.
        case duplicateId
        case unknownGroup
        case duplicateCredentialDirectory
        /// Two Codex subscription accounts with the same Codex home (spec 006).
        case duplicateCodexHome
        case refreshInterval
        case threshold
        case budget
        case weekFallback
        case alignmentAccount
    }

    public let kind: Kind
    /// Human-readable text for the settings window and the dropdown.
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var description: String { message }
}

// MARK: - Decimal decoding helper

extension KeyedDecodingContainer {
    /// Decodes a JSON number into a `Decimal` via its shortest textual form so
    /// that values such as 0.2 do not pick up binary floating-point noise.
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        let double = try decode(Double.self, forKey: key)
        guard let decimal = Decimal(string: String(double)) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a decimal number")
        }
        return decimal
    }
}
