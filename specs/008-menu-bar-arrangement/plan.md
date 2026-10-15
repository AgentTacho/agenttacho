# Implementation Plan: Menu Bar Arrangement

**Branch**: `008-menu-bar-arrangement` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-menu-bar-arrangement/spec.md`

## Summary

One user-defined order drives the bar and the dropdown, and a new Settings tab edits it. The changes:

- **Model.** `Configuration` gains an optional `arrangement` (entry references with kind plus id, and member order per group). Absent means "derive the default order" (FR-004, FR-011).
- **Resolution.** A pure `Configuration.arrangedEntries` resolves the stored arrangement against the current accounts and groups, tolerating unknown, duplicate and misplaced references (FR-011). The bar (`BarLayout.segments`) and the dropdown iterate it instead of their own fixed orders (FR-002, FR-003).
- **Reconciliation.** A pure `Configuration.reconcilingArrangement(previous:)` applies the placement rules FR-004a and FR-005 to FR-008 when Settings applies a change. It works by comparing the previous and the next configuration, so no account or group editor needs to know about the order (research R3).
- **Editing.** Pure `ArrangementEditor` operations (flat rows, drag move, move up and down) live in `UsageCore` and are unit tested. The app's new `MenuBarSettingsTab` is a thin SwiftUI view over them, with a live bar preview and "Show in bar" checkboxes bound through `Configuration.isShownInBar` and `settingShownInBar` (FR-009 to FR-013).
- **Apply and undo.** Settings applies the arrangement through the existing debounced apply and undo flow (FR-014); reconciliation runs inside `applyNow`, except for the configuration an undo restored. An order-only change does not trigger a refresh (research R3a).

## Technical Context

**Language/Version**: Swift 5.10 (toolchain 6.4), macOS 14+

**Primary Dependencies**: Foundation, SwiftUI, AppKit. No package dependencies.

**Storage**: AgentMeter's `config.json` gains an optional top-level `arrangement` key; the file version stays 1 (additive, optional key; see [contracts/config-file.md](contracts/config-file.md)).

**Testing**: Swift Testing via `make test`. New suites for arrangement resolution, reconciliation and editing; `BarLayoutTests` and `ConfigurationTests` extended. The SwiftUI tab is checked by hand (quickstart).

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (`AgentMeter`) with core library (`UsageCore`)

**Performance Goals**: Resolution is linear in the number of accounts and groups (a handful); it runs on every bar and dropdown render without caching.

**Constraints**:
- Existing configs load and render with an unchanged bar order and are not rewritten on load (FR-004, SC-003).
- No new configuration errors: every arrangement problem is resolved by ignoring or appending (FR-011).
- A group and an account may share an id (`Configuration.validate()` allows it); references are kind-qualified.
- Account and group editors keep working unchanged (FR-015).

**Scale/Scope**: 2 new core files, 1 new app file, about 6 changed files, 3 new test suites, 2 extended.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is an unfilled template, so there are no project principles to gate on. The plan follows the conventions of specs 001 to 007 instead: pure logic in `UsageCore` with Swift Testing coverage, thin SwiftUI views in the app target, tolerant decoding of `config.json`, and spec requirement ids cited in doc comments.

Post-design re-check: unchanged, no violations.

## Project Structure

### Documentation (this feature)

```text
specs/008-menu-bar-arrangement/
├── plan.md              # This file
├── research.md          # Phase 0 decisions
├── data-model.md        # Arrangement, references, rows
├── quickstart.md        # Validation guide
├── contracts/
│   ├── config-file.md   # The arrangement key in config.json
│   └── menu-bar-tab.md  # UI contract of the Menu Bar tab
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   ├── Configuration.swift        # + arrangement property, coding key, dataRelevant clears it
│   └── Arrangement.swift          # NEW: Arrangement, EntryRef, ArrangedEntry,
│                                  #      arrangedEntries, defaultArrangement,
│                                  #      reconcilingArrangement, shown-in-bar helpers
├── Bar/
│   ├── BarLayout.swift            # segments() iterates arrangedEntries
│   └── ArrangementEditor.swift    # NEW: rows, move(from:to:), moveUp/Down, canMove

Sources/AgentMeter/
├── SettingsView.swift             # + Menu Bar tab (second), reconcile in applyNow
├── MenuBarSettingsTab.swift       # NEW: preview, list, checkboxes, move buttons
└── DropdownView.swift             # sections in arrangement order, members in member order

Tests/UsageCoreTests/
├── ArrangementTests.swift         # NEW: resolution, default order, tolerance, coding
├── ArrangementReconcileTests.swift# NEW: FR-004a, FR-005 to FR-008, self-reconcile no-op
├── ArrangementEditorTests.swift   # NEW: rows, drag moves, move up/down, rejects
├── BarLayoutTests.swift           # + order follows the arrangement, shared ids
└── ConfigurationTests.swift       # + needsRefresh is false for an order-only change
```

**Structure Decision**: Same two-target layout as specs 001 to 007. Everything that decides an order is pure and lives in `UsageCore`; the app target only renders rows and forwards gestures.

## Complexity Tracking

No constitution violations to justify.
