# Tasks: Account Budget Subtitle

**Input**: Design documents from `specs/018-account-budget-subtitle/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Required. AGENTS.md asks for test-first development of all `UsageCore` logic; test tasks come before their implementation and must fail first. Run tests only with `make test`, build only with `make app`.

## Format: `[ID] [P?] [Story] Description`

## Conventions for every task

- Doc comments cite the spec requirements they implement (for example `spec 018 FR-003`).
- No em dash or en dash characters anywhere (code, comments, docs, commit messages).
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.

## Interfaces (used by every task; names are binding)

```swift
// Sources/UsageCore/Config/AccountBudgetDescription.swift
public enum BudgetAmountFormatter {
    /// Rounded to cents with NSDecimalRound(.plain); no decimals when whole, exactly two otherwise.
    public static func amount(_ value: Decimal, locale: Locale = .current) -> String      // "$400", "$99.50"
    /// amount + " / month" or " / week" (spec 018 FR-003).
    public static func text(_ value: Decimal, period: BudgetPeriod, locale: Locale = .current) -> String
}

public struct AccountBudgetDescription: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case group(iconId: String, name: String, amount: Decimal, period: BudgetPeriod)
        case ownBudget(amount: Decimal, period: BudgetPeriod)
        case missingGroup
    }
    public let provider: String
    public let budget: Kind
    public let visiblePrefix: String      // "Vertex · " for a group; the full text otherwise
    public let iconId: String?            // group icon; nil for own budget and missing group
    public let visibleSuffix: String      // "Vertex, $400 / month" for a group; "" otherwise
    public let visibleText: String        // full text without the icon: "Vertex · Vertex, $400 / month", "OpenAI · own budget, $50 / week", "Vertex · no group"
    public let accessibilityText: String  // "Vertex, group Vertex, $400 per month" (uses BudgetPeriod.perUnit)
    /// nil for subscription and Codex subscription accounts (spec 018 FR-006).
    public static func make(for account: Account, in configuration: Configuration, locale: Locale = .current) -> AccountBudgetDescription?
}

public enum GroupListSubtitle {
    /// "$400 / month, 2 member(s)" (spec 018 FR-004).
    public static func text(group: BudgetGroup, memberCount: Int, locale: Locale = .current) -> String
}
```

---

## Phase 1: Foundational (formatter and description, US1 and US2)

- [X] T001 [P] First run `make test` once to confirm the baseline passes. Then create `Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift` with failing tests, all with `Locale(identifier: "en_US")` unless stated:
  - `BudgetAmountFormatter`: `amount(400)` is "$400"; `text(400, .monthly)` is "$400 / month"; `text(50, .weekly)` is "$50 / week"; `text(99.5, .weekly)` is "$99.50 / week"; `text(99.995, .monthly)` is "$100 / month"; `text(0.125, .weekly)` is "$0.13 / week" (plain rounding); `text(0, .monthly)` is "$0 / month"; `text(-5, .monthly)` is "-$5 / month"; with `Locale(identifier: "de_DE")`, `text(400, .monthly)` has suffix " / month" and contains "400" and "$" (no exact string: ICU spacing varies);
  - `AccountBudgetDescription.make`: a Vertex account in monthly group "Vertex" (icon `solid:wallet`, 400) gives `provider == "Vertex"`, `budget == .group(iconId: "solid:wallet", name: "Vertex", amount: 400, period: .monthly)`, `visiblePrefix == "Vertex · "`, `iconId == "solid:wallet"`, `visibleSuffix == "Vertex, $400 / month"`, `visibleText == "Vertex · Vertex, $400 / month"`, `accessibilityText == "Vertex, group Vertex, $400 per month"`; an OpenAI account with its own weekly budget of 50 gives `visibleText == "OpenAI · own budget, $50 / week"`, `iconId == nil`, `accessibilityText == "OpenAI, own budget, $50 per week"`; a token-based account whose group id names no group (a `Configuration` built with the memberwise init, not validated) gives `visibleText == "Vertex · no group"` and `accessibilityText == "Vertex, no group"`; subscription and Codex subscription accounts give nil;
  - draft changes (spec FR-005), rebuilding after each: `movingAccountToOwnBudget` (own budget with the group's amount and period), `movingAccountToGroup` to another group, `removingGroup(id:destination: .ownBudgets)` and `removingGroup(id:destination: .group(id: other))`, a group rename, a group icon change, a group period change and a group amount change, an own budget amount change and an own budget period change, and a provider change: each yields the new values;
  - Groups list: `GroupListSubtitle.text(group:memberCount:locale:)` is "$400 / month, 2 member(s)" for a monthly group of 400 with 2 members and "$99.50 / week, 0 member(s)" for a weekly group of 99.5 with 0 members; for the same budget it contains exactly `BudgetAmountFormatter.text` of the account subtitle (SC-004).
- [X] T002 Implement `Sources/UsageCore/Config/AccountBudgetDescription.swift` exactly per the Interfaces block, with doc comments citing spec 018 FR-001 to FR-004, FR-007a and FR-008. Run `make test`.

**Checkpoint**: `make test` passes; commit `feat(settings): describe account budgets and format budget amounts`.

---

## Phase 2: User Story 1 - See where an account's spend counts (Priority: P1)

**Independent Test**: quickstart manual checks 1, 2, 4 and 5.

- [X] T003 [US1] In `Sources/AgentTacho/AccountSettingsView.swift`, replace `subtitle(_:)` (its only caller is the list row) with a subtitle view: subscription accounts keep their `SubscriptionPlatform` subtitle; for a token-based account, `AccountBudgetDescription.make(for: account, in: draft)` gives either `Text(visiblePrefix) + labelText(iconId, size: NSFont.preferredFont(forTextStyle: .caption1).pointSize) + Text(" " + visibleSuffix)` when `iconId` is set, or `Text(visibleText)`; keep `.font(.caption)` and `.foregroundStyle(.secondary)`; add `.lineLimit(1)`, `.truncationMode(.tail)` and `.accessibilityLabel(accessibilityText)` (spec 018 FR-001, FR-005, FR-005a, FR-006, FR-007, FR-007a). Run `make test` and `make app`.

**Checkpoint**: commit `feat(settings): show where each account's budget counts`.

---

## Phase 3: User Story 2 - One amount style in Settings (Priority: P2)

**Independent Test**: quickstart manual check 3.

- [X] T004 [US2] In `Sources/AgentTacho/AccountSettingsView.swift` `GroupSettingsView`, replace the row subtitle `"\(UsageFormat.usd(group.budgetUSD)) \(group.period.perUnit), \(…) member(s)"` with `GroupListSubtitle.text(group: group, memberCount: draft.members(of: group.id).count)` (spec 018 FR-004). Run `make test` and `make app`.

**Checkpoint**: commit `feat(settings): use the budget amount style in the Groups list`.

---

## Phase 4: Polish

- [X] T005 Scan the changed files for em and en dash characters (U+2014, U+2013) and for leftover callers of the removed `subtitle(_:)`; run `make test` and `make app` a final time.

## Dependencies & Execution Order

T001 before T002, then T003 and T004 (same file, in order), then T005.
