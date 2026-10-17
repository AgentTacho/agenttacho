# Implementation Plan: Account Budget Subtitle

**Branch**: `018-account-budget-subtitle` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-account-budget-subtitle/spec.md`

## Summary

A new pure `UsageCore` type, `AccountBudgetDescription`, describes a token-based account's budget for the Settings lists: provider name, budget kind (group with icon id and name, own budget, missing group), and the amount text. A shared `BudgetAmountFormatter` renders "$400 / month" style amounts (whole dollars when the cent-rounded amount is whole, exactly two decimals otherwise, locale-aware currency). `AccountSettingsView` builds its subtitle from the description, drawing only the group icon with `labelText`, and sets a VoiceOver label without the glyph; `GroupSettingsView` uses `GroupListSubtitle`, built on the same formatter (research R1 to R3). Interfaces are fixed in tasks.md.

## Global Constraints

- Build and test only with `make test`, `make app`.
- Tests pin `Locale(identifier: "en_US")` for literal strings.
- Doc comments cite `spec 018 FR-...`; no em or en dash characters.

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10)

**Primary Dependencies**: Foundation (`FormatStyle`), SwiftUI for the two list rows; no new dependencies

**Storage**: none

**Testing**: Swift Testing via `make test`

**Target Platform**: macOS 14 or newer, Apple Silicon

**Project Type**: desktop menu bar app (`UsageCore` library plus thin `AgentTacho` executable)

**Performance Goals**: negligible (one string per list row per render)

**Constraints**: logic in `UsageCore` with tests first; tests pin the locale (en_US); no em or en dashes

**Scale/Scope**: two subtitles, one formatter, one description type

## Constitution Check

`.specify/memory/constitution.md` is still the unfilled template, so the project rules in `AGENTS.md` serve as the gate:

| Rule | Status |
|---|---|
| Build and test only through the Makefile | Pass |
| Logic in `UsageCore`, covered by tests, test first | Pass: description and formatter in `UsageCore`, tests first; the view only composes text and draws the icon |
| Doc comments cite spec requirements | Pass |
| No em or en dashes | Pass |
| Read-only on agent files; Security and privacy section stays true | Pass: no credential, network or file change |

Post-design re-check: unchanged, pass.

## Project Structure

```text
specs/018-account-budget-subtitle/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
└── spec.md

Sources/UsageCore/Config/AccountBudgetDescription.swift   # new: description + BudgetAmountFormatter
Sources/AgentTacho/AccountSettingsView.swift              # subtitle(account) and GroupSettingsView row use them
Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift  # new
```

**Structure Decision**: one new `UsageCore` file next to the configuration types it reads; no new targets. Contracts are not needed (no external interface).

## Complexity Tracking

No violations.
