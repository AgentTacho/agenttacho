# Implementation Plan: Demo build and screenshot capture

**Branch**: `024-demo-mode-screenshots` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/024-demo-mode-screenshots/spec.md`

## Summary

A dev-only "AgentTacho Demo" app plays a JSON scenario through three demo sources (Claude plan windows, Codex limits, usage records) instead of the five real sources, with its own bundle identifier, its own `agenttacho-demo` folders, and no keychain, agent file or network access. A capture script drives it in light and dark appearance and writes the eleven screenshot stems the landing page expects as 22 WebP files. The demo code lives in a new `DemoMode` target that release builds do not link, checked by a symbol guard in `build-app.sh`.

## Technical Context

**Language/Version**: Swift 5.10 package tools (Swift 6.4 toolchain), bash for scripts

**Primary Dependencies**: SwiftUI, AppKit, ApplicationServices (Accessibility), CoreGraphics; `screencapture`, `osascript`, `cwebp`/`dwebp`/`webpmux` (libwebp), ImageMagick in the capture script

**Storage**: JSON scenario files in `Resources/demo/`; demo `config.json`, `imported-prices.json` and log under `agenttacho-demo` folders

**Testing**: Swift Testing via `make test` (new `DemoModeTests`); bash tests with stubs via `make test-release`

**Target Platform**: macOS 14+ on Apple Silicon; the capture needs a 2x main display

**Project Type**: desktop menu bar app with core library, release tooling and a dev script

**Performance Goals**: frames apply within 2 s of their offset (FR-012); a full capture under 5 minutes (SC-001)

**Constraints**: no demo code in release builds (FR-003); README "Security and privacy" unchanged (FR-024); no em or en dash; never write to the agents' files

**Scale/Scope**: one new target (about 8 files), small `#if AGENTTACHO_DEMO` blocks in 4 app files, `Paths` and `UpdateState` changes, accessibility identifiers on 6 views, 2 build scripts, 1 capture script with a Swift helper, 2 scenario resources

## Constitution Check

The constitution file is an unfilled template, so the gates come from AGENTS.md:

| Gate | Status |
|---|---|
| Build and test only through the Makefile | Pass: `make app-demo`, `make test`, `make test-release`; the capture script runs `make app-demo` itself |
| Logic in a tested core target, test first | Pass with a justified deviation: logic goes into the new core target `DemoMode`, not `UsageCore` (see Complexity Tracking); the app keeps thin `#if` blocks |
| Doc comments cite spec requirements | Pass: new code cites `spec 024 FR-0xx` |
| No em or en dash | Pass: enforced by review |
| Read-only toward agents' files; README security section true | Pass: the demo build reads no agent files; release builds are unchanged, so the section stays as is |

Re-check after design: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/024-demo-mode-screenshots/
├── spec.md
├── plan.md                    # this file
├── research.md                # R1 to R12
├── data-model.md
├── contracts/
│   ├── scenario-format.md
│   └── capture-cli.md
├── quickstart.md              # Q1 to Q8
├── checklists/requirements.md
└── tasks.md                   # /speckit-tasks
```

### Source Code (repository root)

```text
Package.swift                                # + target DemoMode, + test target DemoModeTests
Sources/
├── DemoMode/                                # NEW (research R2)
│   ├── Scenario.swift                       # Codable model, validation, ScenarioError
│   ├── ScenarioDuration.swift               # "2h10m", "-3d"
│   ├── ScenarioPlayer.swift                 # frames over time
│   ├── DemoSources.swift                    # DemoSubscriptionSource, DemoCodexLimitsSource, DemoRecordSource
│   ├── DemoSetup.swift                      # writes config and prices, sources list, frame offsets, NoCredentials
│   └── ScenarioCoverage.swift               # coverage evaluation used by tests
├── UsageCore/
│   ├── Config/Paths.swift                   # appFolder parameter
│   └── Update/UpdateState.swift             # .demoBuild
└── AgentTacho/
    ├── App.swift                            # #if AGENTTACHO_DEMO wiring, frame refreshes, bar render
    ├── Updater.swift                        # demo early return
    ├── AboutSettingsTab.swift               # "Build: Demo" row
    ├── DropdownView.swift, BreakdownView.swift, BarLabel.swift  # accessibility identifiers
    └── NotificationPresenter.swift          # logs the authorization result (if not already)
Tests/DemoModeTests/                         # NEW: loader, durations, player, sources, coverage, names
Resources/demo/
├── default.json                             # NEW: the story
└── litellm-prices.json                      # NEW: made-up LiteLLM-format prices
scripts/
├── release/build-app.sh, lib.sh, release.sh # DEMO flag, identity, scratch path, symbol guard
├── release/tests/test_build_scripts.sh, test_makefile.sh, run.sh, test_screenshots.sh
└── screenshots/
    ├── capture.sh                           # NEW
    └── uihelper.swift                       # NEW
Makefile                                     # app-demo; app unsets DEMO
README.md                                    # development section (FR-024)
```

**Structure Decision**: Keep the two existing targets and add `DemoMode` beside `UsageCore`. The executable depends on it, references it only under the flag, and the release guard proves it is stripped.

## Implementation approach

1. **Paths and UpdateState** (UsageCore, tests first): `appFolder` with the default unchanged; `.demoBuild` texts.
2. **DemoMode model** (tests first): durations, scenario decoding and validation with JSON paths, the player, the three sources, the monthly clamp (R6), pricing like `SessionLogSource`.
3. **Default scenario and coverage** (tests first): `ScenarioCoverage` and the coverage test for three launch dates; then tune `Resources/demo/default.json` until it passes. Names test (FR-015). Source-list check (SC-002).
4. **Build** (tests first in `scripts/release/tests`): `DEMO` in Makefile, `build-app.sh` (scratch path, identity, resources, combination refusal, symbol guard), `release.sh` refusal, runner unset.
5. **App wiring** under `#if AGENTTACHO_DEMO`: paths, no credential reader, no last good store, demo sources, frame refreshes, updater, login item, credential notifications, LiteLLM preview from the bundle, About row, launch log line, `-demoRenderBar`. Accessibility identifiers in all builds.
6. **Capture**: `uihelper.swift`, `capture.sh`, `test_screenshots.sh` with stubs first.
7. **Docs**: README development section.
8. **Manual**: Q2 to Q8 on the maintainer's Mac.

## Risks

| Risk | Mitigation |
|---|---|
| The demo target links into release builds | `.build/demo` scratch path, `#if` around every use, `nm` guard in `build-app.sh` with a test |
| macOS UI scripting breaks on an OS update (status item owner, banner window) | Status item through Accessibility, banner by pid and layer, all in one helper with clear errors |
| Captures run on the 1st of a month show an empty budget | Monthly clamp (R6), coverage test on the 1st |
| Notification banner hidden by Focus or missing permission | Preflight reads the demo log; `--first-run`; a missing banner fails the run, never a partial set |
| Appearance left in the wrong state | Trap on EXIT, INT, TERM; covered by `test_screenshots.sh` |
| Card crops cut UI | Crops come from accessibility frames; Q8 review |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Logic in a new core target `DemoMode` instead of `UsageCore` | Release binaries must not contain demo code (FR-003); a separate target makes this a precise, testable symbol check | Demo types in `UsageCore` would ship in every release; `#if` in `UsageCore` would make `make test` test a different build than the release |
