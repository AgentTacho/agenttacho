# Implementation Plan: Icon Labels and Standalone Budgets

**Branch**: `004-icon-labels-standalone-budgets` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-icon-labels-standalone-budgets/spec.md`

## Summary

This feature makes three changes:

- **Icon-only labels.** Text labels disappear. Every account and group has one required catalog icon, the type default when none is stored, and icons may repeat.
- **Own budgets.** A token-based account either belongs to a group or carries its own `BudgetSettings` (period, amount, shown-in-bar, thresholds). It behaves like a one-member group in aggregation, thresholds, the dropdown, and the bar.
- **Members in the bar.** Group members can appear in the bar with their share of the group budget.

Two pieces of supporting work make this possible. A derived `budgetOwners` list lets the aggregator and threshold tracker treat groups and standalone accounts alike. The bar layout moves into `UsageCore`, so the ordering and member rules can be unit tested.

## Technical Context

**Language/Version**: Swift 5.10, macOS 14+

**Primary Dependencies**: SwiftUI, AppKit (bar image), Foundation. No new dependencies.

**Storage**: `~/.config/agenttacho/config.json`

**Testing**: Swift Testing via `make test`

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (`AgentTacho`) with a core library (`UsageCore`)

**Performance Goals**: unchanged (spec 001 SC-004). Owner iteration is linear in the number of accounts and groups.

**Constraints**:
- Legacy configs must load unchanged in meaning.
- The group JSON format stays as defined in spec 003.
- No change to subscription fetching.

**Scale/Scope**: about 10 source files and 6 test suites touched, one new core type set (`BudgetSettings`, `TokenMembership`, `BudgetOwner`, `BarLayout`).

## Global Constraints

- Swift 5.10, macOS 14+, no new dependencies.
- Group JSON format stays as defined in spec 003; only `label` is dropped and `icon` becomes required.
- No change to subscription fetching or the endpoint call policy.
- No em-dash or en-dash characters in code, comments, or strings.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution is the unfilled template. The plan follows the codebase conventions: pure logic in `UsageCore` with Swift Testing suites, thin SwiftUI views, and doc comments that cite FR ids. Post-design: no violations. Moving the bar layout into `UsageCore` improves testability, in line with the idea-inbox item `testable-bar-label`.

## Project Structure

### Documentation (this feature)

```text
specs/004-icon-labels-standalone-budgets/
├── plan.md
├── research.md          # R1 to R9
├── data-model.md
├── quickstart.md
├── contracts/config-file.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Configuration.swift        # remove label/LabelContent; IconDefaults; required icon + legacy decode;
│                                     # BudgetSettings; TokenMembership; BudgetGroup.budget view; budgetOwners;
│                                     # validation; move helpers; dataRelevant (R1-R3, R7, R8)
├── Config/ConfigStore.swift          # default account icon (R9)
├── Snapshot/UsageSnapshot.swift      # GroupEntry.memberSpendUSD + memberPercent; UsageSnapshot.accountBudgets (R4)
├── Snapshot/Aggregator.swift         # iterate budgetOwners; member spend; standalone token account window (R4)
├── Snapshot/RefreshCoordinator.swift # stale carry-over and per-owner log line for accountBudgets (R4)
├── Windows/WindowResolver.swift      # collection window considers own budgets with monthly period
├── Notifications/ThresholdTracker.swift # iterate budgetOwners; memberIds in state (R5)
└── Bar/BarLayout.swift               # NEW: ordering, values, levels, member rules (R6)

Sources/AgentTacho/
├── BarLabel.swift            # render BarLayout items (icons + names), drop ordering logic (R6)
├── IconFont.swift            # attributed/Text helpers take an icon reference, not LabelContent (R1)
├── DropdownView.swift        # icon + name everywhere; standalone account entries; member share percent (FR-010, FR-018a)
├── AccountSettingsView.swift # IconField; Budget picker (own budget / groups); BudgetFields; member toggle; new-account flow (R7)
├── SettingsView.swift        # LabelEditor -> IconField; alignment picker uses icon + name
└── NotificationPresenter.swift / App.swift # names in notifications and logs (FR-004)

Tests/UsageCoreTests/
├── ConfigurationTests.swift, ConfigStoreTests.swift, AggregatorTests.swift,
├── ThresholdTrackerTests.swift, RefreshCoordinatorTests.swift (fixtures using label:)
└── BarLayoutTests.swift      # NEW
```

**Structure Decision**: The existing two-target layout stays. A new `Sources/UsageCore/Bar/` folder holds the pure bar layout.

## Design Notes

1. **Model (R1 to R3).**
   - `Account.icon: String` and `BudgetGroup.icon: String`.
   - `IconDefaults.defaultIcon(for:)`.
   - Decoders ignore `label` and default missing, `null`, or empty icons. Encoders never write `label`.
   - `BudgetSettings` has its own `init(from:)`, which applies the spec 003 period rules.
   - `TokenBasedSettings(membership:provider:)` exposes computed `groupId`, `ownBudget`, and `memberShownInBar`.
   - `Account` decoding enforces exactly one of `groupId` and `budget`.
   - `BudgetGroup.budget { get set }` maps to the flat fields.
2. **Owners (R4).**
   - `Configuration.budgetOwners: [BudgetOwner]` lists groups first, then standalone accounts.
   - `budgetOwner(forAccount:)` returns the owner whose window a token account uses.
3. **Aggregator (R4).**
   - Loop over owners and compute each window from `owner.budget.period`.
   - Fill `memberSpendUSD`.
   - Write group entries to `groups` and account owners to `accountBudgets`.
   - Token-account breakdowns use the owner's window.
4. **Coordinator and window resolver.**
   - The collection window is monthly when any owner is monthly.
   - Stale carry-over and the per-owner log line include `accountBudgets`.
   - Log lines use names, not icons.
5. **Thresholds (R5).** Iterate owners and key by `(owner.id, period.windowKind)`. The state stores `memberIds`. A changed member set resets the state, and notifications use `owner.name`.
6. **Bar (R6).** `BarLayout.segments(snapshot:configuration:)` produces items in FR-020 order with member rules. `BarLabelBuilder` renders the glyph from `item.icon` and builds accessibility text from `item.name`.
7. **Settings (R7).**
   - `IconField` replaces `LabelEditor`.
   - `BudgetFields` is extracted and shared by the group editor and the own-budget editor.
   - Membership changes go through the Configuration move helpers.
   - The new-account sheet has three choices.
8. **Relevance (R8).** Update `dataRelevant()` to blank icons, member `shownInBar`, and own-budget presentation fields.

## Risks

- **Wide rename (`label`, `LabelContent`).** It touches every view and many tests. Mitigation: phase 2 makes the model change and fixes all compile errors before any behaviour change.
- **Threshold re-baselining.** It could hide a real crossing that happens in the same refresh as a membership change. This is accepted by FR-015.
- **Dropdown ordering of standalone accounts.** Assumption: they are listed with groups, after them, in accounts-list order. This matches `budgetOwners`.

## Complexity Tracking

No constitution violations to justify.
