import Foundation
import Testing
@testable import UsageCore

/// Spec 044 FR-001, FR-002, FR-006, FR-010, FR-022, SC-004,
/// contracts/config.md, research R1, R2, R8: a budget group without an
/// amount, the group keys `valueAs` and `show`, owners, counting periods and
/// which group edits need a refresh.
@Suite struct GroupNoLimitConfigurationTests {
    static func groups(_ groups: String..., accounts: String = "") -> String {
        #"{"version": 1, "accounts": [\#(accounts)], "groups": [\#(groups.joined(separator: ","))]}"#
    }

    static func decodeWithNotes(_ json: String) throws -> (Configuration, [String]) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (config, notes.notes)
    }

    static func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func groupObject(_ group: BudgetGroup) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try encoded(group)) as? [String: Any])
    }

    static func member(_ id: String, group: String, harness: Harness, kind: SessionKind) -> Account {
        Account(id: id, displayName: id, kind: .tokenBased(TokenBasedSettings(groupId: group, harness: harness, sessionKind: kind)))
    }

    /// A monthly group without an amount with three members and a weekly
    /// group with one, for owners and counting periods.
    static func mixed() -> Configuration {
        Configuration(
            accounts: [
                member("acc-open-claude", group: "grp-open", harness: .claudeCode, kind: .claudeCodeVertex),
                member("acc-open-codex", group: "grp-open", harness: .codex, kind: .codexAPIKey),
                member("acc-open-oc", group: "grp-open", harness: .openCode, kind: .openCodeOpenAI),
                member("acc-team-claude", group: "grp-team", harness: .claudeCode, kind: .claudeCodeDirectoryOnly),
                member("acc-team-codex", group: "grp-team", harness: .codex, kind: .codexAPIKey),
                member("acc-team-oc", group: "grp-team", harness: .openCode, kind: .openCodeAnthropic),
            ],
            groups: [
                BudgetGroup(id: "grp-open", name: "Open models", icon: "solid:gift", period: .monthly, budgetUSD: nil,
                            shownInBar: false, thresholds: [50, 90]),
                BudgetGroup(id: "grp-team", name: "Team", icon: "solid:wallet", period: .weekly, budgetUSD: 500,
                            shownInBar: true, thresholds: [80, 100]),
            ])
    }

    // MARK: Decoding the amount (FR-001, FR-002)

    @Test func absentAndNullAmountGiveAGroupWithoutAnAmount() throws {
        for amount in ["", #", "budgetUSD": null"#] {
            let json = Self.groups(#"{"id": "grp-a", "name": "Free models", "period": "monthly", "shownInBar": false, "thresholds": [50, 90]\#(amount)}"#)
            let group = try #require(try decodeConfig(json).groups.first)
            #expect(group.budgetUSD == nil)
            #expect(group.hasAmount == false)
            #expect(group.budget == nil)
            #expect(group.period == .monthly)
            #expect(group.thresholds == [50, 90])
            #expect(group.shownInBar == false)
            try decodeConfig(json).validate()
        }
    }

    @Test func legacyWeeklyAmountStillDecodes() throws {
        let group = try decodeGroup(#"{"id": "g", "name": "Legacy", "weeklyBudgetUSD": 60}"#)
        #expect(group.budgetUSD == 60)
        #expect(group.hasAmount)
        #expect(group.budget == BudgetSettings(period: .weekly, budgetUSD: 60, shownInBar: true, thresholds: []))
    }

    /// An explicit `null` amount wins over a leftover legacy key, which
    /// counts only when `budgetUSD` is absent (contracts/config.md).
    @Test(arguments: ["weekly", "monthly"])
    func nullAmountWinsOverALegacyWeeklyAmount(period: String) throws {
        let group = try decodeGroup(#"{"id": "g", "name": "Legacy", "period": "\#(period)", "budgetUSD": null, "weeklyBudgetUSD": 60}"#)
        #expect(group.budgetUSD == nil)
        #expect(group.hasAmount == false)
    }

    @Test(arguments: ["0", "-5"])
    func amountOfZeroOrLessStaysInvalid(amount: String) throws {
        let config = try decodeConfig(Self.groups(#"{"id": "grp-a", "name": "Free models", "period": "monthly", "budgetUSD": \#(amount)}"#))
        #expect(throws: ConfigurationError(kind: .budget, message: "Monthly budget of group \"Free models\" must be greater than 0.")) {
            try config.validate()
        }
    }

    @Test(arguments: ["0", "-5"])
    func keptThresholdsOfZeroOrLessAreInvalid(threshold: String) throws {
        let config = try decodeConfig(Self.groups(#"{"id": "grp-a", "name": "Free models", "period": "monthly", "thresholds": [\#(threshold)]}"#))
        #expect(config.groups[0].hasAmount == false)
        #expect(throws: ConfigurationError(kind: .threshold,
                                           message: "Thresholds of group \"Free models\" must be whole-number percents greater than 0 (got \(threshold)).")) {
            try config.validate()
        }
    }

    // MARK: valueAs and show (FR-010, FR-022)

    @Test func absentShowIsAutomaticAndValueAsIsRead() throws {
        let (config, notes) = try Self.decodeWithNotes(Self.groups(#"{"id": "grp-a", "name": "Free models", "valueAs": "claude-opus-5-5"}"#))
        #expect(config.groups[0].show == .automatic)
        #expect(config.groups[0].valueAs == "claude-opus-5-5")
        #expect(notes.isEmpty)
        #expect(BudgetGroup(name: "New", budgetUSD: 60).show == .automatic)
        #expect(BudgetGroup(name: "New", budgetUSD: 60).valueAs == nil)
    }

    @Test(arguments: [("percent", DropdownShow.percent), ("tokens", .tokens), ("money", .money), ("automatic", .automatic)])
    func knownShowValuesDecode(raw: String, expected: DropdownShow) throws {
        let (config, notes) = try Self.decodeWithNotes(Self.groups(#"{"id": "grp-a", "name": "Free models", "show": "\#(raw)"}"#))
        #expect(config.groups[0].show == expected)
        #expect(notes.isEmpty)
    }

    @Test func unknownShowGivesOneNoteAndAutomatic() throws {
        let (config, notes) = try Self.decodeWithNotes(Self.groups(#"{"id": "grp-a", "name": "Free models", "show": "dollars"}"#))
        #expect(config.groups[0].show == .automatic)
        #expect(notes == [#"group "Free models": unknown show value "dollars", using Automatic"#])
    }

    /// A `show` value that is not a string reads as Automatic with one
    /// note in the group's wording, never a configuration error (FR-022).
    @Test func unreadableShowGivesOneNoteAndAutomatic() throws {
        let (config, notes) = try Self.decodeWithNotes(Self.groups(#"{"id": "grp-a", "name": "Free models", "show": 5}"#))
        #expect(config.groups[0].show == .automatic)
        #expect(notes == [#"group "Free models": show is not readable, using Automatic"#])
    }

    /// A blank `valueAs` is no model, as for an account (FR-022).
    @Test func blankValueAsIsNoModel() throws {
        let config = try decodeConfig(Self.groups(#"{"id": "grp-a", "name": "Free models", "valueAs": "   "}"#))
        #expect(config.groups[0].valueAs == nil)
    }

    @Test func nullShowIsAutomaticWithoutANote() throws {
        let (config, notes) = try Self.decodeWithNotes(Self.groups(#"{"id": "grp-a", "name": "Free models", "show": null}"#))
        #expect(config.groups[0].show == .automatic)
        #expect(notes.isEmpty)
    }

    /// A `valueAs` model without a price is valid (FR-022).
    @Test func valueAsWithoutAPriceIsValid() throws {
        let config = try decodeConfig(Self.groups(#"{"id": "grp-a", "name": "Free models", "icon": "solid:gift", "valueAs": "gateway-a/no-such-model"}"#))
        try config.validate()
        #expect(config.groups[0].valueAs == "gateway-a/no-such-model")
    }

    // MARK: Encoding (contracts/config.md "Writing")

    @Test func noAmountWritesNoBudgetKey() throws {
        let group = BudgetGroup(id: "grp-a", name: "Free models", period: .monthly, budgetUSD: nil, shownInBar: false, thresholds: [50, 90])
        let object = try Self.groupObject(group)
        #expect(object["budgetUSD"] == nil)
        #expect(object["weeklyBudgetUSD"] == nil)
        #expect(object["valueAs"] == nil)
        #expect(object["show"] == nil)
        #expect(object["period"] as? String == "monthly")
        #expect(object["thresholds"] as? [Int] == [50, 90])
        #expect(object["shownInBar"] as? Bool == false)
        #expect(!String(decoding: try Self.encoded(group), as: UTF8.self).contains("null"))
    }

    @Test func valueAsAndShowAreWrittenOnlyWhenSet() throws {
        for show in DropdownShow.allCases {
            let group = BudgetGroup(id: "grp-a", name: "Free models", budgetUSD: nil, valueAs: "claude-opus-5-5", show: show)
            let object = try Self.groupObject(group)
            #expect(object["valueAs"] as? String == "claude-opus-5-5")
            #expect(object["show"] as? String == (show == .automatic ? nil : show.rawValue))
        }
    }

    @Test func roundTripsKeepEveryField() throws {
        let groups = [
            BudgetGroup(id: "grp-a", name: "Free models", icon: "solid:gift", period: .monthly, budgetUSD: nil, shownInBar: false,
                        thresholds: [50, 90], timeFormat: .absolute, valueAs: "claude-opus-5-5", show: .tokens),
            BudgetGroup(id: "grp-b", name: "Team", icon: "solid:wallet", period: .weekly, budgetUSD: 500, shownInBar: true,
                        thresholds: [80, 100], valueAs: "claude-opus-5-5", show: .money),
        ]
        let config = Configuration(groups: groups)
        let written = try Self.encoded(config)
        let reread = try JSONDecoder().decode(Configuration.self, from: written)
        #expect(reread == config)
        #expect(try Self.encoded(reread) == written)
    }

    /// A group with an amount and no new keys is written byte for byte as
    /// before this feature (golden literal, SC-004).
    static let groupBefore = #"{"budgetUSD":500,"icon":"solid:wallet","id":"grp-b","name":"Team","period":"monthly","shownInBar":false,"thresholds":[50,90],"timeFormat":"absolute"}"#

    @Test func groupsWithAnAmountEncodeAsBefore() throws {
        let group = try decodeGroup(#"{"id": "grp-b", "name": "Team", "icon": "solid:wallet", "period": "monthly", "budgetUSD": 500, "shownInBar": false, "thresholds": [50, 90], "timeFormat": "absolute"}"#)
        #expect(String(decoding: try Self.encoded(group), as: UTF8.self) == Self.groupBefore)
        #expect(String(decoding: try Self.encoded(try decodeConfig(currentExampleJSON)), as: UTF8.self)
                == NoLimitConfigurationTests.currentExampleBefore)
    }

    // MARK: Membership (FR-006)

    @Test func anyTokenBasedAccountMayJoinEitherGroup() throws {
        try Self.mixed().validate()
        try Self.mixed().validateForSaving()
    }

    // MARK: Owners and counting periods (R1, R2)

    @Test func onlyGroupsWithAnAmountAreBudgetOwners() {
        let config = Self.mixed()
        #expect(config.budgetOwners.map(\.id) == ["grp-team"])
        #expect(config.noLimitGroups.map(\.id) == ["grp-open"])
        #expect(config.budgetOwner(forAccount: "acc-open-claude") == nil)
        #expect(config.budgetOwner(forAccount: "acc-team-codex")?.id == "grp-team")
    }

    @Test func membersOfAGroupWithoutAnAmountCountInItsPeriod() {
        let config = Self.mixed()
        #expect(config.countingPeriod(forAccount: "acc-open-claude") == .monthly)
        #expect(config.countingPeriod(forAccount: "acc-open-codex") == .monthly)
        #expect(config.countingPeriod(forAccount: "acc-team-oc") == .weekly)
    }

    /// The members' monthly period widens the collection window, as a
    /// monthly budget does (R2).
    @Test func monthlyGroupWithoutAnAmountWidensTheCollectionWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12)))
        let weekly = DateInterval(start: now.addingTimeInterval(-2 * 86_400), duration: 7 * 86_400)
        let window = WindowResolver().collectionWindow(weekly: weekly, now: now, configuration: Self.mixed(), calendar: calendar)
        #expect(window.start == calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    }

    // MARK: Refresh (FR-010, R8)

    @Test func presentationEditsOfAGroupNeedNoRefresh() {
        let old = Self.mixed()
        for index in old.groups.indices {
            var changed = old
            changed.groups[index].show = .tokens
            #expect(!changed.needsRefresh(comparedTo: old))
            changed.groups[index].valueAs = "claude-opus-5-5"
            #expect(!changed.needsRefresh(comparedTo: old))
        }
    }

    @Test func keptSettingsOfAGroupWithoutAnAmountNeedNoRefresh() {
        let old = Self.mixed()
        var changed = old
        changed.groups[0].thresholds = [70]
        changed.groups[0].shownInBar = true
        #expect(!changed.needsRefresh(comparedTo: old))
    }

    @Test func addingOrRemovingTheAmountNeedsARefresh() {
        let old = Self.mixed()
        var added = old
        added.groups[0].budgetUSD = 100
        #expect(added.needsRefresh(comparedTo: old))
        var removed = old
        removed.groups[1].budgetUSD = nil
        #expect(removed.needsRefresh(comparedTo: old))
    }

    /// Unchanged from before this feature: thresholds and shown-in-bar of a
    /// group with an amount are presentation only (spec 004 research R8).
    @Test func thresholdsOfAGroupWithAnAmountBehaveAsToday() {
        let old = Self.mixed()
        var changed = old
        changed.groups[1].thresholds = [70]
        changed.groups[1].shownInBar = false
        #expect(!changed.needsRefresh(comparedTo: old))
    }
}
