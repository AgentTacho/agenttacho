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

    /// The configuration key of a token-based account's directory of this
    /// harness: the Claude Code directory or the Codex home; nil for
    /// OpenCode, whose data directories are global (spec 034 FR-007, spec
    /// 037 FR-006).
    public var sessionDirectoryKey: String? {
        switch self {
        case .claudeCode: return "claudeCodeDirectory"
        case .codex: return "codexHome"
        case .openCode: return nil
        }
    }

    /// The directory an empty token-based directory field means; nil for
    /// OpenCode (spec 034 FR-007, FR-008, spec 037 FR-006).
    public var defaultSessionDirectory: String? {
        switch self {
        case .claudeCode: return Paths.defaultClaudeDirectory
        case .codex: return Paths.defaultCodexHome
        case .openCode: return nil
        }
    }
}

/// The provider key of token-based accounts before spec 037, read once to
/// migrate them (spec 037 FR-014, spec 038 FR-011). Never written.
enum LegacyProvider: String, Decodable {
    case vertex
    case openai

    /// Vertex accounts were Claude Code accounts, OpenAI accounts Codex
    /// accounts (spec 037 FR-014).
    var harness: Harness {
        switch self {
        case .vertex: return .claudeCode
        case .openai: return .codex
        }
    }

    /// The kind such an account counts: Vertex or API key (spec 038
    /// FR-011).
    var sessionKind: SessionKind {
        switch self {
        case .vertex: return .claudeCodeVertex
        case .openai: return .codexAPIKey
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
    /// Token-based accounts of a Vertex kind: the Google icon.
    public static let vertex = "brands:google"
    /// Token-based accounts of the Codex API key or OpenCode OpenAI kind,
    /// and Codex subscription accounts: the OpenAI icon (spec 006 FR-016,
    /// FR-017, spec 038 contracts/settings-ui.md).
    public static let openai = "brands:openai"
    /// OpenCode accounts of kind Other provider: the code icon (spec 038
    /// contracts/settings-ui.md).
    public static let openCode = "solid:code"
    /// Budget groups: the wallet icon.
    public static let group = "solid:wallet"

    public static func defaultIcon(for kind: AccountKind) -> String {
        switch kind {
        case .subscription: return subscription
        // A token-based account's icon follows its kind (spec 038
        // contracts/settings-ui.md).
        case .tokenBased(let settings): return settings.sessionKind.defaultIcon
        case .codexSubscription: return openai
        }
    }
}

// MARK: - Settings per account kind

public struct SubscriptionSettings: Codable, Equatable, Sendable {
    /// The Claude Code directory as entered, written to the file under
    /// `credentialDirectory`; Settings binds it, so a cleared field stays
    /// empty while the user types (spec 034 FR-006a, research R3).
    public var enteredCredentialDirectory: String
    public var shownInBar: Bool
    public var thresholds: [Int]
    /// The window the bar value and the section header follow; nil is the
    /// 7-day window (spec 027 FR-005, FR-010). Holds Claude cases only.
    public var headlineWindow: HeadlineChoice?
    /// Further Claude Code directories whose `projects` tree counts for
    /// this account, literal or with `*`; never a login source. Written to
    /// the file by `Account` (spec 035 FR-001, FR-009).
    public var additionalSessionDirectories: [String] = []

    /// The effective Claude Code directory: `~/.claude` for a blank entry,
    /// the entry otherwise. Its sessions, its login and the attribution
    /// tie-breaker all use it; setting it stores the entry (spec 034
    /// FR-006a).
    public var credentialDirectory: String {
        get { AccountDirectory.effective(enteredCredentialDirectory, default: Paths.defaultClaudeDirectory) }
        set { enteredCredentialDirectory = newValue }
    }

    public init(credentialDirectory: String = Paths.defaultClaudeDirectory, shownInBar: Bool = true, thresholds: [Int] = [],
                headlineWindow: HeadlineChoice? = nil, additionalSessionDirectories: [String] = []) {
        self.enteredCredentialDirectory = credentialDirectory
        self.shownInBar = shownInBar
        self.thresholds = thresholds
        self.headlineWindow = headlineWindow
        self.additionalSessionDirectories = additionalSessionDirectories
    }

    private enum CodingKeys: String, CodingKey {
        case enteredCredentialDirectory = "credentialDirectory"
        case shownInBar, thresholds, headlineWindow
    }
}

/// The blank rule shared by the account directory fields (spec 034 FR-006a,
/// FR-007): empty after trimming whitespace and newlines. A directory is
/// read without the surrounding whitespace a paste may bring, as the old
/// directory lists trimmed it, while the field keeps the entry as typed.
enum AccountDirectory {
    static func isBlank(_ entry: String) -> Bool {
        entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The trimmed entry, nil when it is blank.
    static func trimmed(_ entry: String?) -> String? {
        guard let value = entry?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// The trimmed entry, or `fallback` when it is blank.
    static func effective(_ entry: String, default fallback: String) -> String {
        trimmed(entry) ?? fallback
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
    /// The account's one harness: whose sessions feed it, which directory
    /// field it has and which kinds it offers (spec 037 FR-006). Changing it
    /// clears the session directory and the additional session directories,
    /// since a Claude Code directory is no Codex home, sets the kind to the
    /// new harness's default and keeps the condition, whose field becomes
    /// Model when the new harness does not offer it (spec 034 FR-007, spec
    /// 035 research R1, spec 038 edge case "Harness change", research R10).
    /// Initializers do not run it, so decoding keeps the stored values.
    public var harness: Harness {
        didSet {
            if oldValue != harness {
                enteredSessionDirectory = nil
                additionalSessionDirectories = []
                sessionKind = .default(for: harness)
                if let kept = condition, !MatchField.fields(for: harness).contains(kept.field) {
                    condition = kept.withField(.model)
                }
            }
        }
    }
    /// Which per-token sessions of the harness the account counts; always
    /// a kind of `harness` (spec 038 FR-001, FR-002).
    public var sessionKind: SessionKind
    /// The "Only when" condition that narrows the kind; nil when it is off
    /// (spec 038 FR-004, FR-014). Kept while the kind does not offer one,
    /// so choosing Directory only and back brings it back, but then it
    /// neither counts nor is written (`effectiveCondition`).
    public var condition: MatchCondition?

    /// The condition that counts: `condition` when the kind offers one,
    /// else nil. Attribution, overlap, validation, the fingerprint and the
    /// file use it (spec 038 edge case "Kind change", research R10).
    public var effectiveCondition: MatchCondition? {
        sessionKind.offersCondition ? condition : nil
    }

    /// The settings after choosing `kind` in the Sessions pop-up: the
    /// condition stays as it is, except that a kind that requires one and
    /// has none gets `remembered` or the initial condition (spec 038
    /// FR-014). A kind of another harness changes nothing.
    public func choosingKind(_ kind: SessionKind, remembered: MatchCondition?) -> TokenBasedSettings {
        guard kind.harness == harness else { return self }
        var next = self
        next.sessionKind = kind
        if kind.requiresCondition && next.condition == nil {
            next.condition = remembered.map(offered) ?? .initial
        }
        return next
    }

    /// `condition` as the Condition row of this harness offers it: a field
    /// the harness does not offer becomes Model, and the operator follows
    /// the field, so a condition remembered before a harness change never
    /// comes back with a Claude Code field on a Codex or OpenCode account
    /// (spec 038 FR-004, edge case "Harness change").
    func offered(_ condition: MatchCondition) -> MatchCondition {
        condition.withField(MatchField.fields(for: harness).contains(condition.field) ? condition.field : .model)
    }

    /// The settings after ticking (`on`) or unticking "Only when": on keeps
    /// the condition or restores `remembered` or the initial one; off
    /// clears it, except for a kind that requires one (spec 038 FR-014).
    public func settingConditionOn(_ on: Bool, remembered: MatchCondition?) -> TokenBasedSettings {
        var next = self
        if on {
            next.condition = condition ?? remembered.map(offered) ?? .initial
        } else if !sessionKind.requiresCondition {
            next.condition = nil
        }
        return next
    }

    /// The condition the Condition row edits: the condition, or the initial
    /// one for OpenCode Other provider loaded without a condition; writing
    /// through it sets the condition (spec 038 edge case "OpenCode Other
    /// provider without a condition").
    public var conditionForEditing: MatchCondition {
        get { condition ?? .initial }
        set { condition = newValue }
    }
    /// The optional session directory as entered: the Claude Code directory
    /// of a Claude Code account or the Codex home of a Codex account; never
    /// read for an OpenCode account. Only its session files are read, never
    /// a login (spec 034 FR-007, FR-008, spec 037 FR-006).
    public var enteredSessionDirectory: String?

    /// The session directory to read, trimmed; nil when none or a blank one
    /// is entered (spec 034 FR-007).
    public var sessionDirectory: String? { AccountDirectory.trimmed(enteredSessionDirectory) }

    /// The text of the account's directory field: empty for no directory,
    /// and an empty field stores none (spec 034 FR-007).
    public var sessionDirectoryField: String {
        get { enteredSessionDirectory ?? "" }
        set { enteredSessionDirectory = newValue.isEmpty ? nil : newValue }
    }

    /// Further directories of the account's harness (Claude Code
    /// directories or Codex homes; none for OpenCode) whose session files
    /// count for this account, literal or with `*` (spec 035 FR-001, FR-009,
    /// spec 037 FR-006).
    public var additionalSessionDirectories: [String] = []

    /// A nil `sessionKind`, or one of another harness, is the harness's
    /// default kind (spec 038 FR-001, data-model "TokenBasedSettings").
    public init(membership: TokenMembership, harness: Harness = .claudeCode, sessionKind: SessionKind? = nil,
                condition: MatchCondition? = nil, sessionDirectory: String? = nil, additionalSessionDirectories: [String] = []) {
        self.membership = membership
        self.harness = harness
        if let sessionKind, sessionKind.harness == harness {
            self.sessionKind = sessionKind
        } else {
            self.sessionKind = .default(for: harness)
        }
        self.condition = condition
        self.enteredSessionDirectory = sessionDirectory
        self.additionalSessionDirectories = additionalSessionDirectories
    }

    /// A group member whose share is not shown in the bar.
    public init(groupId: String, harness: Harness = .claudeCode, sessionKind: SessionKind? = nil, condition: MatchCondition? = nil) {
        self.init(membership: .group(id: groupId, shownInBar: false), harness: harness, sessionKind: sessionKind, condition: condition)
    }

    /// The directory the account's sessions are read from: the entered one,
    /// or the harness's default for an empty field; nil for OpenCode (spec
    /// 034 FR-008, spec 037 FR-006).
    public var effectiveSessionDirectory: String? {
        guard let fallback = harness.defaultSessionDirectory else { return nil }
        return sessionDirectory ?? fallback
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
    /// The Codex home as entered, written to the file under `codexHome`
    /// (spec 034 FR-006a, research R3).
    public var enteredCodexHome: String = Paths.defaultCodexHome
    /// Shows the longest plan window in the bar (spec 007 FR-012).
    public var shownInBar: Bool = true
    /// Whole-number percents, applied to every plan window (spec 007 FR-014).
    public var thresholds: [Int] = []
    /// Fetches the limits from the plan's usage service; off uses only local
    /// snapshots and never reads the Codex sign-in (spec 007 FR-002, FR-019).
    public var liveLimits: Bool = true
    /// The window the bar value and the section header follow; nil is the
    /// longest effective window (spec 027 FR-005, FR-010). Holds
    /// `codexWindow` only.
    public var headlineWindow: HeadlineChoice?
    /// Further Codex homes whose `sessions` tree counts for this account,
    /// literal or with `*`; never a sign-in or limit snapshot source.
    /// Written to the file by `Account` (spec 035 FR-001, FR-009, FR-010).
    public var additionalSessionDirectories: [String] = []

    /// The effective Codex home: `~/.codex` for a blank entry, the entry
    /// otherwise; its sessions, its sign-in and the tie-breaker use it.
    /// Setting it stores the entry (spec 034 FR-006a).
    public var codexHome: String {
        get { AccountDirectory.effective(enteredCodexHome, default: Paths.defaultCodexHome) }
        set { enteredCodexHome = newValue }
    }

    public init(codexHome: String = Paths.defaultCodexHome, shownInBar: Bool = true, thresholds: [Int] = [], liveLimits: Bool = true,
                headlineWindow: HeadlineChoice? = nil, additionalSessionDirectories: [String] = []) {
        self.enteredCodexHome = codexHome
        self.shownInBar = shownInBar
        self.thresholds = thresholds
        self.liveLimits = liveLimits
        self.headlineWindow = headlineWindow
        self.additionalSessionDirectories = additionalSessionDirectories
    }

    private enum CodingKeys: String, CodingKey {
        case enteredCodexHome = "codexHome"
        case shownInBar, thresholds, liveLimits, headlineWindow
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

    /// The harness whose sessions the account's directories hold: Claude
    /// Code for a Claude subscription, Codex for a Codex subscription, the
    /// account's own harness for a token-based account (spec 035 FR-001,
    /// spec 037 FR-006).
    public var sessionHarness: Harness {
        switch self {
        case .subscription: return .claudeCode
        case .codexSubscription: return .codex
        case .tokenBased(let settings): return settings.harness
        }
    }

    /// The additional session directories of whichever settings the account
    /// has (spec 035 FR-001).
    public var additionalSessionDirectories: [String] {
        get {
            switch self {
            case .subscription(let s): return s.additionalSessionDirectories
            case .codexSubscription(let c): return c.additionalSessionDirectories
            case .tokenBased(let t): return t.additionalSessionDirectories
            }
        }
        set {
            switch self {
            case .subscription(var s):
                s.additionalSessionDirectories = newValue
                self = .subscription(s)
            case .codexSubscription(var c):
                c.additionalSessionDirectories = newValue
                self = .codexSubscription(c)
            case .tokenBased(var t):
                t.additionalSessionDirectories = newValue
                self = .tokenBased(t)
            }
        }
    }
}

/// One entry of an account's additional session directories, for the
/// directory resolution of a refresh (spec 035 FR-008, data-model
/// "Configuration lookups").
public struct AdditionalSessionEntry: Equatable, Sendable {
    public let accountId: String
    /// The entry, trimmed, as stored.
    public let entry: String
    /// True for a Claude or Codex subscription account, whose additional
    /// directories count in the attribution tie-breaker (spec 035 FR-012).
    public let joinsTieBreak: Bool
    /// True when the entry holds `*` (spec 035 FR-004).
    public var isWildcard: Bool { entry.contains("*") }

    public init(accountId: String, entry: String, joinsTieBreak: Bool = false) {
        self.accountId = accountId
        self.entry = entry
        self.joinsTieBreak = joinsTieBreak
    }
}

// MARK: - Account

public struct Account: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// Font Awesome icon as `"style:name"` (for example `"brands:claude"`).
    /// Required, may repeat across entries (spec 004 FR-001, FR-003).
    public var icon: String
    public var displayName: String
    public var kind: AccountKind
    /// The custom marker of a Claude or Codex subscription (spec 006
    /// FR-013, spec 038 FR-006, FR-018). Always nil for a token-based
    /// account, whose marker became a condition (spec 038 FR-011).
    public var customMarker: String?
    /// How the account's section reads its reset and run-out times in the
    /// dropdown (spec 025 FR-016, FR-021). Kept for a token-based account in
    /// a group, where the group's applies, so it is back when the account
    /// gets its own budget.
    public var timeFormat: TimeFormat

    /// The harness of the account's usage: Claude Code for a Claude
    /// subscription, Codex for a Codex subscription, its own harness for a
    /// token-based account (spec 037 FR-006, research R5).
    public var harness: Harness { kind.sessionHarness }

    /// A nil `icon` means the default icon for `kind` (FR-002).
    public init(id: String = UUID().uuidString, icon: String? = nil, displayName: String, kind: AccountKind,
                customMarker: String? = nil, timeFormat: TimeFormat = .relative) {
        self.id = id
        self.icon = icon ?? IconDefaults.defaultIcon(for: kind)
        self.displayName = displayName
        self.kind = kind
        self.customMarker = customMarker
        self.timeFormat = timeFormat
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, icon, displayName, harness, customMarker
        case credentialDirectory, shownInBar, thresholds
        case groupId, provider, budget
        case codexHome, liveLimits
        case timeFormat
        case headlineWindow
        /// A Claude Code account's Claude Code directory (spec 034 FR-007).
        case claudeCodeDirectory
        /// Further session directories of any account kind (spec 035 FR-001).
        case additionalSessionDirectories
        /// A token-based account's match rule of spec 037 and the first
        /// spec 038 builds, read only (spec 038 FR-011).
        case matchRule
        /// A token-based account's session kind; its presence marks the
        /// form written since the spec 038 rework (FR-010).
        case sessionKind
        /// A token-based account's "Only when" condition (spec 038 FR-010).
        case condition
    }

    /// Ignores a legacy `label` key and falls back to the type's default icon
    /// when `icon` is absent, `null`, or empty (spec 004 FR-006). A
    /// token-based account must have exactly one of `groupId` and `budget`
    /// (FR-008); anything else throws a `DecodingError`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        customMarker = try c.decodeIfPresent(String.self, forKey: .customMarker)
        let notes = decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes
        timeFormat = c.decodeTimeFormat(forKey: .timeFormat, notes: notes)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "subscription":
            kind = .subscription(SubscriptionSettings(
                credentialDirectory: try c.decodeIfPresent(String.self, forKey: .credentialDirectory) ?? Paths.defaultClaudeDirectory,
                shownInBar: try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? true,
                thresholds: try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? [],
                headlineWindow: Self.decodeHeadline(c, forCodex: false, notes: notes)))
        case "tokenBased":
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
            let sessions = try Self.decodeSessions(c, marker: customMarker, name: displayName, notes: notes)
            // A token-based marker became a condition (spec 038 FR-011).
            customMarker = nil
            kind = .tokenBased(TokenBasedSettings(membership: membership, harness: sessions.harness, sessionKind: sessions.kind,
                                                  condition: sessions.condition,
                                                  sessionDirectory: Self.decodeSessionDirectory(c, harness: sessions.harness, name: displayName, notes: notes)))
        case "codexSubscription":
            // Missing plan-limit keys get the defaults (spec 007 FR-017).
            kind = .codexSubscription(CodexSubscriptionSettings(
                codexHome: try c.decodeIfPresent(String.self, forKey: .codexHome) ?? Paths.defaultCodexHome,
                shownInBar: try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? true,
                thresholds: try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? [],
                liveLimits: try c.decodeIfPresent(Bool.self, forKey: .liveLimits) ?? true,
                headlineWindow: Self.decodeHeadline(c, forCodex: true, notes: notes)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown account type \"\(type)\"; expected subscription, tokenBased or codexSubscription")
        }
        if kind.sessionHarness == .openCode {
            // OpenCode data directories are global (spec 037 FR-006).
            if c.contains(.additionalSessionDirectories) {
                notes?.append("additionalSessionDirectories of account \"\(Configuration.clipped(displayName))\" does not belong to an OpenCode account, ignored")
            }
        } else {
            kind.additionalSessionDirectories = Self.decodeAdditionalDirectories(c, name: displayName, notes: notes)
        }
        let storedIcon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        icon = storedIcon.isEmpty ? IconDefaults.defaultIcon(for: kind) : storedIcon
    }

    /// Harness, session kind and condition of a token-based account (spec
    /// 038 FR-010, FR-011, research R7, contracts/configuration.md). The
    /// first form present decides: `sessionKind` (written since the rework),
    /// then `matchRule` (spec 037 and the first spec 038 builds), then
    /// `provider` with a non-blank `customMarker` (v0.8.0, never the stored
    /// `harness`, which said `claudeCode` for every account then). With
    /// `sessionKind` or `matchRule`, `harness` missing means Claude Code and
    /// an unknown value throws, as does an unknown `provider`. An unreadable
    /// setting gives the harness's fallback kind without a condition. Each
    /// migrated or unreadable account gets one load note.
    private static func decodeSessions(_ c: KeyedDecodingContainer<CodingKeys>, marker: String?, name: String,
                                       notes: ConfigurationLoadNotes?) throws
        -> (harness: Harness, kind: SessionKind, condition: MatchCondition?) {
        let account = "account \"\(Configuration.clipped(name))\""
        func unreadable(_ harness: Harness) -> (harness: Harness, kind: SessionKind, condition: MatchCondition?) {
            let fallback = SessionKind.fallback(for: harness)
            notes?.append("\(account): which sessions count could not be read; it counts \(fallback.displayName) until you choose in Settings")
            return (harness, fallback, nil)
        }
        // Kept as written so the user can correct it in Settings; it
        // matches no record (spec 038 FR-008, research R7).
        func notingPattern(_ condition: MatchCondition?) -> MatchCondition? {
            if condition?.patternProblem != nil {
                notes?.append("\(account): the regular expression of the condition is not valid; it matches no usage until you correct it in Settings")
            }
            return condition
        }
        if c.contains(.sessionKind) {
            let harness = try c.decodeIfPresent(Harness.self, forKey: .harness) ?? .claudeCode
            guard let stored = try? c.decode(String.self, forKey: .sessionKind),
                  let kind = SessionKind.kind(stored: stored, harness: harness) else { return unreadable(harness) }
            guard c.contains(.condition) else { return (harness, kind, nil) }
            guard kind.offersCondition else {
                notes?.append("condition of \(account) does not apply to Directory only, ignored")
                return (harness, kind, nil)
            }
            guard let condition = (try? c.decode(StoredCondition.self, forKey: .condition))?.condition(for: harness) else {
                return unreadable(harness)
            }
            return (harness, kind, notingPattern(condition))
        }
        if c.contains(.matchRule) {
            let harness = try c.decodeIfPresent(Harness.self, forKey: .harness) ?? .claudeCode
            guard let migrated = (try? c.decode(StoredMatchRule.self, forKey: .matchRule))?.migrated(for: harness) else {
                return unreadable(harness)
            }
            let with = migrated.condition == nil ? "" : " with a condition"
            notes?.append("\(account): match rule migrated to sessions \(migrated.kind.displayName)\(with)")
            return (harness, migrated.kind, notingPattern(migrated.condition))
        }
        let provider = try c.decodeIfPresent(LegacyProvider.self, forKey: .provider) ?? .vertex
        let harness = provider.harness
        let kind = provider.sessionKind
        var condition: MatchCondition?
        var line = "\(account) migrated from provider \(provider.rawValue) to \(harness.displayName), sessions \(kind.displayName)"
        if let marker, !MatchCondition.isBlank(marker) {
            condition = MatchCondition(field: .anywhere, operator: .contains, text: marker)
            // A v0.8.0 marker matched any record; as a condition of the
            // Vertex kind it misses gateway records (spec 038 FR-011).
            if kind == .claudeCodeVertex {
                line += "; its marker became the condition \"Anywhere contains \(Configuration.clipped(marker))\" of Vertex sessions, a company gateway needs Other provider"
            }
        }
        notes?.append(line)
        return (harness, kind, condition)
    }

    /// The `additionalSessionDirectories` key of any account kind (spec 035
    /// FR-001, FR-006, FR-007, contracts/configuration.md): entries trimmed,
    /// blank entries dropped silently, refused entries dropped with one load
    /// note each; a value that is not a list of strings (including null) is
    /// ignored with one load note. None of them makes the configuration
    /// invalid, and nothing dropped is written back.
    private static func decodeAdditionalDirectories(_ c: KeyedDecodingContainer<CodingKeys>, name: String,
                                                    notes: ConfigurationLoadNotes?) -> [String] {
        guard c.contains(.additionalSessionDirectories) else { return [] }
        let account = "account \"\(Configuration.clipped(name))\""
        guard let entries = try? c.decode([String].self, forKey: .additionalSessionDirectories) else {
            notes?.append("additionalSessionDirectories of \(account) is not readable, ignored")
            return []
        }
        let paths = Paths()
        return entries.compactMap { raw -> String? in
            guard let entry = AccountDirectory.trimmed(raw) else { return nil }
            if let refusal = SessionDirectoryEntry.refusal(of: entry, in: .account, paths: paths) {
                notes?.append("additionalSessionDirectories entry \"\(Configuration.clipped(entry))\" of \(account) is refused (\(refusal.reason)), ignored")
                return nil
            }
            return entry
        }
    }

    /// The `headlineWindow` key of a Claude or Codex subscription account
    /// (spec 027 FR-010, contracts/config-file.md): absent is the default
    /// window; a value that is not a string (including null), names no
    /// known window or one of the other account kind is the default window
    /// with a load note for the diagnostic log, never a configuration error.
    private static func decodeHeadline(_ c: KeyedDecodingContainer<CodingKeys>, forCodex: Bool,
                                       notes: ConfigurationLoadNotes?) -> HeadlineChoice? {
        guard c.contains(.headlineWindow) else { return nil }
        guard let raw = (try? c.decodeIfPresent(String.self, forKey: .headlineWindow)) ?? nil else {
            notes?.append("headlineWindow is not readable, using the default window")
            return nil
        }
        if let choice = HeadlineChoice.parse(raw, forCodex: forCodex) { return choice }
        if HeadlineChoice.parse(raw, forCodex: !forCodex) != nil {
            let kind = forCodex ? "a Codex subscription" : "a Claude subscription"
            notes?.append("headlineWindow \"\(Configuration.clipped(raw))\" does not belong to \(kind) account, using the default window")
        } else {
            notes?.append("headlineWindow \"\(Configuration.clipped(raw))\" is not known, using the default window")
        }
        return nil
    }

    /// The session directory key of a token-based account (spec 034 FR-007,
    /// research R5, spec 037 contracts/configuration.md): the harness's own
    /// key is read leniently, a value that is not a string (including null)
    /// is ignored with a load note, a blank one is no directory without a
    /// note; the other harness's key, and any directory key on an OpenCode
    /// account, is ignored with a load note. None of them makes the
    /// configuration invalid.
    private static func decodeSessionDirectory(_ c: KeyedDecodingContainer<CodingKeys>, harness: Harness, name: String,
                                               notes: ConfigurationLoadNotes?) -> String? {
        let ownKey = sessionDirectoryKey(for: harness)
        let account = "account \"\(Configuration.clipped(name))\""
        var directory: String?
        if let ownKey, c.contains(ownKey) {
            if let value = (try? c.decodeIfPresent(String.self, forKey: ownKey)) ?? nil {
                directory = AccountDirectory.isBlank(value) ? nil : value
            } else {
                notes?.append("\(ownKey.stringValue) of \(account) is not readable, ignored")
            }
        }
        for other in Harness.allCases where other != harness {
            guard let otherKey = sessionDirectoryKey(for: other), c.contains(otherKey) else { continue }
            let article = harness == .openCode ? "an" : "a"
            notes?.append("\(otherKey.stringValue) of \(account) does not belong to \(article) \(harness.displayName) account, ignored")
        }
        return directory
    }

    /// The coding key named by `Harness.sessionDirectoryKey`, so the file
    /// format has one source (spec 034 FR-007); nil for OpenCode.
    private static func sessionDirectoryKey(for harness: Harness) -> CodingKeys? {
        guard let name = harness.sessionDirectoryKey else { return nil }
        guard let key = CodingKeys(stringValue: name) else {
            preconditionFailure("Harness.sessionDirectoryKey \(name) is no account key")
        }
        return key
    }

    /// Never writes `label` (spec 004 FR-007). Writes `headlineWindow`
    /// only when a window is chosen (spec 027 FR-010), a token-based
    /// account's session directory only under its harness's key and only
    /// when it is not blank (spec 034 FR-007), and the additional session
    /// directories only when one is not blank (spec 035 FR-001). A
    /// token-based account gets `harness`, `sessionKind` and, when it
    /// counts, `condition`; never `matchRule`, `provider` or `customMarker`
    /// (spec 038 FR-010).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.typeName, forKey: .type)
        try c.encode(icon, forKey: .icon)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(harness, forKey: .harness)
        if kind.tokenBased == nil {
            try c.encode(customMarker, forKey: .customMarker)
        }
        try c.encode(timeFormat, forKey: .timeFormat)
        switch kind {
        case .subscription(let s):
            // Written as entered: a blank entry stays blank in the file
            // (spec 034 FR-006a).
            try c.encode(s.enteredCredentialDirectory, forKey: .credentialDirectory)
            try c.encode(s.shownInBar, forKey: .shownInBar)
            try c.encode(s.thresholds, forKey: .thresholds)
            try c.encodeIfPresent(s.headlineWindow?.stored, forKey: .headlineWindow)
        case .tokenBased(let t):
            switch t.membership {
            case .group(let groupId, let shownInBar):
                try c.encode(groupId, forKey: .groupId)
                try c.encode(shownInBar, forKey: .shownInBar)
            case .ownBudget(let budget):
                try c.encode(budget, forKey: .budget)
            }
            try c.encode(t.sessionKind.storedValue, forKey: .sessionKind)
            try c.encodeIfPresent(t.effectiveCondition.map(StoredCondition.init), forKey: .condition)
            // Written as entered, like the subscription fields, unless blank.
            if let key = Self.sessionDirectoryKey(for: t.harness) {
                let entered = t.enteredSessionDirectory.flatMap { AccountDirectory.isBlank($0) ? nil : $0 }
                try c.encodeIfPresent(entered, forKey: key)
            }
        case .codexSubscription(let settings):
            try c.encode(settings.enteredCodexHome, forKey: .codexHome)
            try c.encode(settings.shownInBar, forKey: .shownInBar)
            try c.encode(settings.thresholds, forKey: .thresholds)
            try c.encode(settings.liveLimits, forKey: .liveLimits)
            try c.encodeIfPresent(settings.headlineWindow?.stored, forKey: .headlineWindow)
        }
        // Trimmed, non-blank entries in order, and the key only when there
        // is one (spec 035 FR-001); never for OpenCode (spec 037 FR-006).
        let additional = kind.additionalSessionDirectories.compactMap { AccountDirectory.trimmed($0) }
        if !additional.isEmpty && harness != .openCode {
            try c.encode(additional, forKey: .additionalSessionDirectories)
        }
    }

    /// The account's directory for `harness`, unexpanded: the effective
    /// Claude Code directory of a Claude subscription, the effective Codex
    /// home of a Codex subscription, or the session directory of a Claude
    /// Code or Codex token-based account, where an empty field means the
    /// default (`~/.claude`, `~/.codex`); nil for an account of another
    /// agent and for OpenCode. The session scanners read exactly these
    /// directories, and the legacy load notes compare with them (spec 034
    /// FR-008, FR-011, spec 037 FR-006).
    public func agentDirectory(for harness: Harness) -> String? {
        switch (harness, kind) {
        case (.claudeCode, .subscription(let settings)): return settings.credentialDirectory
        case (.codex, .codexSubscription(let settings)): return settings.codexHome
        case (_, .tokenBased(let settings)) where settings.harness == harness:
            return settings.effectiveSessionDirectory
        default: return nil
        }
    }
}

/// The `condition` object of the configuration file (spec 038 FR-010,
/// contracts/configuration.md): `{"field":F,"operator":O,"text":T}`.
struct StoredCondition: Codable, Equatable {
    var field: String?
    var `operator`: String?
    var text: String?

    init(_ condition: MatchCondition) {
        field = condition.field.storedValue
        self.operator = condition.operator.storedValue
        text = condition.text
    }

    /// The condition for an account of `harness`, nil when it cannot be
    /// read: a field unknown or not offered for the harness, an unknown
    /// operator, or a blank or missing text. A missing operator is the
    /// field's default, and starts with on Anywhere reads as contains
    /// (spec 038 FR-011, research R7).
    func condition(for harness: Harness) -> MatchCondition? {
        guard let field = field.flatMap(MatchField.init(rawValue:)), MatchField.fields(for: harness).contains(field),
              let text, !MatchCondition.isBlank(text) else { return nil }
        var op = MatchOperator.default(for: field)
        if let stored = self.operator {
            guard let known = MatchOperator(rawValue: stored) else { return nil }
            op = known
        }
        return MatchCondition(field: field, operator: op, text: text).withField(field)
    }
}

/// The `matchRule` object of spec 037 and the first spec 038 builds, read
/// only (spec 038 FR-011): `{"type":"preset","preset":P}`,
/// `{"type":"custom","field":F,"operator":O,"text":T}` or `{"type":"none"}`.
struct StoredMatchRule: Decodable, Equatable {
    var type: String
    var preset: String?
    var field: String?
    var `operator`: String?
    var text: String?

    /// The kind and condition for an account of `harness`, nil when the
    /// rule cannot be read: a preset becomes its kind; `none` becomes
    /// Directory only for Claude Code and API key for Codex, and is
    /// unreadable for OpenCode; a custom rule becomes Claude Code Other
    /// provider, Codex API key or OpenCode Other provider with its field,
    /// operator and text as the condition (spec 038 FR-011, research R7).
    func migrated(for harness: Harness) -> (kind: SessionKind, condition: MatchCondition?)? {
        switch type {
        case "preset":
            return preset.flatMap { SessionKind.kind(stored: $0, harness: harness) }.map { ($0, nil) }
        case "custom":
            guard let condition = StoredCondition(field: field, operator: self.operator, text: text).condition(for: harness) else { return nil }
            switch harness {
            case .claudeCode: return (.claudeCodeOtherProvider, condition)
            case .codex: return (.codexAPIKey, condition)
            case .openCode: return (.openCodeOtherProvider, condition)
            }
        case "none":
            switch harness {
            case .claudeCode: return (.claudeCodeDirectoryOnly, nil)
            case .codex: return (.codexAPIKey, nil)
            case .openCode: return nil
            }
        default:
            return nil
        }
    }
}

extension StoredCondition {
    init(field: String?, operator op: String?, text: String?) {
        self.field = field
        self.operator = op
        self.text = text
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
    /// How the group's section reads its reset and run-out times in the
    /// dropdown (spec 025 FR-016, FR-021).
    public var timeFormat: TimeFormat

    public init(id: String = UUID().uuidString, name: String, icon: String = IconDefaults.group, period: BudgetPeriod = .weekly, budgetUSD: Decimal,
                shownInBar: Bool = true, thresholds: [Int] = [], timeFormat: TimeFormat = .relative) {
        self.id = id
        self.name = name
        self.icon = icon
        self.period = period
        self.budgetUSD = budgetUSD
        self.shownInBar = shownInBar
        self.thresholds = thresholds
        self.timeFormat = timeFormat
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
        case id, name, icon, period, budgetUSD, shownInBar, thresholds, timeFormat
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
        timeFormat = c.decodeTimeFormat(forKey: .timeFormat,
                                        notes: decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes)
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
        try c.encode(timeFormat, forKey: .timeFormat)
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
    // The global `logDirectories` and `codexHomes` lists are gone: Claude
    // Code directories and Codex homes are set per account (spec 034
    // FR-010, FR-012). Their entries only leave load notes.
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
    /// How the bar colors entries at a level (spec 012 FR-001). Text when
    /// absent; an unreadable value also falls back to Text (FR-003).
    public var levelColor: LevelColorStyle
    /// Whether the bar shows the `⚠` and `‼` glyphs (spec 012 FR-002).
    public var showLevelSymbols: Bool
    /// Whether bar entries projected to run out before their reset carry
    /// the marker (spec 011 FR-014). Presentation only; true when absent.
    public var showsRunOutMarker: Bool
    /// Whether a sign-in that stops working is notified (spec 014 FR-012).
    /// Presentation only; true when absent.
    public var notifySignInProblems: Bool
    /// Whether a free limit reset about to expire is notified (spec 033
    /// FR-017). Presentation only; true when absent.
    public var notifyFreeResetExpiry: Bool
    /// Whether AgentTacho checks GitHub for a newer release on its own
    /// (spec 013 FR-002). On when absent; read leniently (research R12).
    public var checksForUpdates: Bool
    /// Whether the refresh pace adapts to agent activity, idle, Low Power
    /// Mode and thermal pressure (spec 016 FR-001). On when absent; a value
    /// that is not a boolean also behaves as on and leaves a load note.
    /// The README's Configuration and "Security and privacy" sections
    /// describe it and the request frequency it leads to (FR-018).
    public var adaptiveRefresh: Bool
    /// Whether level values read as used or as remaining (spec 030 FR-008).
    /// Used when absent; an unreadable value also falls back to used.
    /// Presentation only: thresholds stay stored in used percent (FR-015).
    public var displayDirection: DisplayDirection
    /// The stored dropdown theme, nil for Auto, so Auto writes no key
    /// (spec 032 FR-003, research R2). Read and set through `dropdownTheme`.
    private var dropdownThemeValue: DropdownTheme?

    /// The dropdown's theme (spec 032 FR-001, FR-003). Auto when absent; an
    /// unreadable value also falls back to Auto. Setting Auto stores nothing,
    /// so the configuration equals one that never had a theme.
    public var dropdownTheme: DropdownTheme {
        get { dropdownThemeValue ?? .auto }
        set { dropdownThemeValue = newValue == .auto ? nil : newValue }
    }

    public init(version: Int = Configuration.currentVersion,
                refreshIntervalSeconds: Int = Configuration.defaultRefreshIntervalSeconds,
                openCodeDirectories: [String] = [],
                weekFallback: WeekFallback = .monday,
                alignmentAccountId: String? = nil,
                startAtLogin: Bool = false,
                accounts: [Account] = [],
                groups: [BudgetGroup] = [],
                priceOverrides: [PriceEntry] = [],
                arrangement: Arrangement? = nil,
                levelColor: LevelColorStyle = .text,
                showLevelSymbols: Bool = false,
                showsRunOutMarker: Bool = true,
                notifySignInProblems: Bool = true,
                notifyFreeResetExpiry: Bool = true,
                checksForUpdates: Bool = true,
                adaptiveRefresh: Bool = true,
                displayDirection: DisplayDirection = .used,
                dropdownTheme: DropdownTheme = .auto) {
        self.version = version
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.openCodeDirectories = openCodeDirectories
        self.weekFallback = weekFallback
        self.alignmentAccountId = alignmentAccountId
        self.startAtLogin = startAtLogin
        self.accounts = accounts
        self.groups = groups
        self.priceOverrides = priceOverrides
        self.arrangement = arrangement
        self.levelColor = levelColor
        self.showLevelSymbols = showLevelSymbols
        self.showsRunOutMarker = showsRunOutMarker
        self.notifySignInProblems = notifySignInProblems
        self.notifyFreeResetExpiry = notifyFreeResetExpiry
        self.checksForUpdates = checksForUpdates
        self.adaptiveRefresh = adaptiveRefresh
        self.displayDirection = displayDirection
        self.dropdownTheme = dropdownTheme
    }

    /// Both level display settings (spec 012 FR-001, FR-002).
    public var levelDisplay: LevelDisplaySettings {
        LevelDisplaySettings(levelColor: levelColor, showSymbols: showLevelSymbols)
    }

    public static let `default` = Configuration()

    private enum CodingKeys: String, CodingKey {
        case version, refreshIntervalSeconds, openCodeDirectories, weekFallback, alignmentAccountId, startAtLogin, accounts, groups, priceOverrides
        case arrangement
        case levelColor, showLevelSymbols
        case showsRunOutMarker
        case notifySignInProblems
        case notifyFreeResetExpiry
        case checksForUpdates
        case adaptiveRefresh
        case displayDirection
        case dropdownThemeValue = "dropdownTheme"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Configuration.currentVersion
        refreshIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? Configuration.defaultRefreshIntervalSeconds
        // The type check is unchanged; refused entries are dropped after it,
        // noted when notes are collected (spec 035 FR-006, FR-013).
        openCodeDirectories = Self.droppingRefusedOpenCodeEntries(
            try c.decodeIfPresent([String].self, forKey: .openCodeDirectories) ?? [],
            notes: decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes)
        weekFallback = try c.decodeIfPresent(WeekFallback.self, forKey: .weekFallback) ?? .monday
        alignmentAccountId = try c.decodeIfPresent(String.self, forKey: .alignmentAccountId)
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        // After the accounts, so a note can name the account that covers an
        // entry (spec 034 FR-011, research R6).
        if let notes = decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes {
            try Self.noteDirectories(decoder, accounts: accounts, notes: notes)
        }
        groups = try c.decodeIfPresent([BudgetGroup].self, forKey: .groups) ?? []
        priceOverrides = try c.decodeIfPresent([PriceEntry].self, forKey: .priceOverrides) ?? []
        // An arrangement that cannot be read at all is treated as absent:
        // its problems are never a configuration error (spec 008 FR-011).
        arrangement = (try? c.decodeIfPresent(Arrangement.self, forKey: .arrangement)) ?? nil
        levelColor = Self.decodeLevelColor(c, notes: decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes)
        // A wrong type is a decoding error, like `startAtLogin` (spec 012 FR-002).
        showLevelSymbols = try c.decodeIfPresent(Bool.self, forKey: .showLevelSymbols) ?? false
        // Configurations from before spec 011 keep the marker on (FR-014).
        showsRunOutMarker = try c.decodeIfPresent(Bool.self, forKey: .showsRunOutMarker) ?? true
        // Configurations from before spec 014 notify (FR-012).
        notifySignInProblems = try c.decodeIfPresent(Bool.self, forKey: .notifySignInProblems) ?? true
        // Configurations from before spec 033 notify (FR-017).
        notifyFreeResetExpiry = try c.decodeIfPresent(Bool.self, forKey: .notifyFreeResetExpiry) ?? true
        // A value that is not a boolean never breaks loading (spec 013 FR-002).
        checksForUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .checksForUpdates)) ?? true
        adaptiveRefresh = Self.decodeAdaptiveRefresh(c, notes: decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes)
        displayDirection = Self.decodeDisplayDirection(c, notes: decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes)
        dropdownThemeValue = Self.decodeDropdownTheme(c, notes: decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes)
    }

    /// Each entry of `logDirectories` and `codexHomes` leaves one load note
    /// and is not read; a value that is not a list of strings leaves one
    /// note for the key. No value makes the configuration invalid (spec 034
    /// FR-011, contracts/configuration.md "Load notes"). The keys are not
    /// `CodingKeys`, so the synthesized encoder never writes them (FR-012).
    /// A blank subscription directory that shares its default with another
    /// account gets a note too (FR-006a).
    private static func noteDirectories(_ decoder: Decoder, accounts: [Account], notes: ConfigurationLoadNotes) throws {
        let c = try decoder.container(keyedBy: LegacyDirectoryKey.self)
        let paths = Paths()
        for key in LegacyDirectoryKey.allCases where c.contains(key) {
            let entries = try? c.decode([String].self, forKey: key)
            for note in LegacyDirectoryNotes.notes(key: key, entries: entries, accounts: accounts, paths: paths) {
                notes.append(note)
            }
        }
        for shared in Configuration(accounts: accounts).blankDirectoriesOnSharedDefault(paths: paths) {
            notes.append(shared.note)
        }
    }

    /// The OpenCode entries `SessionDirectoryEntry` accepts; literal relative
    /// entries keep their spec 006 behavior (spec 035 FR-006, FR-013).
    private static func droppingRefusedOpenCodeEntries(_ entries: [String], notes: ConfigurationLoadNotes?) -> [String] {
        let paths = Paths()
        return entries.filter { entry in
            guard let refusal = SessionDirectoryEntry.refusal(of: entry, in: .openCode, paths: paths) else { return true }
            notes?.append("openCodeDirectories entry \"\(clipped(entry))\" is refused (\(refusal.reason)), ignored")
            return false
        }
    }

    /// Like the display direction (spec 030 FR-008): a missing key or
    /// `"auto"` is Auto (stored nil) without a note; an unknown, wrong-case
    /// or non-string (including null) value is Auto too and leaves a note for
    /// the diagnostic log; it never makes the configuration invalid (spec 032
    /// FR-003).
    private static func decodeDropdownTheme(_ c: KeyedDecodingContainer<CodingKeys>, notes: ConfigurationLoadNotes?) -> DropdownTheme? {
        guard c.contains(.dropdownThemeValue) else { return nil }
        guard let raw = (try? c.decodeIfPresent(String.self, forKey: .dropdownThemeValue)) ?? nil else {
            notes?.append("dropdownTheme is not readable, using auto")
            return nil
        }
        guard let theme = DropdownTheme(rawValue: raw) else {
            notes?.append("dropdownTheme \"\(Self.clipped(raw))\" is not known, using auto")
            return nil
        }
        return theme == .auto ? nil : theme
    }

    /// Like the level color (spec 012 FR-003): a missing key is used; an
    /// unknown, wrong-case or non-string (including null) value is used too
    /// and leaves a note for the diagnostic log; it never makes the
    /// configuration invalid (spec 030 FR-008).
    private static func decodeDisplayDirection(_ c: KeyedDecodingContainer<CodingKeys>, notes: ConfigurationLoadNotes?) -> DisplayDirection {
        guard c.contains(.displayDirection) else { return .used }
        guard let raw = (try? c.decodeIfPresent(String.self, forKey: .displayDirection)) ?? nil else {
            notes?.append("displayDirection is not readable, using used")
            return .used
        }
        guard let direction = DisplayDirection(rawValue: raw) else {
            notes?.append("displayDirection \"\(Self.clipped(raw))\" is not known, using used")
            return .used
        }
        return direction
    }

    /// Unlike other booleans (spec 012 FR-002), a value that is not a
    /// boolean (including null) behaves as on and leaves a note for the
    /// diagnostic log; it never makes the configuration invalid (spec 016
    /// FR-001, research R10).
    private static func decodeAdaptiveRefresh(_ c: KeyedDecodingContainer<CodingKeys>, notes: ConfigurationLoadNotes?) -> Bool {
        guard c.contains(.adaptiveRefresh) else { return true }
        guard let value = (try? c.decodeIfPresent(Bool.self, forKey: .adaptiveRefresh)) ?? nil else {
            notes?.append("adaptiveRefresh is not a boolean, using true")
            return true
        }
        return value
    }

    /// An unknown, wrong-case or non-string (including null) level color
    /// falls back to Text and leaves a note for the diagnostic log; it never
    /// makes the configuration invalid (spec 012 FR-003, research R4).
    private static func decodeLevelColor(_ c: KeyedDecodingContainer<CodingKeys>, notes: ConfigurationLoadNotes?) -> LevelColorStyle {
        guard c.contains(.levelColor) else { return .text }
        guard let raw = (try? c.decodeIfPresent(String.self, forKey: .levelColor)) ?? nil else {
            notes?.append("levelColor is not readable, using text")
            return .text
        }
        guard let style = LevelColorStyle(rawValue: raw) else {
            notes?.append("levelColor \"\(Self.clipped(raw))\" is not known, using text")
            return .text
        }
        return style
    }

    /// At most 32 characters of a free-form value for a log note, so a
    /// stray long string never lands in the diagnostic log whole (spec 012
    /// FR-003). Public for the app's log line of a headline click (spec
    /// 027 FR-010).
    public static func clipped(_ value: String, limit: Int = 32) -> String {
        value.count > limit ? String(value.prefix(limit)) + "..." : value
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

    /// The Claude Code directory of every Claude account, in accounts order
    /// and unexpanded: the effective directory of each Claude subscription
    /// and of each token-based Claude Code account, `~/.claude` for an empty
    /// field (spec 034 FR-008, spec 037 FR-006).
    public var accountClaudeCodeDirectories: [String] {
        accounts.compactMap { $0.agentDirectory(for: .claudeCode) }
    }

    /// The Codex home of every Codex account, in accounts order and
    /// unexpanded: the effective home of each Codex subscription and of each
    /// token-based Codex account, `~/.codex` for an empty field (spec 034
    /// FR-008, spec 037 FR-006).
    public var accountCodexHomes: [String] {
        accounts.compactMap { $0.agentDirectory(for: .codex) }
    }

    /// The additional session directory entries of every account whose
    /// sessions are of `harness`, in accounts order and list order,
    /// unexpanded and trimmed; blank entries are left out. A token-based
    /// account's entries count for its harness (spec 035 FR-001, FR-008,
    /// spec 037 FR-006).
    public func additionalSessionEntries(for harness: Harness) -> [AdditionalSessionEntry] {
        accounts.flatMap { account -> [AdditionalSessionEntry] in
            guard account.kind.sessionHarness == harness else { return [] }
            let joinsTieBreak = account.kind.tokenBased == nil
            return account.kind.additionalSessionDirectories.compactMap { entry in
                AccountDirectory.trimmed(entry).map { AdditionalSessionEntry(accountId: account.id, entry: $0, joinsTieBreak: joinsTieBreak) }
            }
        }
    }

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
                // A blank entry reads `~/.claude` (spec 034 FR-006a) but is
                // compared as entered, as before spec 034, so a file that
                // loaded before still loads; two blank entries still
                // collide, and the load notes name a blank entry that shares
                // `~/.claude` with another account. The message uses the
                // field's label (FR-006).
                let dir = AccountDirectory.isBlank(s.enteredCredentialDirectory) ? "" : paths.expand(s.credentialDirectory)
                if !seenDirectories.insert(dir).inserted {
                    throw ConfigurationError(kind: .duplicateCredentialDirectory,
                                             message: "Claude Code directory \"\(s.credentialDirectory)\" is used by more than one Claude subscription account.")
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
                // A condition that counts needs a text (spec 038 FR-008,
                // research R14).
                if t.effectiveCondition?.hasBlankText == true {
                    throw ConfigurationError(kind: .condition,
                                             message: "Account \"\(account.displayName)\": the condition needs a text")
                }
            case .codexSubscription(let settings):
                // Mirrors the credential directory rule (spec 006 FR-015, research R9).
                // Compared canonically, as the Codex limits source keys its
                // per-sign-in state, so a symlink or `..` alias of a home
                // counts as the same home (spec 007 FR-003, FR-007).
                // A blank entry is compared as entered, like a blank Claude
                // Code directory (spec 034 FR-006a).
                let home = AccountDirectory.isBlank(settings.enteredCodexHome) ? "" : Attributor.canonical(paths.expand(settings.codexHome))
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
        try checkSessionDirectoryEntries(paths: paths)
    }

    /// `validate()` plus the checks that every condition's regex compiles
    /// and that an OpenCode Other provider account has a condition: the
    /// save path of Settings and the new account sheet. Loading and
    /// `ConfigStore.update` keep `validate()`, so such a file still loads
    /// (spec 038 FR-008, edge case "OpenCode Other provider without a
    /// condition", research R14).
    public func validateForSaving() throws {
        try validate()
        for account in accounts {
            guard let settings = account.kind.tokenBased else { continue }
            // Only the fields and operators the Condition row offers for
            // the harness (spec 038 FR-004, FR-005).
            if let condition = settings.effectiveCondition, !condition.isOffered(for: settings.harness) {
                throw ConfigurationError(kind: .condition,
                                         message: "Account \"\(account.displayName)\": the condition's field or operator does not apply to \(settings.harness.displayName)")
            }
            if settings.effectiveCondition?.patternProblem != nil {
                throw ConfigurationError(kind: .condition,
                                         message: "Account \"\(account.displayName)\": the regular expression is not valid")
            }
            if settings.sessionKind.requiresCondition && settings.effectiveCondition == nil {
                throw ConfigurationError(kind: .condition,
                                         message: "Account \"\(account.displayName)\": the condition needs a text")
            }
        }
    }

    /// The first refused entry, in accounts order and then the OpenCode
    /// list, with its unclipped text (spec 035 FR-006, contracts/configuration.md
    /// "Settings refusal"). String work only: no file system access.
    private func checkSessionDirectoryEntries(paths: Paths) throws {
        for account in accounts {
            for entry in account.kind.additionalSessionDirectories.compactMap({ AccountDirectory.trimmed($0) }) {
                if let refusal = SessionDirectoryEntry.refusal(of: entry, in: .account, paths: paths) {
                    throw ConfigurationError(kind: .sessionDirectoryEntry,
                                             message: "Additional session directory \"\(entry)\" of account \"\(account.displayName)\": \(refusal.reason).")
                }
            }
        }
        for entry in openCodeDirectories {
            if let refusal = SessionDirectoryEntry.refusal(of: entry, in: .openCode, paths: paths) {
                throw ConfigurationError(kind: .sessionDirectoryEntry,
                                         message: "OpenCode data directory \"\(entry)\": \(refusal.reason).")
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
        // How levels are shown is presentation only (spec 012 FR-004).
        copy.levelColor = .text
        copy.showLevelSymbols = false
        // The run-out marker is presentation only (spec 011 FR-014).
        copy.showsRunOutMarker = true
        // The credential notification switch is presentation only (spec 014
        // FR-012, research R5).
        copy.notifySignInProblems = true
        // The free reset expiry switch is presentation only (spec 033 FR-017).
        copy.notifyFreeResetExpiry = true
        // The update check is not about usage data (spec 013 FR-002).
        copy.checksForUpdates = true
        // The refresh pace changes when the endpoints are called, not what
        // a refresh computes; the app re-arms its timer (spec 016 research R10).
        copy.adaptiveRefresh = true
        // The display direction is presentation only (spec 030 FR-008).
        copy.displayDirection = .used
        // The dropdown theme is presentation only (spec 032 FR-003).
        copy.dropdownTheme = .auto
        for index in copy.accounts.indices {
            copy.accounts[index].icon = ""
            copy.accounts[index].displayName = ""
            // How times read is presentation only (spec 025 FR-022).
            copy.accounts[index].timeFormat = .relative
            switch copy.accounts[index].kind {
            case .subscription(var settings):
                settings.shownInBar = true
                settings.thresholds = []
                // The headline window is presentation only (spec 027 FR-011).
                settings.headlineWindow = nil
                // A blank entry reads the same directory as `~/.claude`
                // (spec 034 FR-006a, research R9).
                settings.enteredCredentialDirectory = settings.credentialDirectory
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
                // Whitespace reads no directory, like an empty field; a new
                // directory stays data relevant (spec 034 research R9).
                settings.enteredSessionDirectory = settings.sessionDirectory
                copy.accounts[index].kind = .tokenBased(settings)
            case .codexSubscription(var settings):
                // Bar visibility and thresholds are presentation only; the
                // live-limits setting changes what a refresh fetches (spec 007
                // research R9).
                settings.shownInBar = true
                settings.thresholds = []
                settings.headlineWindow = nil
                settings.enteredCodexHome = settings.codexHome
                copy.accounts[index].kind = .codexSubscription(settings)
            }
        }
        for index in copy.groups.indices {
            copy.groups[index].icon = ""
            copy.groups[index].name = ""
            copy.groups[index].timeFormat = .relative
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

    // MARK: Headline window (spec 027)

    /// Stores the headline window a click in the dropdown chose for the
    /// subscription account `accountId`; nil or `claudeSevenDay` (the
    /// default window) clears the choice (spec 027 FR-001, FR-010, research
    /// R6). A choice of the other account kind, a token-based account and
    /// an unknown id leave the configuration unchanged.
    public func settingHeadline(_ choice: HeadlineChoice?, accountId: String) -> Configuration {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }) else { return self }
        var copy = self
        switch accounts[index].kind {
        case .subscription(var settings):
            if let choice, choice.claudeWindow == nil { return self }
            settings.headlineWindow = choice == .claudeSevenDay ? nil : choice
            copy.accounts[index].kind = .subscription(settings)
        case .codexSubscription(var settings):
            if let choice, choice.claudeWindow != nil { return self }
            settings.headlineWindow = choice
            copy.accounts[index].kind = .codexSubscription(settings)
        case .tokenBased:
            return self
        }
        return copy
    }

    /// This configuration with each subscription account's headline window
    /// taken from the account with the same id in `current`, so a Settings
    /// draft taken before a click in the dropdown keeps that click when it
    /// is applied (spec 027 FR-010, research R7). Accounts missing in
    /// `current` keep their own value.
    public func keepingHeadlineChoices(of current: Configuration) -> Configuration {
        var copy = self
        for index in copy.accounts.indices {
            guard let other = current.account(id: copy.accounts[index].id) else { continue }
            switch (copy.accounts[index].kind, other.kind) {
            case (.subscription(var settings), .subscription(let currentSettings)):
                settings.headlineWindow = currentSettings.headlineWindow
                copy.accounts[index].kind = .subscription(settings)
            case (.codexSubscription(var settings), .codexSubscription(let currentSettings)):
                settings.headlineWindow = currentSettings.headlineWindow
                copy.accounts[index].kind = .codexSubscription(settings)
            default:
                continue
            }
        }
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
        /// A refused entry of an additional session directory list or of the
        /// OpenCode list (spec 035 FR-006).
        case sessionDirectoryEntry
        /// A condition without a text, or with a regular expression that
        /// is not valid (spec 038 FR-008).
        case condition
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
