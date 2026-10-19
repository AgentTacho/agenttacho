# Implementation Plan: Minimal Dropdown

**Branch**: `025-minimal-dropdown` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/025-minimal-dropdown/spec.md`

## Summary

The dropdown gets a calmer layout. Every limit window and budget shows one text line plus a full-width bar with the pace tick, and an orange note only when the row calls for attention; the pace meter and its tooltip go. Reset and run-out times read relative by default, absolute per account or group. Sections get dividers, the Codex section loses its plan type and token lines (the token total moves into Details), a single-member group loses its member line, and the footer becomes errors, update line, "Last refreshed" (with the pace line as tooltip) and three icons. The gear menu goes.

Technically all wording and decisions move into `UsageCore`: a `PaceReading` that carries pace and burn rate together, a `RowBar` that decides fill, tick, tone and note, a `TimeText` formatter for both time formats, `SectionNote` for every note, and small footer and Details text helpers. A `timeFormat` key is added to accounts and groups in the configuration. The SwiftUI layer only renders these values (research R1 to R7).

## Technical Context

**Language/Version**: Swift (tools version 5.10, Swift Package Manager `Package.swift`), macOS 14 target

**Primary Dependencies**: SwiftUI and AppKit (app layer), Foundation (`UsageCore`); no new dependency

**Storage**: the JSON configuration `~/.config/agenttacho/config.json` gains an optional `timeFormat` key per account and group

**Testing**: Swift Testing (`@Test`, `#expect`) through `make test` (`Tests/UsageCoreTests`, `Tests/DemoModeTests`) and `make test-release` (release scripts, including `scripts/release/tests/test_screenshots.sh`)

**Target Platform**: macOS menu bar app (MenuBarExtra window, always dark panel, 360 pt wide)

**Project Type**: desktop app with a core library (`UsageCore`), a demo library (`DemoMode`) and a thin SwiftUI target (`AgentTacho`)

**Performance Goals**: relative times re-render at most once every 30 seconds while the dropdown is open; no extra refresh, no extra work while closed

**Constraints**: no em or en dash anywhere; logic in `UsageCore` test first; build only through the Makefile; screenshots only from the demo build

**Scale/Scope**: about 5 view files in `Sources/AgentTacho`, 6 to 8 new or changed files in `UsageCore`, 1 new demo scenario, the capture script, README, 9 earlier specs amended

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How this plan complies |
|---|---|---|
| I. Spec-Driven Development | Pass | Spec 025 with clarifications and two review rounds; plan, tasks and implementation follow; earlier specs amended (FR-033). |
| II. Test-First, Logic in UsageCore | Pass | Bar geometry and tone, note text, time formats, section notes, footer text, Details total and `timeFormat` decoding are `UsageCore` types with tests written first (FR-029 to FR-032). The views only render them. |
| III. Read-Only, Private by Default | Pass | No change to credentials, keychain, network requests or the agents' files. The README "Security and privacy" section is untouched; no website privacy change. |
| IV. One Build Entry Point | Pass | `make test`, `make test-release`, `make app`, `make app-demo` only. |
| V. Screenshots and Website Follow the UI | Pass | Section below lists the changed shots, the demo scenario change with its coverage test, the website copy and the README image. The capture and the site pull request run on the maintainer's go (AGENTS.md step 4, publishing rules). |

Post-design re-check: still passes; the design adds no new target, dependency or network path.

## Screenshots and website

| | |
|---|---|
| Shots that change | `plan-limits` (bars instead of meters), `pace` (a row with its bar and orange note instead of the meter tooltip; capture step crops the row, no hover), `budget` (bar), `details` and `harnesses` (total line above the picker for subscription Details; the shot budget's Details itself unchanged apart from layout around it), `groups` (Times picker in the group detail), `dropdown` (everything) |
| New shots | none |
| Demo scenario | `Resources/demo/default.json` keeps the relative default and its existing ahead row with a run-out (orange note) and the two-member "Company budget"; `CoverageReport` gains `attentionRows` and the coverage test checks at least one. New `Resources/demo/variants.json` (not captured) sets the Claude account to absolute times and has a group with one member; `DefaultScenarioTests` and a new coverage test check both. |
| Website copy | site `src/data/features.ts`: the card with the `pace` stem says the pace shows as a tick on the bar with an orange line when a limit will run out (no hover); any card or small thing that mentions the gear menu or "Refresh now" changes to the icon row |
| README image | replace `docs/images/agenttacho-dropdown.png` from the new `dropdown-light.webp` and update its alt text (dropdown changed) |

Capture (`scripts/screenshots/capture.sh`) quits AgentTacho and switches the appearance, so it runs only after the maintainer says go; the site pull request follows the capture and is linked from the app pull request.

## Project Structure

### Documentation (this feature)

```text
specs/025-minimal-dropdown/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1 to R14
├── data-model.md        # Phase 1: types and config key
├── quickstart.md        # Phase 1: how to check the feature
├── contracts/
│   ├── dropdown-ui.md   # Layout, texts and accessibility of the dropdown
│   └── config-file.md   # The timeFormat key
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Pace/PaceReading.swift          # new: pace + burn rate in one value, UsageSnapshot.paceReading(for:)
├── Dropdown/RowBar.swift           # new: fill, tick, tone, note of a window or budget row
├── Dropdown/TimeText.swift         # new: relative and absolute formats, tooltips (FR-016 to FR-020)
├── Dropdown/SectionNote.swift      # new: every section note with style (FR-029)
├── Dropdown/FooterText.swift       # new: "Last refreshed" text and tooltip, Details total line
├── Config/TimeFormat.swift         # new: TimeFormat enum
├── Config/Configuration.swift      # Account.timeFormat, BudgetGroup.timeFormat, decoding notes
├── Pace/BurnRate.swift             # burnWindowKeys made public as paceKeys
└── Config/TimeFormatResolution.swift  # new: the time format of an arranged entry

Sources/AgentTacho/
├── DropdownView.swift              # layout B rows, notes, dividers, footer, icon row; pace meter removed
├── RowBarView.swift                # new: the bar with fill and tick
├── BreakdownView.swift             # optional total line above the view picker
├── AccountSettingsView.swift       # "Times" picker in account and group details (GroupSettingsView lives here too)
└── UpdateViews.swift               # unchanged API; placement only

Sources/DemoMode/ScenarioCoverage.swift   # attentionRows, single-member groups, absolute time formats
Resources/demo/variants.json              # new scenario (absolute times, one-member group)
scripts/screenshots/capture.sh            # pace stem crops the row; Settings via the icon button
scripts/release/tests/test_screenshots.sh # stub expectations for the changed capture steps

Tests/UsageCoreTests/
├── PaceReadingTests.swift, RowBarTests.swift, TimeTextTests.swift,
├── SectionNoteTests.swift, FooterTextTests.swift
└── ConfigurationTests.swift        # timeFormat decode, encode, unknown value note
Tests/DemoModeTests/DefaultScenarioTests.swift, ScenarioTests.swift

README.md, docs/images/agenttacho-dropdown.png
specs/004, 007, 011, 013, 016, 017, 019, 020, 024 spec.md   # amendment notes (FR-033)
```

**Structure Decision**: the existing three-target layout stays. New core types live in a new `Sources/UsageCore/Dropdown/` folder next to `Pace/` and `Bar/`; the app target only replaces rendering code.

## Complexity Tracking

No constitution violations.
