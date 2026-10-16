# Implementation Plan: Pace Line Names the Plan

**Branch**: `019-pace-line-names-plan` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/019-pace-line-names-plan/spec.md`

## Summary

`RefreshPaceStatus` gains the list of plans the line is about (`plans: [PacedEndpoint]`, empty for timer reasons). `AdaptivePace.status(now:)` fills it with the stretched endpoints in the fixed order Claude, Codex. `RefreshPaceStatus.text` names them: one plan gives "<Plan> limits next checked at <time> (no <Agent> activity)", both give "Claude and Codex limits next checked at <time> (no agent activity)"; timer reasons keep today's text. `PacedEndpoint` gets `planName` and `agentName`. The dropdown lets the line wrap instead of truncating it (research R1 to R3).

## Global Constraints

- Build and test only with `make test`, `make app`.
- Tests use the file's `calendar` (Gregorian, UTC) and `locale` (`en_GB`, 24 hour) helpers, plus one `en_US` 12 hour case.
- Doc comments cite `spec 019 FR-...`; no em or en dash characters.

## Technical Context

**Language/Version**: Swift 5.10

**Primary Dependencies**: Foundation, SwiftUI (one `Text` modifier); no new dependencies

**Storage**: none

**Testing**: Swift Testing via `make test` (`RefreshPaceStatusTests`, `AdaptivePaceTests`)

**Target Platform**: macOS 14 or newer, Apple Silicon

**Project Type**: desktop menu bar app (`UsageCore` plus thin `AgentMeter`)

**Constraints**: logic in `UsageCore`, tests first

**Scale/Scope**: two `UsageCore` types, one view modifier, one contract row

## Constitution Check

`.specify/memory/constitution.md` is the unfilled template; `AGENTS.md` is the gate:

| Rule | Status |
|---|---|
| Makefile only | Pass |
| Logic in `UsageCore`, tests first | Pass: wording in `RefreshPaceStatus`, plan selection in `AdaptivePace`; the view only renders and wraps |
| Doc comments cite specs | Pass |
| No em or en dashes | Pass |
| Agent files, credentials, network | Pass: untouched |

Post-design re-check: unchanged, pass.

## Project Structure

```text
Sources/UsageCore/Snapshot/RefreshPaceStatus.swift   # plans field, new wording
Sources/UsageCore/Snapshot/AdaptivePace.swift        # PacedEndpoint names, status(now:) fills plans
Sources/AgentMeter/DropdownView.swift                # pace line wraps (no lineLimit(1))
Tests/UsageCoreTests/RefreshPaceStatusTests.swift    # L2 updated, new cases
Tests/UsageCoreTests/RefreshCoordinatorTests.swift   # paceStatusNamesTheNextPlanLimitCheck expects plans: [.claude]
specs/016-adaptive-refresh/contracts/refresh-pace.md # row L2 points to spec 019
```

**Structure Decision**: existing files only.

## Complexity Tracking

No violations.
