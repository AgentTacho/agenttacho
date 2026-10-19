# Implementation Plan: Section Bands

**Branch**: `028-section-bands` | **Date**: 2026-10-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/028-section-bands/spec.md`

## Summary

The dropdown's dividers go; sections alternate plain and faintly tinted full-width bands, and the pinned footer gets its own slightly stronger band. A new `UsageCore` type `SectionBands` decides each section's stripe from the number of arranged entries and whether Unassigned is shown, and `BandStyle` holds the fill strengths for normal and increased contrast with a tested order. `DropdownView` drops its `Divider`s, moves the horizontal inset from the sections container into each section, pads each section 10 pt vertically inside its band and fills the band with `Color.primary` at the style's strength. The demo coverage reports the stripe sequence (research R1 to R6).

## Technical Context

**Language/Version**: Swift (tools version 5.10, Swift Package Manager `Package.swift`), macOS 14 target

**Primary Dependencies**: SwiftUI and AppKit (app layer), Foundation (`UsageCore`); no new dependency

**Storage**: none (no configuration or `UserDefaults` change)

**Testing**: Swift Testing through `make test` (`Tests/UsageCoreTests`, `Tests/DemoModeTests`) and `make test-release`

**Target Platform**: macOS menu bar app (MenuBarExtra window, always dark panel, 360 pt wide)

**Project Type**: desktop app with a core library (`UsageCore`), a demo library (`DemoMode`) and a thin SwiftUI target (`AgentTacho`)

**Performance Goals**: no measurable cost; one fill per section

**Constraints**: no em or en dash; logic in `UsageCore` test first; build only through the Makefile; the dropdown no taller than before (SC-003)

**Scale/Scope**: 1 new `UsageCore` file, 1 changed app file, coverage and its test, 2 earlier specs and 1 contract amended, 1 docs page

## Global Constraints

- Horizontal inset 12 pt (`inset`), vertical band padding 10 pt (`bandPadding`), sections container top padding 2 pt and bottom 0.
- Strengths of `Color.primary`: tinted 0.04 / 0.08, footer 0.07 / 0.12 (normal / Increase contrast); hover stays 0.06 above the band.
- Distance between two sections' content, and from the last section to the footer content: at most 21 pt (now 20 pt).
- No `Divider` in the dropdown.

## Constitution Check

| Principle | Status | How this plan complies |
|---|---|---|
| I. Spec-Driven Development | Pass | Spec 028 with clarifications and one review round. |
| II. Test-First, Logic in UsageCore | Pass | `SectionBands` and `BandStyle` get tests first (stripe sequence, Unassigned rule, strength order); the view only lays out and fills. |
| III. Read-Only, Private by Default | Pass | No file, credential or network change. |
| IV. One Build Entry Point | Pass | Makefile only. |
| V. Screenshots and Website Follow the UI | Pass | Shots listed below; the demo scenario already shows four sections and the coverage test checks the stripes. The capture run needs the maintainer's go (AGENTS.md step 4) and happens before merge, with the site pull request linked from the app pull request. |

Post-design re-check: unchanged, all pass.

## Screenshots and website

| | |
|---|---|
| Shots that change | `plan-limits`, `pace`, `budget`, `groups`, `details`, `harnesses`, `dropdown` (bands instead of dividers; crops show the band of their section) |
| New shots | none (no new card; a visual refinement of the dropdown) |
| Demo scenario | no change to `Resources/demo/default.json` (four arranged entries already); coverage: `CoverageReport.sectionStripes`, test expects plain, tinted, plain, tinted (plus Unassigned plain if shown) |
| Website copy | none (the site's data files do not mention dividers, spec FR-012a) |
| README image | replace `docs/images/agenttacho-dropdown.png` (dropdown changed), alt text unchanged unless the values shown change |

## Project Structure

### Documentation (this feature)

```text
specs/028-section-bands/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/dropdown-bands.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/Dropdown/
└── SectionBands.swift       # new: BandStyle (strengths), SectionBands.stripes, showsUnassigned (FR-002, FR-003, FR-005, FR-006)

Sources/AgentTacho/
└── DropdownView.swift       # no Divider; per-section inset, padding and band fill; footer band; colorSchemeContrast

Sources/DemoMode/ScenarioCoverage.swift   # CoverageReport.sectionStripes
Tests/UsageCoreTests/SectionBandsTests.swift (new)
Tests/DemoModeTests/DefaultScenarioTests.swift
docs/accounts-and-budgets.md              # "separated by dividers" (FR-011)
specs/025-minimal-dropdown/spec.md, specs/025-minimal-dropdown/contracts/dropdown-ui.md, specs/026-dropdown-layout-polish/spec.md   # amendments (FR-010)
docs/images/agenttacho-dropdown.png       # replaced after the capture (FR-013)
```

**Structure Decision**: unchanged three-target layout; the stripe rule next to the other dropdown helpers (`FooterText`, `MemberDisplay`, `DayRowTotal`).

## Complexity Tracking

No violations.
