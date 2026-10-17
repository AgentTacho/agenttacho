# Implementation Plan: About Tab Update Layout

**Branch**: `020-about-tab-update-layout` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/020-about-tab-update-layout/spec.md`

## Summary

A layout change in two SwiftUI views plus documentation. `AboutSettingsTab.updates` drops the "Updates" heading and the toggle, and stacks the centered "Check for Updates…" button above the status line(s), which use body-size secondary text; the action buttons keep their link style. `AboutSettingsTab.releaseGrid` drops the Signing row, and the tab loses its `draft` binding. `GeneralSettingsTab` gains a `Section("Updates")` with the toggle bound to `draft.checksForUpdates`, right after `Section("Launch")`. `AppVersionInfo.Signing` and its `text` stay, for `UpdatePolicy` and the diagnostic log; only the `AppVersionInfo` doc comment changes (research R1 to R3). Spec 013 (spec and `contracts/update-ui.md`) and the README are updated to the new places (FR-011, FR-012).

## Global Constraints

- Build and test only with `make test`, `make app`.
- Doc comments cite `spec 020 FR-...` where they describe the new layout; no em or en dash characters.
- No change to `UsageCore` update logic, the configuration format, or the dropdown.

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10)

**Primary Dependencies**: SwiftUI (Settings tabs); no new dependencies

**Storage**: unchanged (`checksForUpdates` in the configuration file)

**Testing**: Swift Testing via `make test`; the layout itself is checked by hand (quickstart.md)

**Target Platform**: macOS 14 or newer, Apple Silicon

**Project Type**: desktop menu bar app (`UsageCore` library plus thin `AgentTacho` executable)

**Performance Goals**: not applicable

**Constraints**: `Sources/AgentTacho` stays a thin view layer; no new logic is needed

**Scale/Scope**: two views, one doc comment, three documents

## Constitution Check

`.specify/memory/constitution.md` is still the unfilled template, so the project rules in `AGENTS.md` serve as the gate:

| Rule | Status |
|---|---|
| Build and test only through the Makefile | Pass |
| Logic in `UsageCore`, covered by tests, test first | Pass: no new logic; the only `UsageCore` change is a doc comment (research R2) |
| Doc comments cite spec requirements | Pass |
| No em or en dashes | Pass |
| Read-only on agent files; Security and privacy section stays true | Pass: no credential or network change; the README's update bullet is reworded to name Settings > General (FR-012) |

Post-design re-check: unchanged, pass.

## Project Structure

```text
specs/020-about-tab-update-layout/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/settings-ui.md
├── checklists/requirements.md
└── spec.md

Sources/AgentTacho/AboutSettingsTab.swift     # updates block, release grid, no draft binding
Sources/AgentTacho/SettingsView.swift         # call site; General gets the Updates section
Sources/UsageCore/AppVersionInfo.swift        # doc comment only
specs/013-auto-update/spec.md                 # FR-002, FR-011, US4 narrative and scenario 1
specs/013-auto-update/contracts/update-ui.md  # Settings > About section, new Settings > General section
specs/013-auto-update/RUNBOOK.md              # walkthrough step that turns the toggle off
README.md                                     # six passages (FR-012)
```

**Structure Decision**: edits only, no new source files. `contracts/settings-ui.md` fixes the layout of both tabs for review and the walkthrough.

## Complexity Tracking

No violations.
