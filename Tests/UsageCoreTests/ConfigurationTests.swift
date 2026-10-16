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

        var directory = base
        directory.logDirectories.append("~/elsewhere")
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
        local.logDirectories.append("~/elsewhere")
        local.accounts[1].customMarker = "project-x"
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
        #expect(Set(object.keys) == ["id", "name", "icon", "period", "budgetUSD", "shownInBar", "thresholds"])

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
        let config = try decodeConfig(Self.json)
        #expect(config.codexHomes == ["~/.codex-work"])
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
        #expect(text.contains("\"codexHomes\""))
        #expect(text.contains("\"openCodeDirectories\""))
        #expect(try JSONDecoder().decode(Configuration.self, from: data) == config)
    }

    @Test func locationListsAreOptional() throws {
        let config = try decodeConfig("{}")
        #expect(config.codexHomes.isEmpty)
        #expect(config.openCodeDirectories.isEmpty)
    }

    /// SC-005: a file of the previous version decodes unchanged.
    @Test func previousVersionFileDecodesUnchanged() throws {
        let config = try decodeConfig(contractExampleJSON)
        #expect(config.codexHomes.isEmpty)
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
        let (config, notes) = try decodeWithNotes(contractExampleJSON)
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

    /// FR-012: only Off without symbols hides levels from the bar.
    @Test func hidesLevelsOnlyForOffWithoutSymbols() {
        for style in LevelColorStyle.allCases {
            for symbols in [false, true] {
                let settings = LevelDisplaySettings(levelColor: style, showSymbols: symbols)
                #expect(settings.hidesLevels == (style == .off && !symbols))
            }
        }
        #expect(LevelDisplaySettings.default == LevelDisplaySettings(levelColor: .text, showSymbols: false))
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
        let (config, notes) = try decodeWithNotes(contractExampleJSON)
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
