import Foundation
import Testing
@testable import UsageCore

/// Spec 018: the budget subtitle of token-based accounts in Settings >
/// Accounts and the amount style shared with Settings > Groups (FR-001 to
/// FR-005, FR-007a, FR-008, SC-002, SC-004).
@Suite struct AccountBudgetDescriptionTests {
    let en = Locale(identifier: "en_US")

    static func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    // MARK: Fixture

    /// Accounts: vertex (group "vertex"), openai (own weekly 50), claude
    /// (subscription), codex (Codex subscription). Groups: "vertex" (monthly
    /// 400, wallet icon) and "team" (weekly 99.50).
    static func config() -> Configuration {
        Configuration(
            accounts: [
                Account(id: "vertex", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "vertex", harness: .claudeCode,
                                                                                                 sessionKind: .claudeCodeVertex))),
                Account(id: "openai", displayName: "OpenAI", kind: .tokenBased(TokenBasedSettings(
                    membership: .ownBudget(BudgetSettings(period: .weekly, budgetUSD: 50)), harness: .codex))),
                Account(id: "claude", displayName: "Claude", kind: .subscription(SubscriptionSettings())),
                Account(id: "codex", displayName: "Codex", kind: .codexSubscription(CodexSubscriptionSettings())),
            ],
            groups: [
                BudgetGroup(id: "vertex", name: "Vertex", icon: "solid:wallet", period: .monthly, budgetUSD: 400),
                BudgetGroup(id: "team", name: "Team", icon: "solid:users", period: .weekly, budgetUSD: decimal("99.50")),
            ])
    }

    func describe(_ id: String, in config: Configuration) throws -> AccountBudgetDescription {
        let account = try #require(config.account(id: id))
        return try #require(AccountBudgetDescription.make(for: account, in: config, locale: en))
    }

    // MARK: Amount formatter (FR-003)

    @Test func wholeAmountsHaveNoDecimals() {
        #expect(BudgetAmountFormatter.amount(400, locale: en) == "$400")
        #expect(BudgetAmountFormatter.text(400, period: .monthly, locale: en) == "$400 / month")
        #expect(BudgetAmountFormatter.text(50, period: .weekly, locale: en) == "$50 / week")
    }

    @Test func fractionalAmountsHaveTwoDecimals() {
        #expect(BudgetAmountFormatter.text(Self.decimal("99.5"), period: .weekly, locale: en) == "$99.50 / week")
        #expect(BudgetAmountFormatter.text(Self.decimal("99.50"), period: .monthly, locale: en) == "$99.50 / month")
    }

    /// Rounded to cents first, then whole amounts drop the decimals.
    @Test func amountsRoundToCentsBeforeChoosingDecimals() {
        #expect(BudgetAmountFormatter.text(Self.decimal("99.995"), period: .monthly, locale: en) == "$100 / month")
        #expect(BudgetAmountFormatter.text(Self.decimal("0.125"), period: .weekly, locale: en) == "$0.13 / week")
    }

    /// Spec 018 edge case: zero or negative amounts are shown as entered.
    @Test func zeroAndNegativeAmountsAreShownAsEntered() {
        #expect(BudgetAmountFormatter.text(0, period: .monthly, locale: en) == "$0 / month")
        #expect(BudgetAmountFormatter.text(-5, period: .monthly, locale: en) == "-$5 / month")
        #expect(BudgetAmountFormatter.text(Self.decimal("-5.5"), period: .weekly, locale: en) == "-$5.50 / week")
        #expect(BudgetAmountFormatter.amount(Self.decimal("-0.125"), locale: en) == "-$0.13")
    }

    /// Whole units, rounded half up and never to even, in the locale's
    /// currency style (spec 041 FR-012).
    @Test func wholeAmountsRoundHalfUp() {
        #expect(BudgetAmountFormatter.wholeAmount(Self.decimal("411.5"), locale: en) == "$412")
        #expect(BudgetAmountFormatter.wholeAmount(Self.decimal("410.5"), locale: en) == "$411")
        #expect(BudgetAmountFormatter.wholeAmount(Self.decimal("1234.49"), locale: en) == "$1,234")
        #expect(BudgetAmountFormatter.wholeAmount(Self.decimal("0.5"), locale: en) == "$1")
        #expect(BudgetAmountFormatter.wholeAmount(0, locale: en) == "$0")
        let de = BudgetAmountFormatter.wholeAmount(Self.decimal("1234.5"), locale: Locale(identifier: "de_DE"))
        #expect(de.hasPrefix("1.235"))
        #expect(!de.contains(","))
    }

    /// A locale passed explicitly decides the currency style; the app always
    /// passes `DisplayLocale.numbers` (english-number-format). The period
    /// wording stays.
    @Test func otherLocalesKeepThePeriodWording() {
        let de = Locale(identifier: "de_DE")
        let fractional = BudgetAmountFormatter.text(Self.decimal("1234.5"), period: .monthly, locale: de)
        #expect(fractional.hasPrefix("1.234,50"))
        #expect(fractional.hasSuffix("$ / month"))
        #expect(fractional != BudgetAmountFormatter.text(Self.decimal("1234.5"), period: .monthly, locale: en))
        let whole = BudgetAmountFormatter.text(400, period: .weekly, locale: de)
        #expect(whole.hasPrefix("400"))
        #expect(!whole.contains(","))
        #expect(whole.hasSuffix("$ / week"))
    }

    // MARK: Description (FR-001, FR-002, FR-006, FR-007a)

    @Test func groupMemberNamesTheGroupWithIconAndAmount() throws {
        let d = try describe("vertex", in: Self.config())
        #expect(d.source == "Vertex")
        #expect(d.budget == .group(iconId: "solid:wallet", name: "Vertex", amount: 400, period: .monthly))
        #expect(d.visiblePrefix == "Vertex · ")
        #expect(d.iconId == "solid:wallet")
        #expect(d.visibleSuffix == "Vertex, $400 / month")
        #expect(d.visibleText == "Vertex · Vertex, $400 / month")
        #expect(d.accessibilityText == "Vertex, group Vertex, $400 per month")
    }

    @Test func ownBudgetSaysOwnBudgetWithAmount() throws {
        let d = try describe("openai", in: Self.config())
        #expect(d.source == "API key")
        #expect(d.budget == .ownBudget(amount: 50, period: .weekly))
        #expect(d.visibleText == "API key · own budget, $50 / week")
        #expect(d.visiblePrefix == d.visibleText)
        #expect(d.visibleSuffix == "")
        #expect(d.iconId == nil)
        #expect(d.accessibilityText == "API key, own budget, $50 per week")
    }

    /// A configuration built with the memberwise init, never validated.
    @Test func missingGroupSaysNoGroupWithoutAmount() throws {
        let config = Configuration(accounts: [
            Account(id: "vertex", displayName: "Vertex", kind: .tokenBased(TokenBasedSettings(groupId: "gone", harness: .claudeCode, sessionKind: .claudeCodeVertex))),
        ])
        let d = try describe("vertex", in: config)
        #expect(d.budget == .missingGroup)
        #expect(d.visibleText == "Vertex · no group")
        #expect(d.visiblePrefix == d.visibleText)
        #expect(d.visibleSuffix == "")
        #expect(d.iconId == nil)
        #expect(d.accessibilityText == "Vertex, no group")
    }

    @Test func subscriptionAccountsHaveNoDescription() throws {
        let config = Self.config()
        let claude = try #require(config.account(id: "claude"))
        let codex = try #require(config.account(id: "codex"))
        #expect(AccountBudgetDescription.make(for: claude, in: config, locale: en) == nil)
        #expect(AccountBudgetDescription.make(for: codex, in: config, locale: en) == nil)
    }

    // MARK: Draft changes (FR-005)

    @Test func movingToOwnBudgetKeepsTheGroupsAmountAndPeriod() throws {
        let draft = Self.config().movingAccountToOwnBudget(accountId: "vertex")
        let d = try describe("vertex", in: draft)
        #expect(d.budget == .ownBudget(amount: 400, period: .monthly))
        #expect(d.visibleText == "Vertex · own budget, $400 / month")
    }

    @Test func movingToAnotherGroupShowsThatGroup() throws {
        let draft = Self.config().movingAccountToGroup(accountId: "openai", groupId: "team")
        let d = try describe("openai", in: draft)
        #expect(d.budget == .group(iconId: "solid:users", name: "Team", amount: Self.decimal("99.5"), period: .weekly))
        #expect(d.visibleText == "API key · Team, $99.50 / week")
    }

    @Test func removingTheGroupToOwnBudgetsShowsOwnBudget() throws {
        let draft = Self.config().removingGroup(id: "vertex", destination: .ownBudgets)
        #expect(try describe("vertex", in: draft).visibleText == "Vertex · own budget, $400 / month")
    }

    @Test func removingTheGroupIntoAnotherShowsTheOther() throws {
        let draft = Self.config().removingGroup(id: "vertex", destination: .group(id: "team"))
        #expect(try describe("vertex", in: draft).visibleText == "Vertex · Team, $99.50 / week")
    }

    @Test func groupEditsShowAtOnce() throws {
        var draft = Self.config()
        draft.groups[0].name = "Cloud"
        #expect(try describe("vertex", in: draft).visibleSuffix == "Cloud, $400 / month")
        draft.groups[0].icon = "solid:cloud"
        #expect(try describe("vertex", in: draft).iconId == "solid:cloud")
        draft.groups[0].period = .weekly
        #expect(try describe("vertex", in: draft).visibleSuffix == "Cloud, $400 / week")
        draft.groups[0].budgetUSD = Self.decimal("99.5")
        let d = try describe("vertex", in: draft)
        #expect(d.visibleText == "Vertex · Cloud, $99.50 / week")
        #expect(d.accessibilityText == "Vertex, group Cloud, $99.50 per week")
    }

    @Test func ownBudgetEditsShowAtOnce() throws {
        var draft = Self.config()
        let index = try #require(draft.accounts.firstIndex { $0.id == "openai" })
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(
            membership: .ownBudget(BudgetSettings(period: .weekly, budgetUSD: 75)), harness: .codex))
        #expect(try describe("openai", in: draft).visibleText == "API key · own budget, $75 / week")
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(
            membership: .ownBudget(BudgetSettings(period: .monthly, budgetUSD: 75)), harness: .codex))
        #expect(try describe("openai", in: draft).visibleText == "API key · own budget, $75 / month")
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(
            membership: .ownBudget(BudgetSettings(period: .monthly, budgetUSD: Self.decimal("99.50"))), harness: .codex))
        let d = try describe("openai", in: draft)
        #expect(d.visibleText == "API key · own budget, $99.50 / month")
        #expect(d.accessibilityText == "API key, own budget, $99.50 per month")
    }

    /// The subtitle names the kind; the condition is not shown (spec 038
    /// FR-012).
    @Test func subtitleNamesTheKind() throws {
        var draft = Self.config()
        let index = try #require(draft.accounts.firstIndex { $0.id == "vertex" })
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(groupId: "vertex", harness: .claudeCode, sessionKind: .claudeCodeOtherProvider,
                                                                    condition: MatchCondition(field: .model, operator: .startsWith, text: "intranet/")))
        #expect(try describe("vertex", in: draft).source == "Other provider")
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(groupId: "vertex", harness: .claudeCode))
        #expect(try describe("vertex", in: draft).source == "Directory only")
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(groupId: "vertex", harness: .openCode, sessionKind: .openCodeOpenAI))
        #expect(try describe("vertex", in: draft).source == "OpenAI")
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(groupId: "vertex", harness: .openCode, sessionKind: .openCodeOtherProvider))
        #expect(try describe("vertex", in: draft).source == "Other provider")
    }

    @Test func harnessChangeShowsAtOnce() throws {
        var draft = Self.config()
        let index = try #require(draft.accounts.firstIndex { $0.id == "vertex" })
        draft.accounts[index].kind = .tokenBased(TokenBasedSettings(groupId: "vertex", harness: .codex))
        let d = try describe("vertex", in: draft)
        #expect(d.source == "API key")
        #expect(d.visibleText == "API key · Vertex, $400 / month")
    }

    // MARK: Groups list (FR-004, SC-004)

    @Test func groupListSubtitleUsesTheAmountStyle() throws {
        let config = Self.config()
        let vertex = try #require(config.group(id: "vertex"))
        let team = try #require(config.group(id: "team"))
        #expect(GroupListSubtitle.text(group: vertex, memberCount: 2, locale: en) == "$400 / month, 2 member(s)")
        #expect(GroupListSubtitle.text(group: team, memberCount: 0, locale: en) == "$99.50 / week, 0 member(s)")
    }

    @Test func bothListsShowTheSameAmountText() throws {
        let config = Self.config()
        let vertex = try #require(config.group(id: "vertex"))
        let amount = BudgetAmountFormatter.text(vertex.budgetUSD, period: vertex.period, locale: en)
        #expect(GroupListSubtitle.text(group: vertex, memberCount: 1, locale: en).contains(amount))
        #expect(try describe("vertex", in: config).visibleText.contains(amount))
    }
}

/// Spec 041 FR-020: the Accounts list subtitle of a No limit account.
@Suite struct NoLimitBudgetDescriptionTests {
    let en = Locale(identifier: "en_US")

    static func config(period: BudgetPeriod) -> Configuration {
        Configuration(accounts: [Account(id: "free", displayName: "Free", kind: .tokenBased(TokenBasedSettings(
            membership: .noLimit(NoLimitSettings(period: period)), sessionKind: .claudeCodeOtherProvider)))])
    }

    func describe(_ config: Configuration) throws -> AccountBudgetDescription {
        let account = try #require(config.account(id: "free"))
        return try #require(AccountBudgetDescription.make(for: account, in: config, locale: en))
    }

    @Test func weeklyAndMonthly() throws {
        let weekly = try describe(Self.config(period: .weekly))
        #expect(weekly.visibleText == "Other provider · no limit / week")
        #expect(weekly.accessibilityText == "Other provider, no limit, per week")
        let monthly = try describe(Self.config(period: .monthly))
        #expect(monthly.budget == .noLimit(period: .monthly))
        #expect(monthly.visibleText == "Other provider · no limit / month")
        #expect(monthly.visiblePrefix == monthly.visibleText)
        #expect(monthly.visibleSuffix.isEmpty)
        #expect(monthly.iconId == nil)
        #expect(monthly.accessibilityText == "Other provider, no limit, per month")
    }

    /// The subtitle follows the unsaved draft (spec 018 FR-005).
    @Test func draftPeriodChangeShows() throws {
        var draft = Self.config(period: .weekly)
        var settings = try #require(draft.accounts[0].kind.tokenBased)
        settings.membership = .noLimit(NoLimitSettings(period: .monthly))
        draft.accounts[0].kind = .tokenBased(settings)
        #expect(try describe(draft).visibleText == "Other provider · no limit / month")
    }
}
