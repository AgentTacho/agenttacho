# Implementation Plan: Burn Rate Escalation

**Branch**: `017-burn-rate-escalation` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/017-burn-rate-escalation/spec.md`

## Summary

Every window and budget with a pace gets a burn rate: the sustainable rate (remaining percent over the time left), the average rate since the window start and, from observations kept in memory for 60 minutes, the recent rate. An entry burns fast when a qualifying rate is at least twice the sustainable rate; the bar then shows `↑` instead of `↗`, and the dropdown pace meter says "burning fast" with the run-out at that rate.

- **Core observations.** New `ObservationLog` (pure value type) in `UsageCore/Pace/ObservationLog.swift`: per-window observations, the discard rules of FR-003 and the recent rate of FR-004 (research R1 to R6).
- **Core decision.** New `BurnRate` in `UsageCore/Pace/BurnRate.swift`: sustainable and average rates, the qualification rules and the fast run-out (FR-001, FR-002, FR-005 to FR-007; research R7). `UsageSnapshot.burnRate(for:)` maps a window key to its inputs (research R10).
- **Coordinator.** `RefreshCoordinator` keeps one `ObservationLog`, updates it from every published snapshot (including the early result from saved values) and attaches it as `UsageSnapshot.observations`; price imports and removals (`requestReprice`) and override edits mark budget prices as changed (research R1, R5).
- **Bar.** `BarItem.burnsFast`; `BarLayout` sets it with the same suppression as `↗`; `BarPresentation` draws `↑`; the accessibility suffix names the fast burn (FR-008, FR-009, FR-011; research R8).
- **App.** `PaceMeter` takes the burn rate (color and text via `Pace.summary(runOutText:fastRunOut:)`); the rows pass `snapshot.burnRate(for:)`; the Menu Bar tab toggle label changes (FR-010, FR-012; research R9, R11).
- **Docs.** README marker and toggle descriptions (FR-014). No change to the "Security and privacy" section (FR-013).

## Technical Context

**Language/Version**: Swift 5.10 (toolchain 6.4), macOS 14+

**Primary Dependencies**: Foundation, SwiftUI, AppKit. No package dependencies.

**Storage**: None new. Observations live in memory only; `config.json` is unchanged.

**Testing**: Swift Testing via `make test`. New `BurnRateTests`, `ObservationLogTests`; extended `BarLayoutTests`, `BarPresentationTests`, `PaceTests`, `RefreshCoordinatorTests`.

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (`AgentTacho`) with core library (`UsageCore`)

**Performance Goals**: None beyond today's. At most about 60 observations per window (one per refresh at the 60 s minimum interval) and a handful of windows; the update is linear in that.

**Constraints**:
- All rates use observation times and the snapshot time, never the wall clock (spec 011 research R2).
- No new requests, credential reads or files; the coordinator gets the price-change signal from calls it already receives (research R5).
- `BarItem` and `Pace.summary` keep their current call signatures working (default parameters).

**Scale/Scope**: 2 new core files, 5 changed core files (`UsageSnapshot`, `RefreshCoordinator`, `BarLayout`, `BarPresentation`, `Pace`), 2 changed app files (`DropdownView`, `MenuBarSettingsTab`), README, 2 new test suites, 4 extended.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is an unfilled template. The plan follows AGENTS.md and the conventions of specs 001 to 014: logic in `UsageCore` with tests written first, thin SwiftUI views, FR citations in doc comments, no em or en dashes, read-only access to agent files, security statement unchanged (FR-013), README updated in the same change (FR-014). Post-design re-check: no violations.

## Project Structure

### Documentation (this feature)

```text
specs/017-burn-rate-escalation/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── burn-rate-display.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Pace/
│   ├── Pace.swift                # summary(runOutText:fastRunOut:)
│   ├── ObservationLog.swift      # NEW: BurnWindowKey, RateObservation, RecentRate, ObservationLog
│   └── BurnRate.swift            # NEW: BurnRate.compute, constants; UsageSnapshot.burnRate(for:)
├── Snapshot/
│   ├── UsageSnapshot.swift       # observations: ObservationLog (default empty)
│   └── RefreshCoordinator.swift  # owns the log; price-change flag; attaches log to snapshots
└── Bar/
    ├── BarLayout.swift           # BarItem.burnsFast, accessibilitySuffix; markers(...)
    └── BarPresentation.swift     # "↑" or "↗"

Sources/AgentTacho/
├── DropdownView.swift            # PaceMeter(pace:burn:); rows pass snapshot.burnRate(for:)
└── MenuBarSettingsTab.swift      # toggle label

README.md                         # marker and toggle descriptions

Tests/UsageCoreTests/
├── BurnRateTests.swift           # NEW
├── ObservationLogTests.swift     # NEW
├── BarLayoutTests.swift          # ↑ cases and suppression
├── BarPresentationTests.swift    # glyph and accessibility
├── PaceTests.swift               # summary with fastRunOut
└── RefreshCoordinatorTests.swift # log attached across refreshes, price change, saved values
```

**Structure Decision**: Existing layout; the new types sit next to `Pace` because they extend the pace model.

## Complexity Tracking

No constitution violations to justify.
