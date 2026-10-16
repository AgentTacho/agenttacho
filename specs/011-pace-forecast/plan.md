# Implementation Plan: Pace Forecast

**Branch**: `011-pace-forecast` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/011-pace-forecast/spec.md`

## Summary

Every window and budget gets a pace computed from values the snapshot already holds, shown as a line in the dropdown and as a `↗` marker in the bar:

- **Core computation.** New `Pace` value and `Pace.compute(usedPercent:windowStart:resetsAt:observedAt:now:)` in `UsageCore/Pace/Pace.swift`: expected share, rounded delta, the -5...+5 "on pace" band, the 10% hold back, the run-out only when ahead and before the reset, and the exclusions of FR-007. Adapters for `LimitWindow`, `ModelLimit`, `CodexLimitWindow` and `GroupEntry`, and `Pace.summary(runOutText:)` for the wording (FR-001 to FR-008, FR-017; research R1 to R5, R8).
- **Bar.** `BarItem.runOutMarker`, set by `BarLayout.segments` for subscription, Codex and budget items when the marker is enabled, the level is normal, the item is not stale and the bar window has a run-out (FR-012, FR-013; research R6).
- **Configuration.** `Configuration.showsRunOutMarker`, default true, tolerant decoding (FR-014; research R7).
- **App.** `PaceMeter` view at the end of the Claude, model limit, Codex and budget rows (replaced the first `PaceLine` text line after walkthrough feedback); `UsageFormat.runOutText`; the `↗` glyph in `BarItem.valueText` and the accessibility wording in `BarItem.text`; the toggle in the Menu Bar tab (FR-008 to FR-011, FR-014, FR-015).
- **No I/O.** No requests, credentials or files; the README security section stays as it is (FR-016).

## Technical Context

**Language/Version**: Swift 5.10 (toolchain 6.4), macOS 14+

**Primary Dependencies**: Foundation, SwiftUI, AppKit. No package dependencies.

**Storage**: `config.json` gains one optional key, `showsRunOutMarker`; nothing else is stored.

**Testing**: Swift Testing via `make test`. New `PaceTests`; extended `BarLayoutTests` (marker rules, toggle, member items, levels, stale) and `ConfigurationTests` (key absent, false, round trip).

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (`AgentMeter`) with core library (`UsageCore`)

**Performance Goals**: None beyond today's; a few arithmetic operations per row on each render.

**Constraints**:
- Pace uses observation times and the snapshot time, never the wall clock (research R2).
- Existing configurations load unchanged; the marker defaults to on (SC-004 holds with the toggle off).
- `BarItem`'s initializer keeps its current signature working (default `runOutMarker: false`).

**Scale/Scope**: 1 new core file, 2 changed core files, 3 changed app files, 1 new test suite, 2 extended.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is an unfilled template. The plan follows the project conventions in AGENTS.md and specs 001 to 009: logic in `UsageCore` with tests written first, thin SwiftUI views, tolerant configuration decoding, FR citations in doc comments, no em or en dashes, read-only access to agent files, security statement unchanged. Post-design re-check: no violations.

## Project Structure

### Documentation (this feature)

```text
specs/011-pace-forecast/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── pace-display.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Pace/
│   └── Pace.swift              # NEW: Pace, PaceStatus, Pace.compute, summary(runOutText:),
│                               # adapters for LimitWindow, ModelLimit, CodexLimitWindow, GroupEntry
├── Bar/BarLayout.swift         # BarItem.runOutMarker; segments sets it (subscription 7-day,
│                               # Codex longest effective window, budgets); members never
└── Config/Configuration.swift  # showsRunOutMarker (key, init parameter, decodeIfPresent ?? true)

Sources/AgentMeter/
├── DropdownView.swift          # PaceMeter view; at the end of WindowRow, ModelLimitRow, CodexWindowRow,
│                               # BudgetSection amount line; UsageFormat.runOutText
├── BarLabel.swift              # "↗" in valueText; accessibility wording in text
└── MenuBarSettingsTab.swift    # Toggle bound to draft.showsRunOutMarker

Tests/UsageCoreTests/
├── PaceTests.swift             # NEW
├── BarLayoutTests.swift        # marker cases
└── ConfigurationTests.swift    # showsRunOutMarker decoding and round trip
```

**Structure Decision**: Existing two-target layout. The pace rules live in a new `Pace/` folder of `UsageCore` because they are shared by the bar layout and the dropdown and belong to neither; the app only formats dates and renders.

## Complexity Tracking

No constitution violations to justify.
