# Implementation Plan: Dropdown Layout Polish

**Branch**: `026-dropdown-layout-polish` | **Date**: 2026-10-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/026-dropdown-layout-polish/spec.md`

## Summary

Four layout changes to the dropdown of spec 025: a budget group gets one Details with a "Show accounts" button that reveals the member tables inside it; the "This week" line gives way to a Σ column at the end of every day row; the footer (errors, update line, status row) is pinned below the scrolling sections; and "Last refreshed" moves into the icon row. The member rules, the Σ value and tooltip, the footer error list and the status tooltip are tested `UsageCore` logic; the views render them (research R1 to R7).

## Technical Context

**Language/Version**: Swift (tools version 5.10, Swift Package Manager `Package.swift`), macOS 14 target

**Primary Dependencies**: SwiftUI and AppKit (app layer), Foundation (`UsageCore`); no new dependency

**Storage**: one new UI preference in `UserDefaults` (`showsMemberTables`, like `detailsMode`); no configuration change

**Testing**: Swift Testing through `make test` (`Tests/UsageCoreTests`, `Tests/DemoModeTests`) and `make test-release` (`scripts/release/tests/test_screenshots.sh`)

**Target Platform**: macOS menu bar app (MenuBarExtra window, always dark panel, 360 pt wide, 640 pt height cap)

**Project Type**: desktop app with a core library (`UsageCore`), a demo library (`DemoMode`) and a thin SwiftUI target (`AgentTacho`)

**Performance Goals**: no extra work; the panel still resizes in one step when Details open

**Constraints**: no em or en dash; logic in `UsageCore` test first; build only through the Makefile; no horizontal scrolling, no visible scrollbar

**Scale/Scope**: 2 view files, 3 to 4 new or changed `UsageCore` files, demo coverage, capture script check, 5 earlier specs amended, 2 docs pages

## Constitution Check

| Principle | Status | How this plan complies |
|---|---|---|
| I. Spec-Driven Development | Pass | Spec 026 with clarifications and two review rounds. |
| II. Test-First, Logic in UsageCore | Pass | `MemberDisplay`, `DayRowTotal`, `FooterErrors`, `StatusTooltip` and the moved compact formatters are `UsageCore` types with tests first; views only render. |
| III. Read-Only, Private by Default | Pass | No credential, network or file access change. |
| IV. One Build Entry Point | Pass | Makefile only. |
| V. Screenshots and Website Follow the UI | Pass with recorded exception | The shots change (details, harnesses, dropdown); by the maintainer's decision of 2026-10-19 they are recaptured in one round after this spec and the headline window switch, before the next release (spec FR-018, idea inbox minimal-dropdown-screenshots). The capture script's crops keep working (T-check in tasks). |

## Screenshots and website

| | |
|---|---|
| Shots that change | `details` and `harnesses` (Σ column, no "This week" line), `dropdown` (one budget Details, status row), `budget` unchanged crop |
| New shots | none |
| Demo scenario | no value change; coverage gains the member display of `default` (two-member group with button) and `variants` (one-member group, no button) |
| Website copy | none beyond the spec 025 round; the `details` card text stays true |
| README image | replaced in the screenshot round (spec 025 deviation) |

## Project Structure

### Documentation (this feature)

```text
specs/026-dropdown-layout-polish/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/dropdown-ui.md   # delta to spec 025's contract
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/Dropdown/
├── MemberDisplay.swift      # new: member lines and member tables of a group (FR-002, FR-003, FR-007)
├── DayRowTotal.swift        # new: Σ value and tooltip (FR-009)
├── CompactFormat.swift      # new: millions and compactUSD moved from the app's UsageFormat
└── FooterText.swift         # + FooterErrors (FR-011) and the status tooltip (FR-013); DetailsTotal removed

Sources/AgentTacho/
├── DropdownView.swift       # pinned footer layout, status row, budget section with one Details
└── BreakdownView.swift      # Σ column, 30 pt columns, member tables behind "Show accounts", no total line

Sources/DemoMode/ScenarioCoverage.swift   # member display in the report
Tests/UsageCoreTests/MemberDisplayTests.swift, DayRowTotalTests.swift, CompactFormatTests.swift, FooterTextTests.swift
Tests/DemoModeTests/DefaultScenarioTests.swift
scripts/screenshots/capture.sh, scripts/release/tests/test_screenshots.sh   # details crop with accounts hidden
docs/usage.md, docs/accounts-and-budgets.md
specs/003, 004, 016, 025 spec.md and specs/025/contracts/dropdown-ui.md   # amendments (FR-016)
```

**Structure Decision**: unchanged three-target layout; new core types in `Sources/UsageCore/Dropdown/`.

## Complexity Tracking

No violations; the screenshot timing is a recorded maintainer exception (Constitution Check V).
