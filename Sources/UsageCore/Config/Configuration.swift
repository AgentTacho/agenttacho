import Foundation

// MARK: - Enumerations

/// The harness that produced the usage. Open for later additions (FR-017).
public enum Harness: String, Codable, Sendable, CaseIterable {
    case claudeCode
}

/// Provider behind a token-based account. Selects the built-in detection rule.
public enum Provider: String, Codable, Sendable, CaseIterable {
    case vertex
}

/// Where an effective price comes from (FR-005).
public enum PriceSource: Equatable, Sendable {
    case builtIn
    case imported(ImportProvenance)
    case override
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

public struct TokenBasedSettings: Codable, Equatable, Sendable {
    public var groupId: String
    public var provider: Provider

    public init(groupId: String, provider: Provider = .vertex) {
        self.groupId = groupId
        self.provider = provider
    }
}

public enum AccountKind: Equatable, Sendable {
    case subscription(SubscriptionSettings)
    case tokenBased(TokenBasedSettings)

    public var typeName: String {
        switch self {
        case .subscription: return "subscription"
        case .tokenBased: return "tokenBased"
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
}

// MARK: - Account

public struct Account: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// Text label, 1 to 3 characters; may be empty when an icon is set.
    public var label: String
    /// Optional Font Awesome icon as `"style:name"` (for example
    /// `"brands:claude"`), shown instead of the text label when set.
    public var icon: String?
    public var displayName: String
    public var harness: Harness
    public var kind: AccountKind
    public var customMarker: String?

    public init(id: String = UUID().uuidString, label: String, icon: String? = nil, displayName: String, harness: Harness = .claudeCode, kind: AccountKind, customMarker: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.displayName = displayName
        self.harness = harness
        self.kind = kind
        self.customMarker = customMarker
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, label, icon, displayName, harness, customMarker
        case credentialDirectory, shownInBar, thresholds
        case groupId, provider
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
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
            kind = .tokenBased(TokenBasedSettings(
                groupId: try c.decode(String.self, forKey: .groupId),
                provider: try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .vertex))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown account type \"\(type)\"; expected subscription or tokenBased")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.typeName, forKey: .type)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(harness, forKey: .harness)
        try c.encode(customMarker, forKey: .customMarker)
        switch kind {
        case .subscription(let s):
            try c.encode(s.credentialDirectory, forKey: .credentialDirectory)
            try c.encode(s.shownInBar, forKey: .shownInBar)
            try c.encode(s.thresholds, forKey: .thresholds)
        case .tokenBased(let t):
            try c.encode(t.groupId, forKey: .groupId)
            try c.encode(t.provider, forKey: .provider)
        }
    }
}

// MARK: - Budget group

public struct BudgetGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Text label, 1 to 3 characters; may be empty when an icon is set.
    public var label: String
    /// Optional Font Awesome icon as `"style:name"` (for example
    /// `"brands:claude"`), shown instead of the text label when set.
    public var icon: String?
    public var weeklyBudgetUSD: Decimal
    public var shownInBar: Bool
    public var thresholds: [Int]

    public init(id: String = UUID().uuidString, name: String, label: String, icon: String? = nil, weeklyBudgetUSD: Decimal, shownInBar: Bool = true, thresholds: [Int] = []) {
        self.id = id
        self.name = name
        self.label = label
        self.icon = icon
        self.weeklyBudgetUSD = weeklyBudgetUSD
        self.shownInBar = shownInBar
        self.thresholds = thresholds
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, label, icon, weeklyBudgetUSD, shownInBar, thresholds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        weeklyBudgetUSD = try c.decodeDecimal(forKey: .weeklyBudgetUSD)
        shownInBar = try c.decodeIfPresent(Bool.self, forKey: .shownInBar) ?? true
        thresholds = try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? []
    }
}

// MARK: - Shown label

/// What the menu bar and the dropdown show for an account or group: the
/// icon when one is set and known, otherwise the text label.
public enum LabelContent: Hashable, Sendable {
    case text(String)
    case icon(IconEntry)

    public init(text: String, icon: String?, catalog: IconCatalog = .shared) {
        if let icon, let entry = catalog.icon(for: icon) {
            self = .icon(entry)
        } else {
            self = .text(text)
        }
    }

    /// Identity used for the uniqueness rule (FR-032).
    public var key: String {
        switch self {
        case .text(let text): return text
        case .icon(let entry): return "icon:\(entry.ref)"
        }
    }

    /// Plain-text form for logs and notifications.
    public var plain: String {
        switch self {
        case .text(let text): return text
        case .icon(let entry): return entry.label
        }
    }
}

extension Account {
    public var shownLabel: LabelContent { LabelContent(text: label, icon: icon) }
}

extension BudgetGroup {
    public var shownLabel: LabelContent { LabelContent(text: label, icon: icon) }
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
    public static let maxLabelLength = 3

    public var version: Int
    public var refreshIntervalSeconds: Int
    public var logDirectories: [String]
    public var weekFallback: WeekFallback
    public var alignmentAccountId: String?
    public var startAtLogin: Bool
    public var accounts: [Account]
    public var groups: [BudgetGroup]
    public var priceOverrides: [PriceEntry]

    public init(version: Int = Configuration.currentVersion,
                refreshIntervalSeconds: Int = Configuration.defaultRefreshIntervalSeconds,
                logDirectories: [String] = [],
                weekFallback: WeekFallback = .monday,
                alignmentAccountId: String? = nil,
                startAtLogin: Bool = false,
                accounts: [Account] = [],
                groups: [BudgetGroup] = [],
                priceOverrides: [PriceEntry] = []) {
        self.version = version
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.logDirectories = logDirectories
        self.weekFallback = weekFallback
        self.alignmentAccountId = alignmentAccountId
        self.startAtLogin = startAtLogin
        self.accounts = accounts
        self.groups = groups
        self.priceOverrides = priceOverrides
    }

    public static let `default` = Configuration()

    private enum CodingKeys: String, CodingKey {
        case version, refreshIntervalSeconds, logDirectories, weekFallback, alignmentAccountId, startAtLogin, accounts, groups, priceOverrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Configuration.currentVersion
        refreshIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? Configuration.defaultRefreshIntervalSeconds
        logDirectories = try c.decodeIfPresent([String].self, forKey: .logDirectories) ?? []
        weekFallback = try c.decodeIfPresent(WeekFallback.self, forKey: .weekFallback) ?? .monday
        alignmentAccountId = try c.decodeIfPresent(String.self, forKey: .alignmentAccountId)
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        groups = try c.decodeIfPresent([BudgetGroup].self, forKey: .groups) ?? []
        priceOverrides = try c.decodeIfPresent([PriceEntry].self, forKey: .priceOverrides) ?? []
    }

    // MARK: Lookups

    public var subscriptionAccounts: [Account] { accounts.filter { $0.kind.isSubscription } }
    public var tokenBasedAccounts: [Account] { accounts.filter { !$0.kind.isSubscription } }

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

        var seenLabels = Set<String>()
        /// The text label is 1 to 3 characters, or empty when an icon is set.
        /// The icon must exist in the bundled catalog. Uniqueness applies to
        /// what is shown (FR-032).
        func checkLabel(_ label: String, icon: String?, owner: String) throws {
            let hasIcon = !(icon ?? "").isEmpty
            if let icon, hasIcon, !IconCatalog.shared.contains(icon) {
                throw ConfigurationError(kind: .invalidLabel,
                                         message: "Icon \"\(icon)\" of \(owner) is not a known Font Awesome icon (expected style:name, for example brands:claude).")
            }
            if label.count > Configuration.maxLabelLength || (label.isEmpty && !hasIcon) {
                throw ConfigurationError(kind: .invalidLabel,
                                         message: "Label \"\(label)\" of \(owner) must be 1 to \(Configuration.maxLabelLength) characters, or empty when an icon is set.")
            }
            let shown = LabelContent(text: label, icon: icon)
            if !seenLabels.insert(shown.key).inserted {
                throw ConfigurationError(kind: .duplicateLabel,
                                         message: "Label \"\(shown.plain)\" of \(owner) is already used by another account or group.")
            }
        }

        var seenDirectories = Set<String>()
        let paths = Paths()
        for account in accounts {
            try checkLabel(account.label, icon: account.icon, owner: "account \"\(account.displayName)\"")
            switch account.kind {
            case .subscription(let s):
                let dir = paths.expand(s.credentialDirectory)
                if !seenDirectories.insert(dir).inserted {
                    throw ConfigurationError(kind: .duplicateCredentialDirectory,
                                             message: "Credential directory \"\(s.credentialDirectory)\" is used by more than one subscription account.")
                }
                try checkThresholds(s.thresholds, owner: "account \"\(account.displayName)\"")
            case .tokenBased(let t):
                if group(id: t.groupId) == nil {
                    throw ConfigurationError(kind: .unknownGroup,
                                             message: "Account \"\(account.displayName)\" references unknown budget group \"\(t.groupId)\".")
                }
            }
        }
        for group in groups {
            try checkLabel(group.label, icon: group.icon, owner: "group \"\(group.name)\"")
            if group.weeklyBudgetUSD <= 0 {
                throw ConfigurationError(kind: .budget,
                                         message: "Weekly budget of group \"\(group.name)\" must be greater than 0.")
            }
            if members(of: group.id).isEmpty {
                throw ConfigurationError(kind: .emptyGroup,
                                         message: "Budget group \"\(group.name)\" has no member accounts.")
            }
            try checkThresholds(group.thresholds, owner: "group \"\(group.name)\"")
        }
        if let id = alignmentAccountId {
            guard let account = account(id: id), account.kind.isSubscription else {
                throw ConfigurationError(kind: .alignmentAccount,
                                         message: "Alignment account \"\(id)\" must be an existing subscription account.")
            }
        }
    }

    private func checkThresholds(_ thresholds: [Int], owner: String) throws {
        for t in thresholds where t <= 0 {
            throw ConfigurationError(kind: .threshold,
                                     message: "Thresholds of \(owner) must be whole-number percents greater than 0 (got \(t)).")
        }
    }

    // MARK: Group lifecycle (FR-019)

    /// Removes an account. Deletes a group when its last member goes away and
    /// clears `alignmentAccountId` when it named the removed account.
    public func removingAccount(id: String) -> Configuration {
        var copy = self
        guard let removed = account(id: id) else { return copy }
        copy.accounts.removeAll { $0.id == id }
        if let groupId = removed.kind.tokenBased?.groupId, copy.members(of: groupId).isEmpty {
            copy.groups.removeAll { $0.id == groupId }
        }
        if copy.alignmentAccountId == id {
            copy.alignmentAccountId = nil
        }
        return copy
    }

    /// True when going from `old` to this configuration changes what a
    /// refresh computes. Labels, icons, names, visibility in the bar,
    /// notification thresholds and start at login only change how existing
    /// data is shown, so the settings window applies them without a refresh
    /// (and without another request to the usage endpoint).
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
        for index in copy.accounts.indices {
            copy.accounts[index].label = ""
            copy.accounts[index].icon = nil
            copy.accounts[index].displayName = ""
            if case .subscription(var settings) = copy.accounts[index].kind {
                settings.shownInBar = true
                settings.thresholds = []
                copy.accounts[index].kind = .subscription(settings)
            }
        }
        for index in copy.groups.indices {
            copy.groups[index].label = ""
            copy.groups[index].icon = nil
            copy.groups[index].name = ""
            copy.groups[index].shownInBar = true
            copy.groups[index].thresholds = []
        }
        return copy
    }

    /// Drops groups without members. Moving the last member of a group to
    /// another group empties it, and FR-019 says such a group is deleted.
    public func pruningEmptyGroups() -> Configuration {
        var copy = self
        copy.groups.removeAll { members(of: $0.id).isEmpty }
        return copy
    }
}

// MARK: - Error

public struct ConfigurationError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        case decoding
        case io
        case invalidLabel
        case duplicateLabel
        case unknownGroup
        case emptyGroup
        case duplicateCredentialDirectory
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
