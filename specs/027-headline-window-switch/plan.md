# Implementation Plan: Headline Window Switch

**Branch**: `027-headline-window-switch` | **Date**: 2026-10-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/027-headline-window-switch/spec.md`

## Summary

A click on a Claude or Codex window row makes it the account's headline window, stored as `headlineWindow` with the account. A new `UsageCore` type `HeadlineWindow` resolves the window in effect (choice, fallback for vanished dynamic windows) and gives the bar entry and the section header their percent, level, markers, tag and accessibility name; `BarItem` gains `tag` and `windowName`, and `BarPresentation` and `BarLabel` draw the tag after the icon. The dropdown rows get a marker slot with `●`, a hover state and a tap gesture; the app saves the new configuration without a refresh, and the Settings window keeps choices made in the dropdown (research R1 to R9).

## Technical Context

**Language/Version**: Swift (tools version 5.10, Swift Package Manager `Package.swift`), macOS 14 target

**Primary Dependencies**: SwiftUI and AppKit (app layer), Foundation (`UsageCore`); no new dependency

**Storage**: one optional account field `headlineWindow` in `config.json` (contracts/config-file.md); no `UserDefaults` change

**Testing**: Swift Testing through `make test` (`Tests/UsageCoreTests`, `Tests/DemoModeTests`) and `make test-release`

**Target Platform**: macOS menu bar app (MenuBarExtra window, always dark panel, 360 pt wide)

**Project Type**: desktop app with a core library (`UsageCore`), a demo library (`DemoMode`) and a thin SwiftUI target (`AgentTacho`)

**Performance Goals**: a click updates the bar and the dropdown in the same frame; no refresh, no network

**Constraints**: no em or en dash; logic in `UsageCore` test first; build only through the Makefile; files of the previous version load unchanged

**Scale/Scope**: 1 new and 4 changed `UsageCore` files, 4 app files, demo scenario and coverage, 5 earlier specs amended, 2 docs pages

## Constitution Check

| Principle | Status | How this plan complies |
|---|---|---|
| I. Spec-Driven Development | Pass | Spec 027 with clarifications and one review round. |
| II. Test-First, Logic in UsageCore | Pass | `HeadlineChoice`, `HeadlineWindow`, the `BarLayout` and `BarPresentation` changes, `Configuration.settingHeadline` and `keepingHeadlineChoices` get tests first; views only render and forward taps. |
| III. Read-Only, Private by Default | Pass | Only AgentTacho's own `config.json` is written; no agent file, credential or network change. |
| IV. One Build Entry Point | Pass | Makefile only. |
| V. Screenshots and Website Follow the UI | Pass with recorded exception | Demo scenario and coverage change in this pull request; the shots are recaptured in the shared round after spec 026 and this spec, by the maintainer's decision of 2026-10-19 (spec 026 FR-018, spec FR-016), before the next release. |

## Screenshots and website

| | |
|---|---|
| Shots that change | `menubar` (tag), `menubar-settings` (preview tag), `plan-limits` (marker slot, `●` on 5-hour, header tag), `pace` (marker slot), `dropdown` |
| New shots | none (the switch lives in the existing plan-limits card) |
| Demo scenario | `acc-max` gets `"headlineWindow": "fiveHour"`; coverage test: tag "5h" in the bar, headline row 5-hour, existing level, marker and pace checks still pass (values tuned if needed) |
| Website copy | `features.ts` "Plan limits": click a window to show it in the menu bar; in the shared screenshot round |
| README image | replace in the shared screenshot round (dropdown changed) |

## Project Structure

### Documentation (this feature)

```text
specs/027-headline-window-switch/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/config-file.md, contracts/bar-and-dropdown.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/Config/
├── HeadlineChoice.swift     # new: the stored choice, parse and encode (FR-010)
└── Configuration.swift      # headlineWindow in both subscription settings, Account coding, dataRelevant, settingHeadline, keepingHeadlineChoices

Sources/UsageCore/Bar/
├── HeadlineWindow.swift     # new: resolution, tag, accessibility name (FR-005 to FR-009)
├── BarLayout.swift          # subscriptionItem and codexItem via HeadlineWindow; BarItem.tag, windowName
└── BarPresentation.swift    # tag part and accessibility text

Sources/AgentTacho/
├── BarLabel.swift           # draws the tag after the icon
├── DropdownView.swift       # headers via HeadlineWindow; LimitRowLayout marker slot, hover, tap, accessibility
├── App.swift                # AppModel.setHeadline(accountId:choice:)
└── SettingsView.swift       # keeps dropdown choices in applyNow and onChange

Sources/DemoMode/ScenarioCoverage.swift   # barTags, headlineRows
Resources/demo/default.json               # headlineWindow on acc-max
Tests/UsageCoreTests/HeadlineWindowTests.swift (new), HeadlineChoiceTests.swift (new), BarLayoutTests.swift, BarPresentationTests.swift, ConfigurationTests.swift
Tests/DemoModeTests/DefaultScenarioTests.swift
docs/usage.md, docs/configuration.md
specs/001, 007, 011, 017 spec.md and specs/025/contracts/dropdown-ui.md   # amendments (FR-014)
```

**Structure Decision**: unchanged three-target layout; the choice next to the configuration types, the resolution next to the bar layout.

## Complexity Tracking

No violations; the screenshot timing is a recorded maintainer exception (Constitution Check V).
