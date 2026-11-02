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

    @Test func roundTripKeepsPeriodValueAsAndTimeFormat() throws {
        var config = try decodeConfig(Self.json(Self.example))
        config.accounts[0].timeFormat = .absolute
        let data = try Self.encoded(config)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(decoded == config)
        let account = try Self.accountObjects(config)[0]
        #expect(account["noLimit"] as? [String: String] == ["period": "monthly"])
        #expect(account["valueAs"] as? String == "claude-opus-5-5")
        #expect(account["timeFormat"] as? String == "absolute")
        #expect(account["budget"] == nil)
        #expect(account["groupId"] == nil)
        #expect(account["shownInBar"] == nil)
    }

    /// The period is always written, also for weekly.
    @Test func weeklyPeriodIsWritten() throws {
        let config = try decodeConfig(Self.json(Self.account(#""noLimit": {}"#)))
        let account = try Self.accountObjects(config)[0]
        #expect(account["noLimit"] as? [String: String] == ["period": "weekly"])
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

    @Test func noLimitAccountUsesItsOwnPeriod() {
        #expect(config.countingPeriod(forAccount: "free") == .monthly)
        // A member keeps its group's period when it leaves for No limit.
        #expect(config.movingAccountToNoLimit(accountId: "m1").countingPeriod(forAccount: "m1") == .weekly)
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
