# Implementation Plan: Monthly Budget Period

**Branch**: `003-monthly-budget-period` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-monthly-budget-period/spec.md`

## Summary

Budget groups get a `period` (weekly or monthly) and a period-neutral `budgetUSD`, with the legacy `weeklyBudgetUSD` still decoding as weekly. A monthly group's window is the local calendar month. Each refresh resolves the weekly window as today, adds the monthly window when a monthly group exists, and hands the record source a collection window spanning both. The aggregator then measures every group, and its member accounts, over the group's own window. Threshold state is keyed by the period's window kind, so month rollover, time zone changes, and period switches reset with a baseline through the existing tracker mechanics. Settings get a period picker and period-aware labels, and the per-day trend wraps after 7 columns so a month fits the dropdown.

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10), macOS 14+

**Primary Dependencies**: SwiftUI, Foundation (no new dependencies)

**Storage**: `~/.config/agentmeter/config.json` (JSON, hand-editable)

**Testing**: Swift Testing (`import Testing`, `@Suite`) via `swift test` / `make test`

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (SwiftUI menu bar) with a core library (`UsageCore`)

**Performance Goals**: Refresh durations stay within spec 001 SC-004 (full refresh < 10 s, incremental < 1 s) with up to 31 days of records in memory (spec 003 SC-006)

**Constraints**: No change to subscription handling or the endpoint call policy; config stays backward compatible (old files load unchanged)

**Scale/Scope**: 5 to 10 accounts, a handful of budget groups; about 8 source files and 5 test suites touched

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is still the unfilled template, so there are no ratified principles to gate against. The plan follows the conventions visible in the codebase instead: pure, testable logic in `UsageCore`, thin SwiftUI views, Swift Testing suites per core type, and spec requirement ids cited in doc comments.

Post-design re-check: no violations; no new targets, dependencies, or abstractions beyond one enum (`BudgetPeriod`).

## Project Structure

### Documentation (this feature)

```text
specs/003-monthly-budget-period/
├── plan.md              # This file
├── research.md          # Phase 0 decisions R1 to R9
├── data-model.md        # Entity changes
├── quickstart.md        # Validation guide
├── contracts/
│   └── config-file.md   # Config JSON delta and decoding table
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Configuration.swift          # BudgetPeriod enum; BudgetGroup.period + budgetUSD; legacy decode; validation message (R5, R7)
├── Windows/WindowResolver.swift        # monthWindow(now:calendar:) and collection window helper (R1, R2)
├── Snapshot/UsageSnapshot.swift        # GroupEntry.period + window (R3)
├── Snapshot/Aggregator.swift           # per-group windows, member accounts on group window, perDay last day (R3, R6)
├── Snapshot/RefreshCoordinator.swift   # resolve weekly + monthly, pass collection window to sources, weekly window to aggregator, log per-group window (R2)
└── Notifications/ThresholdTracker.swift # WindowKind.monthly; group key by period (R4)

Sources/AgentMeter/
├── AccountSettingsView.swift   # period picker (edit + create), period labels (FR-014, FR-018, FR-019)
├── SettingsView.swift          # caption on the "Weekly window" section (FR-020)
├── DropdownView.swift          # passes period to BreakdownView
└── BreakdownView.swift         # day row wraps after 7 columns, day-of-month labels for monthly, legend wording (R6)

Tests/UsageCoreTests/
├── WindowResolverTests.swift
├── ConfigurationTests.swift
├── AggregatorTests.swift
├── ThresholdTrackerTests.swift
└── RefreshCoordinatorTests.swift
```

**Structure Decision**: Existing two-target layout (`UsageCore` library + `AgentMeter` app). All behaviour with acceptance criteria lives in `UsageCore` and is covered by Swift Testing suites; the app target only adds controls and labels.

## Design Notes

1. **Model first** (R5, R7): `BudgetPeriod` with raw values `weekly`/`monthly`, wording helpers, and `windowKind`. `BudgetGroup` replaces `weeklyBudgetUSD` with `budgetUSD` and adds `period`; its custom `init(from:)` implements the decoding table in [contracts/config-file.md](contracts/config-file.md), and an explicit `encode(to:)` writes only `period` and `budgetUSD`. Update every call site (`AccountSettingsView`, tests, fixtures).
2. **Windows** (R1, R2): `WindowResolver.monthWindow(now:calendar:)` returns `calendar.dateInterval(of: .month, for: now)`. A small helper returns the collection window: the weekly window joined with the month window when `configuration.groups` contains a monthly group.
3. **Coordinator** (R2): resolve the weekly window (initial and final, as today), compute the collection window from each, pass the collection window in `RefreshContext`, compare collection starts for the T040 re-run, and pass the weekly window plus `now` to the aggregator. The per-group refresh log line includes the group's period. The default calendar becomes `Calendar.autoupdatingCurrent` so a time zone change moves the monthly window (FR-016).
4. **Aggregator** (R3, R6): drop the up-front weekly filter, bucket the collected records by account, then filter per group to its own window; compute each token-based account's breakdown over its group's window; keep Unassigned and subscription breakdowns on the weekly window. `perDay` gains a `lastDay` parameter: the window's last day for weekly, today for monthly.
5. **Thresholds** (R4): add `WindowKind.monthly`; key groups by `group.period.windowKind`. No other tracker change.
6. **UI** (R6 to R8): period `Picker` (segmented) next to the amount in the group editor and in the new-group part of the add-account sheet; labels from `BudgetPeriod`; caption in the Weekly window section; `BreakdownView` takes the period, wraps the day row into rows of 7 using `Grid`, and labels monthly columns with the day of the month.

## Risks

- **Legacy decode regressions**: covered by contract-table tests in `ConfigurationTests` (one test per row).
- **LogIndex pruning with a moving collection start**: the monthly start only moves forward (at rollover), and an earlier start triggers the existing reset path; covered by a `RefreshCoordinatorTests` case that adds a monthly group mid-run.
- **Dropdown height**: a monthly trend adds up to 5 compact rows inside a collapsed "Details" section, shown only when expanded.

## Complexity Tracking

No constitution violations to justify.
