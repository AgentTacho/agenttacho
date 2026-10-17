# Implementation Plan: Explicit Group Management

**Branch**: `009-explicit-group-management` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-explicit-group-management/spec.md`

## Summary

Budget groups stop disappearing on their own and get explicit Add and Remove in the Groups tab:

- **Lifecycle.** Remove the implicit deletion everywhere: `validate()` accepts empty groups, `settingsCandidate` no longer prunes, and `movingAccountToOwnBudget`, `movingAccountToGroup` and `removingAccount` no longer call `deletingGroupIfEmpty` (FR-001 to FR-003).
- **Core operations.** New pure `Configuration.addingGroup(id:)` and `Configuration.removingGroup(id:destination:)` (destination: own budgets, or another group) in `UsageCore`, unit tested (FR-007, FR-010).
- **Arrangement.** `reconcilingArrangement` keeps the removed group's member order when its members take its position or join another group (FR-011).
- **UI.** Groups tab: Add and Remove... buttons, a removal dialog with the member list and destination picker, the new caption, the empty-group note in the editor. Dropdown: the empty-group note in the group section. Account removal text no longer announces a group deletion (FR-005, FR-008 to FR-010, FR-013, FR-015, FR-016).
- **Notifications.** No new mechanism: `ThresholdTracker` already re-baselines when a group's member set changes or an owner is new (spec 004 FR-015); tests pin it for the new cases (FR-006, FR-012).

## Technical Context

**Language/Version**: Swift 5.10 (toolchain 6.4), macOS 14+

**Primary Dependencies**: Foundation, SwiftUI, AppKit. No package dependencies.

**Storage**: `config.json` format unchanged; a group with no members becomes valid.

**Testing**: Swift Testing via `make test`. Extend `ConfigurationTests`, `ArrangementReconcileTests`, `ThresholdTrackerTests`; new `GroupLifecycleTests`. Existing tests that assert pruning or the `emptyGroup` error are inverted.

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (`AgentTacho`) with core library (`UsageCore`)

**Performance Goals**: None beyond today's; no new I/O.

**Constraints**:
- Existing configurations load and behave as before (SC-004).
- Membership stays editable only from the account side (FR-013).
- Undo works through the existing Settings undo flow (FR-012).

**Scale/Scope**: about 4 changed core files, 3 changed app files, 1 new test suite, 4 extended.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is an unfilled template. The plan follows the conventions of specs 001 to 008: pure logic in `UsageCore` with Swift Testing, thin SwiftUI views, tolerant configuration, FR citations in doc comments. Post-design re-check: no violations.

## Project Structure

### Documentation (this feature)

```text
specs/009-explicit-group-management/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── groups-tab.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/Config/
├── Configuration.swift     # validate() accepts empty groups; no implicit deletion in
│                           # movingAccountToOwnBudget/movingAccountToGroup/removingAccount;
│                           # pruningEmptyGroups and deletingGroupIfEmpty removed;
│                           # emptyGroup error kind removed
├── GroupLifecycle.swift    # NEW: GroupRemovalDestination, addingGroup(id:), removingGroup(id:destination:)
└── Arrangement.swift       # settingsCandidate without pruning; member order kept for a removed group

Sources/AgentTacho/
├── SettingsView.swift         # stale pruning comment in applyNow
├── AccountSettingsView.swift  # GroupSettingsView Add/Remove, removal dialog, caption, editor note;
│                              # account removal message (FR-016)
└── DropdownView.swift         # BudgetSection: empty-group note

Tests/UsageCoreTests/
├── GroupLifecycleTests.swift      # NEW
├── ConfigurationTests.swift       # empty group valid; moves and removals keep groups
├── ArrangementReconcileTests.swift# removal placement in member order; no pruning
└── ThresholdTrackerTests.swift    # re-baseline after refill and after removal moves
```

**Structure Decision**: same two-target layout; every rule that changes the configuration is a pure `Configuration` function in `UsageCore`.

## Complexity Tracking

No constitution violations to justify.
