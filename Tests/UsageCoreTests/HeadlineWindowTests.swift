import Foundation
import Testing
@testable import UsageCore

/// spec 027 FR-005, FR-006, FR-008, research R3, R5: the headline window of
/// a Claude subscription, resolved from the choice and the latest values.
@Suite struct ClaudeHeadlineWindowTests {
    static let now = isoDate("2026-10-14T15:00:00Z")
    static let hour: TimeInterval = 3600

    static func status(five: Double? = 58, seven: Double? = 70, models: [ClaudeLimit] = [],
                       fiveResetsIn: TimeInterval = 2.5 * hour) -> SubscriptionStatus {
        let plan = [five.map { ClaudeLimit.fiveHour($0, resetsAt: now.addingTimeInterval(fiveResetsIn)) },
                    seven.map { ClaudeLimit.sevenDay($0, resetsAt: now.addingTimeInterval(3 * 24 * hour)) }]
        return SubscriptionStatus(windows: plan.compactMap { $0 } + models, fetchedAt: now)
    }

    static let fable = ClaudeLimit.model("Fable", 31, resetsAt: now.addingTimeInterval(3 * 24 * hour))

    static func resolve(_ status: SubscriptionStatus?, _ choice: HeadlineChoice?) -> ResolvedHeadline {
        HeadlineWindow.claude(accountId: "acc-max", status: status, choice: choice, now: now)
    }

    @Test(arguments: [nil, HeadlineChoice.claude(.sevenDay)])
    func defaultIsTheSevenDayWindow(choice: HeadlineChoice?) {
        let status = Self.status()
        let headline = Self.resolve(status, choice)
        #expect(headline.claudeWindow == .sevenDay)
        #expect(headline.codexName == nil)
        #expect(headline.isDefault)
        #expect(headline.percent == 70)
        #expect(headline.tag == nil)
        #expect(headline.rowName == "7-day")
        #expect(headline.accessibilityName == "7-day window")
        #expect(headline.pace == status.window(.sevenDay).flatMap { status.pace(of: $0, now: Self.now) })
        #expect(headline.burnKey == .claude("acc-max", .sevenDay))
    }

    /// A chosen model limit whose reset passed shows 0% with its tag and
    /// stays the headline (edge case, spec 010 FR-016).
    @Test func resetModelLimitShowsZeroWithTag() {
        let passed = ClaudeLimit.model("Fable", 31, resetsAt: Self.now.addingTimeInterval(-Self.hour))
        let headline = Self.resolve(Self.status(models: [passed]), .claude(.model("Fable")))
        #expect(headline.claudeWindow == .model("Fable"))
        #expect(!headline.isDefault)
        #expect(headline.percent == 0)
        #expect(headline.tag == "Fable")
    }

    @Test func fiveHourWindow() {
        let status = Self.status()
        let headline = Self.resolve(status, .claude(.fiveHour))
        #expect(headline.claudeWindow == .fiveHour)
        #expect(!headline.isDefault)
        #expect(headline.percent == 58)
        #expect(headline.tag == "5h")
        #expect(headline.rowName == "5-hour")
        #expect(headline.accessibilityName == "5-hour window")
        #expect(headline.pace == status.window(.fiveHour).flatMap { status.pace(of: $0, now: Self.now) })
        #expect(headline.pace != nil)
        #expect(headline.burnKey == .claude("acc-max", .fiveHour))
    }

    /// spec 040 FR-010 (replaces spec 027 US3 scenario 4): a chosen 5-hour
    /// window the values do not contain falls back to the default window,
    /// without a tag.
    @Test func absentFiveHourFallsBackToTheDefault() {
        for status in [Self.status(five: nil), nil] {
            let headline = Self.resolve(status, .claude(.fiveHour))
            #expect(headline.claudeWindow == .sevenDay)
            #expect(headline.isDefault)
            #expect(headline.percent == (status == nil ? nil : 70))
            #expect(headline.tag == nil)
            #expect(headline.rowName == "7-day")
        }
    }

    /// Without values the default window resolves with percent nil.
    @Test func defaultWithoutValues() {
        let headline = Self.resolve(nil, nil)
        #expect(headline.claudeWindow == .sevenDay)
        #expect(headline.isDefault)
        #expect(headline.percent == nil)
        #expect(headline.tag == nil)
        #expect(Self.resolve(nil, .claude(.model("Fable"))).isDefault)
    }

    @Test func modelLimit() {
        let status = Self.status(models: [Self.fable])
        let headline = Self.resolve(status, .claude(.model("Fable")))
        #expect(headline.claudeWindow == .model("Fable"))
        #expect(!headline.isDefault)
        #expect(headline.percent == 31)
        #expect(headline.tag == "Fable")
        #expect(headline.rowName == "Fable")
        #expect(headline.accessibilityName == "Fable weekly limit")
        #expect(headline.pace == status.window(.model("Fable")).flatMap { status.pace(of: $0, now: Self.now) })
        #expect(headline.burnKey == .claude("acc-max", .model("Fable")))
    }

    /// A missing model limit, or one of another case, falls back to the
    /// default window without a tag (FR-006).
    @Test func missingModelLimitFallsBack() {
        for (status, choice) in [(Self.status(), HeadlineChoice.claude(.model("Fable"))),
                                 (Self.status(models: [Self.fable]), .claude(.model("fable")))] {
            let headline = Self.resolve(status, choice)
            #expect(headline.claudeWindow == .sevenDay)
            #expect(headline.isDefault)
            #expect(headline.percent == 70)
            #expect(headline.tag == nil)
            #expect(headline.rowName == "7-day")
        }
    }

    /// A model name longer than 8 characters is cut to 7 plus "…" (FR-008).
    @Test func longModelNamesAreCut() {
        func model(_ name: String) -> ClaudeLimit { .model(name, 1, resetsAt: nil) }
        #expect(HeadlineWindow.tag(claude: model("Fable")) == "Fable")
        #expect(HeadlineWindow.tag(claude: model("Abcdefgh")) == "Abcdefgh")
        #expect(HeadlineWindow.tag(claude: model("Abcdefghi")) == "Abcdefg…")
        #expect(HeadlineWindow.tag(claude: .fiveHour(1, resetsAt: nil)) == "5h")
        #expect(HeadlineWindow.tag(claude: .sevenDay(1, resetsAt: nil)) == "7d")
        let long = ClaudeLimit.model("Opus 4.6 Max", 12, resetsAt: Self.now.addingTimeInterval(Self.hour))
        let headline = Self.resolve(Self.status(models: [long]), .claude(.model("Opus 4.6 Max")))
        #expect(headline.tag == "Opus 4.…")
        #expect(headline.accessibilityName == "Opus 4.6 Max weekly limit")
    }

    /// A window whose reset passed shows 0% and keeps the choice (spec 010
    /// FR-016).
    @Test func resetFiveHourWindowShowsZero() {
        let headline = Self.resolve(Self.status(five: 58, fiveResetsIn: -60), .claude(.fiveHour))
        #expect(headline.percent == 0)
        #expect(headline.tag == "5h")
        #expect(headline.pace == nil)
    }

    /// spec 027 FR-008: the section header shows the tag before the bold
    /// percent, "--" for a chosen fixed window without values, and with the
    /// default window exactly what it shows today.
    @Test func sectionHeader() {
        let status = Self.status()
        #expect(HeadlineWindow.header(Self.resolve(status, nil), state: .ok) == HeadlineHeader(tag: nil, value: "70%"))
        #expect(HeadlineWindow.header(Self.resolve(status, .claude(.fiveHour)), state: .ok) == HeadlineHeader(tag: "5h", value: "58%"))
        // spec 040 FR-010: an absent chosen window shows the default.
        #expect(HeadlineWindow.header(Self.resolve(Self.status(five: nil), .claude(.fiveHour)), state: .ok)
                == HeadlineHeader(tag: nil, value: "70%"))
        #expect(HeadlineWindow.header(Self.resolve(nil, .claude(.fiveHour)), state: .stale(lastGoodAt: nil, error: "x")) == nil)
        // spec 040 FR-009: without a 7-day window the 5-hour window is the
        // default; without any plan window there is no percent, as before.
        #expect(HeadlineWindow.header(Self.resolve(Self.status(seven: nil), nil), state: .ok) == HeadlineHeader(tag: nil, value: "58%"))
        #expect(HeadlineWindow.header(Self.resolve(Self.status(five: nil, seven: nil), nil), state: .ok) == nil)
        // Before the first values and when not signed in: nothing.
        #expect(HeadlineWindow.header(Self.resolve(nil, .claude(.fiveHour)), state: nil) == nil)
        #expect(HeadlineWindow.header(Self.resolve(nil, .claude(.fiveHour)), state: .notSignedIn) == nil)
        // A Codex headline always has a percent.
        let codex = HeadlineWindow.codex(accountId: "c", entry: CodexHeadlineWindowTests.plus, choice: .codexWindow("5-hour"),
                                         now: Self.now)
        #expect(codex?.header == HeadlineHeader(tag: "5h", value: "40%"))
    }

    /// What a click on each row stores: the 7-day row clears the choice.
    @Test func choiceForClaudeRows() {
        let status = Self.status(models: [Self.fable])
        #expect(HeadlineWindow.choice(forClaude: .fiveHour, status: status) == .claude(.fiveHour))
        #expect(HeadlineWindow.choice(forClaude: .sevenDay, status: status) == nil)
        #expect(HeadlineWindow.choice(forClaude: .model("Fable"), status: status) == .claude(.model("Fable")))
        #expect(HeadlineWindow.choice(forClaude: .sevenDay, status: nil) == nil)
    }
}

/// spec 027 FR-005, FR-006, FR-008: the headline window of a Codex plan.
@Suite struct CodexHeadlineWindowTests {
    static let now = isoDate("2026-10-14T15:00:00Z")
    static let hour: TimeInterval = 3600

    static func window(_ minutes: Int, _ used: Double, resetsIn: TimeInterval = 2 * hour) -> CodexLimitWindow {
        CodexLimitWindow(lengthMinutes: minutes, usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn))
    }

    static func entry(_ windows: [CodexLimitWindow]) -> CodexLimitsEntry {
        CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: now, origin: .live, windows: windows),
                         state: .live)
    }

    static let plus = entry([window(300, 40), window(10080, 60, resetsIn: 3 * 24 * hour)])

    static func resolve(_ entry: CodexLimitsEntry, _ choice: HeadlineChoice?) -> ResolvedHeadline? {
        HeadlineWindow.codex(accountId: "acc-codex", entry: entry, choice: choice, now: now)
    }

    @Test func defaultIsTheLongestWindow() throws {
        let headline = try #require(Self.resolve(Self.plus, nil))
        #expect(headline.claudeWindow == nil)
        #expect(headline.codexName == "weekly")
        #expect(headline.isDefault)
        #expect(headline.percent == 60)
        #expect(headline.tag == nil)
        #expect(headline.rowName == "weekly")
        #expect(headline.accessibilityName == "weekly window")
        #expect(headline.burnKey == .codex("acc-codex", "weekly"))
    }

    @Test func fiveHourWindow() throws {
        let headline = try #require(Self.resolve(Self.plus, .codexWindow("5-hour")))
        #expect(headline.codexName == "5-hour")
        #expect(!headline.isDefault)
        #expect(headline.percent == 40)
        #expect(headline.tag == "5h")
        #expect(headline.rowName == "5-hour")
        #expect(headline.accessibilityName == "5-hour window")
        let fiveHour = try #require(Self.plus.windows(now: Self.now).first)
        #expect(headline.pace == Self.plus.pace(of: fiveHour, now: Self.now))
        #expect(headline.burnKey == .codex("acc-codex", "5-hour"))
    }

    /// An observation keeps one window per name (spec 007 FR-009), and the
    /// headline row is the last window of its name, like `barWindow` and
    /// the burn inputs, so only one row is marked.
    @Test func oneRowPerNameIsMarked() throws {
        let entry = Self.entry([Self.window(300, 10), Self.window(310, 45), Self.window(10080, 60)])
        let headline = try #require(Self.resolve(entry, .codexWindow("5-hour")))
        #expect(headline.percent == 10)
        let windows = entry.windows(now: Self.now)
        #expect(windows.count == 2)
        #expect(HeadlineWindow.codexHeadlineIndex(headline, windows: windows) == 0)
        let fallback = try #require(Self.resolve(entry, nil))
        #expect(HeadlineWindow.codexHeadlineIndex(fallback, windows: windows) == 1)
        // Rows with one name: the last one carries the marker.
        let rows = [Self.window(300, 10), Self.window(310, 45), Self.window(10080, 60)]
        #expect(HeadlineWindow.codexHeadlineIndex(headline, windows: rows) == 1)
        #expect(HeadlineWindow.codexHeadlineIndex(ClaudeHeadlineWindowTests.resolve(nil, nil), windows: rows) == nil)
    }

    @Test func tags() {
        #expect(HeadlineWindow.tag(codexName: "5-hour") == "5h")
        #expect(HeadlineWindow.tag(codexName: "2-hour") == "2h")
        #expect(HeadlineWindow.tag(codexName: "30-day") == "30d")
        #expect(HeadlineWindow.tag(codexName: "weekly") == "wk")
    }

    /// A weekly window that is not the longest carries the "wk" tag.
    @Test func weeklyWindowThatIsNotTheLongest() throws {
        let entry = Self.entry([Self.window(10080, 60), Self.window(43200, 20)])
        let headline = try #require(Self.resolve(entry, .codexWindow("weekly")))
        #expect(headline.tag == "wk")
        #expect(headline.accessibilityName == "weekly window")
        #expect(try #require(Self.resolve(entry, nil)).rowName == "30-day")
    }

    /// A chosen window that is the longest one is the default, without tag.
    @Test func chosenLongestWindowIsTheDefault() throws {
        let headline = try #require(Self.resolve(Self.plus, .codexWindow("weekly")))
        #expect(headline.isDefault)
        #expect(headline.tag == nil)
    }

    /// A chosen window the plan no longer reports falls back to the longest.
    @Test func missingWindowFallsBack() throws {
        let entry = Self.entry([Self.window(10080, 60)])
        let headline = try #require(Self.resolve(entry, .codexWindow("5-hour")))
        #expect(headline.isDefault)
        #expect(headline.codexName == "weekly")
        #expect(headline.percent == 60)
        #expect(headline.tag == nil)
    }

    @Test func noWindowsGivesNil() {
        #expect(Self.resolve(CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline")), .codexWindow("5-hour")) == nil)
        #expect(Self.resolve(Self.entry([]), nil) == nil)
    }

    /// What a click on each row stores: the longest window clears it.
    @Test func choiceForCodexRows() {
        #expect(HeadlineWindow.choice(forCodex: "weekly", entry: Self.plus, now: Self.now) == nil)
        #expect(HeadlineWindow.choice(forCodex: "5-hour", entry: Self.plus, now: Self.now) == .codexWindow("5-hour"))
    }

    /// A stored 5-hour choice on a plan that now reports only its 5-hour
    /// window: that window is the default, without tag, and a click on its
    /// row clears the choice (edge cases: the chosen window becomes the
    /// longest; a plan with one window).
    @Test func chosenWindowBecomesTheOnlyOne() throws {
        let entry = Self.entry([Self.window(300, 40)])
        let headline = try #require(Self.resolve(entry, .codexWindow("5-hour")))
        #expect(headline.isDefault)
        #expect(headline.tag == nil)
        #expect(headline.rowName == "5-hour")
        #expect(HeadlineWindow.choice(forCodex: "5-hour", entry: entry, now: Self.now) == nil)
    }
}

/// spec 030 FR-005: the section header's bold percent has
/// the same level as the bar entry, cross-window rules included, because
/// both come from one decision in `BarLayout`.
@Suite struct HeadlineHeaderLevelTests {
    typealias F = RunOutMarkerBarLayoutTests
    typealias T = ThresholdLevelBarLayoutTests

    static func claude(_ sub: SubscriptionEntry, _ thresholds: [Int], _ choice: HeadlineChoice? = nil) -> (HeadlineHeader?, BarItem?) {
        let headline = HeadlineWindow.claude(accountId: "sub", status: sub.status, choice: choice, now: F.now)
        let header = HeadlineWindow.claudeHeader(headline, entry: sub, thresholds: thresholds, direction: .used, now: F.now)
        return (header, T.items(T.config(thresholds, claude: choice), sub: sub)["sub"])
    }

    static func codex(_ entry: CodexLimitsEntry, _ thresholds: [Int], _ choice: HeadlineChoice? = nil) -> (HeadlineHeader?, BarItem?) {
        let headline = HeadlineWindow.codex(accountId: "codex", entry: entry, choice: choice, now: F.now)
        let header = HeadlineWindow.codexHeader(headline, entry: entry, thresholds: thresholds, direction: .used, now: F.now)
        let config = T.config(thresholds).settingHeadline(choice, accountId: "codex")
        return (header, T.items(config, codex: entry)["codex"])
    }

    @Test func claudeHeaderMatchesTheBarEntry() throws {
        let cases: [(SubscriptionEntry, [Int], HeadlineChoice?, BarLevel, Bool)] = [
            (F.sub(seven: 91), [80, 90], nil, .critical, false),
            (F.sub(seven: 85), [80, 90], nil, .warning, false),
            (F.sub(seven: 79), [80, 90], nil, .normal, false),
            (F.sub(seven: 100), [], nil, .critical, true),
            // The 7-day window at 100% while the 5-hour window is the headline.
            (F.sub(seven: 100, five: 40), [80, 90], .claude(.fiveHour), .critical, true),
            (F.sub(seven: 30, five: 85), [80, 90], .claude(.fiveHour), .warning, false),
        ]
        for (sub, thresholds, choice, level, overLimit) in cases {
            let (header, item) = Self.claude(sub, thresholds, choice)
            let unwrapped = try #require(header)
            #expect(unwrapped.level == level)
            #expect(unwrapped.level == item?.level)
            #expect(item?.overLimit == overLimit)
            #expect(unwrapped.value == item?.value)
            #expect(unwrapped.accessibilityValue == unwrapped.value)
        }
    }

    /// The header keeps the tag and "--" of spec 027 FR-008, and nothing
    /// before the first values or when not signed in.
    @Test func claudeHeaderKeepsTagAndPlaceholders() throws {
        let (tagged, _) = Self.claude(F.sub(seven: 30, five: 58), [80, 90], .claude(.fiveHour))
        #expect(tagged?.tag == "5h")
        #expect(tagged?.value == "58%")
        let headline = HeadlineWindow.claude(accountId: "sub", status: nil, choice: nil, now: F.now)
        #expect(HeadlineWindow.claudeHeader(headline, entry: nil, thresholds: [], direction: .used, now: F.now) == nil)
        #expect(HeadlineWindow.claudeHeader(headline, entry: SubscriptionEntry(status: nil, state: .notSignedIn),
                                            thresholds: [], direction: .used, now: F.now) == nil)
        // An absent chosen window falls back to a full 7-day window (spec 040 FR-010).
        let noFive = SubscriptionEntry(status: SubscriptionStatus(windows: [.sevenDay(100, resetsAt: F.window.end)], fetchedAt: F.now),
                                       state: .ok)
        let (fallback, item) = Self.claude(noFive, [80, 90], .claude(.fiveHour))
        #expect(fallback?.value == "100%")
        #expect(fallback?.tag == nil)
        #expect(fallback?.level == .critical)
        #expect(item?.level == .critical)
        // No plan window: no header value.
        let none = SubscriptionEntry(status: SubscriptionStatus(windows: [.model("Fable", 15, resetsAt: F.window.end)], fetchedAt: F.now),
                                     state: .ok)
        #expect(Self.claude(none, [80, 90], nil).0 == nil)
    }

    @Test func codexHeaderMatchesTheBarEntry() throws {
        let cases: [(CodexLimitsEntry, [Int], HeadlineChoice?, BarLevel, Bool)] = [
            (F.codex(five: 10, weekly: 60), [50, 55], nil, .critical, false),
            (F.codex(five: 10, weekly: 52), [50, 55], nil, .warning, false),
            // Any reached limit, whichever window is the headline.
            (F.codex(five: 90, weekly: 40, fiveReached: true), [80, 90], nil, .critical, true),
            (F.codex(five: 30, weekly: 85), [80, 90], .codexWindow("5-hour"), .normal, false),
        ]
        for (entry, thresholds, choice, level, overLimit) in cases {
            let (header, item) = Self.codex(entry, thresholds, choice)
            let unwrapped = try #require(header)
            #expect(unwrapped.level == level)
            #expect(unwrapped.level == item?.level)
            #expect(item?.overLimit == overLimit)
            #expect(unwrapped.value == item?.value)
        }
        #expect(HeadlineWindow.codexHeader(nil, entry: F.codex(weekly: 40), thresholds: [], direction: .used, now: F.now) == nil)
    }
}

/// spec 040 FR-009 to FR-011: the headline of a Claude window list.
@Suite struct ClaudeHeadlineWindowListTests {
    static let now = ClaudeHeadlineWindowTests.now
    static let hour: TimeInterval = 3600
    static let reset = now.addingTimeInterval(2.5 * hour)
    static let weekReset = now.addingTimeInterval(3 * 24 * hour)

    static func daily(_ percent: Double = 40) -> ClaudeLimit {
        ClaudeLimit(identity: ClaudeWindow(rawValue: "limit:daily_all"), kind: "daily_all", group: "daily", length: nil, name: "daily",
                    modelName: nil, allowancePercentOfWeekly: nil, utilizationPercent: percent, resetsAt: weekReset)
    }

    static let furtherFable = ClaudeLimit(identity: ClaudeWindow(rawValue: "model:Fable:daily_scoped"), kind: "daily_scoped",
                                          group: "daily", length: nil, name: "Fable daily", modelName: "Fable",
                                          allowancePercentOfWeekly: nil, utilizationPercent: 22, resetsAt: weekReset)

    static func status(_ windows: [ClaudeLimit]) -> SubscriptionStatus {
        SubscriptionStatus(windows: windows, fetchedAt: now)
    }

    static func resolve(_ windows: [ClaudeLimit], _ choice: HeadlineChoice?) -> ResolvedHeadline {
        HeadlineWindow.claude(accountId: "acc-max", status: status(windows), choice: choice, now: now)
    }

    /// FR-009: the 7-day window, else the longest with a length, else the
    /// first plan window; none without plan windows.
    @Test func defaultWindow() {
        let seven = Self.resolve([.fiveHour(58, resetsAt: Self.reset), .sevenDay(11, resetsAt: Self.weekReset), Self.daily()], nil)
        #expect(seven.claudeWindow == .sevenDay)
        #expect(seven.isDefault)
        let five = Self.resolve([.fiveHour(58, resetsAt: Self.reset), Self.daily(), .model("Fable", 15, resetsAt: Self.weekReset)], nil)
        #expect(five.claudeWindow == .fiveHour)
        #expect(five.isDefault)
        #expect(five.tag == nil)
        #expect(five.percent == 58)
        #expect(five.rowName == "5-hour")
        let daily = Self.resolve([Self.daily(), .model("Fable", 15, resetsAt: Self.weekReset)], nil)
        #expect(daily.claudeWindow == Self.daily().identity)
        #expect(daily.isDefault)
        #expect(daily.tag == nil)
        #expect(daily.percent == 40)
        let none = Self.resolve([.model("Fable", 15, resetsAt: Self.weekReset)], nil)
        #expect(none.percent == nil)
        #expect(none.tag == nil)
        #expect(none.pace == nil)
        #expect(none.header == nil)
    }

    /// FR-010: a chosen window applies only while present; otherwise the
    /// default does, the choice is only read.
    @Test func chosenWindowAppliesOnlyWhilePresent() {
        let windows: [ClaudeLimit] = [.sevenDay(11, resetsAt: Self.weekReset), .model("Fable", 15, resetsAt: Self.weekReset)]
        for choice in [HeadlineChoice.claude(.fiveHour), .claude(Self.daily().identity), .claude(.model("Opus"))] {
            let headline = Self.resolve(windows, choice)
            #expect(headline.claudeWindow == .sevenDay)
            #expect(headline.isDefault)
            #expect(headline.tag == nil)
            #expect(headline.percent == 11)
        }
        let back = Self.resolve([.fiveHour(58, resetsAt: Self.reset)] + windows, .claude(.fiveHour))
        #expect(back.claudeWindow == .fiveHour)
        #expect(!back.isDefault)
        #expect(back.tag == "5h")
        #expect(back.percent == 58)
        #expect(back.pace != nil)
    }

    /// US2 scenario 4: an unknown-group window as the headline: its name as
    /// the tag, no pace.
    @Test func unknownGroupWindowAsHeadline() {
        let headline = Self.resolve([.sevenDay(11, resetsAt: Self.weekReset), Self.daily()], .claude(Self.daily().identity))
        #expect(headline.tag == "daily")
        #expect(headline.percent == 40)
        #expect(headline.pace == nil)
        #expect(headline.rowName == "daily")
        #expect(headline.accessibilityName == "daily window")
        #expect(headline.burnKey == .claude("acc-max", Self.daily().identity))
    }

    /// FR-011: tags and accessibility names.
    @Test func tagsAndAccessibilityNames() {
        var longName = Self.daily()
        longName.name = "rolling fortnight"
        #expect(HeadlineWindow.tag(claude: longName) == "rolling…")
        #expect(HeadlineWindow.tag(claude: Self.furtherFable) == "Fable d…")
        let further = Self.resolve([.sevenDay(11, resetsAt: Self.weekReset), .model("Fable", 15, resetsAt: Self.weekReset), Self.furtherFable],
                                   .claude(Self.furtherFable.identity))
        #expect(further.accessibilityName == "Fable daily limit")
        #expect(further.rowName == "Fable daily")
        let model = Self.resolve([.sevenDay(11, resetsAt: Self.weekReset), .model("Fable", 15, resetsAt: Self.weekReset)],
                                 .claude(.model("Fable")))
        #expect(model.accessibilityName == "Fable weekly limit")
        let five = Self.resolve([.fiveHour(58, resetsAt: Self.reset), .sevenDay(11, resetsAt: Self.weekReset)], .claude(.fiveHour))
        #expect(five.accessibilityName == "5-hour window")
        // A model's first limit is named as one also when its name has a colon.
        let colon = Self.resolve([.sevenDay(11, resetsAt: Self.weekReset), .model("Opus: Max", 15, resetsAt: Self.weekReset)],
                                 .claude(.model("Opus: Max")))
        #expect(colon.accessibilityName == "Opus: Max weekly limit")
    }

    /// The model limit row's name tooltip (spec 025 FR-019a, spec 040
    /// FR-006): the weekly limit with its allowance for a model's first
    /// limit, "<name> limit" for a further one, nil for a plan window.
    @Test func modelLimitNameHelp() {
        #expect(ClaudeLimit.model("Fable", 15, resetsAt: Self.weekReset, allowance: 50).nameHelp
            == "Fable weekly limit, 50% of the 7-day limit")
        #expect(ClaudeLimit.model("Fable", 15, resetsAt: Self.weekReset).nameHelp == "Fable weekly limit")
        #expect(ClaudeLimit.model("Opus: Max", 15, resetsAt: Self.weekReset).nameHelp == "Opus: Max weekly limit")
        #expect(Self.furtherFable.nameHelp == "Fable daily limit")
        #expect(ClaudeLimit.sevenDay(11, resetsAt: Self.weekReset).nameHelp == nil)
        #expect(ClaudeLimit.model("Fable", 15, resetsAt: Self.weekReset).isPrimaryModelLimit)
        #expect(!Self.furtherFable.isPrimaryModelLimit)
        #expect(!ClaudeLimit.sevenDay(11, resetsAt: Self.weekReset).isPrimaryModelLimit)
    }

    /// What a click stores: nil for the default row, the identity otherwise.
    @Test func choiceForClaudeRows() {
        let noSeven = Self.status([.fiveHour(58, resetsAt: Self.reset), Self.daily()])
        #expect(HeadlineWindow.choice(forClaude: .fiveHour, status: noSeven) == nil)
        #expect(HeadlineWindow.choice(forClaude: Self.daily().identity, status: noSeven) == .claude(Self.daily().identity))
        let full = Self.status([.fiveHour(58, resetsAt: Self.reset), .sevenDay(11, resetsAt: Self.weekReset)])
        #expect(HeadlineWindow.choice(forClaude: .fiveHour, status: full) == .claude(.fiveHour))
        #expect(HeadlineWindow.choice(forClaude: .sevenDay, status: full) == nil)
    }
}
