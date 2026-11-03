# Tasks: Unified Token Accounts

**Input**: Design documents from `specs/043-unified-token-accounts/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/config.md, contracts/ui-strings.md, quickstart.md

**Tests**: Required. Constitution II: logic in UsageCore or DemoMode, test first. Every UsageCore task starts with failing tests in the named test file (a test that does not compile because a type or member is missing counts as failing), then the implementation. Build and test only with `make test`, `make test-release`, `make app`, `make app-demo` (never `swift build`, `swift test` or `xcodebuild` directly).

**Conventions**: Doc comments cite `spec 043 FR-0xx` or research `Rn`; update spec 041 citations whose rule this spec changes. Exact strings from contracts/ui-strings.md and contracts/config.md. No em or en dashes (the typographic minus U+2212 in "−$12" is allowed). Invented examples in tests, demo and docs (`gateway-a/`, `gateway-a/open-model-7b`, `proj-alpha`, `~/.claude-gateway`, `~/.claude-api`); real Claude model ids from `Sources/UsageCore/Resources/prices.json` (for example `claude-opus-5-5`: input 4.00, output 20.00, cache write 5m 5.00, 1h 8.00, cache read 0.20 per MTok) are fine.

**Internal model** (research R1): `TokenMembership.noLimit(NoLimitSettings)` now means "own budget without an amount". It is never a budget owner, so existing exclusions (bar, thresholds, pace, burn rate, `accountBudgets`) keep working. Do not make `BudgetSettings.budgetUSD` optional. `TokenBasedSettings.ownBudget` returns nil for an own budget without an amount: own-budget UI gating (Dropdown shows, FR-018a) uses `groupId == nil`, never `ownBudget != nil`.

## Phase 1: Setup

- [X] T001 Confirm the baseline: run `make test` and `make test-release` in the worktree and record the totals in the Task Log at the end of `specs/043-unified-token-accounts/tasks.md` (no code change)

## Phase 2: Foundational (blocks all stories)

**Purpose**: the configuration reads and writes an own budget without an amount, still reads spec 041's `noLimit` form, stores the new `show` setting, and the core types `DropdownShow` and `OwnBudgetForm` exist. T002 to T005 form one compile unit: `make test` passes at the end of T005.

- [X] T002 [P] Extend `Tests/UsageCoreTests/NoLimitConfigurationTests.swift` (contracts/config.md, research R2, FR-002, FR-003, FR-004, FR-010):
  - a token-based account with `"budget": {"period": "monthly", "shownInBar": false, "thresholds": [50, 90]}` (no `budgetUSD`) decodes to `.noLimit(NoLimitSettings(period: .monthly, thresholds: [50, 90], shownInBar: false))`; the same with `"budgetUSD": null`; missing `thresholds` inside it decode as `[]` and missing `shownInBar` as `true`, as `BudgetSettings` does today (so adding an amount later never changes them; `[80, 100]` stays the default only for new accounts and the legacy `noLimit` form);
  - `budgetUSD` 0 and -5 on an own budget stay invalid with today's message; a group budget without `budgetUSD` or with `null` stays invalid;
  - the spec 041 form `"noLimit": {"period": "monthly"}` decodes to `.noLimit(NoLimitSettings(period: .monthly, thresholds: [80, 100], shownInBar: true))` with its `valueAs`; every spec 041 invalid case (forbidden keys inside `noLimit`, account-level `shownInBar` or `thresholds` with `noLimit`, `noLimit` together with `budget` or `groupId`) stays invalid;
  - encoding `.noLimit` writes `budget` with `period`, `shownInBar`, `thresholds` and without `budgetUSD`, never a `noLimit` key; decode/encode round trips keep period, thresholds, shownInBar, `valueAs`, `timeFormat`; a legacy file round trips into the new form;
  - `show`: absent decodes `.automatic`; `"percent"`, `"tokens"`, `"money"` decode; an unknown value gives one load note and `.automatic`; `.automatic` is not written, the others are; `show` on a group member is kept;
  - a configuration without amount-less accounts and without `show` encodes without a `show` key and every `budget` object keeps its `budgetUSD` (golden JSON literal in this file);
  - `"show": null` decodes `.automatic`; a `show` key on a subscription account is ignored with a load note, like `headlineWindow` on a token-based account;
  - through `needsRefresh(comparedTo:)`: a `show` change does not need a refresh; a change of an amount-less account's `thresholds` or `shownInBar` does not either (masked like `.ownBudget`); adding or removing an amount does
- [X] T003 [P] Write `Tests/UsageCoreTests/DropdownShowTests.swift` and `Tests/UsageCoreTests/OwnBudgetFormTests.swift` (data-model.md, research R3, R7, FR-011, FR-012, FR-018, FR-019):
  - `DropdownShow.resolve(hasAmount:hasPricedUsage:)` gives every row of the table in data-model.md;
  - `DropdownShow` pop-up rules in core: `isEnabled(.percent, hasAmount: false) == false` with the help text of contracts/ui-strings.md; with Percent stored and no amount the selection stays Percent (selected and disabled);
  - `OwnBudgetForm(membership:)` from `.ownBudget(BudgetSettings(period: .monthly, budgetUSD: 300, shownInBar: false, thresholds: [50, 90]))` has `amount == 300`; setting `amount = nil` gives `.noLimit` with period monthly, thresholds `[50, 90]`, shownInBar false; setting it back to 300 gives the original `.ownBudget`; a form from `.noLimit(NoLimitSettings())` has `amount == nil`, weekly, `[80, 100]`, shown in bar; `amount` 0 or less gives `.ownBudget` with that amount, which `validateForSaving()` refuses with today's message; only `nil` gives `.noLimit` (FR-002, FR-019)
- [X] T004 In `Sources/UsageCore/Config/Configuration.swift`: add `thresholds` (default `[80, 100]`) and `shownInBar` (default `true`) to `NoLimitSettings`; add `show: DropdownShow` (default `.automatic`) to `TokenBasedSettings` and the `show` coding key on `Account`; decode a token-based `budget` without `budgetUSD` (absent or `null`) as `.noLimit`, keep group budgets requiring it; keep reading `noLimit` with spec 041's validation and the new defaults; encode `.noLimit` as `budget` without `budgetUSD`; encode `show` only when not Automatic; mask `show` in `dataRelevant`; remove `movingAccountToNoLimit(accountId:)` and adjust `Tests/UsageCoreTests/NoLimitTransitionTests.swift` (the switch to No limit is now "clear the amount", covered by `OwnBudgetForm`); keep `movingAccountToOwnBudget` (group prefill, FR-019) but make its `.noLimit` branch `return self` (it wrote `budgetUSD: 0` and dropped thresholds, against FR-002 and FR-003), with a test in `NoLimitTransitionTests`; keep `movingAccountToGroup`; mask `NoLimitSettings.thresholds` and `shownInBar` in `dataRelevant` as `.ownBudget` masks its own; add an SC-005 path test in `NoLimitTransitionTests` (empty, then amount, then empty; amount, then group, then own budget; empty, then group, then own budget) running `validateForSaving()` and a decode/encode round trip at each step; update doc comments that say "No limit choice" to "own budget without an amount (spec 043)"
- [X] T005 Add `Sources/UsageCore/Config/DropdownShow.swift` and `Sources/UsageCore/Config/OwnBudgetForm.swift`; `make test` passes. Interfaces:
  ```swift
  public enum DropdownShow: String, Codable, CaseIterable, Sendable { case automatic, percent, tokens, money }
  public enum HeadlineMeasure: Equatable, Sendable { case percent, tokens, money }
  extension DropdownShow {
      public func resolve(hasAmount: Bool, hasPricedUsage: Bool) -> HeadlineMeasure
      public static func isEnabled(_ choice: DropdownShow, hasAmount: Bool) -> Bool
      public static func help(_ choice: DropdownShow, hasAmount: Bool) -> String?
  }
  public struct OwnBudgetForm: Equatable, Sendable {
      public var period: BudgetPeriod; public var amount: Decimal?; public var thresholds: [Int]; public var shownInBar: Bool
      public init(_ membership: TokenMembership)   // from .ownBudget or .noLimit
      public var membership: TokenMembership       // .ownBudget when amount != nil, else .noLimit
  }
  ```

## Phase 3: User Story 1 - An account without a limit is an own budget without an amount (Priority: P1) MVP

**Goal**: Settings offers Own budget and groups only; an empty amount means no limit; the amount-less account keeps spec 041's dropdown section and stays out of the menu bar.

**Independent Test**: create an account with an empty amount, save, reopen: the file has `budget` without `budgetUSD`, the section shows the token headline, the menu bar has no entry.

- [X] T006 [P] [US1] Extend `Tests/UsageCoreTests/AggregatorTests.swift` (research R4): an amount-less account's `noLimitAccounts` entry now carries a priced breakdown (per-model `costUSD` for priced models, `priced == false` for unpriced ones), `unpricedUsage` (only records with `!isPriced`, also when one model has both kinds), `spentUSD` (sum of priced records), `hasPricedUsage` and `unpricedModels`; with only unpriced records `spentUSD == 0`, `hasPricedUsage == false`; still no `accountBudgets` entry; `tokenAccounts` entry unchanged; an existing coordinator carry-over test still passes with the new fields
- [X] T007 [P] [US1] Extend `Tests/UsageCoreTests/ArrangementTests.swift` and `Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift` (FR-020, FR-021): `offersShownInBar` stays false for an amount-less row and a new core help text for the disabled checkbox is the string of contracts/ui-strings.md; `budgetCaption` is "No limit"; the Accounts list subtitle of an own budget without an amount reads "<session kind> · no limit / month" with its VoiceOver text, also for the unsaved draft
- [X] T008 [US1] In `Sources/UsageCore/Snapshot/UsageSnapshot.swift` extend `NoLimitEntry`; in `Sources/UsageCore/Snapshot/Aggregator.swift`, for each account without an amount, build a priced breakdown (`breakdown(of:priced: true, ...)`) for the entry and an unpriced per-model breakdown of only its records with `!isPriced` (so Value as values exactly the unpriced records, research R5); compute `spentUSD` and `hasPricedUsage` from the records, not from per-model rows (a model with any unpriced record loses its `costUSD`); `tokenAccounts` keeps its unpriced entry; `make test` passes. Interfaces:
  ```swift
  public struct NoLimitEntry {
      public var breakdown: UsageBreakdown          // priced
      public var unpricedUsage: [ModelUsage]        // per model, records with !isPriced only
      public var spentUSD: Decimal                  // sum of priced records
      public var hasPricedUsage: Bool
      public var unpricedModels: [String] { get }   // from unpricedUsage
  }
  ```
- [X] T009 [US1] In `Sources/AgentTacho/AccountSettingsView.swift`: remove the "No limit" item and `noLimitTag` from the editor's budget picker and the new account sheet (FR-017); add a separate own-budget fields view bound to `OwnBudgetForm` for `.ownBudget` and `.noLimit` alike (tag `ownBudgetTag`), leaving `BudgetFields` unchanged for the group editor (groups always need an amount); Amount field with placeholder `No limit`, saving accepts it empty (FR-019); thresholds and "Show in menu bar" disabled without an amount with the help text of contracts/ui-strings.md (FR-018); Value as pop-up shown always with the caption of contracts/ui-strings.md, disabled with help when an amount is set; the new account sheet keeps its preselection (first group when one exists) and its Own budget choice starts as `.noLimit(NoLimitSettings())` with the sheet's caption; delete `NoLimitFields` once unused
- [X] T010 [US1] In `Sources/AgentTacho/MenuBarSettingsTab.swift` show the "Show in bar" checkbox of an amount-less row disabled and unchecked with the help text from T007 instead of hiding it (FR-020); `make app` builds

## Phase 4: User Story 2 - Pay-as-you-go spend without a cap (Priority: P1)

**Goal**: an amount-less account with priced usage shows real spend as its headline, worded as spend, with cost Details and the usual unpriced note.

**Independent Test**: an amount-less monthly account with priced records costing 37.42 US$ shows "$37", tooltip "$37.42 spent this month", line "spent this month", no "≈".

- [X] T011 [P] [US2] Write `Tests/UsageCoreTests/HeadlineTextTests.swift` (research R6, contracts/ui-strings.md, FR-013, FR-016): Tokens text/tooltip/accessibility ("48.2M", "48,213,507 tokens this month", "48.2 million tokens this month"); Money spent ("$37" for 37.42, "$38" for 37.50 (half up), "$0" for 0, "<$1" for 0.40, tooltip and accessibility "$37.42 spent this month", weekly variant); Money remaining mode with an amount ("$63", "$62.58 left of $100/month"; over: "−$12" with U+2212, "$12.40 over $100/month"; below one dollar "<$1" left and "−<$1" over); Percent delegates to `DirectedPercent` unchanged; spoken token counts for K, M, B, a count below 1,000 and 0; no Money output contains "≈"
- [X] T012 [P] [US2] Extend `Tests/UsageCoreTests/ReferenceValueTests.swift` (research R5, FR-006): only rows with `priced == false` are valued; a breakdown with only priced rows and a Value as model gives `.value(0, model:)`; `.missing` unchanged
- [X] T013 [P] [US2] Extend `Tests/UsageCoreTests/NoLimitPresentationTests.swift` (FR-007, FR-011, FR-013, FR-014, FR-015): Automatic with priced usage gives the Money headline and `periodLine == "spent this month"`; with only unpriced usage the Tokens headline and "this month" exactly as before (spec 041 strings); Money without Value as and with unpriced models adds the "incomplete, unpriced" note naming them; Tokens never adds it; a set Value as model shows the value line also as "≈ $0 at <model> prices"; a missing Value as model shows the missing-model note and, under Money, also the incomplete note; the value tooltip uses the "models without a price" variant when the account also has priced usage; `measure` is `.money` / `.tokens` accordingly and stored Percent without an amount gives the Automatic measure (US3 scenario 6); a stale entry under Money keeps the stale note; `showsCost` (new) is true under Money and false under Tokens; accessibility text per contracts/ui-strings.md
- [X] T014 [US2] Add `Sources/UsageCore/Dropdown/HeadlineText.swift`; change `Sources/UsageCore/Pricing/ReferenceValue.swift` callers to pass `entry.unpricedUsage`; change `Sources/UsageCore/Dropdown/NoLimitPresentation.swift` to take the account's `show`, resolve the measure, use `HeadlineText`, and add `measure` and `showsCost`; `make test` passes. Interfaces:
  ```swift
  public struct HeadlineText: Equatable, Sendable {
      public let text: String; public let tooltip: String?; public let accessibilityText: String
      public static func tokens(_ total: Int, period: BudgetPeriod) -> HeadlineText
      public static func spent(_ amount: Decimal, period: BudgetPeriod) -> HeadlineText
      public static func budget(entry: GroupEntry, show: DropdownShow, direction: DisplayDirection) -> HeadlineText   // T016
  }
  // NoLimitPresentation.make(name:entry:show:value:times:lastSuccessfulRefreshAt:isPreliminary:dates:)
  // NoLimitPresentation.make(account:snapshot:prices:times:dates:) reads settings.show
  // new properties: measure: HeadlineMeasure?, showsCost: Bool
  ```
- [X] T015 [US2] In `Sources/AgentTacho/DropdownView.swift` `NoLimitSection`: render the presentation's headline and tooltip, and pass `showsCost` and the incomplete flag to `BreakdownView` so Money sections show cost per model and the Σ tooltip matches the unpriced note (FR-014); `make app` builds

## Phase 5: User Story 3 - Choose what the dropdown shows (Priority: P2)

**Goal**: the "Dropdown shows" pop-up per account; a budgeted account can show tokens or money as its headline with the rest of the section unchanged.

**Independent Test**: step one budgeted and one amount-less account through Automatic, Percent, Tokens and Money and check each headline.

- [X] T016 [P] [US3] Extend `Tests/UsageCoreTests/HeadlineTextTests.swift` with the budget entry point `HeadlineText.budget(entry:show:direction:)` (T014 interfaces): Automatic and Percent give today's percent text; Tokens gives the entry's token total; Money gives spent (or left/over in remaining mode); group sections always use Percent
- [X] T017 [US3] Implement the budget entry point in `Sources/UsageCore/Dropdown/HeadlineText.swift`; in `Sources/AgentTacho/DropdownView.swift` `BudgetSection` take the header text, tooltip and accessibility label from it (own budgets pass the account's `show`, groups `.automatic`), keeping the percent tone color; `make test` passes and `make app` builds
- [X] T018 [US3] In `Sources/AgentTacho/AccountSettingsView.swift` add the `Dropdown shows` pop-up (Automatic, Percent, Tokens, Money) to the own budget editor, with Percent disabled and the stored-Percent display rule from `DropdownShow` (T005); hidden for group members, the stored value kept (FR-018a); `make app` builds

## Phase 6: User Story 4 - Existing No limit accounts keep working (Priority: P2)

**Goal**: spec 041 files load unchanged and look the same for unpriced accounts.

**Independent Test**: a spec 041 file with an unpriced No limit account valued as `claude-opus-5-5` gives the same section strings before and after, and saves in the new form.

- [X] T019 [US4] Add a test to `Tests/UsageCoreTests/NoLimitPresentationTests.swift` that loads a spec 041 configuration JSON (with `noLimit` and `valueAs`) and an unpriced snapshot, and checks headline, tooltip, period line, value line, value tooltip and reset text equal the spec 041 strings recorded in `specs/041-no-limit-accounts/contracts/ui-strings.md` (SC-003); the accessibility label uses the new spoken form of FR-016 ("48.2 million tokens this month"), not spec 041's; and the account's subtitle is unchanged

## Phase 7: User Story 5 - Adding and removing an amount (Priority: P3)

**Goal**: entering or clearing an amount flips the account cleanly, keeping its settings and threshold rules.

**Independent Test**: toggle one account's amount between empty and 300 and check controls, configuration, menu bar entry and threshold state.

- [X] T020 [US5] Extend `Tests/UsageCoreTests/ThresholdTrackerTests.swift` and `Tests/UsageCoreTests/BarLayoutTests.swift` (FR-008, FR-009): an account whose amount is removed loses its bar segment and threshold state; when an amount is entered again the first refresh records a baseline without notifying for thresholds already exceeded; thresholds `[50, 90]` and shown-in-bar off kept while amount-less apply again (bar entry absent because shown-in-bar off); bar values are identical for `show` `.money` and `.automatic` (FR-010). Expect no production change: the tracker already drops and re-baselines state when the owner set changes

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T021 Demo (plan "Screenshots and website", FR-023): in `Resources/demo/default.json` write `acc-free` as `budget` `{"period": "monthly"}` without `budgetUSD` (keep `valueAs`), add `acc-api` ("API key", icon `solid:key`, `tokenBased`, Claude Code, `sessionKind` `otherProvider`, `claudeCodeDirectory` `~/.claude-api`, monthly budget without amount) arranged right after `acc-free`, and add a few usage entries this month for `acc-api` with a built-in priced Claude model (a few dollars in total); in `Sources/DemoMode/ScenarioCoverage.swift` report each amount-less section's resolved measure; in `Tests/DemoModeTests/DefaultScenarioTests.swift` check `acc-free` Tokens headline with value line, `acc-api` Money headline, neither in the bar (`barValues.count` unchanged), `BarLayout.shotNoLimitAccountId == "acc-free"` in `Tests/UsageCoreTests/ShotTargetTests.swift`, the band list grows by one stripe, `tokenBasedAccountsUseSessionKinds` lists `acc-api`; make sure `DemoSources` moves `acc-api`'s monthly records into the month like `acc-free`'s
- [X] T022 [P] Docs (FR-022): `docs/configuration.md` replace the section "Accounts without a limit" with the optional amount (`budget` without `budgetUSD`), the `show` key, the Value as rule for unpriced models and the migration of `noLimit`; keep the anchor `#accounts-without-a-limit` (linked from `docs/configuration.md` and `docs/accounts-and-budgets.md`) or update both links; update the Menu Bar and Accounts tab lines; `docs/accounts-and-budgets.md` describes two budget choices with an optional amount
- [X] T023 [P] Website copy (plan "Screenshots and website"): in the site checkout `/Users/rhuss/Work/projects/agenttacho.github.io` (clone with `gh repo clone AgentTacho/agenttacho.github.io` if missing), branch `043-unified-token-accounts` from an up to date `main`, edit the budget card in `src/data/features.ts` with one clause that the amount is optional, so an account can track real spend or tokens without a limit; run `npm run check`, `npm run build`, `npm test`; commit, do not push and open no pull request (the submit step does)
- [X] T024 Run `make test` and `make test-release`; check that no changed file contains an em or en dash (`rg '\x{2014}|\x{2013}'` over the files changed against `main`); record totals in the Task Log; the feature commit on main should be `feat(accounts): own budgets with an optional amount and a dropdown headline choice` so the generated release notes name it (FR-022)
- [X] T025 Check `quickstart.md` steps 1 to 6 as far as possible without the maintainer (tests and `make app-demo` build) and record in the Task Log which steps need a look by hand in `/speckit-spex-walkthrough`

## Dependencies & Execution Order

- Phase 2 (T002 to T005) blocks everything.
- US1 (T006 to T010) depends on Phase 2. US2 (T011 to T015) depends on T008. US3 (T016 to T018) depends on T014 (HeadlineText) and T009 (editor). US4 (T019) depends on T014. US5 (T020) depends on Phase 2.
- Polish: T021 needs US2; T022 and T023 any time after Phase 2; T024 and T025 last.

## Parallel Opportunities

- T002 and T003 (different test files).
- US1: T006 and T007 in parallel; T009 and T010 in parallel after T008.
- US2: T011, T012, T013 in parallel; then T014; then T015.
- US5 (T020) alongside US2 after Phase 2.
- T022 and T023 in parallel.

## Implementation Strategy

MVP is Phase 2 plus US1: the budget picker has two choices and an empty amount means no limit, with spec 041's section unchanged. US2 adds real spend for pay-as-you-go accounts, US3 the per-account headline choice, US4 locks the migration, US5 the amount toggling. Polish adds the demo coverage, docs and website copy that constitution V requires before merge.

## Task Log

- T001 baseline: `make test` 2549 tests in 277 suites (UsageCore) and 77 tests in 7 suites (DemoMode) passed; `make test-release` 266 passed, 0 failed.
- T002 to T005: one compile unit; `make test` 2579 + 77 passed. Deviation: `ConfigurationTests.badPeriodOrMissingAmountThrows` asserted that a `budget` without `budgetUSD` throws (spec 003); split into `badPeriodThrows` and `missingAmountIsAnOwnBudgetWithoutAnAmount` (spec 043 FR-002). Extra: an own budget without an amount validates its kept thresholds like a budget's (whole percents above 0), since they apply once an amount is entered. The `show` key on a subscription account gives a load note; `"show": null` is Automatic without a note.
- T006 to T008: `make test` 2582 + 77 passed.
- Checkpoint 1 (after T008): review agent found no correctness issues (findings 0, fixed 0).
- T009, T010: `make app` builds; `make test` 2582 + 77 passed. `NoLimitFields` deleted; `BudgetFields` stays for groups only. Help texts on disabled controls are tooltips (`.help`).
- T011 to T014: `make test` 2609 + 77 passed. `HeadlineText` also has `percent(usedPercent:direction:)` and `money(spent:budget:roundedPercent:period:direction:)`, which `budget(entry:show:direction:)` (T017) uses. `NoLimitPresentation` gained `incomplete` (for the Details' Σ tooltip) besides `measure` and `showsCost`. The accessibility label of a section without an amount now uses the spoken count ("48.2 million tokens this month"); the spec 041 tests were updated accordingly.
- T015: `make app` builds; `make test` 2609 + 77 passed.
- T016, T017: `make test` 2613 + 77 passed; `make app` builds.
- Checkpoint 2 (after T016): review agent found no spec violations; one minor note fixed: the Money tooltip's cents rounded half to even, now half up like `BudgetAmountFormatter.amount` (SC-004), with a test (findings 1, fixed 1). Its second note (in remaining mode the headline rounds half up while the existing amount line rounds half to even, so exactly 50 cents left can read "$63" next to "62") is left as is: FR-013 requires half up for the headline, and the amount line is unchanged spec 030 behavior.
- T018: `make app` builds; `make test` 2620 + 78 passed.
- T019: `make test` 2618 + 77 passed. The spec 041 strings (headline, tooltip, value line, value tooltip, reset text, subtitle) are unchanged; the accessibility label uses the FR-016 spoken form.
- T020: `make test` 2617 + 77 passed; no production change, as expected.
- T021: `make test` 2619 + 78 passed. `acc-api` uses `claude-opus-5-5` records (about $5 this month) in project `~/src/proj-alpha`; `acc-free` is written as `"budget": {"period": "monthly"}` (its kept thresholds therefore load as `[]`, no visible effect). The coverage report gained `NoLimitSectionCoverage.measure`. A ShotTargetTests case covers the new form.
- T022: `docs/configuration.md` section "Accounts without a limit" rewritten (anchor kept), Menu Bar and Accounts tab lines updated; `docs/accounts-and-budgets.md` names two budget choices with an optional amount. The `noLimit` form was never in a release (introduced after v0.9.0), so the docs call it a form of earlier builds.
- T023: site branch `043-unified-token-accounts` from up to date `main` (3352297), commit 8e444e0 `feat(site): budgets with an optional amount` (budget card in `src/data/features.ts`); `npm run check`, `npm run build` and `npm test` (18 passed) pass. Not pushed, no pull request.
- T024: `make test` 2620 tests in 285 suites (UsageCore) and 78 tests in 7 suites (DemoMode) passed; `make test-release` 266 passed, 0 failed; no em or en dash in any file changed against `main`. The squash commit on main should be `feat(accounts): own budgets with an optional amount and a dropdown headline choice` (FR-022); the branch commits are per task.
- T025 quickstart: step 1 passes (`make test`, including the legacy `noLimit` fixture and the demo coverage for `acc-free` Tokens with value line and `acc-api` Money, neither in the bar). Step 2: `make app-demo` builds; the dropdown look (Free models tokens and value line, API key whole-dollar headline with tooltip, "spent this month", cost Details, no menu bar entries) needs a look by hand. Steps 3 to 5 (Settings editor controls and help texts, entering and clearing 300, Dropdown shows on a budgeted account, remaining mode with Money) are covered in core by `OwnBudgetFormTests`, `DropdownShowTests`, `HeadlineTextTests` and `BudgetHeadlineTextTests`, but the SwiftUI controls (disabled states, tooltips, the disabled Percent item) need a look by hand in `/speckit-spex-walkthrough`. Step 6 is covered by `OptionalAmountConfigurationTests.legacyFileRoundTripsIntoTheNewForm` and `LegacyNoLimitSectionTests`; loading the maintainer's own configuration is a by-hand check. Screenshots were not recaptured (needs the maintainer's permission); the plan expects unchanged crops after one capture run.
