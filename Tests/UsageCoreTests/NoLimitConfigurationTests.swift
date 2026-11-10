import Foundation
import Testing
@testable import UsageCore

/// Spec 041 FR-001 to FR-004, contracts/config.md, research R1 and R2: the
/// `noLimit` and `valueAs` keys of a token-based account, their decoding,
/// validation and encoding.
@Suite struct NoLimitConfigurationTests {
    /// The account of contracts/config.md.
    static let example = """
    {
      "id": "acc-free",
      "type": "tokenBased",
      "icon": "solid:gift",
      "displayName": "Free models",
      "harness": "claudeCode",
      "sessionKind": "otherProvider",
      "condition": {"field": "model", "operator": "startsWith", "text": "gateway-a/"},
      "noLimit": {"period": "monthly"},
      "valueAs": "claude-opus-5-5",
      "timeFormat": "relative"
    }
    """

    static let group = """
    {"id": "grp-a", "name": "Team", "icon": "solid:wallet", "period": "weekly", "budgetUSD": 100, "shownInBar": true, "thresholds": [80]}
    """

    /// A configuration holding `accounts` and one group `grp-a`.
    static func json(_ accounts: String...) -> String {
        """
        {"version": 1, "accounts": [\(accounts.joined(separator: ","))], "groups": [\(group)]}
        """
    }

    /// A token-based account with the extra `keys` (without braces).
    static func account(_ keys: String, id: String = "acc-x", name: String = "Gateway") -> String {
        """
        {"id": "\(id)", "type": "tokenBased", "displayName": "\(name)", "harness": "claudeCode", "sessionKind": "otherProvider",
         "condition": {"field": "model", "operator": "startsWith", "text": "gateway-a/"}, \(keys)}
        """
    }

    static func encoded(_ config: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(config)
    }

    static func accountObjects(_ config: Configuration) throws -> [[String: Any]] {
        let object = try #require(try JSONSerialization.jsonObject(with: try encoded(config)) as? [String: Any])
        return try #require(object["accounts"] as? [[String: Any]])
    }

    /// The debug description of the decoding error `json` raises: the text
    /// `ConfigStore` shows for a data-corrupted error.
    static func decodingMessage(_ json: String) -> String? {
        do {
            _ = try decodeConfig(json)
            return nil
        } catch DecodingError.dataCorrupted(let context) {
            return context.debugDescription
        } catch DecodingError.keyNotFound(_, let context) {
            return context.debugDescription
        } catch DecodingError.typeMismatch(_, let context) {
            return context.debugDescription
        } catch {
            return "\(error)"
        }
    }

    // MARK: Decoding

    @Test func decodesTheContractExample() throws {
        let config = try decodeConfig(Self.json(Self.example))
        let settings = try #require(config.accounts.first?.kind.tokenBased)
        #expect(settings.membership == .noLimit(NoLimitSettings(period: .monthly)))
        #expect(settings.noLimit == NoLimitSettings(period: .monthly))
        #expect(settings.valueAs == "claude-opus-5-5")
        #expect(settings.ownBudget == nil)
        #expect(settings.groupId == nil)
        #expect(config.accounts[0].timeFormat == .relative)
        try config.validate()
    }

    /// FR-002: absent period means weekly.
    @Test func noLimitWithoutPeriodIsWeekly() throws {
        let config = try decodeConfig(Self.json(Self.account(#""noLimit": {}"#)))
        #expect(config.accounts[0].kind.tokenBased?.noLimit == NoLimitSettings(period: .weekly))
        try config.validate()
    }

    @Test func unknownPeriodFailsWithThePeriodMessage() throws {
        let noLimit = Self.decodingMessage(Self.json(Self.account(#""noLimit": {"period": "yearly"}"#)))
        let budget = Self.decodingMessage(Self.json(Self.account(#""budget": {"period": "yearly", "budgetUSD": 10}"#)))
        #expect(noLimit != nil)
        #expect(noLimit == budget)
    }

    // MARK: Exactly one (FR-001)

    @Test func noneOfTheThreeIsInvalid() {
        #expect(Self.decodingMessage(Self.json(Self.account(#""timeFormat": "relative""#)))
                == #"Account "Gateway" has neither groupId, budget nor noLimit; set exactly one"#)
    }

    @Test(arguments: [
        #""groupId": "grp-a", "budget": {"budgetUSD": 10}"#,
        #""groupId": "grp-a", "noLimit": {}"#,
        #""budget": {"budgetUSD": 10}, "noLimit": {}"#,
        #""groupId": "grp-a", "budget": {"budgetUSD": 10}, "noLimit": {}"#,
    ])
    func moreThanOneIsInvalid(keys: String) {
        #expect(Self.decodingMessage(Self.json(Self.account(keys)))
                == #"Account "Gateway" has more than one of groupId, budget and noLimit; set exactly one"#)
    }

    // MARK: Forbidden keys (FR-002)

    @Test(arguments: [
        #""noLimit": {"period": "weekly", "budgetUSD": 10}"#,
        #""noLimit": {"thresholds": [80]}"#,
        #""noLimit": {"shownInBar": true}"#,
        #""noLimit": {"period": "monthly"}, "shownInBar": false"#,
        #""noLimit": {"period": "monthly"}, "thresholds": [80]"#,
    ])
    func noLimitHasNoAmountThresholdsOrBarSetting(keys: String) {
        #expect(Self.decodingMessage(Self.json(Self.account(keys)))
                == #"Account "Gateway": No limit has no amount, thresholds or menu bar setting"#)
    }

    // MARK: Value as (FR-003)

    @Test(arguments: [
        #""budget": {"budgetUSD": 10}, "valueAs": "claude-opus-5-5""#,
        #""groupId": "grp-a", "valueAs": "claude-opus-5-5""#,
    ])
    func valueAsOnABudgetIsKeptWithoutEffect(keys: String) throws {
        let config = try decodeConfig(Self.json(Self.account(keys)))
        #expect(config.accounts[0].kind.tokenBased?.valueAs == "claude-opus-5-5")
        try config.validate()
        let accounts = try Self.accountObjects(config)
        #expect(accounts[0]["valueAs"] as? String == "claude-opus-5-5")
        #expect(try JSONDecoder().decode(Configuration.self, from: try Self.encoded(config)) == config)
    }

    @Test func valueAsWithoutAPriceIsValid() throws {
        let config = try decodeConfig(Self.json(Self.account(#""noLimit": {}, "valueAs": "gateway-x/unknown""#)))
        #expect(config.accounts[0].kind.tokenBased?.valueAs == "gateway-x/unknown")
        try config.validate()
        try config.validateForSaving()
    }

    @Test(arguments: [#""""#, #""   ""#])
    func blankValueAsIsAbsent(raw: String) throws {
        let config = try decodeConfig(Self.json(Self.account(#""noLimit": {}, "valueAs": \#(raw)"#)))
        #expect(config.accounts[0].kind.tokenBased?.valueAs == nil)
        #expect(try Self.accountObjects(config)[0]["valueAs"] == nil)
    }

    // MARK: Encoding

    /// A legacy `noLimit` account is written in the spec 043 form: `budget`
    /// without `budgetUSD`, never `noLimit` (spec 043 FR-004).
    @Test func roundTripKeepsPeriodValueAsAndTimeFormat() throws {
        var config = try decodeConfig(Self.json(Self.example))
        config.accounts[0].timeFormat = .absolute
        let data = try Self.encoded(config)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(decoded == config)
        let account = try Self.accountObjects(config)[0]
        let budget = try #require(account["budget"] as? [String: Any])
        #expect(budget["period"] as? String == "monthly")
        #expect(budget["shownInBar"] as? Bool == true)
        #expect(budget["thresholds"] as? [Int] == [80, 100])
        #expect(budget["budgetUSD"] == nil)
        #expect(account["noLimit"] == nil)
        #expect(account["valueAs"] as? String == "claude-opus-5-5")
        #expect(account["timeFormat"] as? String == "absolute")
        #expect(account["groupId"] == nil)
        #expect(account["shownInBar"] == nil)
    }

    /// The period is always written, also for weekly.
    @Test func weeklyPeriodIsWritten() throws {
        let config = try decodeConfig(Self.json(Self.account(#""noLimit": {}"#)))
        let account = try Self.accountObjects(config)[0]
        let budget = try #require(account["budget"] as? [String: Any])
        #expect(budget["period"] as? String == "weekly")
        #expect(account["noLimit"] == nil)
        #expect(account["valueAs"] == nil)
    }

    /// The sorted-keys encoding of `currentExampleJSON`, captured before
    /// spec 041.
    static let currentExampleBefore = #"{"accounts":[{"credentialDirectory":"~\/.claude","customMarker":null,"displayName":"Claude Max","harness":"claudeCode","icon":"brands:claude","id":"acc-max","shownInBar":true,"thresholds":[80,100],"timeFormat":"relative","type":"subscription"},{"displayName":"Claude Code via Vertex","groupId":"grp-vertex","harness":"claudeCode","icon":"brands:google","id":"acc-vertex","sessionKind":"vertex","shownInBar":false,"timeFormat":"relative","type":"tokenBased"}],"adaptiveRefresh":true,"alignmentAccountId":"acc-max","checksForUpdates":true,"displayDirection":"used","groups":[{"budgetUSD":60,"icon":"solid:wallet","id":"grp-vertex","name":"Vertex weekly","period":"weekly","shownInBar":true,"thresholds":[80,100],"timeFormat":"relative"}],"levelColor":"text","notifyFreeResetExpiry":true,"notifySignInProblems":true,"openCodeDirectories":[],"priceOverrides":[{"cacheReadPerMTok":0.2,"cacheWrite1hPerMTok":8,"cacheWrite5mPerMTok":5,"inputPerMTok":4,"model":"claude-opus-5-5","outputPerMTok":20}],"refreshIntervalSeconds":300,"showLevelSymbols":false,"showsRunOutMarker":true,"startAtLogin":false,"version":1,"weekFallback":{"hour":0,"weekday":2}}"#

    /// A configuration without No limit accounts is written byte for byte
    /// as before (contracts/config.md "Encoding").
    @Test func configurationWithoutNoLimitEncodesAsBefore() throws {
        let config = try decodeConfig(currentExampleJSON)
        #expect(String(decoding: try Self.encoded(config), as: UTF8.self) == Self.currentExampleBefore)
    }

    /// A No limit account built in code encodes and decodes unchanged.
    @Test func builtAccountRoundTrips() throws {
        var settings = TokenBasedSettings(membership: .noLimit(NoLimitSettings(period: .monthly)), harness: .codex)
        settings.valueAs = "claude-opus-5-5"
        let config = Configuration(accounts: [Account(id: "acc-free", displayName: "Free", kind: .tokenBased(settings))])
        try config.validate()
        #expect(try JSONDecoder().decode(Configuration.self, from: try Self.encoded(config)) == config)
    }
}

/// Spec 041 FR-002, FR-006, research R3: the period an account's tokens are
/// counted over, shared by the aggregator, the collection window and the
/// demo record source.
@Suite struct CountingPeriodTests {
    let config = NoLimitTransitionTests.config()

    @Test func noLimitAccountUsesItsOwnPeriod() throws {
        #expect(config.countingPeriod(forAccount: "free") == .monthly)
        // A member that gets its own budget keeps the group's period, and
        // clearing the amount keeps it too (spec 043 FR-003, FR-019).
        var moved = config.movingAccountToOwnBudget(accountId: "m1")
        let index = try #require(moved.accounts.firstIndex { $0.id == "m1" })
        var settings = try #require(moved.accounts[index].kind.tokenBased)
        var form = OwnBudgetForm(settings.membership)
        form.amount = nil
        settings.membership = form.membership
        moved.accounts[index].kind = .tokenBased(settings)
        #expect(moved.countingPeriod(forAccount: "m1") == .weekly)
    }

    @Test func ownBudgetUsesItsBudgetPeriod() {
        #expect(config.countingPeriod(forAccount: "own") == .monthly)
    }

    @Test func memberUsesItsGroupPeriod() {
        #expect(config.countingPeriod(forAccount: "m1") == .weekly)
        #expect(config.countingPeriod(forAccount: "solo") == .monthly)
    }

    @Test func otherAccountsHaveNone() {
        var c = config
        c.accounts.append(Account(id: "max", displayName: "Max", kind: .subscription(SubscriptionSettings())))
        c.accounts.append(Account(id: "lost", displayName: "Lost", kind: .tokenBased(TokenBasedSettings(groupId: "gone"))))
        #expect(c.countingPeriod(forAccount: "max") == nil)
        #expect(c.countingPeriod(forAccount: "lost") == nil)
        #expect(c.countingPeriod(forAccount: "unknown") == nil)
    }
}

/// Spec 041 FR-016: a new No limit account starts weekly without a Value as
/// model, whatever period an own budget had in the new account sheet.
@Suite struct NewNoLimitAccountTests {
    @Test func startsWeekly() {
        #expect(NoLimitSettings().period == .weekly)
        let settings = TokenBasedSettings(membership: .noLimit(NoLimitSettings()))
        #expect(settings.valueAs == nil)
    }
}

/// Spec 043 FR-002 to FR-004, FR-010, contracts/config.md, research R2, R3:
/// an own budget without an amount (`budget` without `budgetUSD`), the
/// spec 041 `noLimit` form read only, and the account-level `show` key.
@Suite struct OptionalAmountConfigurationTests {
    typealias Base = NoLimitConfigurationTests

    static func decodeWithNotes(_ json: String) throws -> (Configuration, [String]) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (config, notes.notes)
    }

    static func membership(_ keys: String) throws -> TokenMembership? {
        try decodeConfig(Base.json(Base.account(keys))).accounts.first?.kind.tokenBased?.membership
    }

    // MARK: Decoding the new form (FR-002, FR-003)

    @Test func budgetWithoutAmountIsNoLimit() throws {
        let expected = TokenMembership.noLimit(NoLimitSettings(period: .monthly, thresholds: [50, 90], shownInBar: false))
        #expect(try Self.membership(#""budget": {"period": "monthly", "shownInBar": false, "thresholds": [50, 90]}"#) == expected)
        #expect(try Self.membership(#""budget": {"period": "monthly", "budgetUSD": null, "shownInBar": false, "thresholds": [50, 90]}"#) == expected)
        try decodeConfig(Base.json(Base.account(#""budget": {"period": "monthly"}"#))).validate()
    }

    /// Missing keys inside `budget` decode as `BudgetSettings` decodes them,
    /// so entering an amount later never changes them.
    @Test func missingKeysInsideBudgetDecodeAsBudgetSettingsDoes() throws {
        #expect(try Self.membership(#""budget": {}"#) == .noLimit(NoLimitSettings(period: .weekly, thresholds: [], shownInBar: true)))
        let budget = try #require(try decodeConfig(Base.json(Base.account(#""budget": {"budgetUSD": 10}"#))).accounts[0].kind.tokenBased?.ownBudget)
        #expect(budget.thresholds == [])
        #expect(budget.shownInBar == true)
    }

    /// The kept thresholds of an own budget without an amount follow the
    /// budget rule, since they apply once an amount is entered (FR-003).
    @Test(arguments: ["0", "-5"])
    func keptThresholdsOfZeroOrLessAreInvalid(threshold: String) throws {
        let config = try decodeConfig(Base.json(Base.account(#""budget": {"period": "monthly", "thresholds": [\#(threshold)]}"#)))
        #expect(config.accounts[0].kind.tokenBased?.noLimit != nil)
        #expect(throws: ConfigurationError(kind: .threshold,
                                           message: "Thresholds of account \"Gateway\" must be whole-number percents greater than 0 (got \(threshold)).")) {
            try config.validate()
        }
    }

    @Test(arguments: ["0", "-5"])
    func amountOfZeroOrLessStaysInvalid(amount: String) throws {
        let config = try decodeConfig(Base.json(Base.account(#""budget": {"period": "weekly", "budgetUSD": \#(amount)}"#)))
        #expect(throws: ConfigurationError(kind: .budget, message: "Weekly budget of account \"Gateway\" must be greater than 0.")) {
            try config.validate()
        }
    }

    /// A group's amount is optional since spec 044 (FR-001, contracts/config.md):
    /// an absent amount and `null` each give a group without an amount, and
    /// a group with an amount decodes as before.
    @Test func groupAmountIsOptional() throws {
        func groups(_ group: String) -> String { #"{"version": 1, "accounts": [], "groups": [\#(group)]}"# }
        #expect(Base.decodingMessage(groups(#"{"id": "grp-a", "name": "Team", "period": "weekly"}"#)) == nil)
        let absent = try decodeConfig(groups(#"{"id": "grp-a", "name": "Team", "period": "weekly"}"#))
        #expect(absent.groups.first?.budgetUSD == nil)
        let null = try decodeConfig(groups(#"{"id": "grp-a", "name": "Team", "period": "weekly", "budgetUSD": null}"#))
        #expect(null.groups.first?.budgetUSD == nil)
        #expect(null.groups.first?.hasAmount == false)
        let config = try decodeConfig(groups(#"{"id": "grp-a", "name": "Team", "period": "weekly", "budgetUSD": 25}"#))
        #expect(config.groups.first?.budgetUSD == 25)
    }

    // MARK: Legacy noLimit form (FR-004)

    @Test func legacyFormGetsTheNewAccountDefaults() throws {
        let config = try decodeConfig(Base.json(Base.example))
        let settings = try #require(config.accounts.first?.kind.tokenBased)
        #expect(settings.membership == .noLimit(NoLimitSettings(period: .monthly, thresholds: [80, 100], shownInBar: true)))
        #expect(settings.valueAs == "claude-opus-5-5")
        #expect(settings.show == .automatic)
    }

    /// Each converted account gets exactly one load note, like the other
    /// one-way migrations; the new form gets none (FR-004).
    @Test func legacyFormGivesOneLoadNotePerAccount() throws {
        let long = String(repeating: "x", count: 40)
        let (_, notes) = try Self.decodeWithNotes(Base.json(
            Base.example,
            Base.account(#""noLimit": {}"#, id: "acc-long", name: long)))
        #expect(notes == [
            "account \"Free models\": No limit is now an own budget without an amount; the next save writes the new form",
            "account \"\(String(repeating: "x", count: 32))...\": No limit is now an own budget without an amount; the next save writes the new form",
        ])
        let (_, newForm) = try Self.decodeWithNotes(Base.json(Base.account(#""budget": {"period": "monthly"}"#)))
        #expect(newForm.isEmpty)
    }

    @Test func legacyFileRoundTripsIntoTheNewForm() throws {
        let legacy = try decodeConfig(Base.json(Base.example))
        let written = try Base.encoded(legacy)
        let text = String(decoding: written, as: UTF8.self)
        #expect(!text.contains("noLimit"))
        let reread = try JSONDecoder().decode(Configuration.self, from: written)
        #expect(reread == legacy)
        #expect(try Base.encoded(reread) == written)
    }

    @Test func budgetTogetherWithLegacyFormIsInvalid() {
        #expect(Base.decodingMessage(Base.json(Base.account(#""budget": {"period": "weekly"}, "noLimit": {}"#)))
                == #"Account "Gateway" has more than one of groupId, budget and noLimit; set exactly one"#)
    }

    // MARK: Encoding (R2)

    @Test func noLimitIsWrittenAsBudgetWithoutAmount() throws {
        let settings = TokenBasedSettings(membership: .noLimit(NoLimitSettings(period: .monthly, thresholds: [50, 90], shownInBar: false)),
                                          valueAs: "claude-opus-5-5")
        var account = Account(id: "acc-api", displayName: "API key", kind: .tokenBased(settings))
        account.timeFormat = .absolute
        let config = Configuration(accounts: [account])
        try config.validate()
        let object = try Base.accountObjects(config)[0]
        let budget = try #require(object["budget"] as? [String: Any])
        #expect(Set(budget.keys) == ["period", "shownInBar", "thresholds"])
        #expect(budget["thresholds"] as? [Int] == [50, 90])
        #expect(budget["shownInBar"] as? Bool == false)
        #expect(object["noLimit"] == nil)
        let decoded = try JSONDecoder().decode(Configuration.self, from: try Base.encoded(config))
        #expect(decoded == config)
        #expect(decoded.accounts[0].timeFormat == .absolute)
        #expect(decoded.accounts[0].kind.tokenBased?.valueAs == "claude-opus-5-5")
    }

    /// An own budget with an amount and a group member are written as before,
    /// without a `show` key (golden literal, written before spec 043).
    static let ownBudgetBefore = #"{"budget":{"budgetUSD":50,"period":"monthly","shownInBar":false,"thresholds":[50,90]},"condition":{"field":"model","operator":"startsWith","text":"gateway-a\/"},"displayName":"Gateway","harness":"claudeCode","icon":"solid:key","id":"acc-x","sessionKind":"otherProvider","timeFormat":"relative","type":"tokenBased"}"#

    @Test func accountsWithAnAmountEncodeAsBefore() throws {
        let config = try decodeConfig(Base.json(Base.account(#""icon": "solid:key", "budget": {"period": "monthly", "budgetUSD": 50, "shownInBar": false, "thresholds": [50, 90]}"#)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(String(decoding: try encoder.encode(config.accounts[0]), as: UTF8.self) == Self.ownBudgetBefore)
        // The group member of the current example keeps its form too.
        #expect(String(decoding: try Base.encoded(try decodeConfig(currentExampleJSON)), as: UTF8.self) == Base.currentExampleBefore)
    }

    // MARK: show (FR-010, R3)

    @Test func absentShowIsAutomatic() throws {
        let config = try decodeConfig(Base.json(Base.account(#""budget": {"budgetUSD": 10}"#)))
        #expect(config.accounts[0].kind.tokenBased?.show == .automatic)
        #expect(TokenBasedSettings(membership: .noLimit(NoLimitSettings())).show == .automatic)
    }

    @Test(arguments: [("percent", DropdownShow.percent), ("tokens", .tokens), ("money", .money), ("automatic", .automatic)])
    func knownShowValuesDecode(raw: String, expected: DropdownShow) throws {
        let (config, notes) = try Self.decodeWithNotes(Base.json(Base.account(#""budget": {"budgetUSD": 10}, "show": "\#(raw)""#)))
        #expect(config.accounts[0].kind.tokenBased?.show == expected)
        #expect(notes.isEmpty)
    }

    @Test func unknownShowGivesOneNoteAndAutomatic() throws {
        let (config, notes) = try Self.decodeWithNotes(Base.json(Base.account(#""budget": {"budgetUSD": 10}, "show": "dollars""#)))
        #expect(config.accounts[0].kind.tokenBased?.show == .automatic)
        #expect(notes == ["show \"dollars\" of account \"Gateway\" is not known, using automatic"])
    }

    /// A value that is not a string is Automatic with a note, never a
    /// configuration error (contracts/config.md).
    @Test func unreadableShowGivesOneNoteAndAutomatic() throws {
        let (config, notes) = try Self.decodeWithNotes(Base.json(Base.account(#""budget": {"budgetUSD": 10}, "show": 3"#)))
        #expect(config.accounts[0].kind.tokenBased?.show == .automatic)
        #expect(notes == ["show of account \"Gateway\" is not readable, using automatic"])
    }

    @Test func nullShowIsAutomatic() throws {
        let (config, notes) = try Self.decodeWithNotes(Base.json(Base.account(#""budget": {"budgetUSD": 10}, "show": null"#)))
        #expect(config.accounts[0].kind.tokenBased?.show == .automatic)
        #expect(notes.isEmpty)
    }

    @Test func showOnASubscriptionIsIgnoredWithANote() throws {
        let json = #"{"version": 1, "accounts": [{"id": "acc-max", "type": "subscription", "displayName": "Max", "show": "money"}]}"#
        let (config, notes) = try Self.decodeWithNotes(json)
        #expect(notes == ["show of account \"Max\" does not belong to a subscription account, ignored"])
        let object = try Base.accountObjects(config)[0]
        #expect(object["show"] == nil)
    }

    @Test func automaticIsNotWrittenTheOthersAre() throws {
        for show in DropdownShow.allCases {
            var settings = TokenBasedSettings(membership: .noLimit(NoLimitSettings()))
            settings.show = show
            let config = Configuration(accounts: [Account(id: "a", displayName: "A", kind: .tokenBased(settings))])
            let object = try Base.accountObjects(config)[0]
            #expect(object["show"] as? String == (show == .automatic ? nil : show.rawValue))
            #expect(try JSONDecoder().decode(Configuration.self, from: try Base.encoded(config)) == config)
        }
    }

    /// Kept while the account is in a group (FR-018a).
    @Test func showOnAGroupMemberIsKept() throws {
        let config = try decodeConfig(Base.json(Base.account(#""groupId": "grp-a", "show": "tokens""#)))
        #expect(config.accounts[0].kind.tokenBased?.show == .tokens)
        #expect(try Base.accountObjects(config)[0]["show"] as? String == "tokens")
        let back = config.movingAccountToOwnBudget(accountId: "acc-x")
        #expect(back.accounts[0].kind.tokenBased?.show == .tokens)
    }

    // MARK: Refresh (FR-010, FR-003)

    static func withSettings(_ config: Configuration, _ change: (inout TokenBasedSettings) -> Void) -> Configuration {
        var copy = config
        var settings = copy.accounts[0].kind.tokenBased!
        change(&settings)
        copy.accounts[0].kind = .tokenBased(settings)
        return copy
    }

    @Test func showChangeNeedsNoRefresh() throws {
        let config = try decodeConfig(Base.json(Base.account(#""budget": {"budgetUSD": 10}"#)))
        let changed = Self.withSettings(config) { $0.show = .money }
        #expect(!changed.needsRefresh(comparedTo: config))
    }

    @Test func amountLessThresholdsAndBarNeedNoRefresh() throws {
        let config = try decodeConfig(Base.json(Base.account(#""budget": {"period": "monthly"}"#)))
        let changed = Self.withSettings(config) {
            $0.membership = .noLimit(NoLimitSettings(period: .monthly, thresholds: [10], shownInBar: false))
        }
        #expect(!changed.needsRefresh(comparedTo: config))
        let otherPeriod = Self.withSettings(config) { $0.membership = .noLimit(NoLimitSettings(period: .weekly, thresholds: [])) }
        #expect(otherPeriod.needsRefresh(comparedTo: config))
    }

    @Test func addingOrRemovingAnAmountNeedsARefresh() throws {
        let config = try decodeConfig(Base.json(Base.account(#""budget": {"period": "monthly"}"#)))
        let withAmount = Self.withSettings(config) {
            var form = OwnBudgetForm($0.membership)
            form.amount = 300
            $0.membership = form.membership
        }
        #expect(withAmount.needsRefresh(comparedTo: config))
        #expect(config.needsRefresh(comparedTo: withAmount))
    }
}
