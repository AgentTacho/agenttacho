# Tasks: Icon Labels and Standalone Budgets

**Input**: Design documents from `/specs/004-icon-labels-standalone-budgets/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/config-file.md, quickstart.md

**Tests**: Included. Every `UsageCore` type has Swift Testing suites (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task before its implementation, and confirm it fails when the package compiles.

**Organization**: Phase 2 holds the model changes that every story depends on: the label removal, the required icon, and the membership type. After that, phases follow the user stories in this order:

- US1 (icons, P1)
- US4 (legacy configs, P1)
- US2 (own budgets, P1)
- US3 (members in the bar, P2)

US4 comes before US2 because its decoding tests guard the model change early.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: The task can run in parallel. It touches different files from the other tasks running at the same time and has no dependency on incomplete tasks.
- **[Story]**: The user story the task belongs to (US1 to US4).

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Remove text labels, make icons required, and introduce `BudgetSettings` and `TokenMembership` with behaviour equivalent to today: every existing account is a group member. The package must compile and pass at the end of this phase.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 In `Sources/UsageCore/Config/Configuration.swift`, add `public enum IconDefaults` with these members (research R1, data-model IconDefaults):
  - `static let subscription = "brands:claude"`
  - `static let vertex = "brands:google"`
  - `static let group = "solid:wallet"`
  - `static func defaultIcon(for kind: AccountKind) -> String`, which returns `subscription` for subscriptions and `vertex` for the Vertex provider
- [X] T003 In `Sources/UsageCore/Config/Configuration.swift`, add `public struct BudgetSettings: Codable, Equatable, Sendable { period: BudgetPeriod; budgetUSD: Decimal; shownInBar: Bool; thresholds: [Int] }` (research R3, data-model BudgetSettings):
  - Memberwise init with defaults `period: .weekly`, `shownInBar: true`, `thresholds: []`.
  - A custom `init(from:)`: absent `period` means weekly; `null` or an unknown value throws. Absent `budgetUSD` throws (use `decodeDecimal`). `shownInBar` defaults to true and `thresholds` to `[]`.
  - An explicit `encode(to:)`.
- [X] T004 In `Sources/UsageCore/Config/Configuration.swift`, add `public enum TokenMembership: Equatable, Sendable { case group(id: String, shownInBar: Bool); case ownBudget(BudgetSettings) }`. Change `TokenBasedSettings` to `membership: TokenMembership` plus `provider`, and drop its `Codable` conformance (`Account` encodes and decodes it by hand, and `TokenMembership` is not `Codable`). Add computed, get-only accessors (research R3):
  - `groupId: String?`
  - `ownBudget: BudgetSettings?`
  - `memberShownInBar: Bool`

  Keep a convenience `init(groupId: String, provider: Provider = .vertex)` that creates `.group(id:shownInBar: false)`.
- [X] T005 In `Sources/UsageCore/Config/Configuration.swift`, change `Account` (FR-001, FR-002, FR-006 to FR-008, R2, R3):
  - Remove `label`. Make `icon: String`. The memberwise init takes `icon: String? = nil` and falls back to `IconDefaults.defaultIcon(for: kind)`.
  - In `init(from:)`, ignore `label`. Treat an absent, `null`, or empty `icon` as the type default.
  - For `tokenBased`, decode `groupId` (optional), `budget` (optional `BudgetSettings`), and account-level `shownInBar` (default false for members). Throw a `DecodingError` when both `groupId` and `budget` are present, or neither.
  - In `encode(to:)`, never write `label` and always write `icon`. For members, write `groupId` and `shownInBar`. For own budgets, write `budget`.
- [X] T006 In `Sources/UsageCore/Config/Configuration.swift`, change `BudgetGroup` (FR-001, FR-002, FR-006, FR-007, R2, R3):
  - Remove `label`. Make `icon: String`, defaulting to `IconDefaults.group` when absent, `null`, or empty. Ignore `label` on decode and never encode it.
  - Add a computed `public var budget: BudgetSettings { get set }` over `period`, `budgetUSD`, `shownInBar`, and `thresholds`.
  - Update the memberwise init: `icon: String = IconDefaults.group`, with no `label`.
- [X] T007 In `Sources/UsageCore/Config/Configuration.swift`, remove `LabelContent`, the `shownLabel` extensions, and `Configuration.maxLabelLength`. In `validate()` (FR-003, FR-005, FR-009):
  - Remove the label length and uniqueness checks (`checkLabel`, `seenLabels`, and the `.duplicateLabel`/`.invalidLabel` usages; keep or rename the enum cases as needed).
  - Check that each account and group icon exists in `IconCatalog.shared`, throwing `.invalidLabel` with the message `Icon "<icon>" of <owner> is not a known Font Awesome icon (expected style:name, for example brands:claude).`
  - Check `groupId` references only for members.
  - Validate own budgets with the same budget and threshold checks and messages as groups, using `"\(budget.period.budgetLabel) of account \"\(displayName)\" must be greater than 0."`.
- [X] T008 In `Sources/UsageCore/Config/Configuration.swift`, update `members(of:)` to use `kind.tokenBased?.groupId`. Update `removingAccount(id:)` the same way. In `dataRelevant()`, stop touching `label`; blank `icon` (set to `""`), member `shownInBar`, and own-budget `shownInBar` and `thresholds` (research R8).
- [X] T009 Update `Sources/UsageCore/Config/ConfigStore.swift`: the default subscription account uses `icon: IconDefaults.subscription` and no label (research R9).
- [X] T010 Make the package compile again with behaviour unchanged:
  - **Labels**: replace every `shownLabel`/`LabelContent`/`label` use in `Sources/AgentMeter/` (`BarLabel.swift`, `IconFont.swift`, `DropdownView.swift`, `AccountSettingsView.swift`, `SettingsView.swift`, `NotificationPresenter.swift`, `App.swift`) and in `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` (log line: use `group.name`). Use an icon reference resolved via `IconCatalog.shared.icon(for:)` for glyphs, and the entity's name for plain text (FR-004).
  - **Icon rendering**: change `IconFont.attributed` and the dropdown `labelText`/`pickerText` helpers to take an icon reference string.
  - **Temporary editor**: replace the `LabelEditor` text field with an icon-only control for now. T014 finalizes it as `IconField`.
  - **Optional `groupId`**: fix the call sites broken by `groupId` becoming `String?`. In `Sources/UsageCore/Snapshot/Aggregator.swift` (the token-account period lookup), use `$0.groupId.flatMap { configuration.group(id: $0) }`. In `Sources/AgentMeter/AccountSettingsView.swift` (`TokenBasedEditor`'s `Picker(selection: $settings.groupId)`), bind through a `Binding<String>` whose getter reads `settings.groupId ?? ""` and whose setter writes `settings.membership = .group(id: newValue, shownInBar: settings.memberShownInBar)`.
  - **Tests**: update every test that constructs `Account(label:...)` or `BudgetGroup(... label: ...)` in `Tests/UsageCoreTests/` to the new initializers.
- [X] T011 Run `make test` and `make build`; all suites pass

**Checkpoint**: Icons are required and labels are gone. Every token-based account is still a group member, and behaviour is otherwise unchanged.

---

## Phase 3: User Story 1 - Icon-only labels with defaults (Priority: P1) 🎯 MVP

**Goal**: The user sees exactly one icon per entry everywhere, new entries get type defaults, and duplicates are allowed.

**Independent Test**: Create two accounts and a group with the same icon, then save. Confirm the configuration validates, settings show no text field, and the icon cannot be removed.

### Tests for User Story 1

- [X] T012 [P] [US1] Add tests in `Tests/UsageCoreTests/ConfigurationTests.swift` (FR-002, FR-003, FR-005):
  - `IconDefaults.defaultIcon(for:)` returns the Claude icon for subscriptions and the Google icon for Vertex accounts. A default `BudgetGroup` gets `solid:wallet`.
  - Two accounts and a group sharing `brands:claude` pass `validate()`.
  - An unknown icon fails `validate()` with the icon message.
  - All three defaults exist in `IconCatalog.shared`.
- [X] T013 [P] [US1] Add tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for encoding (FR-007): an encoded configuration contains no `"label"` key anywhere, and every account and group has an `"icon"` string.

### Implementation for User Story 1

- [X] T014 [US1] In `Sources/AgentMeter/SettingsView.swift`, replace `LabelEditor` with `IconField(icon: Binding<String>, title: String = "Icon")` (FR-001, FR-002, FR-004, R7):
  - It shows the glyph, the icon's catalog label, and a "Choose…" button.
  - It has no remove button and no text field.
  - Its caption reads "Shown in the menu bar and the dropdown. Several entries may share an icon."
  - `IconPickerSheet` is bound through a `Binding<String?>` adapter that ignores `nil`, so the icon can never be cleared.
- [X] T015 [US1] In `Sources/AgentMeter/AccountSettingsView.swift`, use `IconField` in the account editor, the group editor, and the new-account sheet (FR-002, FR-004):
  - The new-account sheet preselects `IconDefaults.defaultIcon(for:)` for the chosen type and updates it when the type changes, unless the user already picked an icon.
  - A new group in the sheet starts with `IconDefaults.group`.
  - Account and group list rows show the icon glyph followed by the name.
  - The alignment picker in `SettingsView.swift` shows the icon plus the name.
- [X] T016 [US1] In `Sources/AgentMeter/NotificationPresenter.swift` and `Sources/AgentMeter/App.swift`, make sure notification titles, bodies, and log lines use entity names (FR-004). In `Sources/AgentMeter/BarLabel.swift`, base the accessibility text on names, not icon labels (FR-004).
- [X] T017 [US1] Run `make test` and `make build`

**Checkpoint**: Icon-only labelling is complete (US1 deliverable).

---

## Phase 4: User Story 4 - Existing configurations keep working (Priority: P1)

**Goal**: Previous-version files load with defaults applied and are rewritten only on save.

**Independent Test**: Load a previous-version file that has text labels, entries without icons, and entries with icons. Every entry ends up with an icon, all budgets are unchanged, and the file is untouched until it is saved.

### Tests for User Story 4

- [X] T018 [P] [US4] Add tests in `Tests/UsageCoreTests/ConfigurationTests.swift` (FR-006, contracts/config-file.md rows 1 and 2):
  - A previous-version JSON with `"label": "M"` and no `icon` on a subscription, a Vertex account, and a group decodes to `brands:claude`, `brands:google`, and `solid:wallet`.
  - `"icon": null` and `"icon": ""` also fall back to the default.
  - An account with both `label` and `icon` keeps its icon.
  - The groups' period, amount, thresholds, and shown-in-bar settings are unchanged.
- [X] T019 [P] [US4] Add tests in `Tests/UsageCoreTests/ConfigStoreTests.swift` (FR-007, spec US4 scenario 3):
  - Loading a legacy file with labels leaves its bytes unchanged.
  - Saving then reloading gives equal accounts and groups, and the saved file has no `label`.
- [X] T020 [US4] Fix any failure from T018 or T019 in `Sources/UsageCore/Config/Configuration.swift` or `Sources/UsageCore/Config/ConfigStore.swift`, then run `make test`

**Checkpoint**: Upgrade safety is proven by tests.

---

## Phase 5: User Story 2 - Token-based account with its own budget (Priority: P1)

**Goal**: A token-based account can hold its own budget and behaves like a one-member group in the dropdown, the bar, and notifications. Settings can move accounts between an own budget and a group.

**Independent Test**: Configure an account with its own $100 monthly budget. Confirm the snapshot entry, a 25% value in the bar, a 50% notification naming the account, and moves in both directions.

### Tests for User Story 2

- [X] T021 [P] [US2] Add decoding and validation tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for every token-based row of `specs/004-icon-labels-standalone-budgets/contracts/config-file.md` (FR-008, FR-009):
  - `groupId` only gives a member with `shownInBar == false`.
  - `budget` only gives an own budget.
  - Both, or neither, throws.
  - `budget.period` absent means weekly.
  - `budget.period` set to `null` or `"yearly"` throws.
  - `budget.budgetUSD` absent throws.
  - `budgetUSD: 0` fails `validate()` with "Weekly budget of account "<name>" must be greater than 0.".
  - A threshold of 0 in an own budget fails `validate()` with the existing threshold message, naming the account.
  - An own budget round-trips through encode and decode.
- [X] T022 [P] [US2] Add tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for `budgetOwners` and the move helpers (FR-014, R4, R7):
  - `budgetOwners` lists groups first, then standalone accounts in accounts-list order.
  - `movingAccountToOwnBudget(accountId:)` prefills period, amount, thresholds, and shown-in-bar from the former group. It deletes the group when it empties and keeps it when other members remain.
  - `movingAccountToGroup(accountId:groupId:)` discards the own budget, sets `memberShownInBar = false`, and deletes an emptied former group.
  - `dataRelevant` treats own-budget `shownInBar` and `thresholds` as presentation-only, and `period` and `budgetUSD` as data-relevant (`needsRefresh`). None of these edits needs a network refresh.
- [X] T023 [P] [US2] Add tests in `Tests/UsageCoreTests/AggregatorTests.swift` (FR-010, R4):
  - A standalone account with a monthly $100 budget and $25 spent this month gets `snapshot.accountBudgets[accountId]` with spent 25, percent 25, `period == .monthly`, the month window, and a breakdown with a per-day trend.
  - Its `tokenAccounts` breakdown uses the same window.
  - It appears in no group.
  - Member spend (FR-018a, SC-004): two members with $90 and $60 in a $300 group give `memberPercent` 30 and 20, the group percent is 50, and the `memberSpendUSD` values sum to `spentUSD`.
- [X] T024 [P] [US2] Add tests in `Tests/UsageCoreTests/ThresholdTrackerTests.swift` (FR-012, FR-015, SC-005):
  - An own budget crossing 50% yields one crossing whose `entityName` is the account's `displayName` and whose `windowKind` matches the period.
  - Moving an account from its own budget into a group drops the account's state.
  - The group's next observation after the member set changes is a baseline: no crossing even if the percent jumped above a threshold.
  - The reverse move behaves the same way.
- [X] T025 [P] [US2] Create `Tests/UsageCoreTests/BarLayoutTests.swift` with tests for `BarLayout.segments(snapshot:configuration:)`, before member support (FR-004, FR-011, FR-020):
  - **Order**: subscriptions and standalone accounts shown in bar, in accounts-list order, then shown groups in groups-list order.
  - **Standalone values**: an own budget shows its percent and level from its warning threshold (warning at the lowest threshold, critical at 100% or more). It shows "…" when `snapshot` is `nil` or has no entry, and is stale when its entry is stale.
  - **Unchanged rules** (spec 001): subscription values and levels behave as before, including "--" for not signed in.
  - **Names**: each item carries the entity's name.
- [X] T026 [P] [US2] Add a test in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`: when the record source fails, the previous `accountBudgets` entries are carried over and marked stale (spec 001 FR-007, needed by the tracker's stale skip).

### Implementation for User Story 2

- [X] T027 [US2] In `Sources/UsageCore/Config/Configuration.swift`, add `public struct BudgetOwner: Equatable, Sendable { id, name, icon, budget: BudgetSettings, memberIds: [String], kind: Kind }` with `enum Kind { case group, account }`. Also add (data-model BudgetOwner, R4, R7):
  - `public var budgetOwners: [BudgetOwner]`
  - `public func budgetOwner(forAccount id: String) -> BudgetOwner?`
  - `public func movingAccountToOwnBudget(accountId: String) -> Configuration`
  - `public func movingAccountToGroup(accountId: String, groupId: String) -> Configuration`

  Deleting an emptied group goes through the same logic as `removingAccount`.
- [X] T028 [US2] In `Sources/UsageCore/Snapshot/UsageSnapshot.swift`, add `public var accountBudgets: [String: GroupEntry]` to `UsageSnapshot` (init parameter with default `[:]`). Add `memberSpendUSD: [String: Decimal]` (default `[:]`) and `public func memberPercent(_ accountId: String) -> Int` to `GroupEntry` (R4).
- [X] T029 [US2] In `Sources/UsageCore/Snapshot/Aggregator.swift`, iterate `configuration.budgetOwners` instead of `configuration.groups` (FR-010, FR-017, R4):
  - Compute each owner's window from `owner.budget.period`.
  - Fill `memberSpendUSD` from the same window-filtered records.
  - Store group owners in `groups` and account owners in `accountBudgets`.
  - Give each token-based account's breakdown the window of `budgetOwner(forAccount:)`.
- [X] T030 [US2] In `Sources/UsageCore/Windows/WindowResolver.swift`, make the collection window include the month whenever any `budgetOwners` element has a monthly period, not only groups. In `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`, include `accountBudgets` in the stale carry-over and the per-owner refresh log line, using owner names. Add a coordinator test in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` showing that a monthly own budget with only weekly groups widens the collection window.
- [X] T031 [US2] In `Sources/UsageCore/Notifications/ThresholdTracker.swift` (FR-012, FR-015, R5):
  - Iterate `configuration.budgetOwners` with key `(owner.id, owner.budget.period.windowKind)`.
  - Read the entry from `snapshot.groups` or `snapshot.accountBudgets` by owner kind.
  - Store `memberIds` in the state and reset to a baseline when it changes.
  - Use `owner.name` as `entityName`.
  - Keep the existing skip for stale entries and for entries whose period differs from the configuration.
- [X] T032 [US2] In `Sources/AgentMeter/DropdownView.swift`, list standalone accounts after the groups, in accounts-list order (FR-010, FR-004):
  - Reuse the group section layout through a shared view: icon plus name, "$X of $Y per <period> (P%)", reset, breakdown, and incomplete note.
  - The entry is read from `snapshot.accountBudgets`.
- [X] T033 [US2] In `Sources/AgentMeter/AccountSettingsView.swift` and `Sources/AgentMeter/SettingsView.swift`, change the token-based account editor (FR-009, FR-013, FR-014, FR-010 wording, R7):
  - **Budget picker**: "Own budget" first, then every group by icon and name.
  - **Own budget**: shows a `BudgetFields` view extracted from the group editor (period picker, amount with the period label and the "must be greater than 0" error naming the period, shown-in-bar toggle, `ThresholdsEditor`).
  - **Switching**: apply `movingAccountToOwnBudget` or `movingAccountToGroup` to the draft configuration.
  - **New-account sheet**: offer "Existing group", "New group", and "Own budget". A new own budget defaults to weekly, $60, shown in bar, thresholds `[80, 100]`.
- [X] T034 [US2] Create `Sources/UsageCore/Bar/BarLayout.swift` (R6, FR-011, FR-020):
  - `public enum BarLevel: Equatable, Sendable { case normal, warning, critical }`
  - `public struct BarItem: Equatable, Sendable { public let id: String; public let icon: String; public let name: String; public let value: String; public let level: BarLevel; public let stale: Bool }`
  - `public enum BarLayout`, with `static func warningThreshold(_ thresholds: [Int]) -> Int` and `static func level(percent: Int?, thresholds: [Int]) -> BarLevel` moved from `BarLabelBuilder`
  - `public static func segments(snapshot: UsageSnapshot?, configuration: Configuration) -> [BarItem]`, which produces subscriptions and standalone accounts in accounts-list order, then groups in groups-list order. It keeps today's subscription rules ("…", "--", stale) and treats an own budget like a group.
- [X] T035 [US2] In `Sources/AgentMeter/BarLabel.swift`, make `BarLabelBuilder` consume `BarLayout.segments`. Keep only the rendering: the template image with each glyph from `item.icon`, and plain or accessibility text from names. Remove the duplicated ordering and level logic, and update callers in `Sources/AgentMeter/App.swift` (R6, FR-004).
- [X] T036 [US2] Run `make test` and `make build`

**Checkpoint**: Standalone budgets work end to end.

---

## Phase 6: User Story 3 - Group member shown individually in the bar (Priority: P2)

**Goal**: Members can appear in the bar as their share of the group budget, in the FR-020 order. The dropdown shows every member's share.

**Independent Test**: In a group with a $300 budget and one shown member that spent $90, `BarLayout` yields the member item with "30%" right after the group item. If the group is hidden, the member takes the group's place.

### Tests for User Story 3

- [X] T037 [US3] Extend `Tests/UsageCoreTests/BarLayoutTests.swift` with member tests:
  - **Order** (FR-019, FR-020): each shown group is followed by its shown members in accounts-list order. A hidden group's shown members take its position. Several shown members keep accounts-list order.
  - **Member values** (FR-017, FR-018): the value is `memberPercent`, and above 100% the actual value is shown. The level uses the group's warning threshold. A member shows "…" when the group has no entry or `snapshot` is `nil`, and is stale when the group is stale. Members never add threshold entries.
  - **Ids**: member item ids are `"<groupId>/<accountId>"`.

### Implementation for User Story 3

- [X] T038 [US3] In `Sources/UsageCore/Bar/BarLayout.swift`, add member items. After each group's position (whether or not the group itself is shown), emit the group's members whose `memberShownInBar` is true, in accounts-list order. Each member uses `GroupEntry.memberPercent`, the group's warning threshold, the group's placeholder and stale state, and the id `"<groupId>/<accountId>"` (FR-017 to FR-020).
- [X] T039 [US3] In `Sources/AgentMeter/AccountSettingsView.swift`, show the toggle "Show this account's share in the menu bar" for group members, bound to `memberShownInBar` (default off). In `Sources/AgentMeter/DropdownView.swift`, show every member's share as " (P%)" next to its spend, using `GroupEntry.memberPercent` (FR-016, FR-018a).
- [X] T040 [US3] Run `make test` and `make build`

**Checkpoint**: All user stories are complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T041 [P] Update `specs/001-agentmeter/contracts/config-file.md` so its example uses `icon` instead of `label`, with a pointer to `specs/004-icon-labels-standalone-budgets/contracts/config-file.md`
- [X] T042 [P] Update `README.md` wherever it mentions text labels, mandatory groups, or the bar contents, so it covers icons, own budgets, and member shares
- [X] T043 Run `rg -n "shownLabel|LabelContent|maxLabelLength|\\.label\\b" Sources` and confirm that the remaining hits refer only to `IconEntry.label` (the catalog name)
- [X] T044 Build the app (`make app`). If GUI interaction is not possible, record the manual steps of `specs/004-icon-labels-standalone-budgets/quickstart.md` as not run
  - Result: `make app` built `build/AgentMeter.app`. Manual steps 1 to 7 of quickstart.md were **not run** (no GUI interaction in the automated pipeline).
- [X] T045 Run `make test` and `make build` a final time

---

## Dependencies & Execution Order

- **Phase 1** before **Phase 2**. Phase 2 blocks everything (the shared type change).
- **US1 (Phase 3)** and **US4 (Phase 4)** depend only on Phase 2, and can be done in either order.
- **US2 (Phase 5)** depends on Phase 2.
- **US3 (Phase 6)** depends on US2's T028 and T029 (`memberSpendUSD`, `accountBudgets`) and on `BarLayout` from T034 and T035.
- **Polish** comes after all stories.

### Within Each Story

Write the tests first and confirm they fail, then implement, then run the `make test` checkpoint.

### Parallel Opportunities

- T012 and T013 both edit `ConfigurationTests.swift`. Write them in sequence, or as one editing pass.
- T018 (ConfigurationTests) and T019 (ConfigStoreTests) touch different files.
- T021 and T022 share `ConfigurationTests.swift`. T023 (AggregatorTests) and T024 (ThresholdTrackerTests) run in parallel with them.
- T025 (new BarLayoutTests) and T026 (RefreshCoordinatorTests) touch files no other US2 test task touches.
- T041 and T042 are independent documentation edits.

## Implementation Strategy

1. **Phase 2** is the large mechanical step: labels out, icons required, membership type in. Behaviour stays the same.
2. **US1 and US4** complete the icon story and prove upgrade safety. This is the MVP.
3. **US2** adds own budgets end to end, including the bar, and moves the bar layout into `UsageCore`.
4. **US3** adds member shares to the bar layout and the dropdown.
5. **Polish**: documentation and final checks.
