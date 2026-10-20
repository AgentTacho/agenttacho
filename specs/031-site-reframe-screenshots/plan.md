# Implementation Plan: Site Reframe Screenshots

**Branch**: `031-site-reframe-screenshots` | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/031-site-reframe-screenshots/spec.md`

## Summary

The landing page's six-card grid needs two new images and drops six old ones. The demo scenario gets a second Claude Max account; the app marks the first and second Claude Max sections (and the first one's details) for the capture; `capture.sh` captures `same-provider` and `glance` with a measured uniform margin and an aspect check, drops six stems and the whole notification setup; the release tests, the coverage tests, `AGENTS.md` and `docs/website.md` follow. Which accounts are "first" and "second" is decided in `UsageCore` (test first); the SwiftUI layer only attaches identifiers.

## Technical Context

**Language/Version**: Swift 6 (app, UsageCore, DemoMode), POSIX shell with awk (capture and release tests)

**Primary Dependencies**: SwiftUI, swift-testing; ImageMagick (`magick`), libwebp tools, the repository's `uihelper` (accessibility frames, presses, scroll)

**Storage**: demo scenario JSON (`Resources/demo/default.json`)

**Testing**: `make test` (UsageCore and DemoMode tests), `make test-release` (shell tests with stubbed tools)

**Target Platform**: macOS 14+, Apple Silicon

**Project Type**: desktop app (menu bar) plus release scripts

**Performance Goals**: none beyond today's capture (fewer images, one extra scroll per crop)

**Constraints**: no visible change in the real app; no real accounts in any image; no notification setup needed for the capture

**Scale/Scope**: one scenario file, two Swift views, one UsageCore function, one capture script, two test files, two docs

## Constitution Check

| Principle | Status |
|---|---|
| I. Spec-driven | Spec 031 with clarifications and review; doc comments cite `spec 031 FR-xxx`. |
| II. Test first, logic in UsageCore | The choice of the first and second Claude Max account is a `BarLayout` function with tests before the view uses it. The margin and aspect rule lives in `capture.sh` (like the existing `crop`), covered by release tests written first. |
| III. Read-only, private | Demo data only, invented names (`demoFilesUseInventedNamesOnly` still passes); no credential or network change, so no README or site privacy update. |
| IV. One build entry point | Only `make test`, `make test-release`, `make app-demo`. |
| V. Screenshots and website | Section below; the capture run itself waits for the maintainer (AGENTS.md step 4). |

No violations; no complexity tracking needed.

## Screenshots and website

| | |
|---|---|
| Shots that change | `menubar` (a fifth entry, the second Claude Max account), `budget` (same row, possibly different position in the window) |
| New shots | `glance`, `same-provider` |
| Dropped shots | `plan-limits`, `pace`, `details`, `groups`, `alert`, `dropdown` |
| Demo scenario | second Claude Max account "Claude Max · Personal" (`~/.claude-personal`, 5-hour 20%, 7-day 35%, on pace, a few usage records) after the renamed "Claude Max · Work"; coverage test: two Claude Code subscriptions with different directories, adjacent, both in the bar, non-empty details for the first, second calm and on pace |
| Website copy | none here; the site's phase-2 pull request swaps the placeholders for `glance` and `same-provider`, deletes the dropped pairs, sizes the two card image areas from the printed pixel sizes and updates `tests/page.test.ts` |

## Design

### App (Sources)

- `UsageCore/Bar/BarLayout.swift`: `shotClaudeAccountIds(configuration:) -> [String]`, the ids of the first two Claude subscription accounts in arrangement order (spec 031 FR-010a). Tests in `Tests/UsageCoreTests` (order, fewer than two, Codex subscriptions and token accounts ignored, a group between them).
- `AgentTacho/DropdownView.swift`: `SubscriptionSection` gets an optional `shotIdentifier` (`agenttacho.claudeSection` for the first, `agenttacho.claudeSection2` for the second, nil otherwise), applied with `shotContainer` to the section's outer `VStack`, and passes `agenttacho.claudeDetails` to its `BreakdownView` for the first account only. The `agenttacho.claudePlan` container and the `agenttacho.paceRow` identifier go (only the dropped stems used them).
- `AgentTacho/BreakdownView.swift`: the shot identifier becomes a value (`shotIdentifier: String?`) instead of `isShotTarget`, so budgets pass `agenttacho.details` and the first Claude section passes `agenttacho.claudeDetails`.

### Demo scenario

`Resources/demo/default.json`: rename `acc-max` to "Claude Max · Work"; add `acc-max-personal` ("Claude Max · Personal", `claudeCode`, `credentialDirectory` `~/.claude-personal`, `shownInBar` true, thresholds 80/100); arrangement `acc-max, acc-max-personal, acc-codex, grp-company, acc-side`; plan data `max`, 5-hour 20% resetting in 2h30m, 7-day 35% resetting in 3d12h (both at or below elapsed time, so on pace); four usage records over the week (Opus and Sonnet, `~/src/side-quest` style invented projects).

### Capture (`scripts/screenshots/capture.sh`)

- `STEMS="menubar budget harnesses prices menubar-settings glance same-provider"`.
- New `fill_crop <image> <window> <region> <out>`: computes the uniform margin `m = min(left, top, right, bottom distance to the window, 4% of the region's shorter side)` in points (4% of the region's shorter side is never more than 4% of the image's), fails when `m*2 < 4` px or the aspect of `(w+2m):(h+2m)` lies outside 3:4 to 4:3, otherwise crops `(w+2m)x(h+2m)` at 2x. Its arithmetic is one awk program, like `crop`.
- New `union <frame> <frame>`: the bounding frame of two frames.
- Dropdown order (FR-010b): open dropdown; `scrollto agenttacho.claudeSection`; capture window; `same-provider` = `fill_crop` of the union of `claudeSection` and `claudeSection2`; press `agenttacho.claudeDetails`, press `Models`, `scrollto agenttacho.claudeSection`, capture, `glance` = `fill_crop` of `claudeSection`; press `agenttacho.claudeDetails` again to collapse; `scrollto agenttacho.budgetRow`, capture, `budget` = `crop` of the row (scroll added: with five sections the row may sit below the height cap); then `harnesses` as today (press `agenttacho.details`, `Harnesses`, scroll, capture, crop) and press `Models` to restore.
- Settings: `menubar-settings` and `prices` stay; the Groups tab capture goes.
- Removed: the `alert` block, `check_notifications`, the notification part of `preflight`, `first_run`, the `--first-run` argument and its usage text, `PERMISSION_TIMEOUT`/`SETTINGS_TIMEOUT` if unused, the NotificationCenter `pgrep`.

### Tests and docs

- `scripts/release/tests/test_screenshots.sh`: `STEMS` updated; the uihelper stub returns distinct frames for `claudeSection`, `claudeSection2` and the window so the `fill_crop` geometry is asserted exactly; new tests for the order (same-provider before the details press, collapse before `harnesses`), scroll before each new capture, a failing aspect, a margin below 4 px; the 22-file test becomes 14; first-run, banner-style and permission tests are removed.
- `Tests/DemoModeTests/DefaultScenarioTests.swift`: the shot-list test drops the `pace` attention row comment and keeps the attention row (the glance shot shows it), updates `headlineRows`, and adds the two-account checks; the band test expects five stripes; a new test `secondClaudeAccountIsCalm` checks levels, pace state and the 15-point difference at the last frame.
- `AGENTS.md`, `docs/website.md`: counts, stem list, card and strip wording, capture setup.

## Project Structure

### Documentation (this feature)

```text
specs/031-site-reframe-screenshots/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/capture-stems.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/Bar/BarLayout.swift
Sources/AgentTacho/DropdownView.swift
Sources/AgentTacho/BreakdownView.swift
Resources/demo/default.json
Tests/UsageCoreTests/BarLayoutShotTests.swift      (new or added to an existing BarLayout test file)
Tests/DemoModeTests/DefaultScenarioTests.swift
scripts/screenshots/capture.sh
scripts/release/tests/test_screenshots.sh
AGENTS.md
docs/website.md
```

**Structure Decision**: existing layout; no new targets.

## Complexity Tracking

None.
