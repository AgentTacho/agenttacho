import Foundation
import Testing
@testable import UsageCore

let contractExampleJSON = """
{
  "version": 1,
  "refreshIntervalSeconds": 300,
  "logDirectories": ["~/profiles/acme/claude"],
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

/// The contract example without the dropped `logDirectories` key, for tests
/// that expect a file without load notes (spec 034 FR-011).
let currentExampleJSON = contractExampleJSON.replacingOccurrences(of: "  \"logDirectories\": [\"~/profiles/acme/claude\"],\n", with: "")

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
        // The dropped global list is not read; its entry leaves a load note
        // (spec 034 FR-011).
        let (_, notes) = try TimeFormatConfigurationTests.decodeWithNotes(contractExampleJSON)
        #expect(notes == [#"logDirectories entry "~/profiles/acme/claude" is no longer read; set it as the Claude Code directory of an account in Settings > Accounts"#])
        #expect(config.weekFallback == WeekFallback(weekday: 2, hour: 0))
        #expect(config.alignmentAccountId == "acc-max")
        #expect(config.startAtLogin == false)
        #expect(config.accounts.count == 2)
        #expect(config.groups.count == 1)
        #expect(config.priceOverrides.count == 1)

        let max = config.accounts[0]
        #expect(max.id == "acc-max")
        #expect(max.icon == IconDefaults.subscription)
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

        #expect(config.groups[0].budgetUSD == Decimal(60))
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

    @Test func currentExampleHasNoLegacyKey() {
        #expect(!currentExampleJSON.contains("logDirectories"))
        #expect(currentExampleJSON.count < contractExampleJSON.count)
    }

    /// Settings apply immediately; only data-relevant edits trigger a refresh.
    @Test func presentationEditsDoNotNeedARefresh() throws {
        let base = try example()
        var edited = base
        edited.accounts[0].icon = "solid:robot"
        edited.accounts[0].displayName = "Renamed"
        edited.groups[0].name = "Renamed group"
        edited.groups[0].icon = "solid:cloud"
        edited.groups[0].shownInBar.toggle()
        edited.groups[0].thresholds = [50]
        edited.startAtLogin.toggle()
        if case .subscription(var settings) = edited.accounts[0].kind {
            settings.thresholds = [10, 20]
            settings.shownInBar.toggle()
            edited.accounts[0].kind = .subscription(settings)
        }
        #expect(!edited.needsRefresh(comparedTo: base))

        var budget = base
        budget.groups[0].budgetUSD += 1
        #expect(budget.needsRefresh(comparedTo: base))

        var interval = base
        interval.refreshIntervalSeconds += 60
        #expect(interval.needsRefresh(comparedTo: base))

        // A token-based account's directory changes what a refresh reads
        // (spec 034 research R9).
        var directory = base
        if case .tokenBased(var settings) = directory.accounts[1].kind {
            settings.enteredSessionDirectory = "~/elsewhere"
            directory.accounts[1].kind = .tokenBased(settings)
        }
        #expect(directory.needsRefresh(comparedTo: base))

        var marker = base
        marker.accounts[0].customMarker = "project-x"
        #expect(marker.needsRefresh(comparedTo: base))
    }

    /// Spec 008 research R3a: an order-only change redraws without a refresh.
    @Test func arrangementChangeNeedsNoRefresh() throws {
        let base = try example()
        var reordered = base
        reordered.arrangement = Arrangement(entries: base.arrangedEntries.reversed().map(\.ref))
        #expect(reordered != base)
        #expect(!reordered.needsRefresh(comparedTo: base))
        #expect(!reordered.needsNetworkRefresh(comparedTo: base))
    }

    @Test func needsNetworkRefreshOnlyForSubscriptionChanges() throws {
        let base = try example()

        var local = base
        local.priceOverrides[0].inputPerMTok += 1
        local.groups[0].budgetUSD += 1
        local.accounts[1].customMarker = "project-x"
        if case .tokenBased(var settings) = local.accounts[1].kind {
            settings.enteredSessionDirectory = "~/elsewhere"
            local.accounts[1].kind = .tokenBased(settings)
        }
        local.accounts[0].icon = "solid:robot"
        if case .subscription(var settings) = local.accounts[0].kind {
            settings.thresholds = [10]
            local.accounts[0].kind = .subscription(settings)
        }
        #expect(local.needsRefresh(comparedTo: base))
        #expect(!local.needsNetworkRefresh(comparedTo: base))

        var removed = base
        removed.accounts.remove(at: 0)
        removed.alignmentAccountId = nil
        #expect(removed.needsNetworkRefresh(comparedTo: base))

        var added = base
        added.accounts.append(Account(id: "acc-2", displayName: "Work",
                                      kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude-work"))))
        #expect(added.needsNetworkRefresh(comparedTo: base))

        var directory = base
        if case .subscription(var settings) = directory.accounts[0].kind {
            settings.credentialDirectory = "~/.claude-other"
            directory.accounts[0].kind = .subscription(settings)
        }
        #expect(directory.needsNetworkRefresh(comparedTo: base))

        var realigned = added
        realigned.alignmentAccountId = "acc-2"
        #expect(realigned.needsNetworkRefresh(comparedTo: added))
    }

    /// The icon must exist in the catalog (spec 004 FR-005).
    @Test func rejectsUnknownIcons() throws {
        var config = try example()
        #expect(validationKind(config) == nil)
        for unknown in ["brands:no-such-icon", "claude", "duotone:claude", ""] {
            config.accounts[0].icon = unknown
            #expect(validationKind(config) == .unknownIcon, "\(unknown)")
        }
        config.accounts[0].icon = "solid:cloud"
        config.groups[0].icon = "regular:cloud"
        #expect(validationKind(config) == nil)

        // Round trip keeps the icon.
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(decoded.accounts[0].icon == "solid:cloud")
        #expect(decoded.groups[0].icon == "regular:cloud")
    }

    /// An `emoji` key left over from an earlier build is ignored like any
    /// unknown key; the default icon applies.
    @Test func leftoverEmojiKeyIsIgnored() throws {
        let config = try example()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        var accounts = try #require(object["accounts"] as? [[String: Any]])
        accounts[0]["emoji"] = "✻"
        object["accounts"] = accounts
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.accounts[0].icon == IconDefaults.subscription)
        #expect(validationKind(decoded) == nil)
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

    /// Spec 009 FR-001: a group without members is valid.
    @Test func acceptsEmptyGroup() throws {
        var config = try example()
        config.groups.append(BudgetGroup(id: "grp-empty", name: "Empty", budgetUSD: 10, shownInBar: false, thresholds: []))
        #expect(validationKind(config) == nil)
    }

    /// Spec 009 FR-001, edge case "empty group in a hand-edited
    /// configuration": a file with a group nobody references decodes,
    /// validates and keeps the group.
    @Test func handWrittenEmptyGroupDecodesAndValidates() throws {
        let json = contractExampleJSON.replacingOccurrences(of: """
              "thresholds": [80, 100]
            }
          ],
          "priceOverrides"
        """, with: """
              "thresholds": [80, 100]
            },
            {
              "id": "grp-spare",
              "name": "Spare",
              "label": "S",
              "weeklyBudgetUSD": 25,
              "shownInBar": false,
              "thresholds": [50]
            }
          ],
          "priceOverrides"
        """)
        let config = try decodeConfig(json)
        #expect(config.groups.map(\.id) == ["grp-vertex", "grp-spare"])
        #expect(config.members(of: "grp-spare").isEmpty)
        #expect(config.group(id: "grp-spare")?.budget == BudgetSettings(budgetUSD: 25, shownInBar: false, thresholds: [50]))
        #expect(validationKind(config) == nil)
    }

    /// Ids are lookup keys: two accounts or two groups with one id are
    /// rejected instead of trapping or shadowing each other later.
    @Test func rejectsDuplicateIds() throws {
        var accounts = try example()
        accounts.accounts.append(Account(
            id: accounts.accounts[0].id, displayName: "Second",
            kind: .subscription(SubscriptionSettings(credentialDirectory: "~/other", shownInBar: false, thresholds: []))))
        #expect(validationKind(accounts) == .duplicateId)

        var groups = try example()
        let group = groups.groups[0]
        groups.groups.append(BudgetGroup(id: group.id, name: "Twin", budgetUSD: 10))
        #expect(validationKind(groups) == .duplicateId)

        // A group and an own-budget account may share an id.
        var shared = try example()
        shared.accounts.append(Account(
            id: group.id, displayName: "Own",
            kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 10))))))
        #expect(validationKind(shared) == nil)
    }

    @Test func rejectsSharedCredentialDirectory() throws {
        var config = try example()
        config.accounts.append(Account(
            id: "acc-two", displayName: "Second", harness: .claudeCode,
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
        config.groups[0].budgetUSD = 0
        #expect(validationKind(config) == .budget)
        config.groups[0].budgetUSD = -1
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

    /// Spec 009 FR-002: removing the last member keeps the group with all
    /// its settings.
    @Test func removingLastMemberKeepsGroup() throws {
        let config = try example()
        let result = config.removingAccount(id: "acc-vertex")
        #expect(result.accounts.map(\.id) == ["acc-max"])
        #expect(result.groups == config.groups)
        #expect(result.members(of: "grp-vertex").isEmpty)
        #expect(validationKind(result) == nil)
    }

    @Test func removingNonLastMemberKeepsGroup() throws {
        var config = try example()
        config.accounts.append(Account(
            id: "acc-v2", displayName: "Second Vertex", harness: .claudeCode,
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
            id: "acc-two", displayName: "Second", harness: .claudeCode,
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

    /// Spec 009 FR-002: the last member moving to another group leaves the
    /// former group in place, empty and valid.
    @Test func movingLastMemberToAnotherGroupKeepsTheFormerGroup() throws {
        var config = try example()
        config.groups.append(BudgetGroup(id: "grp-b", name: "Other", budgetUSD: 20))
        let moved = config.movingAccountToGroup(accountId: "acc-vertex", groupId: "grp-b")
        #expect(moved.groups == config.groups)
        #expect(moved.members(of: "grp-vertex").isEmpty)
        #expect(moved.members(of: "grp-b").map(\.id) == ["acc-vertex"])
        #expect(validationKind(moved) == nil)
    }

    @Test func removingAlignmentAccountClearsAlignment() throws {
        let config = try example()
        let result = config.removingAccount(id: "acc-max")
        #expect(result.alignmentAccountId == nil)
        #expect(result.accounts.map(\.id) == ["acc-vertex"])
        #expect(validationKind(result) == nil)
    }
}

/// Spec 003: the budget period of a group and its wording (FR-014, research R4, R7).
@Suite struct BudgetPeriodTests {
    @Test func rawValues() {
        #expect(BudgetPeriod.weekly.rawValue == "weekly")
        #expect(BudgetPeriod.monthly.rawValue == "monthly")
        #expect(BudgetPeriod(rawValue: "yearly") == nil)
        #expect(BudgetPeriod.allCases == [.weekly, .monthly])
    }

    @Test func wording() {
        #expect(BudgetPeriod.weekly.adjective == "weekly")
        #expect(BudgetPeriod.monthly.adjective == "monthly")
        #expect(BudgetPeriod.weekly.perUnit == "per week")
        #expect(BudgetPeriod.monthly.perUnit == "per month")
        #expect(BudgetPeriod.weekly.budgetLabel == "Weekly budget")
        #expect(BudgetPeriod.monthly.budgetLabel == "Monthly budget")
    }

    @Test func windowKind() {
        #expect(BudgetPeriod.weekly.windowKind == .weekly)
        #expect(BudgetPeriod.monthly.windowKind == .monthly)
        #expect(WindowKind.monthly.displayName == "monthly")
    }
}

func decodeGroup(_ json: String) throws -> BudgetGroup {
    try JSONDecoder().decode(BudgetGroup.self, from: Data(json.utf8))
}

/// Spec 003: decoding and encoding of a group's period and amount
/// (FR-002, FR-003, FR-004, FR-004a; contracts/config-file.md).
@Suite struct BudgetGroupCodingTests {
    /// Row 2: a legacy group with only `weeklyBudgetUSD` loads as weekly.
    @Test func legacyWeeklyAmountLoadsAsWeekly() throws {
        let group = try decodeGroup(#"{"id": "g", "name": "Vertex", "label": "V", "weeklyBudgetUSD": 60}"#)
        #expect(group.period == .weekly)
        #expect(group.budgetUSD == Decimal(60))
        #expect(group.shownInBar == true)
        #expect(group.thresholds == [])
        // An explicit weekly period with only the legacy amount is row 2 too.
        let explicit = try decodeGroup(#"{"id": "g", "name": "Vertex", "label": "V", "period": "weekly", "weeklyBudgetUSD": 60}"#)
        #expect(explicit.period == .weekly)
        #expect(explicit.budgetUSD == Decimal(60))
    }

    /// The contract example (legacy form) keeps its amount and thresholds.
    @Test func legacyContractExampleKeepsGroup() throws {
        let config = try decodeConfig(contractExampleJSON)
        let group = config.groups[0]
        #expect(group.period == .weekly)
        #expect(group.budgetUSD == Decimal(60))
        #expect(group.thresholds == [80, 100])
        #expect(group.shownInBar == true)
        try config.validate()
    }

    /// Rows 1 and 3: the new form round-trips for both periods.
    @Test func newFormRoundTrips() throws {
        for period in BudgetPeriod.allCases {
            let group = BudgetGroup(id: "g", name: "Vertex", period: period, budgetUSD: Decimal(string: "400.5")!,
                                    shownInBar: false, thresholds: [50, 90])
            let decoded = try JSONDecoder().decode(BudgetGroup.self, from: JSONEncoder().encode(group))
            #expect(decoded == group)
        }
        let monthly = try decodeGroup(#"{"id": "g", "name": "Vertex", "label": "V", "period": "monthly", "budgetUSD": 400}"#)
        #expect(monthly.period == .monthly)
        #expect(monthly.budgetUSD == Decimal(400))
        let weekly = try decodeGroup(#"{"id": "g", "name": "Vertex", "label": "V", "period": "weekly", "budgetUSD": 60}"#)
        #expect(weekly.period == .weekly)
        #expect(weekly.budgetUSD == Decimal(60))
    }

    /// Encoding writes `period` and `budgetUSD` and never `weeklyBudgetUSD` (FR-004).
    @Test func encodingWritesNewFormOnly() throws {
        let legacy = try decodeGroup(#"{"id": "g", "name": "Vertex", "label": "V", "weeklyBudgetUSD": 60}"#)
        let data = try JSONEncoder().encode(legacy)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["period"] as? String == "weekly")
        #expect((object["budgetUSD"] as? NSNumber)?.intValue == 60)
        #expect(object["weeklyBudgetUSD"] == nil)
        // `timeFormat` is always written (spec 025 contracts/config-file.md).
        #expect(Set(object.keys) == ["id", "name", "icon", "period", "budgetUSD", "shownInBar", "thresholds", "timeFormat"])

        let monthly = BudgetGroup(id: "g", name: "Vertex", icon: "brands:google", period: .monthly, budgetUSD: 400)
        let text = String(decoding: try JSONEncoder().encode(monthly), as: UTF8.self)
        #expect(text.contains("\"period\":\"monthly\""))
        #expect(text.contains("\"icon\":\"brands:google\""))
        #expect(!text.contains("weeklyBudgetUSD"))
    }

    /// Rows 1 and 3: when both amounts are present, `budgetUSD` wins (FR-004a).
    @Test func newAmountWinsOverLegacyAmount() throws {
        let weekly = try decodeGroup(#"{"id": "g", "name": "V", "label": "V", "budgetUSD": 80, "weeklyBudgetUSD": 60}"#)
        #expect(weekly.period == .weekly)
        #expect(weekly.budgetUSD == 80)
        let monthly = try decodeGroup(#"{"id": "g", "name": "V", "label": "V", "period": "monthly", "budgetUSD": 400, "weeklyBudgetUSD": 60}"#)
        #expect(monthly.period == .monthly)
        #expect(monthly.budgetUSD == 400)
    }

    /// Row 4: a monthly group with only the legacy weekly amount is rejected (FR-004a).
    @Test func monthlyWithOnlyLegacyAmountIsADecodeError() {
        #expect(throws: DecodingError.self) {
            try decodeGroup(#"{"id": "g", "name": "V", "label": "V", "period": "monthly", "weeklyBudgetUSD": 60}"#)
        }
    }

    /// Row 5: a group with neither amount is rejected (FR-004a).
    @Test func missingAmountIsADecodeError() {
        #expect(throws: DecodingError.self) { try decodeGroup(#"{"id": "g", "name": "V", "label": "V"}"#) }
        #expect(throws: DecodingError.self) { try decodeGroup(#"{"id": "g", "name": "V", "label": "V", "period": "weekly"}"#) }
        #expect(throws: DecodingError.self) { try decodeGroup(#"{"id": "g", "name": "V", "label": "V", "period": "monthly"}"#) }
    }

    /// Row 6: an unknown period string or a non-string period is rejected (FR-004a).
    @Test func invalidPeriodIsADecodeError() {
        #expect(throws: DecodingError.self) {
            try decodeGroup(#"{"id": "g", "name": "V", "label": "V", "period": "yearly", "budgetUSD": 60}"#)
        }
        #expect(throws: DecodingError.self) {
            try decodeGroup(#"{"id": "g", "name": "V", "label": "V", "period": 1, "budgetUSD": 60}"#)
        }
        // The whole configuration file is rejected, not just the group.
        let json = contractExampleJSON.replacingOccurrences(of: "\"weeklyBudgetUSD\": 60", with: "\"period\": \"yearly\", \"budgetUSD\": 60")
        #expect(throws: DecodingError.self) { try decodeConfig(json) }
    }

    /// Only an absent `period` means weekly; an explicit `null` is rejected (FR-004a).
    @Test func nullPeriodIsADecodeError() {
        #expect(throws: DecodingError.self) {
            try decodeGroup(#"{"id": "g", "name": "Vertex", "label": "V", "period": null, "budgetUSD": 60}"#)
        }
    }

    /// A period or amount change reprices at the next refresh without calling
    /// the usage endpoint (FR-010).
    @Test func periodChangeNeedsALocalRefreshOnly() throws {
        let base = try decodeConfig(contractExampleJSON)
        var period = base
        period.groups[0].period = .monthly
        #expect(period.needsRefresh(comparedTo: base))
        #expect(!period.needsNetworkRefresh(comparedTo: base))

        var amount = base
        amount.groups[0].budgetUSD = 400
        #expect(amount.needsRefresh(comparedTo: base))
        #expect(!amount.needsNetworkRefresh(comparedTo: base))
    }

    /// A group created without a period defaults to weekly (FR-002).
    @Test func memberwiseDefaultIsWeekly() {
        #expect(BudgetGroup(name: "G", budgetUSD: 10).period == .weekly)
    }

    /// The validation message names the period (FR-019).
    @Test func validationMessageNamesPeriod() throws {
        var config = try decodeConfig(contractExampleJSON)
        config.groups[0].budgetUSD = 0
        config.groups[0].period = .monthly
        do {
            try config.validate()
            Issue.record("expected a budget error")
        } catch let error as ConfigurationError {
            #expect(error.kind == .budget)
            #expect(error.message == "Monthly budget of group \"Vertex weekly\" must be greater than 0.")
        }
        config.groups[0].period = .weekly
        config.groups[0].budgetUSD = -1
        do {
            try config.validate()
            Issue.record("expected a budget error")
        } catch let error as ConfigurationError {
            #expect(error.message == "Weekly budget of group \"Vertex weekly\" must be greater than 0.")
        }
    }
}

/// Spec 004 icon labels: defaults, duplicates and the catalog check.
@Suite struct IconLabelTests {
    func message(_ config: Configuration) -> String? {
        do {
            try config.validate()
            return nil
        } catch let error as ConfigurationError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    /// FR-002: the Claude icon for subscriptions, the Google icon for Vertex
    /// accounts, the wallet icon for groups.
    @Test func defaultIconsPerType() {
        #expect(IconDefaults.defaultIcon(for: .subscription(SubscriptionSettings())) == "brands:claude")
        #expect(IconDefaults.defaultIcon(for: .tokenBased(TokenBasedSettings(groupId: "g", provider: .vertex))) == "brands:google")
        #expect(BudgetGroup(name: "G", budgetUSD: 10).icon == "solid:wallet")
        #expect(Account(displayName: "S", kind: .subscription(SubscriptionSettings())).icon == "brands:claude")
        #expect(Account(displayName: "V", kind: .tokenBased(TokenBasedSettings(groupId: "g"))).icon == "brands:google")
    }

    /// The defaults exist in the bundled catalog (spec assumption).
    @Test func defaultIconsExistInCatalog() {
        for icon in [IconDefaults.subscription, IconDefaults.vertex, IconDefaults.group] {
            #expect(IconCatalog.shared.contains(icon), "\(icon)")
        }
    }

    /// FR-003: two accounts and a group may share one icon.
    @Test func duplicateIconsAreAccepted() throws {
        var config = Configuration()
        config.accounts = [
            Account(id: "a", icon: "brands:claude", displayName: "Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude"))),
            Account(id: "b", icon: "brands:claude", displayName: "Work",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude-work"))),
            Account(id: "v", icon: "brands:claude", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "g"))),
        ]
        config.groups = [BudgetGroup(id: "g", name: "Team", icon: "brands:claude", budgetUSD: 60)]
        #expect(message(config) == nil)
    }

    /// FR-005: an icon outside the catalog makes the configuration invalid.
    @Test func unknownIconIsRejectedWithMessage() throws {
        var config = try decodeConfig(contractExampleJSON)
        config.accounts[0].icon = "brands:no-such-icon"
        #expect(validationKind(config) == .unknownIcon)
        #expect(message(config) == "Icon \"brands:no-such-icon\" of account \"Claude Max\" is not a known Font Awesome icon (expected style:name, for example brands:claude).")

        config.accounts[0].icon = IconDefaults.subscription
        config.groups[0].icon = "solid:nope"
        #expect(message(config) == "Icon \"solid:nope\" of group \"Vertex weekly\" is not a known Font Awesome icon (expected style:name, for example brands:claude).")
    }

    /// FR-007: the encoded file has no `label` key anywhere and an `icon`
    /// string on every account and group.
    @Test func encodingWritesIconsAndNoLabels() throws {
        let config = try decodeConfig(contractExampleJSON)
        let data = try JSONEncoder().encode(config)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"label\""))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        let groups = try #require(object["groups"] as? [[String: Any]])
        #expect(!accounts.isEmpty && !groups.isEmpty)
        for entry in accounts + groups {
            #expect(entry["label"] == nil)
            #expect(entry["icon"] is String)
        }
    }
}

/// Spec 004 US4: configuration files written by the previous version.
@Suite struct LegacyIconDecodingTests {
    /// A previous-version file: text labels, no icons, a shared group.
    static let legacyJSON = """
    {
      "accounts": [
        { "id": "acc-max", "type": "subscription", "label": "M", "displayName": "Claude Max",
          "credentialDirectory": "~/.claude", "shownInBar": true, "thresholds": [80, 100] },
        { "id": "acc-v1", "type": "tokenBased", "label": "V1", "displayName": "Vertex one",
          "provider": "vertex", "groupId": "grp" },
        { "id": "acc-v2", "type": "tokenBased", "label": "V2", "displayName": "Vertex two",
          "provider": "vertex", "groupId": "grp", "customMarker": null }
      ],
      "groups": [
        { "id": "grp", "name": "Team", "label": "T", "period": "monthly", "budgetUSD": 300,
          "shownInBar": false, "thresholds": [50, 90] }
      ]
    }
    """

    /// FR-006: entries without an icon get their type's default.
    @Test func labelsOnlyGetDefaultIcons() throws {
        let config = try decodeConfig(Self.legacyJSON)
        #expect(config.accounts.map(\.icon) == ["brands:claude", "brands:google", "brands:google"])
        #expect(config.groups[0].icon == "solid:wallet")
        // Budgets, thresholds and memberships are unchanged (SC-002).
        let group = config.groups[0]
        #expect(group.period == .monthly)
        #expect(group.budgetUSD == 300)
        #expect(group.shownInBar == false)
        #expect(group.thresholds == [50, 90])
        #expect(config.members(of: "grp").map(\.id) == ["acc-v1", "acc-v2"])
        #expect(config.accounts[1].kind.tokenBased?.memberShownInBar == false)
        #expect(config.accounts[0].kind.subscription?.thresholds == [80, 100])
        #expect(validationKind(config) == nil)
    }

    /// FR-006: a `null` or empty icon also falls back to the default.
    @Test func nullAndEmptyIconsFallBack() throws {
        for value in ["null", "\"\""] {
            let json = Self.legacyJSON
                .replacingOccurrences(of: "\"label\": \"M\",", with: "\"label\": \"M\", \"icon\": \(value),")
                .replacingOccurrences(of: "\"label\": \"V1\",", with: "\"label\": \"V1\", \"icon\": \(value),")
                .replacingOccurrences(of: "\"label\": \"T\",", with: "\"label\": \"T\", \"icon\": \(value),")
            let config = try decodeConfig(json)
            #expect(config.accounts[0].icon == "brands:claude", "\(value)")
            #expect(config.accounts[1].icon == "brands:google", "\(value)")
            #expect(config.groups[0].icon == "solid:wallet", "\(value)")
        }
    }

    /// FR-006, US4 scenario 2: a stored icon is kept and the label ignored.
    @Test func storedIconIsKept() throws {
        let json = Self.legacyJSON
            .replacingOccurrences(of: "\"label\": \"M\",", with: "\"label\": \"M\", \"icon\": \"solid:robot\",")
            .replacingOccurrences(of: "\"label\": \"T\",", with: "\"label\": \"T\", \"icon\": \"solid:cloud\",")
        let config = try decodeConfig(json)
        #expect(config.accounts[0].icon == "solid:robot")
        #expect(config.groups[0].icon == "solid:cloud")
    }
}

/// Spec 004 FR-008, FR-009: every token-based row of contracts/config-file.md.
@Suite struct OwnBudgetDecodingTests {
    static func json(_ tokenFields: String) -> String {
        """
        {
          "accounts": [
            { "id": "acc-max", "type": "subscription", "icon": "brands:claude", "displayName": "Claude Max" },
            { "id": "acc-own", "type": "tokenBased", "displayName": "Personal Vertex", "provider": "vertex"\(tokenFields) },
            { "id": "acc-team", "type": "tokenBased", "displayName": "Team Vertex", "provider": "vertex", "groupId": "grp" }
          ],
          "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 300 } ]
        }
        """
    }

    func message(_ config: Configuration) -> String? {
        do {
            try config.validate()
            return nil
        } catch let error as ConfigurationError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    @Test func groupIdOnlyIsAMemberWithShareHidden() throws {
        let config = try decodeConfig(Self.json(#", "groupId": "grp""#))
        let settings = try #require(config.accounts[1].kind.tokenBased)
        #expect(settings.membership == .group(id: "grp", shownInBar: false))
        #expect(settings.groupId == "grp")
        #expect(settings.ownBudget == nil)
        #expect(settings.memberShownInBar == false)

        let shown = try decodeConfig(Self.json(#", "groupId": "grp", "shownInBar": true"#))
        #expect(shown.accounts[1].kind.tokenBased?.memberShownInBar == true)
    }

    @Test func budgetOnlyIsAnOwnBudget() throws {
        let config = try decodeConfig(Self.json(#", "budget": { "period": "monthly", "budgetUSD": 100, "shownInBar": false, "thresholds": [50] }"#))
        let settings = try #require(config.accounts[1].kind.tokenBased)
        #expect(settings.groupId == nil)
        #expect(settings.ownBudget == BudgetSettings(period: .monthly, budgetUSD: 100, shownInBar: false, thresholds: [50]))
        #expect(settings.memberShownInBar == false)
        #expect(message(config) == nil)
    }

    @Test func bothOrNeitherThrows() {
        #expect(throws: DecodingError.self) {
            try decodeConfig(Self.json(#", "groupId": "grp", "budget": { "budgetUSD": 100 }"#))
        }
        #expect(throws: DecodingError.self) { try decodeConfig(Self.json("")) }
    }

    @Test func budgetDefaults() throws {
        let config = try decodeConfig(Self.json(#", "budget": { "budgetUSD": 100 }"#))
        let budget = try #require(config.accounts[1].kind.tokenBased?.ownBudget)
        #expect(budget.period == .weekly)
        #expect(budget.shownInBar == true)
        #expect(budget.thresholds == [])
    }

    @Test func badPeriodOrMissingAmountThrows() {
        for fields in [#", "budget": { "period": null, "budgetUSD": 100 }"#,
                       #", "budget": { "period": "yearly", "budgetUSD": 100 }"#,
                       #", "budget": { "period": 1, "budgetUSD": 100 }"#,
                       #", "budget": { "period": "monthly" }"#] {
            #expect(throws: DecodingError.self, "\(fields)") { try decodeConfig(Self.json(fields)) }
        }
    }

    @Test func zeroAmountAndBadThresholdFailValidation() throws {
        let zero = try decodeConfig(Self.json(#", "budget": { "budgetUSD": 0 }"#))
        #expect(validationKind(zero) == .budget)
        #expect(message(zero) == "Weekly budget of account \"Personal Vertex\" must be greater than 0.")

        let monthly = try decodeConfig(Self.json(#", "budget": { "period": "monthly", "budgetUSD": -5 }"#))
        #expect(message(monthly) == "Monthly budget of account \"Personal Vertex\" must be greater than 0.")

        let threshold = try decodeConfig(Self.json(#", "budget": { "budgetUSD": 100, "thresholds": [0] }"#))
        #expect(validationKind(threshold) == .threshold)
        #expect(message(threshold) == "Thresholds of account \"Personal Vertex\" must be whole-number percents greater than 0 (got 0).")
    }

    @Test func ownBudgetRoundTrips() throws {
        let config = try decodeConfig(Self.json(#", "budget": { "period": "monthly", "budgetUSD": 100.5, "thresholds": [80, 100] }"#))
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Configuration.self, from: data) == config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        #expect(accounts[1]["groupId"] == nil)
        #expect(accounts[1]["budget"] is [String: Any])
        #expect(accounts[2]["groupId"] as? String == "grp")
        #expect(accounts[2]["shownInBar"] as? Bool == false)
        #expect(accounts[2]["budget"] == nil)
    }
}

/// Spec 004 FR-014, research R4 and R7: budget owners and membership moves.
@Suite struct BudgetOwnerTests {
    /// Accounts: a subscription, own budget A, members m1 and m2 of "team",
    /// own budget B, and the single member s1 of "solo".
    func config() -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "max", displayName: "Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "own-a", displayName: "Own A",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(period: .monthly, budgetUSD: 100, thresholds: [50]))))),
            Account(id: "m1", displayName: "Member one", kind: .tokenBased(TokenBasedSettings(membership: .group(id: "team", shownInBar: true)))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "team"))),
            Account(id: "own-b", displayName: "Own B",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 20))))),
            Account(id: "s1", displayName: "Solo member", kind: .tokenBased(TokenBasedSettings(groupId: "solo"))),
        ]
        c.groups = [
            BudgetGroup(id: "team", name: "Team", period: .monthly, budgetUSD: 300, shownInBar: false, thresholds: [70, 95]),
            BudgetGroup(id: "solo", name: "Solo", icon: "solid:cloud", budgetUSD: 40, thresholds: [90]),
        ]
        return c
    }

    @Test func ownersListGroupsThenStandaloneAccounts() throws {
        let c = config()
        try c.validate()
        let owners = c.budgetOwners
        #expect(owners.map(\.id) == ["team", "solo", "own-a", "own-b"])
        #expect(owners.map(\.kind) == [.group, .group, .account, .account])
        #expect(owners[0].memberIds == ["m1", "m2"])
        #expect(owners[0].name == "Team")
        #expect(owners[0].icon == "solid:wallet")
        #expect(owners[0].budget == BudgetSettings(period: .monthly, budgetUSD: 300, shownInBar: false, thresholds: [70, 95]))
        #expect(owners[2].memberIds == ["own-a"])
        #expect(owners[2].name == "Own A")
        #expect(owners[2].icon == "brands:google")
        #expect(owners[2].budget.period == .monthly)

        #expect(c.budgetOwner(forAccount: "m2")?.id == "team")
        #expect(c.budgetOwner(forAccount: "own-b")?.id == "own-b")
        #expect(c.budgetOwner(forAccount: "max") == nil)
        #expect(c.budgetOwner(forAccount: "nope") == nil)
    }

    @Test func movingToOwnBudgetPrefillsFromTheGroup() throws {
        let moved = config().movingAccountToOwnBudget(accountId: "m1")
        #expect(moved.account(id: "m1")?.kind.tokenBased?.ownBudget
                == BudgetSettings(period: .monthly, budgetUSD: 300, shownInBar: false, thresholds: [70, 95]))
        // The group keeps its remaining member.
        #expect(moved.group(id: "team") != nil)
        #expect(moved.members(of: "team").map(\.id) == ["m2"])
        try moved.validate()

        // The last member leaving keeps the group with all its settings
        // (spec 009 FR-002, FR-004).
        let solo = config().movingAccountToOwnBudget(accountId: "s1")
        #expect(solo.groups == config().groups)
        #expect(solo.members(of: "solo").isEmpty)
        #expect(solo.account(id: "s1")?.kind.tokenBased?.ownBudget == BudgetSettings(budgetUSD: 40, thresholds: [90]))
        try solo.validate()

        // An account that already has its own budget is unchanged.
        #expect(config().movingAccountToOwnBudget(accountId: "own-a") == config())
    }

    @Test func movingToGroupDiscardsTheOwnBudget() throws {
        let moved = config().movingAccountToGroup(accountId: "own-a", groupId: "team")
        let settings = try #require(moved.account(id: "own-a")?.kind.tokenBased)
        #expect(settings.membership == .group(id: "team", shownInBar: false))
        #expect(settings.memberShownInBar == false)
        #expect(moved.members(of: "team").map(\.id) == ["own-a", "m1", "m2"])
        #expect(moved.budgetOwners.map(\.id) == ["team", "solo", "own-b"])
        try moved.validate()

        // Moving the only member of "solo" to "team" keeps "solo", empty
        // (spec 009 FR-002), and the member's shown-in-bar setting starts
        // off in the new group.
        let emptied = config().movingAccountToGroup(accountId: "s1", groupId: "team")
        #expect(emptied.groups == config().groups)
        #expect(emptied.members(of: "solo").isEmpty)
        #expect(emptied.account(id: "s1")?.kind.tokenBased?.membership == .group(id: "team", shownInBar: false))
        try emptied.validate()

        // m1 moving to "solo" leaves "team" with m2 and resets its share flag.
        let switched = config().movingAccountToGroup(accountId: "m1", groupId: "solo")
        #expect(switched.account(id: "m1")?.kind.tokenBased?.membership == .group(id: "solo", shownInBar: false))
        #expect(switched.group(id: "team") != nil)
    }

    /// Research R8: own-budget visibility and thresholds, and a member's
    /// share in the bar, are presentation only; period and amount are not.
    @Test func ownBudgetRelevance() throws {
        let base = config()
        func editingOwnA(_ change: (inout BudgetSettings) -> Void) -> Configuration {
            var copy = base
            var budget = copy.accounts[1].kind.tokenBased!.ownBudget!
            change(&budget)
            copy.accounts[1].kind = .tokenBased(TokenBasedSettings(membership: .ownBudget(budget)))
            return copy
        }
        let presentation = editingOwnA { $0.shownInBar.toggle(); $0.thresholds = [10, 20] }
        #expect(!presentation.needsRefresh(comparedTo: base))

        var member = base
        member.accounts[3].kind = .tokenBased(TokenBasedSettings(membership: .group(id: "team", shownInBar: true)))
        #expect(!member.needsRefresh(comparedTo: base))

        for edited in [editingOwnA { $0.period = .weekly }, editingOwnA { $0.budgetUSD = 150 },
                       base.movingAccountToGroup(accountId: "own-a", groupId: "team")] {
            #expect(edited.needsRefresh(comparedTo: base))
            #expect(!edited.needsNetworkRefresh(comparedTo: base))
        }
        #expect(!presentation.needsNetworkRefresh(comparedTo: base))
    }
}

// MARK: - Spec 006: harnesses, OpenAI provider, Codex subscriptions

/// spec 006 FR-016 to FR-018, contracts/config-file.md.
@Suite struct HarnessConfigurationTests {
    static let json = """
    {
      "logDirectories": [],
      "codexHomes": ["~/.codex-work"],
      "openCodeDirectories": ["~/oc-data"],
      "accounts": [
        { "id": "acc-oai", "type": "tokenBased", "icon": "brands:openai", "displayName": "OpenAI API",
          "harness": "claudeCode", "provider": "openai", "customMarker": null,
          "budget": { "period": "monthly", "budgetUSD": 50, "shownInBar": true, "thresholds": [80, 100] } },
        { "id": "acc-codex", "type": "codexSubscription", "icon": "brands:openai", "displayName": "ChatGPT Plus",
          "harness": "codex", "codexHome": "~/.codex-work", "customMarker": null },
        { "id": "acc-codex2", "type": "codexSubscription", "displayName": "ChatGPT Default" }
      ]
    }
    """

    @Test func decodesCodexSubscriptionAndOpenAI() throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.json)
        // The dropped extra homes are only noted (spec 034 FR-011).
        #expect(notes == [#"codexHomes entry "~/.codex-work" is no longer read; it is already covered by account "ChatGPT Plus""#])
        #expect(config.openCodeDirectories == ["~/oc-data"])
        #expect(config.accounts[0].kind.tokenBased?.provider == .openai)
        #expect(config.accounts[1].kind.codexSubscription?.codexHome == "~/.codex-work")
        #expect(config.accounts[1].harness == .codex)
        // Without codexHome the default home applies; without icon the OpenAI icon.
        #expect(config.accounts[2].kind.codexSubscription?.codexHome == "~/.codex")
        #expect(config.accounts[2].icon == "brands:openai")
        #expect(config.codexSubscriptionAccounts.map(\.id) == ["acc-codex", "acc-codex2"])
        #expect(config.tokenBasedAccounts.map(\.id) == ["acc-oai"])
        #expect(config.subscriptionAccounts.isEmpty)
        try config.validate()
    }

    @Test func roundTrips() throws {
        let config = try decodeConfig(Self.json)
        let data = try JSONEncoder().encode(config)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"type\":\"codexSubscription\""))
        #expect(text.contains("\"codexHome\""))
        #expect(!text.contains("\"codexHomes\""))
        #expect(!text.contains("\"logDirectories\""))
        #expect(text.contains("\"openCodeDirectories\""))
        #expect(try JSONDecoder().decode(Configuration.self, from: data) == config)
    }

    @Test func locationListsAreOptional() throws {
        let config = try decodeConfig("{}")
        #expect(config.openCodeDirectories.isEmpty)
    }

    /// SC-005: a file of the previous version decodes unchanged.
    @Test func previousVersionFileDecodesUnchanged() throws {
        let config = try decodeConfig(contractExampleJSON)
        #expect(config.openCodeDirectories.isEmpty)
        #expect(config.codexSubscriptionAccounts.isEmpty)
        #expect(config.tokenBasedAccounts.map(\.id) == ["acc-vertex"])
        #expect(config.subscriptionAccounts.map(\.id) == ["acc-max"])
        try config.validate()
    }

    @Test func unknownProviderIsADecodeError() {
        let json = """
        { "accounts": [ { "id": "a", "type": "tokenBased", "displayName": "X", "provider": "azure", "budget": { "budgetUSD": 5 } } ] }
        """
        #expect(throws: DecodingError.self) { try decodeConfig(json) }
    }

    @Test func duplicateCodexHomeIsInvalid() throws {
        var config = try decodeConfig(Self.json)
        config.accounts[2].kind = .codexSubscription(CodexSubscriptionSettings(codexHome: "~/.codex-work/"))
        #expect(validationKind(config) == .duplicateCodexHome)
        config.accounts[2].kind = .codexSubscription(CodexSubscriptionSettings(codexHome: "~/.codex"))
        #expect(validationKind(config) == nil)
    }

    /// A symlink or `..` spelling of another account's Codex home is the
    /// same home (spec 007 FR-003, FR-007).
    @Test func aliasedCodexHomeIsInvalid() throws {
        let root = try makeTempDirectory("config-codex-alias")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("codex-real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("codex-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        var config = try decodeConfig(Self.json)
        config.accounts[1].kind = .codexSubscription(CodexSubscriptionSettings(codexHome: real.path))
        config.accounts[2].kind = .codexSubscription(CodexSubscriptionSettings(codexHome: link.path))
        #expect(validationKind(config) == .duplicateCodexHome)
        config.accounts[2].kind = .codexSubscription(CodexSubscriptionSettings(codexHome: root.path + "/x/../codex-real"))
        #expect(validationKind(config) == .duplicateCodexHome)
        config.accounts[2].kind = .codexSubscription(CodexSubscriptionSettings(codexHome: root.appendingPathComponent("codex-other").path))
        #expect(validationKind(config) == nil)
    }

    @Test func defaultIconsForNewKinds() {
        #expect(IconDefaults.defaultIcon(for: .openai) == "brands:openai")
        #expect(IconDefaults.defaultIcon(for: .tokenBased(TokenBasedSettings(groupId: "g", provider: .openai))) == "brands:openai")
        #expect(IconDefaults.defaultIcon(for: .codexSubscription(CodexSubscriptionSettings())) == "brands:openai")
        #expect(IconCatalog.shared.contains(IconDefaults.openai))
    }

    @Test func harnessDisplayNames() {
        #expect(Harness.claudeCode.displayName == "Claude Code")
        #expect(Harness.codex.displayName == "Codex")
        #expect(Harness.openCode.displayName == "OpenCode")
    }
}

// MARK: - Spec 007: Codex plan limits settings

/// spec 007 FR-016, FR-017, contracts/config-file.md, research R9.
@Suite struct CodexPlanLimitsConfigurationTests {
    static func codexAccount(id: String = "acc-codex", home: String = "~/.codex",
                             shownInBar: Bool = true, thresholds: [Int] = [], liveLimits: Bool = true) -> Account {
        Account(id: id, displayName: "ChatGPT Plus", harness: .codex,
                kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home, shownInBar: shownInBar,
                                                                   thresholds: thresholds, liveLimits: liveLimits)))
    }

    /// FR-017: a spec 006 account (only `codexHome`) gets the defaults.
    @Test func previousVersionAccountGetsDefaults() throws {
        let config = try decodeConfig(HarnessConfigurationTests.json)
        let settings = try #require(config.accounts[1].kind.codexSubscription)
        #expect(settings.shownInBar == true)
        #expect(settings.thresholds == [])
        #expect(settings.liveLimits == true)
        let bare = try #require(config.accounts[2].kind.codexSubscription)
        #expect(bare == CodexSubscriptionSettings())
    }

    @Test func allKeysRoundTrip() throws {
        let json = """
        { "accounts": [ { "id": "acc-codex", "type": "codexSubscription", "displayName": "ChatGPT Plus",
          "harness": "codex", "codexHome": "~/.codex-work", "shownInBar": false, "thresholds": [80, 95], "liveLimits": false } ] }
        """
        let config = try decodeConfig(json)
        let settings = try #require(config.accounts[0].kind.codexSubscription)
        #expect(settings == CodexSubscriptionSettings(codexHome: "~/.codex-work", shownInBar: false, thresholds: [80, 95], liveLimits: false))
        let data = try JSONEncoder().encode(config)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"liveLimits\":false"))
        #expect(text.contains("\"shownInBar\":false"))
        #expect(text.contains("\"thresholds\":[80,95]"))
        #expect(try JSONDecoder().decode(Configuration.self, from: data) == config)

        // Defaults are written too (contracts/config-file.md: always written).
        let defaults = Configuration(accounts: [Self.codexAccount()])
        let written = String(decoding: try JSONEncoder().encode(defaults), as: UTF8.self)
        #expect(written.contains("\"liveLimits\":true"))
        #expect(written.contains("\"shownInBar\":true"))
        #expect(written.contains("\"thresholds\":[]"))
    }

    /// FR-014: thresholds are whole-number percents greater than 0.
    @Test func nonPositiveThresholdIsInvalid() {
        var config = Configuration(accounts: [Self.codexAccount(thresholds: [80, 0])])
        #expect(validationKind(config) == .threshold)
        config.accounts[0] = Self.codexAccount(thresholds: [-5])
        #expect(validationKind(config) == .threshold)
        config.accounts[0] = Self.codexAccount(thresholds: [80, 95])
        #expect(validationKind(config) == nil)
    }

    /// Bar visibility and thresholds are presentation only; live limits
    /// change what a refresh computes (research R9).
    @Test func onlyLiveLimitsNeedsARefresh() {
        let base = Configuration(accounts: [Self.codexAccount()])
        let hidden = Configuration(accounts: [Self.codexAccount(shownInBar: false)])
        let thresholds = Configuration(accounts: [Self.codexAccount(thresholds: [80])])
        let localOnly = Configuration(accounts: [Self.codexAccount(liveLimits: false)])
        #expect(!hidden.needsRefresh(comparedTo: base))
        #expect(!thresholds.needsRefresh(comparedTo: base))
        #expect(localOnly.needsRefresh(comparedTo: base))
    }

    /// FR-016: a Codex account is never the designated subscription.
    @Test func codexAccountIsNeverTheAlignmentAccount() throws {
        let claude = Account(id: "acc-max", displayName: "Claude Max", kind: .subscription(SubscriptionSettings()))
        var config = Configuration(accounts: [Self.codexAccount(), claude])
        #expect(config.effectiveAlignmentAccountId == "acc-max")
        config.alignmentAccountId = "acc-codex"
        #expect(validationKind(config) == .alignmentAccount)
        #expect(config.effectiveAlignmentAccountId == "acc-max")
        config.alignmentAccountId = "acc-max"
        #expect(validationKind(config) == nil)
    }
}

/// Spec 012 FR-001 to FR-003, SC-005: the level display settings.
@Suite struct LevelDisplayConfigurationTests {
    /// Decodes `json` with a fresh load-notes collector in the decoder's userInfo.
    private func decodeWithNotes(_ json: String) throws -> (Configuration, [String]) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (config, notes.notes)
    }

    @Test func absentSettingsUseTheDefaults() throws {
        let (config, notes) = try decodeWithNotes(currentExampleJSON)
        #expect(config.levelColor == .text)
        #expect(config.showLevelSymbols == false)
        #expect(notes.isEmpty)
        #expect(Configuration().levelColor == .text)
        #expect(Configuration().showLevelSymbols == false)
    }

    @Test(arguments: [("text", LevelColorStyle.text), ("pill", .pill), ("off", .off)])
    func knownValuesDecodeAsGiven(raw: String, expected: LevelColorStyle) throws {
        let (config, notes) = try decodeWithNotes(#"{ "levelColor": "\#(raw)", "showLevelSymbols": true }"#)
        #expect(config.levelColor == expected)
        #expect(config.showLevelSymbols == true)
        #expect(notes.isEmpty)
    }

    /// FR-003: unknown, wrong-case or non-string (including null) values
    /// fall back to text with exactly one note and no error.
    @Test(arguments: [#""rainbow""#, #""Pill""#, "3", "null"])
    func unreadableLevelColorFallsBackToText(value: String) throws {
        let (config, notes) = try decodeWithNotes(#"{ "levelColor": \#(value) }"#)
        #expect(config.levelColor == .text)
        #expect(notes.count == 1)
        #expect(notes.first?.contains("levelColor") == true)
        try config.validate()
    }

    /// A long unknown value is clipped in the note, so it never reaches
    /// the diagnostic log whole.
    @Test func longUnknownLevelColorIsClippedInTheNote() throws {
        let long = String(repeating: "x", count: 10_000)
        let (config, notes) = try decodeWithNotes(#"{ "levelColor": "\#(long)" }"#)
        #expect(config.levelColor == .text)
        #expect(notes.count == 1)
        #expect((notes.first?.count ?? .max) < 100)
        #expect(notes.first?.contains(String(repeating: "x", count: 32) + "...") == true)
    }

    @Test func unknownLevelColorWithoutCollectorStillDecodes() throws {
        let config = try decodeConfig(#"{ "levelColor": "rainbow" }"#)
        #expect(config.levelColor == .text)
    }

    /// Consistent with `startAtLogin`: a wrong type is a decoding error.
    @Test func nonBooleanShowLevelSymbolsIsADecodingError() {
        #expect(throws: DecodingError.self) { try decodeConfig(#"{ "showLevelSymbols": "yes" }"#) }
    }

    /// FR-003, clarification 3: both keys are written on save, and an
    /// unknown value is written back as the value in effect.
    @Test func encodingWritesBothKeysAndReplacesUnknownValues() throws {
        let (config, _) = try decodeWithNotes(#"{ "levelColor": "rainbow" }"#)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(config), as: UTF8.self)
        #expect(json.contains(#""levelColor":"text""#))
        #expect(json.contains(#""showLevelSymbols":false"#))

        var pill = Configuration()
        pill.levelColor = .pill
        pill.showLevelSymbols = true
        let roundTrip = try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(pill))
        #expect(roundTrip.levelColor == .pill)
        #expect(roundTrip.showLevelSymbols == true)
    }

    /// FR-004: presentation only, so no refresh.
    @Test func levelSettingsNeedNoRefresh() throws {
        let base = try decodeConfig(contractExampleJSON)
        var color = base
        color.levelColor = .pill
        var symbols = base
        symbols.showLevelSymbols = true
        for edited in [color, symbols] {
            #expect(edited != base)
            #expect(!edited.needsRefresh(comparedTo: base))
            #expect(!edited.needsNetworkRefresh(comparedTo: base))
        }
    }

    @Test func levelDisplayBundlesBothSettings() {
        var config = Configuration()
        #expect(config.levelDisplay == LevelDisplaySettings.default)
        config.levelColor = .off
        config.showLevelSymbols = true
        #expect(config.levelDisplay == LevelDisplaySettings(levelColor: .off, showSymbols: true))
    }

    /// FR-001, FR-002: colored text without symbols by default.
    @Test func defaultLevelDisplayIsTextWithoutSymbols() {
        #expect(LevelDisplaySettings.default == LevelDisplaySettings(levelColor: .text, showSymbols: false))
    }
}

/// spec 030 FR-008: the global display direction, used by default and read
/// leniently, so an older or hand-edited file never fails to load.
@Suite struct DisplayDirectionConfigurationTests {
    @Test func missingKeyDecodesAsUsed() throws {
        #expect(try decodeConfig("{}").displayDirection == .used)
        #expect(Configuration().displayDirection == .used)
    }

    @Test func remainingDecodesAsRemaining() throws {
        #expect(try decodeConfig(#"{ "displayDirection": "remaining" }"#).displayDirection == .remaining)
        #expect(try decodeConfig(#"{ "displayDirection": "used" }"#).displayDirection == .used)
    }

    /// Wrong case, unknown strings, other types and null fall back to used
    /// without failing the file.
    @Test(arguments: [#""Remaining""#, #""sideways""#, "42", "null"])
    func unreadableValueFallsBackToUsed(value: String) throws {
        let config = try decodeConfig(#"{ "displayDirection": \#(value) }"#)
        #expect(config.displayDirection == .used)
        try config.validate()
    }

    private func decodeWithNotes(_ json: String) throws -> (Configuration, [String]) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (config, notes.notes)
    }

    /// The fallback leaves one note for the diagnostic log: unknown strings
    /// are named, other types and null are not readable; a missing key or a
    /// known value leaves none (spec 030 FR-008).
    @Test func fallbackLeavesANote() throws {
        #expect(try decodeWithNotes(#"{ "displayDirection": "sideways" }"#).1
                == [#"displayDirection "sideways" is not known, using used"#])
        #expect(try decodeWithNotes(#"{ "displayDirection": "Remaining" }"#).1
                == [#"displayDirection "Remaining" is not known, using used"#])
        #expect(try decodeWithNotes(#"{ "displayDirection": 42 }"#).1 == ["displayDirection is not readable, using used"])
        #expect(try decodeWithNotes(#"{ "displayDirection": null }"#).1 == ["displayDirection is not readable, using used"])
        #expect(try decodeWithNotes("{}").1.isEmpty)
        #expect(try decodeWithNotes(#"{ "displayDirection": "remaining" }"#).1.isEmpty)
    }

    @Test(arguments: [DisplayDirection.used, .remaining])
    func encodingRoundTrips(direction: DisplayDirection) throws {
        var config = try decodeConfig(contractExampleJSON)
        config.displayDirection = direction
        let decoded = try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(config))
        #expect(decoded.displayDirection == direction)
        #expect(decoded == config)
    }

    /// A file written before spec 030 loads with direction used and its
    /// thresholds unchanged.
    @Test func olderFileLoadsUnchanged() throws {
        let config = try decodeConfig(contractExampleJSON)
        #expect(config.displayDirection == .used)
        #expect(config.account(id: "acc-max")?.kind.subscription?.thresholds == [80, 100])
        try config.validate()
    }

    /// SC-004: switching the direction never changes the stored
    /// thresholds; they encode and decode in used percent either way.
    @Test func directionKeepsTheStoredThresholds() throws {
        let used = try decodeConfig(contractExampleJSON)
        var remaining = used
        remaining.displayDirection = .remaining
        let decoded = try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(remaining))
        #expect(decoded.account(id: "acc-max")?.kind.subscription?.thresholds == [80, 100])
        #expect(decoded.groups.map(\.thresholds) == used.groups.map(\.thresholds))
        #expect(decoded.accounts == used.accounts)
    }

    /// The direction is presentation only, so it needs no refresh.
    @Test func directionNeedsNoRefresh() throws {
        let base = try decodeConfig(contractExampleJSON)
        var remaining = base
        remaining.displayDirection = .remaining
        #expect(remaining != base)
        #expect(!remaining.needsRefresh(comparedTo: base))
        #expect(!remaining.needsNetworkRefresh(comparedTo: base))
    }
}

/// spec 032 FR-003: the dropdown theme, Auto by default, read leniently and
/// written only when it is not Auto.
@Suite struct DropdownThemeConfigurationTests {
    @Test func missingKeyDecodesAsAuto() throws {
        #expect(try decodeConfig("{}").dropdownTheme == .auto)
        #expect(Configuration().dropdownTheme == .auto)
    }

    @Test(arguments: [DropdownTheme.auto, .dark, .light])
    func knownValueDecodes(theme: DropdownTheme) throws {
        #expect(try decodeConfig(#"{ "dropdownTheme": "\#(theme.rawValue)" }"#).dropdownTheme == theme)
    }

    /// Wrong case, unknown strings, other types and null fall back to Auto
    /// without failing the file.
    @Test(arguments: [#""Dark""#, #""sepia""#, "42", "true", "null"])
    func unreadableValueFallsBackToAuto(value: String) throws {
        let config = try decodeConfig(#"{ "dropdownTheme": \#(value) }"#)
        #expect(config.dropdownTheme == .auto)
        #expect(config == Configuration())
        try config.validate()
    }

    private func decodeWithNotes(_ json: String) throws -> (Configuration, [String]) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (config, notes.notes)
    }

    /// The fallback leaves one note for the diagnostic log, like
    /// `displayDirection` (spec 030 FR-008); a missing key, `"auto"` or a
    /// known value leaves none.
    @Test func fallbackLeavesANote() throws {
        #expect(try decodeWithNotes(#"{ "dropdownTheme": "sepia" }"#).1
                == [#"dropdownTheme "sepia" is not known, using auto"#])
        #expect(try decodeWithNotes(#"{ "dropdownTheme": "Dark" }"#).1
                == [#"dropdownTheme "Dark" is not known, using auto"#])
        #expect(try decodeWithNotes(#"{ "dropdownTheme": 42 }"#).1 == ["dropdownTheme is not readable, using auto"])
        #expect(try decodeWithNotes(#"{ "dropdownTheme": true }"#).1 == ["dropdownTheme is not readable, using auto"])
        #expect(try decodeWithNotes(#"{ "dropdownTheme": null }"#).1 == ["dropdownTheme is not readable, using auto"])
        #expect(try decodeWithNotes("{}").1.isEmpty)
        #expect(try decodeWithNotes(#"{ "dropdownTheme": "auto" }"#).1.isEmpty)
        #expect(try decodeWithNotes(#"{ "dropdownTheme": "light" }"#).1.isEmpty)
    }

    private func encodedObject(_ config: Configuration) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Auto writes no key, whether it was never set or set back.
    @Test func autoIsNotWritten() throws {
        #expect(try encodedObject(Configuration())["dropdownTheme"] == nil)
        var config = try decodeConfig(contractExampleJSON)
        config.dropdownTheme = .auto
        #expect(try encodedObject(config)["dropdownTheme"] == nil)
        let decoded = try decodeConfig(#"{ "dropdownTheme": "auto" }"#)
        #expect(try encodedObject(decoded)["dropdownTheme"] == nil)
    }

    @Test(arguments: [DropdownTheme.dark, .light])
    func fixedThemeIsWrittenAndRoundTrips(theme: DropdownTheme) throws {
        var config = try decodeConfig(contractExampleJSON)
        config.dropdownTheme = theme
        #expect(try encodedObject(config)["dropdownTheme"] as? String == theme.rawValue)
        let decoded = try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(config))
        #expect(decoded.dropdownTheme == theme)
        #expect(decoded == config)
    }

    /// Setting Auto after Dark gives a configuration equal to one that never
    /// had a theme.
    @Test func settingAutoAfterDarkEqualsNeverSet() throws {
        let base = try decodeConfig(contractExampleJSON)
        var config = base
        config.dropdownTheme = .dark
        #expect(config != base)
        config.dropdownTheme = .auto
        #expect(config == base)
        #expect(Configuration(dropdownTheme: .auto) == Configuration())
        #expect(Configuration(dropdownTheme: .light).dropdownTheme == .light)
    }

    /// The theme is presentation only, so it needs no refresh.
    @Test(arguments: [DropdownTheme.dark, .light])
    func themeNeedsNoRefresh(theme: DropdownTheme) throws {
        let base = try decodeConfig(contractExampleJSON)
        var changed = base
        changed.dropdownTheme = theme
        #expect(changed != base)
        #expect(!changed.needsRefresh(comparedTo: base))
        #expect(!changed.needsNetworkRefresh(comparedTo: base))
    }
}

/// spec 011 FR-014: the run-out marker toggle, on by default and tolerant
/// of configurations written before it existed.
@Suite struct RunOutMarkerSettingTests {
    @Test func defaultConfigurationShowsTheMarker() {
        #expect(Configuration().showsRunOutMarker == true)
    }

    @Test func missingKeyDecodesAsOn() throws {
        let config = try decodeConfig(contractExampleJSON)
        #expect(config.showsRunOutMarker == true)
        let empty = try decodeConfig("{}")
        #expect(empty.showsRunOutMarker == true)
    }

    @Test func falseDecodesAsOff() throws {
        let config = try decodeConfig(#"{ "showsRunOutMarker": false }"#)
        #expect(config.showsRunOutMarker == false)
    }

    @Test func roundTrips() throws {
        var config = Configuration()
        config.showsRunOutMarker = false
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(decoded.showsRunOutMarker == false)
        #expect(decoded == config)
        config.showsRunOutMarker = true
        let on = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(on.showsRunOutMarker == true)
    }

    /// The marker is presentation only: toggling it needs no refresh.
    @Test func togglingNeedsNoRefresh() {
        let base = Configuration()
        var edited = base
        edited.showsRunOutMarker = false
        #expect(!edited.needsRefresh(comparedTo: base))
    }
}

/// spec 016 FR-001, research R10: the "Adapt refresh" setting, on by
/// default and decoded leniently (a non-boolean behaves as on and leaves a
/// load note).
@Suite struct AdaptiveRefreshSettingTests {
    private func decodeWithNotes(_ json: String) throws -> (Configuration, [String]) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (config, notes.notes)
    }

    @Test func missingKeyDecodesAsOn() throws {
        #expect(Configuration().adaptiveRefresh == true)
        let (config, notes) = try decodeWithNotes(currentExampleJSON)
        #expect(config.adaptiveRefresh == true)
        #expect(notes.isEmpty)
        let (empty, _) = try decodeWithNotes("{}")
        #expect(empty.adaptiveRefresh == true)
    }

    @Test(arguments: [true, false])
    func booleansDecodeAsGiven(value: Bool) throws {
        let (config, notes) = try decodeWithNotes(#"{ "adaptiveRefresh": \#(value) }"#)
        #expect(config.adaptiveRefresh == value)
        #expect(notes.isEmpty)
    }

    /// FR-001: unlike other booleans, a wrong type never makes the
    /// configuration invalid; it behaves as on with exactly one note.
    @Test(arguments: [#""yes""#, "3", "null"])
    func nonBooleanDecodesAsOnWithANote(value: String) throws {
        let (config, notes) = try decodeWithNotes(#"{ "adaptiveRefresh": \#(value) }"#)
        #expect(config.adaptiveRefresh == true)
        #expect(notes == ["adaptiveRefresh is not a boolean, using true"])
        try config.validate()
    }

    @Test func nonBooleanWithoutCollectorStillDecodes() throws {
        let config = try decodeConfig(#"{ "adaptiveRefresh": "yes" }"#)
        #expect(config.adaptiveRefresh == true)
    }

    @Test func encodingWritesTheKey() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let on = String(decoding: try encoder.encode(Configuration()), as: UTF8.self)
        #expect(on.contains(#""adaptiveRefresh":true"#))
        var config = Configuration()
        config.adaptiveRefresh = false
        let off = String(decoding: try encoder.encode(config), as: UTF8.self)
        #expect(off.contains(#""adaptiveRefresh":false"#))
        let decoded = try JSONDecoder().decode(Configuration.self, from: Data(off.utf8))
        #expect(decoded == config)
    }

    /// research R10: toggling only re-arms the app's timer, it causes no
    /// refresh and no endpoint call.
    @Test func togglingNeedsNoRefresh() throws {
        let base = try decodeConfig(contractExampleJSON)
        var edited = base
        edited.adaptiveRefresh = false
        #expect(edited != base)
        #expect(!edited.needsRefresh(comparedTo: base))
        #expect(!edited.needsNetworkRefresh(comparedTo: base))
    }
}

/// spec 014 FR-012: the credential notification switch, on by default and
/// for configurations written before it existed; presentation only.
@Suite struct SignInNotificationSettingTests {
    @Test func defaultConfigurationNotifies() {
        #expect(Configuration().notifySignInProblems == true)
    }

    @Test func missingKeyDecodesAsOn() throws {
        #expect(try decodeConfig(contractExampleJSON).notifySignInProblems == true)
        #expect(try decodeConfig("{}").notifySignInProblems == true)
    }

    @Test func falseRoundTrips() throws {
        var config = Configuration()
        config.notifySignInProblems = false
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(decoded.notifySignInProblems == false)
        #expect(decoded == config)
    }

    @Test func keyIsAlwaysEncoded() throws {
        for value in [true, false] {
            var config = Configuration()
            config.notifySignInProblems = value
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any]
            #expect(object?["notifySignInProblems"] as? Bool == value)
        }
    }

    @Test func togglingNeedsNoRefresh() {
        let base = Configuration()
        var edited = base
        edited.notifySignInProblems = false
        #expect(!edited.needsRefresh(comparedTo: base))
        #expect(!base.needsRefresh(comparedTo: edited))
    }
}

/// spec 033 FR-017: the free reset expiry notification switch, on by
/// default and for configurations written before it existed; presentation
/// only.
@Suite struct FreeResetExpirySettingTests {
    @Test func defaultConfigurationNotifies() {
        #expect(Configuration().notifyFreeResetExpiry == true)
    }

    @Test func missingKeyDecodesAsOn() throws {
        #expect(try decodeConfig(contractExampleJSON).notifyFreeResetExpiry == true)
        #expect(try decodeConfig("{}").notifyFreeResetExpiry == true)
    }

    @Test func falseRoundTrips() throws {
        var config = Configuration()
        config.notifyFreeResetExpiry = false
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(decoded.notifyFreeResetExpiry == false)
        #expect(decoded == config)
    }

    @Test func keyIsAlwaysEncoded() throws {
        for value in [true, false] {
            var config = Configuration()
            config.notifyFreeResetExpiry = value
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any]
            #expect(object?["notifyFreeResetExpiry"] as? Bool == value)
        }
    }

    @Test func togglingNeedsNoRefresh() {
        let base = Configuration()
        var edited = base
        edited.notifyFreeResetExpiry = false
        #expect(!edited.needsRefresh(comparedTo: base))
        #expect(!base.needsRefresh(comparedTo: edited))
        #expect(!edited.needsNetworkRefresh(comparedTo: base))
    }
}

/// spec 013 FR-002, research R12: the automatic update check toggle, on by
/// default, read leniently, presentation only for refreshes.
@Suite struct UpdateCheckSettingTests {
    @Test func defaultConfigurationChecks() {
        #expect(Configuration().checksForUpdates == true)
    }

    @Test func missingKeyDecodesAsOn() throws {
        #expect(try decodeConfig(contractExampleJSON).checksForUpdates == true)
        #expect(try decodeConfig("{}").checksForUpdates == true)
    }

    @Test func falseDecodesAsOff() throws {
        #expect(try decodeConfig(#"{ "checksForUpdates": false }"#).checksForUpdates == false)
    }

    /// A value that is not a boolean is ignored, and the rest still loads.
    @Test func nonBooleanDecodesAsOn() throws {
        let config = try decodeConfig(#"{ "checksForUpdates": "no", "refreshIntervalSeconds": 120 }"#)
        #expect(config.checksForUpdates == true)
        #expect(config.refreshIntervalSeconds == 120)
    }

    @Test func roundTrips() throws {
        var config = Configuration()
        config.checksForUpdates = false
        let data = try JSONEncoder().encode(config)
        #expect(String(decoding: data, as: UTF8.self).contains("\"checksForUpdates\":false"))
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(decoded.checksForUpdates == false)
        #expect(decoded == config)
        #expect(Configuration(checksForUpdates: false).checksForUpdates == false)
    }

    @Test func togglingNeedsNoRefresh() {
        let base = Configuration()
        var edited = base
        edited.checksForUpdates = false
        #expect(!edited.needsRefresh(comparedTo: base))
        #expect(!edited.needsNetworkRefresh(comparedTo: base))
    }
}

/// spec 025 FR-021, FR-022, contracts/config-file.md: the `timeFormat` key
/// on accounts and groups.
@Suite struct TimeFormatConfigurationTests {
    /// A Claude and a Codex subscription, a group member, an own budget and
    /// a group; `value` is the raw JSON of every `timeFormat`, nil for none.
    static func json(_ value: String?) -> String {
        let key = value.map { #", "timeFormat": \#($0)"# } ?? ""
        return """
        {
          "accounts": [
            { "id": "acc-claude", "type": "subscription", "displayName": "Claude Max", "credentialDirectory": "~/.claude"\(key) },
            { "id": "acc-codex", "type": "codexSubscription", "displayName": "ChatGPT Plus"\(key) },
            { "id": "acc-vertex", "type": "tokenBased", "displayName": "Vertex", "groupId": "grp-company"\(key) },
            { "id": "acc-openai", "type": "tokenBased", "displayName": "OpenAI", "provider": "openai",
              "budget": { "period": "monthly", "budgetUSD": 50 }\(key) }
          ],
          "groups": [
            { "id": "grp-company", "name": "Company budget", "budgetUSD": 300\(key) }
          ]
        }
        """
    }

    static func decodeWithNotes(_ json: String) throws -> (Configuration, [String]) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (config, notes.notes)
    }

    static func formats(_ config: Configuration) -> [TimeFormat] {
        config.accounts.map(\.timeFormat) + config.groups.map(\.timeFormat)
    }

    @Test func absentKeyIsRelative() throws {
        let (config, notes) = try Self.decodeWithNotes(Self.json(nil))
        #expect(Self.formats(config) == Array(repeating: .relative, count: 5))
        #expect(notes.isEmpty)
        try config.validate()
    }

    @Test(arguments: [(#""relative""#, TimeFormat.relative), (#""absolute""#, .absolute)])
    func knownValuesDecodeAsGiven(raw: String, expected: TimeFormat) throws {
        let (config, notes) = try Self.decodeWithNotes(Self.json(raw))
        #expect(Self.formats(config) == Array(repeating: expected, count: 5))
        #expect(notes.isEmpty)
    }

    /// An unknown string reads as relative with one note per entry; the
    /// rest of the file loads.
    @Test func unknownValueIsRelativeWithANote() throws {
        let (config, notes) = try Self.decodeWithNotes(Self.json(#""x""#))
        #expect(Self.formats(config) == Array(repeating: .relative, count: 5))
        #expect(notes.count == 5)
        #expect(notes.allSatisfy { $0 == #"timeFormat "x" is not known, using relative"# })
        #expect(config.accounts.map(\.displayName) == ["Claude Max", "ChatGPT Plus", "Vertex", "OpenAI"])
        #expect(config.groups.first?.budgetUSD == 300)
        try config.validate()
    }

    @Test(arguments: ["null", "3", #"{ "a": 1 }"#])
    func unreadableValueIsRelativeWithANote(raw: String) throws {
        let (config, notes) = try Self.decodeWithNotes(Self.json(raw))
        #expect(Self.formats(config) == Array(repeating: .relative, count: 5))
        #expect(notes.count == 5)
        #expect(notes.allSatisfy { $0 == "timeFormat is not readable, using relative" })
    }

    @Test func unknownValueWithoutCollectorStillDecodes() throws {
        let config = try decodeConfig(Self.json(#""Absolute""#))
        #expect(Self.formats(config) == Array(repeating: .relative, count: 5))
    }

    /// Every save writes the key, also for the default, and an unknown value
    /// is written back as relative.
    @Test func encodingAlwaysWritesTheKey() throws {
        let (config, _) = try Self.decodeWithNotes(Self.json(#""x""#))
        let data = try JSONEncoder().encode(config)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        let groups = try #require(object["groups"] as? [[String: Any]])
        for entry in accounts + groups {
            #expect(entry["timeFormat"] as? String == "relative")
        }
    }

    @Test func roundTrip() throws {
        var config = try decodeConfig(Self.json(nil))
        config.accounts[0].timeFormat = .absolute
        config.groups[0].timeFormat = .absolute
        let decoded = try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(Self.formats(decoded) == [.absolute, .relative, .relative, .relative, .absolute])
    }

    @Test func defaultsInCode() {
        #expect(Account(displayName: "A", kind: .subscription(SubscriptionSettings())).timeFormat == .relative)
        #expect(BudgetGroup(name: "G", budgetUSD: 10).timeFormat == .relative)
    }

    /// The account's value for an account section, the group's for a group
    /// section (FR-016).
    @Test func timeFormatOfAnArrangedEntry() throws {
        var config = try decodeConfig(Self.json(nil))
        config.accounts[0].timeFormat = .absolute
        config.groups[0].timeFormat = .absolute
        let entries = config.arrangedEntries
        func format(_ id: String) throws -> TimeFormat {
            config.timeFormat(for: try #require(entries.first { $0.ref.id == id }))
        }
        #expect(try format("acc-claude") == .absolute)
        #expect(try format("acc-codex") == .relative)
        #expect(try format("acc-openai") == .relative)
        #expect(try format("grp-company") == .absolute)
        config.accounts[3].timeFormat = .absolute
        #expect(try format("acc-openai") == .absolute)
    }

    /// A token-based account in a group keeps its stored value, though it
    /// has no section of its own (FR-021).
    @Test func groupMemberKeepsItsStoredValue() throws {
        let config = try decodeConfig(Self.json(#""absolute""#))
        let member = try #require(config.account(id: "acc-vertex"))
        #expect(member.timeFormat == .absolute)
        let decoded = try JSONDecoder().decode(Configuration.self, from: try JSONEncoder().encode(config))
        #expect(decoded.account(id: "acc-vertex")?.timeFormat == .absolute)
        let moved = decoded.movingAccountToOwnBudget(accountId: "acc-vertex")
        #expect(moved.account(id: "acc-vertex")?.timeFormat == .absolute)
    }

    /// The time format only changes the dropdown, so no refresh (FR-022).
    @Test func timeFormatNeedsNoRefresh() throws {
        let base = try decodeConfig(Self.json(nil))
        var account = base
        account.accounts[0].timeFormat = .absolute
        var group = base
        group.groups[0].timeFormat = .absolute
        for edited in [account, group] {
            #expect(edited != base)
            #expect(!edited.needsRefresh(comparedTo: base))
            #expect(!edited.needsNetworkRefresh(comparedTo: base))
        }
    }
}

/// spec 027 FR-010, FR-011, contracts/config-file.md: the `headlineWindow`
/// key on Claude and Codex subscription accounts.
@Suite struct HeadlineWindowConfigurationTests {
    /// A Claude and a Codex subscription and a token-based account with its
    /// own budget; `claude`, `codex` and `token` are the raw JSON of each
    /// account's `headlineWindow`, nil for none.
    static func json(claude: String? = nil, codex: String? = nil, token: String? = nil) -> String {
        func key(_ value: String?) -> String { value.map { #", "headlineWindow": \#($0)"# } ?? "" }
        return """
        {
          "accounts": [
            { "id": "acc-claude", "type": "subscription", "displayName": "Claude Max", "credentialDirectory": "~/.claude"\(key(claude)) },
            { "id": "acc-codex", "type": "codexSubscription", "displayName": "ChatGPT Plus"\(key(codex)) },
            { "id": "acc-openai", "type": "tokenBased", "displayName": "OpenAI", "provider": "openai",
              "budget": { "period": "monthly", "budgetUSD": 50 }\(key(token)) }
          ]
        }
        """
    }

    static func choices(_ config: Configuration) -> [HeadlineChoice?] {
        [config.account(id: "acc-claude")?.kind.subscription?.headlineWindow,
         config.account(id: "acc-codex")?.kind.codexSubscription?.headlineWindow]
    }

    static func encoded(_ config: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    @Test func absentKeyIsTheDefault() throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.json())
        #expect(Self.choices(config) == [nil, nil])
        #expect(notes.isEmpty)
        try config.validate()
    }

    @Test func defaultsInCode() {
        #expect(SubscriptionSettings().headlineWindow == nil)
        #expect(CodexSubscriptionSettings().headlineWindow == nil)
    }

    @Test func knownValuesDecode() throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(
            Self.json(claude: #""fiveHour""#, codex: #""window:5-hour""#))
        #expect(Self.choices(config) == [.claudeFiveHour, .codexWindow("5-hour")])
        #expect(notes.isEmpty)
        let model = try decodeConfig(Self.json(claude: #""model:Fable""#))
        #expect(Self.choices(model) == [.claudeModel("Fable"), nil])
    }

    /// An unknown value, a value of the other account kind, a non-string or
    /// null is the default window with one note each; the file stays valid.
    @Test(arguments: [#""x""#, #""window:5-hour""#, #""model:""#, "null", "3", #"{ "a": 1 }"#])
    func invalidClaudeValueIsTheDefaultWithANote(raw: String) throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.json(claude: raw))
        #expect(Self.choices(config) == [nil, nil])
        #expect(notes.count == 1)
        #expect(notes.allSatisfy { $0.hasPrefix("headlineWindow") })
        #expect(config.accounts.count == 3)
        try config.validate()
    }

    @Test(arguments: [#""fiveHour""#, #""window:week""#, #""window:0-hour""#, "null", "true"])
    func invalidCodexValueIsTheDefaultWithANote(raw: String) throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.json(codex: raw))
        #expect(Self.choices(config) == [nil, nil])
        #expect(notes.count == 1)
        #expect(notes.allSatisfy { $0.hasPrefix("headlineWindow") })
        try config.validate()
    }

    /// A token-based account ignores the key like any unknown key.
    @Test func tokenBasedAccountIgnoresTheKey() throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.json(token: #""fiveHour""#))
        #expect(notes.isEmpty)
        let text = String(decoding: try Self.encoded(config), as: UTF8.self)
        #expect(!text.contains("headlineWindow"))
    }

    /// Written only when set; a file without the key re-encodes without it,
    /// and setting then clearing a choice gives the same bytes.
    @Test func encodesOnlyWhenSet() throws {
        let base = try decodeConfig(Self.json())
        let baseData = try Self.encoded(base)
        #expect(!String(decoding: baseData, as: UTF8.self).contains("headlineWindow"))

        let chosen = base.settingHeadline(.claudeFiveHour, accountId: "acc-claude")
            .settingHeadline(.codexWindow("5-hour"), accountId: "acc-codex")
        let object = try #require(try JSONSerialization.jsonObject(with: try Self.encoded(chosen)) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        #expect(accounts.map { $0["headlineWindow"] as? String } == ["fiveHour", "window:5-hour", nil])

        let cleared = chosen.settingHeadline(nil, accountId: "acc-claude").settingHeadline(nil, accountId: "acc-codex")
        #expect(try Self.encoded(cleared) == baseData)
    }

    @Test func roundTrip() throws {
        let config = try decodeConfig(Self.json())
            .settingHeadline(.claudeModel("Opus 4.6"), accountId: "acc-claude")
            .settingHeadline(.codexWindow("weekly"), accountId: "acc-codex")
        let decoded = try JSONDecoder().decode(Configuration.self, from: try Self.encoded(config))
        #expect(decoded == config)
        #expect(Self.choices(decoded) == [.claudeModel("Opus 4.6"), .codexWindow("weekly")])
    }

    /// An invalid value is dropped by the next save (FR-010).
    @Test func invalidValueIsDroppedOnSave() throws {
        let config = try decodeConfig(Self.json(claude: #""bogus""#))
        #expect(!String(decoding: try Self.encoded(config), as: UTF8.self).contains("headlineWindow"))
    }

    /// The choice is presentation only, so no refresh (FR-011).
    @Test func choiceNeedsNoRefresh() throws {
        let base = try decodeConfig(Self.json())
        let edited = base.settingHeadline(.claudeFiveHour, accountId: "acc-claude")
            .settingHeadline(.codexWindow("5-hour"), accountId: "acc-codex")
        #expect(edited != base)
        #expect(!edited.needsRefresh(comparedTo: base))
        #expect(!edited.needsNetworkRefresh(comparedTo: base))
    }

    /// The default window clears the choice; a choice of the other kind and
    /// a token-based account leave the configuration unchanged.
    @Test func settingHeadlineRules() throws {
        let base = try decodeConfig(Self.json())
        let five = base.settingHeadline(.claudeFiveHour, accountId: "acc-claude")
        #expect(Self.choices(five) == [.claudeFiveHour, nil])
        #expect(Self.choices(five.settingHeadline(.claudeSevenDay, accountId: "acc-claude")) == [nil, nil])
        #expect(Self.choices(five.settingHeadline(nil, accountId: "acc-claude")) == [nil, nil])
        #expect(base.settingHeadline(.codexWindow("5-hour"), accountId: "acc-claude") == base)
        #expect(base.settingHeadline(.claudeFiveHour, accountId: "acc-codex") == base)
        #expect(base.settingHeadline(.claudeFiveHour, accountId: "acc-openai") == base)
        #expect(base.settingHeadline(.claudeFiveHour, accountId: "missing") == base)
        // Only the named account changes.
        var two = base
        two.accounts.append(Account(id: "acc-second", displayName: "Second",
                                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude-2"))))
        let chosen = two.settingHeadline(.claudeFiveHour, accountId: "acc-second")
        #expect(chosen.account(id: "acc-second")?.kind.subscription?.headlineWindow == .claudeFiveHour)
        #expect(chosen.account(id: "acc-claude")?.kind.subscription?.headlineWindow == nil)
    }

    /// A Settings candidate built from an older draft keeps the newer choice
    /// made in the dropdown (FR-010, research R7).
    @Test func keepingHeadlineChoices() throws {
        let draft = try decodeConfig(Self.json())
        var edited = draft
        edited.accounts[0].displayName = "Renamed"
        let current = draft.settingHeadline(.claudeFiveHour, accountId: "acc-claude")
            .settingHeadline(.codexWindow("5-hour"), accountId: "acc-codex")
        let candidate = edited.keepingHeadlineChoices(of: current)
        #expect(Self.choices(candidate) == [.claudeFiveHour, .codexWindow("5-hour")])
        #expect(candidate.accounts[0].displayName == "Renamed")
        // A cleared choice in `current` clears the draft's.
        let cleared = current.keepingHeadlineChoices(of: draft)
        #expect(Self.choices(cleared) == [nil, nil])
        // An account missing in `current` stays as it is.
        var added = current
        added.accounts.append(Account(id: "acc-new", displayName: "New",
                                      kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude-new"))))
        added = added.settingHeadline(.claudeFiveHour, accountId: "acc-new")
        let kept = added.keepingHeadlineChoices(of: draft)
        #expect(kept.account(id: "acc-new")?.kind.subscription?.headlineWindow == .claudeFiveHour)
    }

    /// The Settings window's candidate, built from a draft taken before a
    /// click in the dropdown, keeps that click when it is applied (FR-010,
    /// research R7).
    @Test func settingsCandidateFromAnOldDraftKeepsANewerChoice() throws {
        let applied = try decodeConfig(Self.json())
        var draft = applied
        draft.accounts[1].displayName = "ChatGPT Pro"
        let current = applied.settingHeadline(.claudeFiveHour, accountId: "acc-claude")
        let candidate = draft.settingsCandidate(applied: applied, undoTarget: nil).keepingHeadlineChoices(of: current)
        #expect(Self.choices(candidate) == [.claudeFiveHour, nil])
        #expect(candidate.account(id: "acc-codex")?.displayName == "ChatGPT Pro")
        #expect(!candidate.needsRefresh(comparedTo: current))
    }

    /// Removing an account removes its choice with it (FR-010).
    @Test func removingAccountRemovesItsChoice() throws {
        let config = try decodeConfig(Self.json()).settingHeadline(.claudeFiveHour, accountId: "acc-claude")
        let removed = config.removingAccount(id: "acc-claude")
        #expect(!String(decoding: try Self.encoded(removed), as: UTF8.self).contains("headlineWindow"))
    }

    /// A choice saved through one store is loaded by a new store on the same
    /// file, as after a restart (SC-004).
    @Test func survivesARestart() throws {
        let dir = try makeTempDirectory("store-headline")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let config = try decodeConfig(Self.json())
            .settingHeadline(.claudeFiveHour, accountId: "acc-claude")
            .settingHeadline(.codexWindow("5-hour"), accountId: "acc-codex")
        try ConfigStore(fileURL: file).save(config)
        let (loaded, error) = ConfigStore(fileURL: file).load()
        #expect(error == nil)
        #expect(loaded == config)
        #expect(Self.choices(loaded) == [.claudeFiveHour, .codexWindow("5-hour")])
    }
}

/// spec 034 FR-006a, research R3: a subscription account keeps what the
/// user entered; a blank entry means the default directory for every reader.
@Suite struct SubscriptionDirectoryDefaultTests {
    private static func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(value)) as? [String: Any])
    }

    @Test(arguments: ["", "   ", "\n", " \t\n "])
    func blankClaudeEntryMeansTheDefault(entry: String) {
        let settings = SubscriptionSettings(credentialDirectory: entry)
        #expect(settings.enteredCredentialDirectory == entry)
        #expect(settings.credentialDirectory == Paths.defaultClaudeDirectory)
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankCodexEntryMeansTheDefault(entry: String) {
        let settings = CodexSubscriptionSettings(codexHome: entry)
        #expect(settings.enteredCodexHome == entry)
        #expect(settings.codexHome == Paths.defaultCodexHome)
    }

    /// A typed entry is the directory, without surrounding whitespace.
    @Test func typedEntryIsReturnedTrimmed() {
        #expect(SubscriptionSettings(credentialDirectory: "~/.claude-personal").credentialDirectory == "~/.claude-personal")
        #expect(SubscriptionSettings(credentialDirectory: " ~/.claude-personal").credentialDirectory == "~/.claude-personal")
        #expect(SubscriptionSettings(credentialDirectory: " ~/.claude-personal").enteredCredentialDirectory == " ~/.claude-personal")
        #expect(CodexSubscriptionSettings(codexHome: "~/.codex-lab").codexHome == "~/.codex-lab")
        #expect(SubscriptionSettings().enteredCredentialDirectory == Paths.defaultClaudeDirectory)
        #expect(CodexSubscriptionSettings().enteredCodexHome == Paths.defaultCodexHome)
    }

    @Test func setterStoresTheEntry() {
        var claude = SubscriptionSettings(credentialDirectory: "~/.claude-personal")
        claude.credentialDirectory = ""
        #expect(claude.enteredCredentialDirectory == "")
        #expect(claude.credentialDirectory == Paths.defaultClaudeDirectory)
        var codex = CodexSubscriptionSettings(codexHome: "~/.codex-lab")
        codex.codexHome = " "
        #expect(codex.enteredCodexHome == " ")
        #expect(codex.codexHome == Paths.defaultCodexHome)
    }

    /// An empty entry stays empty in the file and keeps meaning the default.
    @Test func emptyEntryRoundTripsAsEmpty() throws {
        let json = #"""
        { "accounts": [
          { "id": "acc-max", "type": "subscription", "displayName": "Max", "credentialDirectory": "" },
          { "id": "acc-codex", "type": "codexSubscription", "displayName": "Plus", "harness": "codex", "codexHome": "" }
        ] }
        """#
        let config = try decodeConfig(json)
        #expect(config.accounts[0].kind.subscription?.enteredCredentialDirectory == "")
        #expect(config.accounts[0].kind.subscription?.credentialDirectory == "~/.claude")
        #expect(config.accounts[1].kind.codexSubscription?.enteredCodexHome == "")
        #expect(config.accounts[1].kind.codexSubscription?.codexHome == "~/.codex")
        let object = try Self.encodedObject(config)
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        #expect(accounts[0]["credentialDirectory"] as? String == "")
        #expect(accounts[1]["codexHome"] as? String == "")
        #expect(try decodeConfig(String(decoding: try JSONEncoder().encode(config), as: UTF8.self)) == config)
    }

    /// The settings structs encode under the keys they always had.
    @Test func encodedKeysAreUnchanged() throws {
        let claude = try Self.encodedObject(SubscriptionSettings(credentialDirectory: ""))
        #expect(claude["credentialDirectory"] as? String == "")
        #expect(claude["enteredCredentialDirectory"] == nil)
        let codex = try Self.encodedObject(CodexSubscriptionSettings(codexHome: "~/.codex-lab"))
        #expect(codex["codexHome"] as? String == "~/.codex-lab")
        #expect(codex["enteredCodexHome"] == nil)
        let decoded = try JSONDecoder().decode(SubscriptionSettings.self,
                                               from: Data(#"{ "credentialDirectory": "~/.claude-personal", "shownInBar": true, "thresholds": [] }"#.utf8))
        #expect(decoded.enteredCredentialDirectory == "~/.claude-personal")
    }
}

/// spec 034 FR-007, research R4: a token-based account's optional session
/// directory, whose meaning follows the provider.
@Suite struct TokenBasedSessionDirectoryTests {
    @Test func defaultsToNoDirectory() {
        let settings = TokenBasedSettings(groupId: "grp")
        #expect(settings.enteredSessionDirectory == nil)
        #expect(settings.sessionDirectory == nil)
    }

    @Test(arguments: ["", "  ", "\n\t"])
    func blankEntryIsNoDirectory(entry: String) {
        let settings = TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex, sessionDirectory: entry)
        #expect(settings.enteredSessionDirectory == entry)
        #expect(settings.sessionDirectory == nil)
    }

    @Test func typedEntryIsTheDirectory() {
        let settings = TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex,
                                          sessionDirectory: "~/profiles/acme/claude")
        #expect(settings.sessionDirectory == "~/profiles/acme/claude")
    }

    /// A Claude Code directory is no Codex home: switching the provider
    /// clears the entry, setting the same provider keeps it.
    @Test func switchingTheProviderClearsTheEntry() {
        var settings = TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex,
                                          sessionDirectory: "~/profiles/acme/claude")
        settings.provider = .vertex
        #expect(settings.sessionDirectory == "~/profiles/acme/claude")
        settings.provider = .openai
        #expect(settings.enteredSessionDirectory == nil)
        settings.enteredSessionDirectory = "~/.codex-lab"
        settings.provider = .openai
        #expect(settings.sessionDirectory == "~/.codex-lab")
        settings.provider = .vertex
        #expect(settings.enteredSessionDirectory == nil)
    }

    /// The Settings field: no directory shows as an empty field, and an
    /// empty field stores none.
    @Test func fieldTextMapsEmptyToNoDirectory() {
        var settings = TokenBasedSettings(groupId: "grp")
        #expect(settings.sessionDirectoryField == "")
        settings.sessionDirectoryField = "~/profiles/acme/claude"
        #expect(settings.enteredSessionDirectory == "~/profiles/acme/claude")
        settings.sessionDirectoryField = " "
        #expect(settings.enteredSessionDirectory == " ")
        #expect(settings.sessionDirectory == nil)
        settings.sessionDirectoryField = ""
        #expect(settings.enteredSessionDirectory == nil)
    }

    @Test func providerDescribesItsDirectory() {
        #expect(Provider.vertex.sessionDirectoryKey == "claudeCodeDirectory")
        #expect(Provider.openai.sessionDirectoryKey == "codexHome")
        #expect(Provider.vertex.sessionHarness == .claudeCode)
        #expect(Provider.openai.sessionHarness == .codex)
        #expect(Provider.vertex.defaultSessionDirectory == "~/.claude")
        #expect(Provider.openai.defaultSessionDirectory == "~/.codex")
    }
}

/// spec 034 FR-007, research R5, contracts/configuration.md "Account keys":
/// the `claudeCodeDirectory` and `codexHome` keys of token-based accounts.
@Suite struct TokenBasedDirectoryCodingTests {
    static func json(provider: String = "vertex", name: String = "Acme Vertex", fields: String = "") -> String {
        """
        { "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 100 } ],
          "accounts": [
            { "id": "acc-token", "type": "tokenBased", "displayName": "\(name)",
              "provider": "\(provider)", "groupId": "grp"\(fields) }
          ] }
        """
    }

    static func decode(_ json: String) throws -> (Configuration, [String]) {
        try TimeFormatConfigurationTests.decodeWithNotes(json)
    }

    static func directory(_ config: Configuration) -> String? {
        config.accounts.first?.kind.tokenBased?.sessionDirectory
    }

    static func accountObject(_ config: Configuration) throws -> [String: Any] {
        let object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(config)) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        return try #require(accounts.first)
    }

    @Test func vertexClaudeCodeDirectoryRoundTrips() throws {
        let (config, notes) = try Self.decode(Self.json(fields: #", "claudeCodeDirectory": "~/profiles/acme/claude""#))
        #expect(notes.isEmpty)
        #expect(Self.directory(config) == "~/profiles/acme/claude")
        let account = try Self.accountObject(config)
        #expect(account["claudeCodeDirectory"] as? String == "~/profiles/acme/claude")
        #expect(account["codexHome"] == nil)
        let decoded = try decodeConfig(String(decoding: try JSONEncoder().encode(config), as: UTF8.self))
        #expect(decoded == config)
        try config.validate()
    }

    @Test func openAICodexHomeRoundTrips() throws {
        let (config, notes) = try Self.decode(Self.json(provider: "openai", name: "OpenAI Lab", fields: #", "codexHome": "~/.codex-lab""#))
        #expect(notes.isEmpty)
        #expect(Self.directory(config) == "~/.codex-lab")
        let account = try Self.accountObject(config)
        #expect(account["codexHome"] as? String == "~/.codex-lab")
        #expect(account["claudeCodeDirectory"] == nil)
        #expect(try decodeConfig(String(decoding: try JSONEncoder().encode(config), as: UTF8.self)) == config)
    }

    @Test func absentKeyIsNoDirectory() throws {
        let (config, notes) = try Self.decode(Self.json())
        #expect(notes.isEmpty)
        #expect(Self.directory(config) == nil)
        #expect(try Self.accountObject(config)["claudeCodeDirectory"] == nil)
    }

    /// A blank value is no directory, gives no note and is not written, for
    /// either provider.
    @Test(arguments: [#""""#, #""   ""#], [("vertex", "claudeCodeDirectory"), ("openai", "codexHome")])
    func blankValueIsOmittedOnSave(value: String, provider: (name: String, key: String)) throws {
        let (config, notes) = try Self.decode(Self.json(provider: provider.name, fields: #", "\#(provider.key)": \#(value)"#))
        #expect(notes.isEmpty)
        #expect(Self.directory(config) == nil)
        #expect(try Self.accountObject(config)[provider.key] == nil)
        var edited = config
        if case .tokenBased(var settings) = edited.accounts[0].kind {
            settings.enteredSessionDirectory = "  "
            edited.accounts[0].kind = .tokenBased(settings)
        }
        #expect(try Self.accountObject(edited)[provider.key] == nil)
    }

    /// The provider's own key with a value that is not a string is ignored
    /// with a note; the configuration stays valid.
    @Test(arguments: ["null", "42", "true", #"["~/x"]"#])
    func unreadableOwnKeyIsIgnoredWithANote(value: String) throws {
        let (vertex, vertexNotes) = try Self.decode(Self.json(fields: #", "claudeCodeDirectory": \#(value)"#))
        #expect(Self.directory(vertex) == nil)
        #expect(vertexNotes == [#"claudeCodeDirectory of account "Acme Vertex" is not readable, ignored"#])
        try vertex.validate()
        let (openai, openaiNotes) = try Self.decode(Self.json(provider: "openai", name: "OpenAI Lab", fields: #", "codexHome": \#(value)"#))
        #expect(Self.directory(openai) == nil)
        #expect(openaiNotes == [#"codexHome of account "OpenAI Lab" is not readable, ignored"#])
        try openai.validate()
    }

    /// The other provider's key is ignored with a note and not written back.
    @Test func otherProvidersKeyIsIgnoredWithANote() throws {
        let (vertex, vertexNotes) = try Self.decode(Self.json(fields: #", "codexHome": "~/.codex-lab""#))
        #expect(Self.directory(vertex) == nil)
        #expect(vertexNotes == [#"codexHome of account "Acme Vertex" does not belong to a Vertex account, ignored"#])
        #expect(try Self.accountObject(vertex)["codexHome"] == nil)
        try vertex.validate()

        let (openai, openaiNotes) = try Self.decode(Self.json(provider: "openai", name: "OpenAI Lab",
                                                              fields: #", "claudeCodeDirectory": "~/profiles/acme/claude""#))
        #expect(Self.directory(openai) == nil)
        #expect(openaiNotes == [#"claudeCodeDirectory of account "OpenAI Lab" does not belong to an OpenAI account, ignored"#])
        #expect(try Self.accountObject(openai)["claudeCodeDirectory"] == nil)

        // Any value of the other key gives the note, the own key still counts.
        let (both, bothNotes) = try Self.decode(Self.json(fields: #", "claudeCodeDirectory": "~/profiles/acme/claude", "codexHome": 3"#))
        #expect(Self.directory(both) == "~/profiles/acme/claude")
        #expect(bothNotes == [#"codexHome of account "Acme Vertex" does not belong to a Vertex account, ignored"#])
    }

    /// A Vertex account without a provider key reads `claudeCodeDirectory`.
    @Test func missingProviderMeansVertex() throws {
        let json = #"""
        { "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 100 } ],
          "accounts": [ { "id": "acc-token", "type": "tokenBased", "displayName": "V", "groupId": "grp",
                          "claudeCodeDirectory": "~/profiles/acme/claude" } ] }
        """#
        let (config, notes) = try Self.decode(json)
        #expect(notes.isEmpty)
        #expect(Self.directory(config) == "~/profiles/acme/claude")
    }

    @Test func longNamesAreClipped() throws {
        let name = String(repeating: "n", count: 40)
        let (_, notes) = try Self.decode(Self.json(name: name, fields: #", "codexHome": "~/x""#))
        #expect(notes == ["codexHome of account \"\(String(repeating: "n", count: 32))...\" does not belong to a Vertex account, ignored"])
    }

    /// Subscription accounts keep strict decoding of their directory keys.
    @Test func subscriptionAccountsStayStrict() {
        let claude = #"{ "accounts": [ { "id": "a", "type": "subscription", "displayName": "M", "credentialDirectory": 3 } ] }"#
        #expect(throws: DecodingError.self) { try decodeConfig(claude) }
        let codex = #"{ "accounts": [ { "id": "a", "type": "codexSubscription", "displayName": "P", "codexHome": 3 } ] }"#
        #expect(throws: DecodingError.self) { try decodeConfig(codex) }
    }
}

/// spec 034 FR-006, FR-006a, FR-008, research R9, data-model
/// "Configuration lookups": the account directories a refresh reads, and
/// which edits of them need a refresh.
@Suite struct AccountDirectoryLookupTests {
    static func claude(_ id: String, _ dir: String) -> Account {
        Account(id: id, displayName: id, kind: .subscription(SubscriptionSettings(credentialDirectory: dir)))
    }

    static func codex(_ id: String, _ home: String) -> Account {
        Account(id: id, displayName: id, harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home)))
    }

    static func token(_ id: String, _ provider: Provider, _ dir: String?) -> Account {
        Account(id: id, displayName: id, harness: provider.sessionHarness,
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: provider,
                                                     sessionDirectory: dir)))
    }

    static func config(_ accounts: [Account]) -> Configuration {
        Configuration(accounts: accounts, groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
    }

    @Test func lookupsFollowTheAccountsOrder() {
        let config = Self.config([
            Self.token("vertex", .vertex, "~/profiles/acme/claude"),
            Self.codex("plus", ""),
            Self.claude("max", "~/.claude-personal"),
            Self.token("vertex-empty", .vertex, nil),
            Self.token("openai", .openai, "~/.codex-lab"),
            Self.claude("pro", "  "),
            Self.token("openai-blank", .openai, " "),
        ])
        // An empty field resolves to the default (spec 034 FR-008).
        #expect(config.accountClaudeCodeDirectories == ["~/profiles/acme/claude", "~/.claude-personal", "~/.claude", "~/.claude"])
        #expect(config.accountCodexHomes == ["~/.codex", "~/.codex-lab", "~/.codex"])
        #expect(Configuration().accountClaudeCodeDirectories.isEmpty)
        #expect(Configuration().accountCodexHomes.isEmpty)
    }

    /// A blank entry is compared as entered, as before spec 034: next to
    /// `~/.claude` (or `~/.codex`) it stays valid, so a file that loaded
    /// before still loads, and the load notes name it; two blank entries
    /// and two equal spellings still collide.
    @Test func blankEntryNextToTheDefaultStaysValid() throws {
        try Self.config([Self.claude("max", ""), Self.claude("pro", "~/.claude")]).validate()
        try Self.config([Self.codex("plus", " "), Self.codex("pro", "~/.codex")]).validate()
        let blanks = Self.config([Self.claude("max", ""), Self.claude("pro", " ")])
        do {
            try blanks.validate()
            Issue.record("expected a duplicate directory error")
        } catch let error as ConfigurationError {
            #expect(error.kind == .duplicateCredentialDirectory)
            #expect(error.message == #"Claude Code directory "~/.claude" is used by more than one Claude subscription account."#)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(validationKind(Self.config([Self.codex("plus", ""), Self.codex("pro", "\n")])) == .duplicateCodexHome)
        #expect(validationKind(Self.config([Self.claude("max", "~/.claude"), Self.claude("pro", "~/.claude/")])) == .duplicateCredentialDirectory)
    }

    /// A file saved before spec 034 with a cleared field next to the
    /// default loads, with a note for the cleared account (spec 034
    /// FR-006a).
    @Test func blankEntryNextToTheDefaultLoadsWithANote() throws {
        let json = """
        { "accounts": [
            { "id": "acc-max", "type": "subscription", "displayName": "Max", "credentialDirectory": "~/.claude" },
            { "id": "acc-old", "type": "subscription", "displayName": "Old", "credentialDirectory": "" }
          ] }
        """
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(json)
        try config.validate()
        #expect(notes == [#"Claude Code directory of account "Old" is empty, so it reads ~/.claude like account "Max""#])
        #expect(config.accounts[1].kind.subscription?.credentialDirectory == "~/.claude")
    }

    /// Every directory field is saved as typed (unless blank) and read
    /// without the surrounding whitespace.
    @Test func directoriesAreSavedAsTyped() throws {
        let config = Self.config([Self.claude("max", "~/.claude-personal "), Self.codex("plus", " ~/.codex-lab"),
                                  Self.token("vertex", .vertex, " ~/profiles/acme/claude")])
        let object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(config)) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        #expect(accounts[0]["credentialDirectory"] as? String == "~/.claude-personal ")
        #expect(accounts[1]["codexHome"] as? String == " ~/.codex-lab")
        #expect(accounts[2]["claudeCodeDirectory"] as? String == " ~/profiles/acme/claude")
        let decoded = try decodeConfig(String(decoding: try JSONEncoder().encode(config), as: UTF8.self))
        #expect(decoded.accountClaudeCodeDirectories == ["~/.claude-personal", "~/profiles/acme/claude"])
        #expect(decoded.accountCodexHomes == ["~/.codex-lab"])
    }

    /// Whitespace around a typed directory is not part of the path that is
    /// read, and the field keeps what was typed.
    @Test func surroundingWhitespaceIsNotRead() {
        let token = TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex,
                                       sessionDirectory: " ~/profiles/acme/claude\n")
        #expect(token.sessionDirectory == "~/profiles/acme/claude")
        #expect(token.enteredSessionDirectory == " ~/profiles/acme/claude\n")
        let claude = SubscriptionSettings(credentialDirectory: "~/.claude-personal ")
        #expect(claude.credentialDirectory == "~/.claude-personal")
        #expect(claude.enteredCredentialDirectory == "~/.claude-personal ")
        #expect(CodexSubscriptionSettings(codexHome: " ~/.codex-lab").codexHome == "~/.codex-lab")
    }

    /// A token-based directory may equal any other directory.
    @Test func tokenBasedDirectoryMayEqualASubscriptionDirectory() throws {
        try Self.config([
            Self.claude("max", "~/.claude-personal"),
            Self.token("vertex", .vertex, "~/.claude-personal"),
            Self.token("vertex-2", .vertex, "~/.claude-personal"),
            Self.codex("plus", "~/.codex-lab"),
            Self.token("openai", .openai, "~/.codex-lab"),
        ]).validate()
    }

    /// Clearing a subscription field to the default, or whitespace in a
    /// token-based field, changes nothing a refresh computes.
    @Test func blankEntriesCompareAsTheirDefault() {
        let base = Self.config([Self.claude("max", "~/.claude"), Self.codex("plus", "~/.codex"), Self.token("vertex", .vertex, nil)])
        let blank = Self.config([Self.claude("max", ""), Self.codex("plus", " "), Self.token("vertex", .vertex, "  ")])
        #expect(blank != base)
        #expect(!blank.needsRefresh(comparedTo: base))
        #expect(!blank.needsNetworkRefresh(comparedTo: base))
    }

    /// A new token-based directory needs a local refresh, never a network one.
    @Test func tokenBasedDirectoryNeedsALocalRefreshOnly() {
        let base = Self.config([Self.claude("max", "~/.claude"), Self.token("vertex", .vertex, nil)])
        let edited = Self.config([Self.claude("max", "~/.claude"), Self.token("vertex", .vertex, "~/profiles/acme/claude")])
        #expect(edited.needsRefresh(comparedTo: base))
        #expect(!edited.needsNetworkRefresh(comparedTo: base))
    }
}

/// spec 034 FR-011, FR-012, research R6: the dropped `logDirectories` and
/// `codexHomes` keys are noted on load and never written again.
@Suite struct LegacyDirectoryConfigurationTests {
    static let json = #"""
    { "logDirectories": ["~/profiles/acme/claude", "", "~/.claude"],
      "codexHomes": ["~/.codex-lab"],
      "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 100 } ],
      "accounts": [
        { "id": "acc-acme", "type": "tokenBased", "displayName": "Acme Vertex", "provider": "vertex", "groupId": "grp",
          "codexHome": "~/x" }
      ] }
    """#

    @Test func legacyKeysDecodeIntoNotesInOrder() throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.json)
        #expect(notes == [
            #"codexHome of account "Acme Vertex" does not belong to a Vertex account, ignored"#,
            #"logDirectories entry "~/profiles/acme/claude" is no longer read; set it as the Claude Code directory of an account in Settings > Accounts"#,
            #"logDirectories entry "~/.claude" is no longer read; it is already covered by account "Acme Vertex""#,
            #"codexHomes entry "~/.codex-lab" is no longer read; set it as the Codex home of an account in Settings > Accounts"#,
        ])
        try config.validate()
        // Nothing from the lists is read for usage; the Vertex account's
        // empty field reads ~/.claude (spec 034 FR-008).
        #expect(config.accountClaudeCodeDirectories == ["~/.claude"])
        #expect(config.accountCodexHomes.isEmpty)
    }

    /// US3 scenario 3: an old entry equal to a Claude subscription's
    /// directory is still read through the account, and the note says so.
    @Test func entryCoveredBySubscriptionAccount() throws {
        let json = #"""
        { "logDirectories": ["~/.claude-personal"],
          "accounts": [
            { "id": "acc-max", "type": "subscription", "displayName": "Max", "credentialDirectory": "~/.claude-personal" }
          ] }
        """#
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(json)
        #expect(notes == [#"logDirectories entry "~/.claude-personal" is no longer read; it is already covered by account "Max""#])
        #expect(config.accountClaudeCodeDirectories == ["~/.claude-personal"])
        try config.validate()
    }

    @Test func legacyKeysAreNeverWritten() throws {
        let config = try decodeConfig(Self.json)
        let text = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(!text.contains("logDirectories"))
        #expect(!text.contains("codexHomes"))
        #expect(!String(decoding: try JSONEncoder().encode(Configuration()), as: UTF8.self).contains("logDirectories"))
    }

    /// A value that is not a list of strings gives one note for the key and
    /// keeps the configuration valid.
    @Test(arguments: ["null", #""~/profiles/acme/claude""#, #"["~/x", 3]"#, "{}"])
    func unreadableValueGivesOneNote(value: String) throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(#"{ "logDirectories": \#(value), "codexHomes": \#(value) }"#)
        #expect(notes == ["logDirectories is not a list of directories, ignored", "codexHomes is not a list of directories, ignored"])
        #expect(config == Configuration())
        try config.validate()
    }

    @Test func entryCoveredByAVertexAccount() throws {
        let json = #"""
        { "logDirectories": ["~/profiles/acme/claude/"],
          "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 100 } ],
          "accounts": [
            { "id": "acc-acme", "type": "tokenBased", "displayName": "Acme Vertex", "provider": "vertex", "groupId": "grp",
              "claudeCodeDirectory": "~/profiles/acme/claude" }
          ] }
        """#
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(json)
        #expect(notes == [#"logDirectories entry "~/profiles/acme/claude/" is no longer read; it is already covered by account "Acme Vertex""#])
        #expect(config.accountClaudeCodeDirectories == ["~/profiles/acme/claude"])
    }
}

// MARK: - Spec 035: additional session directories

/// spec 035 FR-001, FR-003, research R1, R10: every Claude subscription,
/// Vertex, Codex subscription and OpenAI account carries an optional list
/// of additional session directories.
@Suite struct AdditionalSessionDirectoryTests {
    static func claude(_ id: String, _ dir: String = "~/.claude", extra: [String] = []) -> Account {
        Account(id: id, displayName: id,
                kind: .subscription(SubscriptionSettings(credentialDirectory: dir, additionalSessionDirectories: extra)))
    }

    static func codex(_ id: String, _ home: String = "~/.codex", extra: [String] = []) -> Account {
        Account(id: id, displayName: id, harness: .codex,
                kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home, additionalSessionDirectories: extra)))
    }

    static func token(_ id: String, _ provider: Provider, _ dir: String? = nil, extra: [String] = []) -> Account {
        Account(id: id, displayName: id, harness: provider.sessionHarness,
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: provider,
                                                     sessionDirectory: dir, additionalSessionDirectories: extra)))
    }

    static func config(_ accounts: [Account]) -> Configuration {
        Configuration(accounts: accounts, groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
    }

    @Test func listIsEmptyByDefault() {
        #expect(SubscriptionSettings().additionalSessionDirectories.isEmpty)
        #expect(CodexSubscriptionSettings().additionalSessionDirectories.isEmpty)
        #expect(TokenBasedSettings(groupId: "grp").additionalSessionDirectories.isEmpty)
    }

    /// The accessors of `AccountKind` read and write the list of whichever
    /// settings struct the account has, and name the harness of its sessions.
    @Test func accessorsFollowTheKind() {
        var claude = Self.claude("max", extra: ["~/.claude-lab"]).kind
        #expect(claude.sessionHarness == .claudeCode)
        #expect(claude.additionalSessionDirectories == ["~/.claude-lab"])
        claude.additionalSessionDirectories = ["~/agent-sessions/openshell/*/claude"]
        #expect(claude.subscription?.additionalSessionDirectories == ["~/agent-sessions/openshell/*/claude"])

        var codex = Self.codex("plus", extra: ["~/.codex"]).kind
        #expect(codex.sessionHarness == .codex)
        #expect(codex.additionalSessionDirectories == ["~/.codex"])
        codex.additionalSessionDirectories = []
        #expect(codex.codexSubscription?.additionalSessionDirectories == [])

        var vertex = Self.token("vertex", .vertex, extra: ["~/.claude-lab"]).kind
        #expect(vertex.sessionHarness == .claudeCode)
        vertex.additionalSessionDirectories.append("~/.claude-*")
        #expect(vertex.tokenBased?.additionalSessionDirectories == ["~/.claude-lab", "~/.claude-*"])

        let openai = Self.token("openai", .openai, extra: ["~/.codex"]).kind
        #expect(openai.sessionHarness == .codex)
        #expect(openai.additionalSessionDirectories == ["~/.codex"])
    }

    /// A Claude Code directory is no Codex home: switching the provider
    /// clears the list with the main directory, setting the same provider
    /// keeps it (spec 035 edge case "Switching a token-based account's
    /// provider").
    @Test func switchingTheProviderClearsTheList() {
        var settings = TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex,
                                          sessionDirectory: "~/profiles/acme/claude", additionalSessionDirectories: ["~/.claude-lab"])
        settings.provider = .vertex
        #expect(settings.additionalSessionDirectories == ["~/.claude-lab"])
        settings.provider = .openai
        #expect(settings.additionalSessionDirectories.isEmpty)
        #expect(settings.enteredSessionDirectory == nil)
    }

    /// Entries in accounts order, then list order; Vertex entries only for
    /// Claude Code, OpenAI entries only for Codex.
    @Test func entriesFollowTheAccountsOrderPerHarness() {
        let config = Self.config([
            Self.codex("plus", extra: ["~/.codex", "~/agent-sessions/openshell/*/codex"]),
            Self.token("vertex", .vertex, extra: ["~/.claude-lab"]),
            Self.claude("max", extra: ["~/agent-sessions/openshell/*/claude", "~/.claude-*"]),
            Self.token("openai", .openai, extra: ["~/.codex-lab"]),
            Self.claude("pro", "~/.claude-pro"),
        ])
        #expect(config.additionalSessionEntries(for: .claudeCode) == [
            AdditionalSessionEntry(accountId: "vertex", entry: "~/.claude-lab"),
            AdditionalSessionEntry(accountId: "max", entry: "~/agent-sessions/openshell/*/claude", joinsTieBreak: true),
            AdditionalSessionEntry(accountId: "max", entry: "~/.claude-*", joinsTieBreak: true),
        ])
        #expect(config.additionalSessionEntries(for: .codex) == [
            AdditionalSessionEntry(accountId: "plus", entry: "~/.codex", joinsTieBreak: true),
            AdditionalSessionEntry(accountId: "plus", entry: "~/agent-sessions/openshell/*/codex", joinsTieBreak: true),
            AdditionalSessionEntry(accountId: "openai", entry: "~/.codex-lab"),
        ])
        #expect(config.additionalSessionEntries(for: .openCode).isEmpty)
        #expect(config.additionalSessionEntries(for: .claudeCode).map(\.isWildcard) == [false, true, true])
        // The main directory lookups are unchanged.
        #expect(config.accountClaudeCodeDirectories == ["~/.claude", "~/.claude", "~/.claude-pro"])
        #expect(config.accountCodexHomes == ["~/.codex", "~/.codex"])
    }

    /// A list change refreshes usage locally and never asks the usage
    /// endpoint, on every kind (spec 035 FR-003).
    @Test(arguments: [Provider?.none, .vertex, .openai])
    func listChangesNeedALocalRefreshOnly(provider: Provider?) {
        func account(_ extra: [String]) -> [Account] {
            if let provider { return [Self.claude("max"), Self.token("t", provider, extra: extra)] }
            return [Self.claude("max", extra: extra), Self.codex("plus", extra: extra)]
        }
        let base = Self.config(account(["~/.claude-lab", "~/agent-sessions/openshell/*/claude"]))
        for edited in [Self.config(account(["~/.claude-lab", "~/agent-sessions/openshell/*/claude", "~/.claude-*"])),
                       Self.config(account(["~/.claude-lab"])),
                       Self.config(account(["~/agent-sessions/openshell/*/claude", "~/.claude-lab"]))] {
            #expect(edited.needsRefresh(comparedTo: base))
            #expect(!edited.needsNetworkRefresh(comparedTo: base))
        }
    }
}

/// spec 035 FR-001, FR-006, FR-007, contracts/configuration.md "Account key
/// additionalSessionDirectories": the key on all four account kinds.
@Suite struct AdditionalSessionDirectoryCodingTests {
    /// The contract example: a Claude subscription and a Codex subscription.
    static let contractJSON = #"""
    { "accounts": [
      { "id": "acc-max", "type": "subscription", "icon": "brands:claude",
        "displayName": "Claude Max", "credentialDirectory": "",
        "additionalSessionDirectories": ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"],
        "shownInBar": true, "thresholds": [] },
      { "id": "acc-plan", "type": "codexSubscription", "icon": "brands:openai",
        "displayName": "ChatGPT Plus", "codexHome": "~/.codex-lab",
        "additionalSessionDirectories": ["~/.codex"],
        "shownInBar": true, "thresholds": [], "liveLimits": true }
    ] }
    """#

    /// One account of `type` (`subscription`, `codexSubscription`, `vertex`
    /// or `openai`) with the given extra fields.
    static func json(_ type: String, name: String = "Lab", fields: String) -> String {
        let account: String
        switch type {
        case "vertex", "openai":
            account = #"{ "id": "acc", "type": "tokenBased", "displayName": "\#(name)", "provider": "\#(type)", "groupId": "grp"\#(fields) }"#
        default:
            account = #"{ "id": "acc", "type": "\#(type)", "displayName": "\#(name)"\#(fields) }"#
        }
        return #"{ "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 100 } ], "accounts": [ \#(account) ] }"#
    }

    static let kinds = ["subscription", "codexSubscription", "vertex", "openai"]

    static func accountObject(_ config: Configuration) throws -> [String: Any] {
        try TokenBasedDirectoryCodingTests.accountObject(config)
    }

    @Test func contractExampleRoundTrips() throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.contractJSON)
        #expect(notes.isEmpty)
        #expect(config.accounts[0].kind.additionalSessionDirectories == ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"])
        #expect(config.accounts[1].kind.additionalSessionDirectories == ["~/.codex"])
        let text = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(try decodeConfig(text) == config)
        try config.validate()
    }

    /// Entries are trimmed, blank entries dropped, the order kept, on every
    /// kind; the next save writes the kept entries.
    @Test(arguments: kinds)
    func listOfStringsRoundTrips(type: String) throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(
            Self.json(type, fields: #", "additionalSessionDirectories": [" ~/.lab-b ", "", "  ", "~/agent-sessions/openshell/*/x\n"]"#))
        #expect(notes.isEmpty)
        #expect(config.accounts[0].kind.additionalSessionDirectories == ["~/.lab-b", "~/agent-sessions/openshell/*/x"])
        #expect(try Self.accountObject(config)["additionalSessionDirectories"] as? [String] == ["~/.lab-b", "~/agent-sessions/openshell/*/x"])
        #expect(try decodeConfig(String(decoding: try JSONEncoder().encode(config), as: UTF8.self)) == config)
    }

    /// An absent key, an empty list and a list of blank entries are no
    /// list; the key is not written (US3 scenario 4).
    @Test(arguments: kinds, ["", #", "additionalSessionDirectories": []"#, #", "additionalSessionDirectories": ["", " "]"#])
    func emptyListIsNotWritten(type: String, fields: String) throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(Self.json(type, fields: fields))
        #expect(notes.isEmpty)
        #expect(config.accounts[0].kind.additionalSessionDirectories.isEmpty)
        #expect(try Self.accountObject(config)["additionalSessionDirectories"] == nil)
    }

    /// A list edited in Settings is written trimmed, without blank entries.
    @Test func encodeWritesTrimmedNonBlankEntries() throws {
        var config = AdditionalSessionDirectoryTests.config([AdditionalSessionDirectoryTests.claude("max")])
        config.accounts[0].kind.additionalSessionDirectories = ["  ", " ~/.claude-lab"]
        #expect(try Self.accountObject(config)["additionalSessionDirectories"] as? [String] == ["~/.claude-lab"])
        config.accounts[0].kind.additionalSessionDirectories = [" "]
        #expect(try Self.accountObject(config)["additionalSessionDirectories"] == nil)
    }
}

/// spec 035 FR-006, FR-007, US3 scenarios 1 to 4, research R12: hand-edited
/// values of `additionalSessionDirectories` load leniently.
extension AdditionalSessionDirectoryCodingTests {
    /// A value that is not a list of strings is ignored with one note on
    /// every kind; the configuration stays valid and the key is not written.
    @Test(arguments: kinds, ["null", #""~/.claude-lab""#, "42", "{}", #"["~/.claude-lab", 3]"#])
    func unreadableValueIsIgnoredWithANote(type: String, value: String) throws {
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(
            Self.json(type, fields: #", "additionalSessionDirectories": \#(value)"#))
        #expect(config.accounts[0].kind.additionalSessionDirectories.isEmpty)
        #expect(notes == [#"additionalSessionDirectories of account "Lab" is not readable, ignored"#])
        try config.validate()
        #expect(try Self.accountObject(config)["additionalSessionDirectories"] == nil)
    }

    /// Refused entries are dropped with one note each, the others kept and
    /// written back (US3 scenario 2).
    @Test(arguments: kinds)
    func refusedEntriesAreDroppedWithANote(type: String) throws {
        let value = #"["~/.lab-a", "~/agent-sessions/**/x", "~/*/x", "~", "/", "agent-sessions/*/x", "~/agent-sessions/openshell/*/x"]"#
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(
            Self.json(type, fields: #", "additionalSessionDirectories": \#(value)"#))
        #expect(config.accounts[0].kind.additionalSessionDirectories == ["~/.lab-a", "~/agent-sessions/openshell/*/x"])
        #expect(notes == [
            #"additionalSessionDirectories entry "~/agent-sessions/**/x" of account "Lab" is refused (** is not supported, * covers one folder level), ignored"#,
            #"additionalSessionDirectories entry "~/*/x" of account "Lab" is refused (* may not stand for a whole folder directly under the home folder or /), ignored"#,
            #"additionalSessionDirectories entry "~" of account "Lab" is refused (the home folder or / is not a session directory), ignored"#,
            #"additionalSessionDirectories entry "/" of account "Lab" is refused (the home folder or / is not a session directory), ignored"#,
            #"additionalSessionDirectories entry "agent-sessions/*/x" of account "Lab" is refused (it must start with ~/ or /), ignored"#,
        ])
        try config.validate()
        #expect(try Self.accountObject(config)["additionalSessionDirectories"] as? [String] == ["~/.lab-a", "~/agent-sessions/openshell/*/x"])
    }

    @Test func notesClipNamesAndEntries() throws {
        let name = String(repeating: "n", count: 40)
        let entry = "~/" + String(repeating: "e", count: 40) + "/**"
        let (_, notes) = try TimeFormatConfigurationTests.decodeWithNotes(
            Self.json("subscription", name: name, fields: #", "additionalSessionDirectories": ["\#(entry)"]"#))
        #expect(notes == ["additionalSessionDirectories entry \"\(Configuration.clipped(entry))\" of account \"\(Configuration.clipped(name))\" is refused (** is not supported, * covers one folder level), ignored"])
        let (_, other) = try TimeFormatConfigurationTests.decodeWithNotes(
            Self.json("openai", name: name, fields: #", "additionalSessionDirectories": 1"#))
        #expect(other == ["additionalSessionDirectories of account \"\(Configuration.clipped(name))\" is not readable, ignored"])
    }
}

/// spec 035 FR-006, FR-013, research R12, contracts/configuration.md
/// "Settings refusal": `validate()` refuses what loading drops, so a
/// Settings draft shows "Not applied".
@Suite struct SessionDirectoryValidationTests {
    typealias Make = AdditionalSessionDirectoryTests

    static func error(_ config: Configuration) -> ConfigurationError? {
        do {
            try config.validate()
            return nil
        } catch let error as ConfigurationError {
            return error
        } catch {
            return nil
        }
    }

    @Test func accountEntryMessages() {
        let cases: [(String, String)] = [
            ("agent-sessions/*/claude", "it must start with ~/ or /"),
            ("~/agent-sessions/**/claude", "** is not supported, * covers one folder level"),
            ("~/", "the home folder or / is not a session directory"),
            ("~/*/claude", "* may not stand for a whole folder directly under the home folder or /"),
        ]
        for (entry, reason) in cases {
            let error = Self.error(Make.config([Make.claude("max", extra: ["~/.claude-lab", entry])]))
            #expect(error?.kind == .sessionDirectoryEntry)
            #expect(error?.message == "Additional session directory \"\(entry)\" of account \"max\": \(reason).")
        }
        // The message is not clipped.
        let long = "~/" + String(repeating: "x", count: 40) + "/**"
        #expect(Self.error(Make.config([Make.token("vertex", .vertex, extra: [long])]))?.message
                == "Additional session directory \"\(long)\" of account \"vertex\": ** is not supported, * covers one folder level.")
    }

    @Test func openCodeEntryMessages() {
        var config = Configuration(openCodeDirectories: ["opencode-lab", "~/agent-sessions/openshell/*/opencode", "agent-sessions/*/opencode"])
        #expect(Self.error(config)?.kind == .sessionDirectoryEntry)
        #expect(Self.error(config)?.message == #"OpenCode data directory "agent-sessions/*/opencode": it must start with ~/ or /."#)
        config.openCodeDirectories = ["opencode-lab", "~/agent-sessions/openshell/*/opencode"]
        #expect(Self.error(config) == nil)
    }

    /// Accounts first, in accounts order, then the OpenCode list.
    @Test func firstRefusedEntryWins() {
        var config = Make.config([Make.claude("max", extra: ["~/.claude-lab"]), Make.codex("plus", extra: ["/*"]),
                                  Make.token("openai", .openai, extra: ["~"])])
        config.openCodeDirectories = ["/**"]
        #expect(Self.error(config)?.message == #"Additional session directory "/*" of account "plus": * may not stand for a whole folder directly under the home folder or /."#)
        config.accounts[1].kind.additionalSessionDirectories = []
        #expect(Self.error(config)?.message == #"Additional session directory "~" of account "openai": the home folder or / is not a session directory."#)
        config.accounts[2].kind.additionalSessionDirectories = []
        #expect(Self.error(config)?.message == #"OpenCode data directory "/**": ** is not supported, * covers one folder level."#)
    }

    /// A `*` in a main directory field stays an ordinary character.
    @Test func starInAMainDirectoryIsNotRefused() throws {
        try Make.config([Make.claude("max", "~/*/claude"), Make.codex("plus", "~/*"), Make.token("vertex", .vertex, "*")]).validate()
    }

    /// Loading drops refused OpenCode entries, with a note when notes are
    /// collected, and keeps literal relative ones; nothing dropped is
    /// written back.
    @Test func refusedOpenCodeEntriesAreDroppedOnLoad() throws {
        let json = #"{ "openCodeDirectories": ["opencode-lab", "~/agent-sessions/**/opencode", "/*", "~/agent-sessions/openshell/*/opencode"] }"#
        let (config, notes) = try TimeFormatConfigurationTests.decodeWithNotes(json)
        #expect(config.openCodeDirectories == ["opencode-lab", "~/agent-sessions/openshell/*/opencode"])
        #expect(notes == [
            #"openCodeDirectories entry "~/agent-sessions/**/opencode" is refused (** is not supported, * covers one folder level), ignored"#,
            #"openCodeDirectories entry "/*" is refused (* may not stand for a whole folder directly under the home folder or /), ignored"#,
        ])
        try config.validate()
        // Without a notes collector the entries are dropped all the same.
        #expect(try decodeConfig(json).openCodeDirectories == ["opencode-lab", "~/agent-sessions/openshell/*/opencode"])
        let text = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(!text.contains("**"))
        // The type check is unchanged: a value that is not a list throws.
        #expect(throws: DecodingError.self) { try decodeConfig(#"{ "openCodeDirectories": "~/x" }"#) }
    }
}
