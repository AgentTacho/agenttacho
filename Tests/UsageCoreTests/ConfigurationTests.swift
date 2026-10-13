import Foundation
import Testing
@testable import UsageCore

let contractExampleJSON = """
{
  "version": 1,
  "refreshIntervalSeconds": 300,
  "logDirectories": ["~/.local/share/cc-deck/profiles/work/claude"],
  "weekFallback": { "weekday": 2, "hour": 0 },
  "alignmentAccountId": "acc-max",
  "startAtLogin": false,
  "accounts": [
    {
      "id": "acc-max",
      "type": "subscription",
      "label": "M",
      "displayName": "Claude Max",
      "harness": "claudeCode",
      "credentialDirectory": "~/.claude",
      "shownInBar": true,
      "thresholds": [80, 100]
    },
    {
      "id": "acc-vertex",
      "type": "tokenBased",
      "label": "VC",
      "displayName": "Claude Code via Vertex",
      "harness": "claudeCode",
      "provider": "vertex",
      "groupId": "grp-vertex",
      "customMarker": null
    }
  ],
  "groups": [
    {
      "id": "grp-vertex",
      "name": "Vertex weekly",
      "label": "V",
      "weeklyBudgetUSD": 60,
      "shownInBar": true,
      "thresholds": [80, 100]
    }
  ],
  "priceOverrides": [
    {
      "model": "claude-opus-5-5",
      "inputPerMTok": 4.0,
      "outputPerMTok": 20.0,
      "cacheWrite5mPerMTok": 5.0,
      "cacheWrite1hPerMTok": 8.0,
      "cacheReadPerMTok": 0.2
    }
  ]
}
"""

func decodeConfig(_ json: String) throws -> Configuration {
    try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
}

func validationKind(_ config: Configuration) -> ConfigurationError.Kind? {
    do {
        try config.validate()
        return nil
    } catch let error as ConfigurationError {
        return error.kind
    } catch {
        return nil
    }
}

@Suite struct ConfigurationTests {
    func example() throws -> Configuration { try decodeConfig(contractExampleJSON) }

    @Test func decodesContractExample() throws {
        let config = try example()
        #expect(config.version == 1)
        #expect(config.refreshIntervalSeconds == 300)
        #expect(config.logDirectories == ["~/.local/share/cc-deck/profiles/work/claude"])
        #expect(config.weekFallback == WeekFallback(weekday: 2, hour: 0))
        #expect(config.alignmentAccountId == "acc-max")
        #expect(config.startAtLogin == false)
        #expect(config.accounts.count == 2)
        #expect(config.groups.count == 1)
        #expect(config.priceOverrides.count == 1)

        let max = config.accounts[0]
        #expect(max.id == "acc-max")
        #expect(max.label == "M")
        #expect(max.harness == .claudeCode)
        guard case .subscription(let sub) = max.kind else {
            Issue.record("expected subscription account")
            return
        }
        #expect(sub.credentialDirectory == "~/.claude")
        #expect(sub.shownInBar == true)
        #expect(sub.thresholds == [80, 100])

        let vertex = config.accounts[1]
        guard case .tokenBased(let tok) = vertex.kind else {
            Issue.record("expected token-based account")
            return
        }
        #expect(tok.groupId == "grp-vertex")
        #expect(tok.provider == .vertex)
        #expect(vertex.customMarker == nil)

        #expect(config.groups[0].weeklyBudgetUSD == Decimal(60))
        #expect(config.priceOverrides[0].cacheReadPerMTok == Decimal(string: "0.2"))
        #expect(config.priceOverrides[0].source == .override)
        try config.validate()
    }

    @Test func roundTripsThroughEncoder() throws {
        let config = try example()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(decoded == config)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"type\":\"subscription\""))
        #expect(text.contains("\"type\":\"tokenBased\""))
    }

    @Test func rejectsLabelLength() throws {
        var config = try example()
        config.accounts[0].label = "MAXX"
        #expect(validationKind(config) == .invalidLabel)
        config.accounts[0].label = ""
        #expect(validationKind(config) == .invalidLabel)
        config.accounts[0].label = "MAX"
        #expect(validationKind(config) == nil)
    }

    @Test func rejectsDuplicateLabelsAcrossAccountsAndGroups() throws {
        var config = try example()
        config.groups[0].label = "VC"
        #expect(validationKind(config) == .duplicateLabel)
        // Case-sensitive comparison: "vc" and "VC" are distinct.
        config.groups[0].label = "vc"
        #expect(validationKind(config) == nil)
        config.accounts[0].label = "VC"
        config.groups[0].label = "V"
        #expect(validationKind(config) == .duplicateLabel)
    }

    @Test func rejectsTokenAccountWithUnknownGroup() throws {
        var config = try example()
        config.accounts[1].kind = .tokenBased(TokenBasedSettings(groupId: "nope", provider: .vertex))
        #expect(validationKind(config) == .unknownGroup)
    }

    @Test func rejectsTokenAccountWithoutGroup() throws {
        let json = contractExampleJSON.replacingOccurrences(of: "\"groupId\": \"grp-vertex\",", with: "")
        #expect(throws: (any Error).self) { try decodeConfig(json) }
    }

    @Test func rejectsEmptyGroup() throws {
        var config = try example()
        config.groups.append(BudgetGroup(id: "grp-empty", name: "Empty", label: "E", weeklyBudgetUSD: 10, shownInBar: false, thresholds: []))
        #expect(validationKind(config) == .emptyGroup)
    }

    @Test func rejectsSharedCredentialDirectory() throws {
        var config = try example()
        config.accounts.append(Account(
            id: "acc-two", label: "M2", displayName: "Second", harness: .claudeCode,
            kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude/", shownInBar: false, thresholds: [])),
            customMarker: nil))
        #expect(validationKind(config) == .duplicateCredentialDirectory)
        config.accounts[2].kind = .subscription(SubscriptionSettings(credentialDirectory: "~/other", shownInBar: false, thresholds: []))
        #expect(validationKind(config) == nil)
    }

    @Test func rejectsRefreshIntervalBelowMinimum() throws {
        var config = try example()
        config.refreshIntervalSeconds = 59
        let kind = validationKind(config)
        #expect(kind == .refreshInterval)
        do { try config.validate() } catch let error as ConfigurationError {
            #expect(error.message.contains("60"))
        }
        config.refreshIntervalSeconds = 60
        #expect(validationKind(config) == nil)
    }

    @Test func rejectsZeroThreshold() throws {
        var config = try example()
        config.groups[0].thresholds = [0, 50]
        #expect(validationKind(config) == .threshold)
        config.groups[0].thresholds = [50]
        config.accounts[0].kind = .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: [-5]))
        #expect(validationKind(config) == .threshold)
    }

    @Test func rejectsNonPositiveBudget() throws {
        var config = try example()
        config.groups[0].weeklyBudgetUSD = 0
        #expect(validationKind(config) == .budget)
        config.groups[0].weeklyBudgetUSD = -1
        #expect(validationKind(config) == .budget)
    }

    @Test func rejectsWeekFallbackOutOfRange() throws {
        var config = try example()
        config.weekFallback = WeekFallback(weekday: 0, hour: 0)
        #expect(validationKind(config) == .weekFallback)
        config.weekFallback = WeekFallback(weekday: 8, hour: 0)
        #expect(validationKind(config) == .weekFallback)
        config.weekFallback = WeekFallback(weekday: 7, hour: 24)
        #expect(validationKind(config) == .weekFallback)
        config.weekFallback = WeekFallback(weekday: 7, hour: 23)
        #expect(validationKind(config) == nil)
    }

    @Test func rejectsAlignmentAccountThatIsNotSubscription() throws {
        var config = try example()
        config.alignmentAccountId = "acc-vertex"
        #expect(validationKind(config) == .alignmentAccount)
        config.alignmentAccountId = "missing"
        #expect(validationKind(config) == .alignmentAccount)
        config.alignmentAccountId = nil
        #expect(validationKind(config) == nil)
    }

    @Test func rejectsUnknownAccountType() throws {
        let json = contractExampleJSON.replacingOccurrences(of: "\"type\": \"tokenBased\"", with: "\"type\": \"bedrockThing\"")
        #expect(throws: (any Error).self) { try decodeConfig(json) }
    }

    @Test func rejectsWrongFieldType() throws {
        let json = contractExampleJSON.replacingOccurrences(of: "\"refreshIntervalSeconds\": 300", with: "\"refreshIntervalSeconds\": \"300\"")
        #expect(throws: DecodingError.self) { try decodeConfig(json) }
    }

    @Test func ignoresUnknownTopLevelKeys() throws {
        let json = contractExampleJSON.replacingOccurrences(of: "\"version\": 1,", with: "\"version\": 1, \"futureKey\": {\"a\": 1},")
        let config = try decodeConfig(json)
        #expect(config.version == 1)
        try config.validate()
    }

    @Test func removingLastMemberDeletesGroup() throws {
        let config = try example()
        let result = config.removingAccount(id: "acc-vertex")
        #expect(result.accounts.map(\.id) == ["acc-max"])
        #expect(result.groups.isEmpty)
    }

    @Test func removingNonLastMemberKeepsGroup() throws {
        var config = try example()
        config.accounts.append(Account(
            id: "acc-v2", label: "V2", displayName: "Second Vertex", harness: .claudeCode,
            kind: .tokenBased(TokenBasedSettings(groupId: "grp-vertex", provider: .vertex)), customMarker: nil))
        let result = config.removingAccount(id: "acc-vertex")
        #expect(result.accounts.map(\.id) == ["acc-max", "acc-v2"])
        #expect(result.groups.map(\.id) == ["grp-vertex"])
    }

    @Test func effectiveAlignmentAccountDefaultsToFirstSubscription() throws {
        var config = try example()
        #expect(config.effectiveAlignmentAccountId == "acc-max")
        config.alignmentAccountId = nil
        #expect(config.effectiveAlignmentAccountId == "acc-max")

        config.accounts.append(Account(
            id: "acc-two", label: "M2", displayName: "Second", harness: .claudeCode,
            kind: .subscription(SubscriptionSettings(credentialDirectory: "~/other", shownInBar: false, thresholds: [])),
            customMarker: nil))
        config.alignmentAccountId = "acc-two"
        #expect(config.effectiveAlignmentAccountId == "acc-two")
        // A stale id that no longer names a subscription account falls back to the first one.
        config.alignmentAccountId = "acc-vertex"
        #expect(config.effectiveAlignmentAccountId == "acc-max")
        config.accounts.removeAll { $0.kind.isSubscription }
        #expect(config.effectiveAlignmentAccountId == nil)
    }

    @Test func pruningEmptyGroupsDropsGroupsLeftWithoutMembers() throws {
        var config = try example()
        // Move the only Vertex account into a new group; the old group is now empty.
        config.groups.append(BudgetGroup(id: "grp-b", name: "Other", label: "B", weeklyBudgetUSD: 20))
        config.accounts[1].kind = .tokenBased(TokenBasedSettings(groupId: "grp-b", provider: .vertex))
        #expect(validationKind(config) == .emptyGroup)
        let pruned = config.pruningEmptyGroups()
        #expect(pruned.groups.map(\.id) == ["grp-b"])
        #expect(pruned.accounts.map(\.id) == ["acc-max", "acc-vertex"])
        #expect(validationKind(pruned) == nil)
        // Groups with members are untouched.
        #expect(try example().pruningEmptyGroups() == example())
    }

    @Test func removingAlignmentAccountClearsAlignment() throws {
        let config = try example()
        let result = config.removingAccount(id: "acc-max")
        #expect(result.alignmentAccountId == nil)
        #expect(result.accounts.map(\.id) == ["acc-vertex"])
        #expect(validationKind(result) == nil)
    }
}
