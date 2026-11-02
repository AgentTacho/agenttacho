import Foundation
import Testing
@testable import UsageCore

/// spec 040 FR-001 to FR-006, FR-012, research R3 to R5: the Claude window
/// list built from the usage endpoint's `limits` entries, with the top-level
/// fallback.
@Suite struct ClaudeLimitsTests {
    static let reset = Date(timeIntervalSince1970: 1_793_000_000)
    static let hour: TimeInterval = 3600
    static let week: TimeInterval = 7 * 24 * 3600

    /// Entries with `rawIndex` set to their position.
    static func entries(_ list: [ClaudeLimitEntry]) -> [ClaudeLimitEntry] {
        list.enumerated().map { index, entry in
            var copy = entry
            copy.rawIndex = index
            return copy
        }
    }

    static func entry(_ kind: String?, _ group: String?, _ percent: Double? = 10, resetsAt: Date? = reset,
                      model: String? = nil, modelScope: Bool = false, surface: Bool = false,
                      unreadable: Bool = false) -> ClaudeLimitEntry {
        ClaudeLimitEntry(kind: kind, group: group, percent: percent, resetsAt: resetsAt, resetUnreadable: unreadable,
                         modelName: model, hasModelScope: modelScope || model != nil, isSurfaceOnly: surface, rawIndex: 0)
    }

    static func build(_ list: [ClaudeLimitEntry]?, allowances: [Int: Int] = [:],
                      five: (percent: Double, resetsAt: Date?)? = nil,
                      seven: (percent: Double, resetsAt: Date?)? = nil) -> (windows: [ClaudeLimit], report: ClaudeWindowReport) {
        ClaudeLimits.build(entries: list.map(entries), allowances: allowances, fallbackFiveHour: five, fallbackSevenDay: seven)
    }

    // MARK: - Fixtures

    @Test func fixturesHaveThePinnedValues() {
        let five = ClaudeLimit.fiveHour(40, resetsAt: Self.reset)
        #expect(five.identity == .fiveHour)
        #expect(five.kind == "five_hour")
        #expect(five.group == "five_hour")
        #expect(five.name == "5-hour")
        #expect(five.length == 5 * Self.hour)
        #expect(five.modelName == nil)
        #expect(!five.isModelLimit)
        #expect(five.utilizationPercent == 40)
        #expect(five.resetsAt == Self.reset)

        let seven = ClaudeLimit.sevenDay(11, resetsAt: nil)
        #expect(seven.identity == .sevenDay)
        #expect(seven.kind == "seven_day")
        #expect(seven.group == "weekly")
        #expect(seven.name == "7-day")
        #expect(seven.length == Self.week)
        #expect(seven.resetsAt == nil)

        let model = ClaudeLimit.model("Fable", 15, resetsAt: Self.reset, allowance: 50)
        #expect(model.identity == .model("Fable"))
        #expect(model.kind == "weekly_scoped")
        #expect(model.group == "weekly")
        #expect(model.name == "Fable")
        #expect(model.modelName == "Fable")
        #expect(model.isModelLimit)
        #expect(model.length == Self.week)
        #expect(model.allowancePercentOfWeekly == 50)
    }

    @Test func groupLengths() {
        #expect(ClaudeLimits.groupLength("weekly") == Self.week)
        #expect(ClaudeLimits.groupLength("WEEKLY") == Self.week)
        #expect(ClaudeLimits.groupLength("five_hour") == 5 * Self.hour)
        #expect(ClaudeLimits.groupLength("session") == 5 * Self.hour)
        #expect(ClaudeLimits.groupLength("5h") == 5 * Self.hour)
        #expect(ClaudeLimits.groupLength("daily") == nil)
        #expect(ClaudeLimits.groupLength(nil) == nil)
    }

    // MARK: - (a) the 2026-11-02 shape

    @Test func todaysShape() {
        let (windows, report) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry("weekly_scoped", "weekly", 15, model: "Fable"),
        ], allowances: [1: 50])
        #expect(windows.map(\.identity) == [.sevenDay, .model("Fable")])
        #expect(windows.map(\.name) == ["7-day", "Fable"])
        #expect(windows.map(\.length) == [Self.week, Self.week])
        #expect(windows[0].kind == "weekly_all")
        #expect(windows[0].utilizationPercent == 11)
        #expect(windows[0].allowancePercentOfWeekly == nil)
        #expect(windows[1].modelName == "Fable")
        #expect(windows[1].allowancePercentOfWeekly == 50)
        #expect(windows[1].utilizationPercent == 15)
        #expect(windows.allSatisfy { $0.resetsAt == Self.reset })
        #expect(!report.usedFallback)
    }

    // MARK: - (b) a returning 5-hour group

    @Test(arguments: ["five_hour", "session", "5h", "Session"])
    func fiveHourGroups(group: String) {
        let (windows, _) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry("\(group)_all", group, 40),
        ])
        #expect(windows.map(\.identity) == [.fiveHour, .sevenDay])
        #expect(windows[0].name == "5-hour")
        #expect(windows[0].length == 5 * Self.hour)
        #expect(windows[0].utilizationPercent == 40)
    }

    // MARK: - (c), (d) unknown groups

    @Test func unknownGroupComesAfterKnownPlanWindowsAndBeforeModelLimits() {
        let (windows, _) = Self.build([
            Self.entry("weekly_scoped", "weekly", 15, model: "Fable"),
            Self.entry("daily_all", "daily", 40),
            Self.entry("weekly_all", "weekly", 11),
        ])
        #expect(windows.map(\.identity) == [.sevenDay, ClaudeWindow(rawValue: "limit:daily_all"), .model("Fable")])
        #expect(windows[1].name == "daily")
        #expect(windows[1].length == nil)
        #expect(windows[1].group == "daily")
        #expect(!windows[1].isModelLimit)
    }

    @Test func unknownGroupNameIsLowercasedWithSpaces() {
        let (windows, _) = Self.build([Self.entry("rolling_all", "Rolling_Day", 5)])
        #expect(windows.map(\.name) == ["rolling day"])
        #expect(windows[0].identity == ClaudeWindow(rawValue: "limit:rolling_all"))
    }

    // MARK: - (e), (f) two windows of one known group

    @Test func twoWeeklyKindsWithWeeklyAllSecond() {
        let (windows, _) = Self.build([
            Self.entry("weekly_extra", "weekly", 20),
            Self.entry("weekly_all", "weekly", 11),
        ])
        #expect(windows.map(\.identity) == [ClaudeWindow(rawValue: "limit:weekly_extra"), .sevenDay])
        #expect(windows.map(\.name) == ["weekly extra", "7-day"])
        #expect(windows.map(\.length) == [Self.week, Self.week])
    }

    @Test func twoWeeklyKindsWithoutWeeklyAllGiveSevenDayToTheFirst() {
        let (windows, _) = Self.build([
            Self.entry("weekly_one", "weekly", 20),
            Self.entry("weekly_two", "weekly", 11),
        ])
        #expect(windows.map(\.identity) == [.sevenDay, ClaudeWindow(rawValue: "limit:weekly_two")])
        #expect(windows.map(\.name) == ["7-day", "weekly two"])
    }

    @Test func twoFiveHourGroupEntries() {
        let (windows, _) = Self.build([
            Self.entry("five_hour_all", "five_hour", 40),
            Self.entry("session_other", "session", 30),
        ])
        #expect(windows.map(\.identity) == [.fiveHour, ClaudeWindow(rawValue: "limit:session_other")])
        #expect(windows.map(\.name) == ["5-hour", "session other"])
    }

    // MARK: - (g), (h) model limits

    @Test func twoLimitsOfOneModel() {
        let (windows, _) = Self.build([
            Self.entry("daily_scoped", "daily", 30, model: "Fable"),
            Self.entry("weekly_scoped", "weekly", 15, model: "Fable"),
        ])
        #expect(windows.map(\.identity) == [ClaudeWindow(rawValue: "model:Fable:daily_scoped"), .model("Fable")])
        #expect(windows.map(\.name) == ["Fable daily", "Fable"])
        #expect(windows.map(\.length) == [nil, Self.week])
        #expect(windows.allSatisfy { $0.modelName == "Fable" })
    }

    @Test func secondWeeklyLimitOfAModelIsNamedFromItsKind() {
        let (windows, _) = Self.build([
            Self.entry("weekly_scoped", "weekly", 15, model: "Fable"),
            Self.entry("weekly_scoped_extra", "weekly", 5, model: "Fable"),
        ])
        #expect(windows.map(\.identity) == [.model("Fable"), ClaudeWindow(rawValue: "model:Fable:weekly_scoped_extra")])
        #expect(windows.map(\.name) == ["Fable", "Fable weekly scoped extra"])
    }

    @Test func modelLimitWithoutAWeeklyEntryTakesTheFirst() {
        let (windows, _) = Self.build([
            Self.entry("daily_scoped", "daily", 30, model: "Fable"),
            Self.entry("hourly_scoped", "hourly", 5, model: "Fable"),
        ])
        #expect(windows.map(\.identity) == [.model("Fable"), ClaudeWindow(rawValue: "model:Fable:hourly_scoped")])
        #expect(windows.map(\.name) == ["Fable", "Fable hourly"])
    }

    @Test func modelLimitAndPlanWindowWithTheSameNameKeepDifferentIdentities() {
        let (windows, _) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry("x_all", "daily", 20),
            Self.entry("weekly_scoped", "weekly", 15, model: "daily"),
        ])
        #expect(windows.map(\.name) == ["7-day", "daily", "daily"])
        #expect(windows.map(\.identity) == [.sevenDay, ClaudeWindow(rawValue: "limit:x_all"), .model("daily")])
    }

    // MARK: - (i), (j), (k) skipped entries

    @Test func surfaceOnlyScopeIsSkippedAndReported() {
        let (windows, report) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry("weekly_surface", "weekly", 30, surface: true),
        ])
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(report.skipped == ["weekly_surface/weekly/surface"])
    }

    @Test func modelScopeWithoutANameIsSkipped() {
        let (windows, report) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry("weekly_scoped", "weekly", 30, modelScope: true),
        ])
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(report.skipped.count == 1)
    }

    @Test func entryWithoutKindAndGroupIsSkipped() {
        let (windows, report) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry(nil, nil, 30),
        ])
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(report.skipped == ["//none"])
    }

    @Test func entryWithoutKindUsesItsGroup() {
        let (windows, report) = Self.build([Self.entry(nil, "daily", 30)])
        #expect(windows.map(\.identity) == [ClaudeWindow(rawValue: "limit:daily")])
        #expect(windows[0].name == "daily")
        #expect(windows[0].kind == "daily")
        #expect(report.read == ["/daily/none"])
    }

    /// An empty kind counts as missing, so the identity uses the group.
    @Test func emptyKindUsesTheGroup() {
        let (windows, _) = Self.build([Self.entry("", "daily", 30), Self.entry("x", "", 20, model: "Fable")])
        #expect(windows.map(\.identity) == [ClaudeWindow(rawValue: "limit:daily"), .model("Fable")])
        #expect(windows[1].group == nil)
    }

    @Test func entryWithoutGroupIsNamedFromItsKind() {
        let (windows, report) = Self.build([Self.entry("daily_all", nil, 30)])
        #expect(windows.map(\.identity) == [ClaudeWindow(rawValue: "limit:daily_all")])
        #expect(windows[0].name == "daily all")
        #expect(windows[0].length == nil)
        #expect(report.read == ["daily_all//none"])
    }

    @Test func duplicateIdentityKeepsTheFirst() {
        let (windows, report) = Self.build([
            Self.entry("daily_all", "daily", 30),
            Self.entry("daily_all", "daily", 50),
        ])
        #expect(windows.map(\.identity) == [ClaudeWindow(rawValue: "limit:daily_all")])
        #expect(windows[0].utilizationPercent == 30)
        #expect(report.read == ["daily_all/daily/none"])
        #expect(report.skipped == ["daily_all/daily/none"])
    }

    @Test func entryWithoutPercentIsSkipped() {
        let (windows, report) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry("daily_all", "daily", nil),
        ])
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(report.skipped == ["daily_all/daily/none"])
    }

    // MARK: - (l) ordering

    @Test func equalLengthsKeepResponseOrder() {
        let (windows, _) = Self.build([
            Self.entry("weekly_b", "weekly", 1),
            Self.entry("session_all", "session", 2),
            Self.entry("weekly_all", "weekly", 3),
            Self.entry("five_hour_x", "5h", 4),
            Self.entry("monthly_all", "monthly", 5),
            Self.entry("daily_all", "daily", 6),
        ])
        #expect(windows.map(\.utilizationPercent) == [2, 4, 1, 3, 5, 6])
    }

    // MARK: - (m), (n) top-level fallback

    @Test func noUnscopedEntryUsesTheFallback() {
        let other = Self.reset.addingTimeInterval(-3 * Self.hour)
        let (windows, report) = Self.build([Self.entry("weekly_scoped", "weekly", 15, model: "Fable")],
                                           allowances: [0: 50], five: (40, other), seven: (11, Self.reset))
        #expect(windows.map(\.identity) == [.fiveHour, .sevenDay, .model("Fable")])
        #expect(windows.map(\.kind) == ["five_hour", "seven_day", "weekly_scoped"])
        #expect(windows.map(\.group) == ["five_hour", "weekly", "weekly"])
        #expect(windows.map(\.name) == ["5-hour", "7-day", "Fable"])
        #expect(windows[0].resetsAt == other)
        #expect(windows[0].utilizationPercent == 40)
        #expect(windows[2].allowancePercentOfWeekly == 50)
        #expect(report.usedFallback)
        #expect(report.read == ["five_hour/five_hour/none", "seven_day/weekly/none", "weekly_scoped/weekly/model:Fable"])
    }

    @Test func missingLimitsUsesTheFallback() {
        let (windows, report) = Self.build(nil, five: (40, Self.reset), seven: (11, nil))
        #expect(windows.map(\.identity) == [.fiveHour, .sevenDay])
        #expect(windows[1].resetsAt == nil)
        #expect(report.usedFallback)
    }

    @Test func emptyLimitsUsesTheFallback() {
        let (windows, report) = Self.build([], seven: (11, Self.reset))
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(report.usedFallback)
    }

    @Test func unreadableUnscopedEntryUsesTheFallback() {
        let (windows, report) = Self.build([Self.entry("weekly_all", "weekly", 11, unreadable: true)], seven: (12, Self.reset))
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(windows[0].utilizationPercent == 12)
        #expect(report.usedFallback)
        #expect(report.skipped == ["weekly_all/weekly/none"])
    }

    @Test func readableUnscopedEntryIgnoresTheFallback() {
        let (windows, report) = Self.build([Self.entry("weekly_all", "weekly", 11)], five: (40, Self.reset), seven: (99, Self.reset))
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(windows[0].utilizationPercent == 11)
        #expect(!report.usedFallback)
    }

    @Test func noWindowsAtAll() {
        let (windows, report) = Self.build([])
        #expect(windows.isEmpty)
        #expect(report.read.isEmpty)
    }

    // MARK: - (o) reset times

    @Test func nullResetIsKeptAlsoForModelLimits() {
        let (windows, _) = Self.build([
            Self.entry("weekly_all", "weekly", 0, resetsAt: nil),
            Self.entry("weekly_scoped", "weekly", 0, resetsAt: nil, model: "Fable"),
        ])
        #expect(windows.map(\.identity) == [.sevenDay, .model("Fable")])
        #expect(windows.allSatisfy { $0.resetsAt == nil })
    }

    @Test func unreadableResetIsSkipped() {
        let (windows, report) = Self.build([
            Self.entry("weekly_all", "weekly", 11),
            Self.entry("weekly_scoped", "weekly", 15, resetsAt: nil, model: "Fable", unreadable: true),
        ])
        #expect(windows.map(\.identity) == [.sevenDay])
        #expect(report.skipped == ["weekly_scoped/weekly/model:Fable"])
    }

    /// The identity of each entry by raw index; skipped entries have none.
    @Test func identitiesByRawIndex() {
        let ids = ClaudeLimits.identities(entries: Self.entries([
            Self.entry("weekly_scoped", "weekly", 15, model: "Fable"),
            Self.entry("weekly_all", "weekly", 11),
            Self.entry(nil, nil, 3),
            Self.entry("daily_all", "daily", 40),
        ]))
        #expect(ids == [0: .model("Fable"), 1: .sevenDay, 3: ClaudeWindow(rawValue: "limit:daily_all")])
    }

    // MARK: - (p) the report

    @Test func reportListsTheWindowsInResponseOrder() {
        let (_, report) = Self.build([
            Self.entry("weekly_scoped", "weekly", 15, model: "Fable"),
            Self.entry("weekly_all", "weekly", 11),
        ])
        #expect(report.read == ["weekly_scoped/weekly/model:Fable", "weekly_all/weekly/none"])
        #expect(report.skipped.isEmpty)
        #expect(!report.usedFallback)
        #expect(report.signature == ["weekly_scoped/weekly/model:Fable", "weekly_all/weekly/none"])
    }

    @Test func signatureMarksSkippedEntries() {
        let report = ClaudeWindowReport(usedFallback: false, read: ["a/b/none"], skipped: ["a/b/none"])
        #expect(report.signature == ["a/b/none", "a/b/none skipped"])
    }
}

/// spec 040 FR-006, FR-009, spec 010 FR-016: the window list on the status.
@Suite struct SubscriptionStatusWindowsTests {
    static let fetched = Date(timeIntervalSince1970: 1_793_000_000)
    static let later = fetched.addingTimeInterval(3600)
    static let earlier = fetched.addingTimeInterval(-3600)

    static func limit(_ raw: String, length: TimeInterval?, percent: Double = 10, resetsAt: Date? = later) -> ClaudeLimit {
        ClaudeLimit(identity: ClaudeWindow(rawValue: raw), kind: raw, group: nil, length: length, name: raw, modelName: nil,
                    allowancePercentOfWeekly: nil, utilizationPercent: percent, resetsAt: resetsAt)
    }

    @Test func accessors() {
        let windows: [ClaudeLimit] = [
            .fiveHour(40, resetsAt: Self.later), .sevenDay(11, resetsAt: Self.later),
            .model("Fable", 15, resetsAt: Self.later, allowance: 50),
        ]
        let status = SubscriptionStatus(windows: windows, subscriptionType: "max", fetchedAt: Self.fetched)
        #expect(status.windows == windows)
        #expect(status.windowReport == nil)
        #expect(status.subscriptionType == "max")
        #expect(status.window(.sevenDay)?.utilizationPercent == 11)
        #expect(status.window(.model("Fable"))?.allowancePercentOfWeekly == 50)
        #expect(status.window(ClaudeWindow(rawValue: "limit:daily_all")) == nil)
        #expect(status.planWindows.map(\.identity) == [.fiveHour, .sevenDay])
        #expect(status.modelLimitWindows.map(\.identity) == [.model("Fable")])
    }

    @Test func defaultIsSevenDay() {
        let status = SubscriptionStatus(windows: [.fiveHour(40, resetsAt: nil), .sevenDay(11, resetsAt: nil),
                                                  Self.limit("limit:monthly", length: 30 * 86400)], fetchedAt: Self.fetched)
        #expect(status.defaultWindow?.identity == .sevenDay)
    }

    @Test func defaultIsTheLongestWithALength() {
        let status = SubscriptionStatus(windows: [.fiveHour(40, resetsAt: nil),
                                                  Self.limit("limit:a", length: 86400), Self.limit("limit:b", length: 86400),
                                                  Self.limit("limit:daily", length: nil),
                                                  .model("Fable", 15, resetsAt: nil)], fetchedAt: Self.fetched)
        #expect(status.defaultWindow?.identity == ClaudeWindow(rawValue: "limit:a"))
    }

    @Test func defaultIsTheFirstPlanWindowWithoutLengths() {
        let status = SubscriptionStatus(windows: [Self.limit("limit:x", length: nil), Self.limit("limit:y", length: nil),
                                                  .model("Fable", 15, resetsAt: nil)], fetchedAt: Self.fetched)
        #expect(status.defaultWindow?.identity == ClaudeWindow(rawValue: "limit:x"))
    }

    @Test func noDefaultWithoutPlanWindows() {
        #expect(SubscriptionStatus(windows: [.model("Fable", 15, resetsAt: nil)], fetchedAt: Self.fetched).defaultWindow == nil)
        #expect(SubscriptionStatus(windows: [], fetchedAt: Self.fetched).defaultWindow == nil)
    }

    /// Every window past its reset shows 0% without a reset time, model
    /// limits and unknown groups included (spec 010 FR-016).
    @Test func effectiveZeroesEveryWindowPastItsReset() {
        let status = SubscriptionStatus(windows: [
            .fiveHour(40, resetsAt: Self.earlier), .sevenDay(11, resetsAt: Self.later),
            Self.limit("limit:daily", length: nil, percent: 30, resetsAt: Self.fetched),
            .model("Fable", 15, resetsAt: Self.earlier),
        ], fetchedAt: Self.fetched)
        let effective = status.effective(now: Self.fetched)
        #expect(effective.windows.map(\.utilizationPercent) == [0, 11, 0, 0])
        #expect(effective.windows.map(\.resetsAt) == [nil, Self.later, nil, nil])
        #expect(effective.windows.map(\.identity) == status.windows.map(\.identity))
    }
}

/// spec 040 FR-012: the text of the window log line and of the summary.
@Suite struct ClaudeWindowLogTextTests {
    @Test func logMessageListsTheWindowsAndTheSource() {
        let report = ClaudeWindowReport(usedFallback: false, read: ["weekly_all/weekly/none", "weekly_scoped/weekly/model:Fable"],
                                        skipped: ["weekly_surface/weekly/surface"])
        #expect(report.logMessage(accountId: "acc-max")
            == "acc-max: windows weekly_all/weekly/none, weekly_scoped/weekly/model:Fable, weekly_surface/weekly/surface skipped (limits)")
        let fallback = ClaudeWindowReport(usedFallback: true, read: ["seven_day/weekly/none"], skipped: [])
        #expect(fallback.logMessage(accountId: "a") == "a: windows seven_day/weekly/none (fallback)")
        #expect(ClaudeWindowReport(usedFallback: true, read: [], skipped: []).logMessage(accountId: "a") == "a: windows none (fallback)")
    }

    @Test func summaryNamesTheShownWindows() {
        let reset = Date(timeIntervalSince1970: 1_793_000_000)
        let status = SubscriptionStatus(windows: [.sevenDay(11.4, resetsAt: reset), .model("Fable", 15, resetsAt: reset)],
                                        fetchedAt: reset)
        #expect(status.windowSummary == "7-day 11%, Fable 15%")
        #expect(SubscriptionStatus(windows: [], fetchedAt: reset).windowSummary == "no limits")
    }
}
