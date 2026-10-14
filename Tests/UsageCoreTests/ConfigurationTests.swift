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
        edited.accounts[0].label = "X"
        edited.accounts[0].icon = "brands:claude"
        edited.accounts[0].displayName = "Renamed"
        edited.groups[0].name = "Renamed group"
        edited.groups[0].label = "G"
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

    @Test func needsNetworkRefreshOnlyForSubscriptionChanges() throws {
        let base = try example()

        var local = base
        local.priceOverrides[0].inputPerMTok += 1
        local.groups[0].budgetUSD += 1
        local.logDirectories.append("~/elsewhere")
        local.accounts[1].customMarker = "project-x"
        local.accounts[0].label = "X"
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
        added.accounts.append(Account(id: "acc-2", label: "W", displayName: "Work",
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

    @Test func rejectsLabelLength() throws {
        var config = try example()
        config.accounts[0].label = "MAXX"
        #expect(validationKind(config) == .invalidLabel)
        config.accounts[0].label = ""
        #expect(validationKind(config) == .invalidLabel)
        config.accounts[0].label = "MAX"
        #expect(validationKind(config) == nil)
    }

    /// The icon is shown instead of the text when both are set; the text may
    /// then be empty, unknown icons are rejected, and uniqueness applies to
    /// what is shown.
    @Test func iconTakesPrecedenceOverText() throws {
        var config = try example()
        config.accounts[0].icon = "brands:claude"
        #expect(config.accounts[0].shownLabel == .icon(IconCatalog.shared.icon(for: "brands:claude")!))
        #expect(config.accounts[0].shownLabel.plain == "Claude")
        #expect(validationKind(config) == nil)

        config.accounts[0].label = ""
        #expect(validationKind(config) == nil)

        config.accounts[0].icon = nil
        #expect(validationKind(config) == .invalidLabel)            // neither text nor icon

        for unknown in ["brands:no-such-icon", "claude", "duotone:claude"] {
            config.accounts[0].icon = unknown
            #expect(validationKind(config) == .invalidLabel, "\(unknown)")
        }

        config.accounts[0].icon = "solid:cloud"
        config.groups[0].icon = "solid:cloud"
        #expect(validationKind(config) == .duplicateLabel)          // same icon shown twice

        // The same name in another style is a different icon.
        config.groups[0].icon = "regular:cloud"
        #expect(validationKind(config) == nil)

        // Text labels hidden behind distinct icons may repeat.
        config.accounts[0].label = config.groups[0].label
        #expect(validationKind(config) == nil)

        // Round trip keeps the icon; a config without it decodes to nil.
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(decoded.accounts[0].icon == "solid:cloud")
        #expect(decoded.groups[0].icon == "regular:cloud")
        #expect(try example().accounts[0].icon == nil)
    }

    /// An `emoji` key left over from an earlier build is ignored like any
    /// unknown key; the text label applies.
    @Test func leftoverEmojiKeyIsIgnored() throws {
        let config = try example()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        var accounts = try #require(object["accounts"] as? [[String: Any]])
        accounts[0]["emoji"] = "✻"
        object["accounts"] = accounts
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.accounts[0].icon == nil)
        #expect(decoded.accounts[0].shownLabel == .text(config.accounts[0].label))
        #expect(validationKind(decoded) == nil)
    }

    /// Text labels count user-perceived characters: an emoji typed into the
    /// text field counts as one, including base character plus variation selector.
    @Test func textLabelsCountCharactersNotCodePoints() throws {
        var config = try example()
        for label in ["✻", "☁️", "✻M", "🤖V2"] {
            config.accounts[0].label = label
            #expect(validationKind(config) == nil, "label \(label)")
        }
        config.accounts[0].label = "☁️ABC"
        #expect(validationKind(config) == .invalidLabel)

        // Emoji labels survive the JSON round trip unchanged.
        config.accounts[0].label = "☁️"
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Configuration.self, from: data).accounts[0].label == "☁️")
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
        config.groups.append(BudgetGroup(id: "grp-empty", name: "Empty", label: "E", budgetUSD: 10, shownInBar: false, thresholds: []))
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
        config.groups.append(BudgetGroup(id: "grp-b", name: "Other", label: "B", budgetUSD: 20))
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
            let group = BudgetGroup(id: "g", name: "Vertex", label: "V", period: period, budgetUSD: Decimal(string: "400.5")!,
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
        #expect(Set(object.keys) == ["id", "name", "label", "period", "budgetUSD", "shownInBar", "thresholds"])

        let monthly = BudgetGroup(id: "g", name: "Vertex", label: "", icon: "brands:google", period: .monthly, budgetUSD: 400)
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
        #expect(BudgetGroup(name: "G", label: "G", budgetUSD: 10).period == .weekly)
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
