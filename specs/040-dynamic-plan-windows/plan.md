# Implementation Plan: Dynamic Claude Plan Windows

**Branch**: `040-dynamic-plan-windows` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/040-dynamic-plan-windows/spec.md`

## Summary

Claude subscription windows become one ordered list (`SubscriptionStatus.windows: [ClaudeLimit]`) built from the usage endpoint's `limits` array, with the top-level `five_hour` / `seven_day` objects as a lenient fallback. Each window carries a stable identity (`ClaudeWindow`, now a string-backed struct: `fiveHour`, `sevenDay`, `model:<name>`, `model:<name>:<kind>`, `limit:<kind>`), a length from a small group table (nil for unknown groups), and a display name. The dropdown, threshold tracker, pace, burn rate, headline resolution, bar tag, last-good store and demo scenario all iterate the list; the fixed 5-hour row disappears when Anthropic does not report the window. Configuration and last-good files of the previous version keep working, and the last-good file stays readable by the previous version (research R2, R3, R8, R9).

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10), macOS app

**Primary Dependencies**: Foundation, SwiftUI (app layer only); no new dependencies

**Storage**: `~/.config/agenttacho/config.json` (unchanged keys, new `headlineWindow` values); `~/Library/Application Support/agenttacho/last-good.json` (added `windows` key, version 1)

**Testing**: Swift Testing via `make test` (UsageCoreTests, DemoModeTests); `make test-release`

**Target Platform**: macOS menu bar app

**Project Type**: desktop app with library targets (`UsageCore`, `DemoMode`) and a thin SwiftUI target (`AgentTacho`)

**Performance Goals**: none new; parsing a handful of entries per fetch

**Constraints**: read-only towards agent files; no new network request, no new credential access (constitution III); no em or en dashes

**Scale/Scope**: about 15 source files and 20 test files touched (mostly mechanical replacement of `fiveHour` / `sevenDay` accessors)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Issue first, AI welcome, specs | Pass | Maintainer-initiated brainstorm 40 and spec 040; commits carry `Assisted-By` |
| II. Test-first, logic in UsageCore | Pass | Builder, ordering, identity, headline, tags, thresholds, log signature, last-good compatibility in UsageCore with tests first; `DropdownView` only loops over `status.windows` |
| III. Read-only, private by default | Pass | Same request, same token handling; the log and last-good file gain kind and group strings from the answer only (no tokens, no account names). README "Security and privacy" stays true; FR-016 rewords only the feature list. Website privacy section unchanged |
| IV. One build entry point | Pass | `make test`, `make test-release`, `make app-demo` only |
| V. Screenshots and website follow the UI | Pass | See the section below; capture run asked from the maintainer (AGENTS.md step 4) |

Re-check after Phase 1: unchanged, no violations.

## Screenshots and website

| | |
|---|---|
| Shots that change | `glance` (Claude section without 5-hour row, Fable as headline), `menubar` (Claude Max entry `✳ Fable 50%` instead of `✳ 5h 58%`), `menubar-settings` (preview follows the bar), `same-provider` if it shows Claude window rows; the capture writes all 14 files anyway |
| New shots | none |
| Demo scenario | `Resources/demo/default.json`: Claude accounts as `limits` lists, no 5-hour window, `acc-max` headline `model:Fable`; `variants.json` adds an unknown-group window. Coverage test: a Claude account without a 5-hour window shows no 5-hour row; existing level, marker, pace and tag checks keep passing |
| Website copy | site `src/data` entries that say "5-hour and 7-day" for Claude (plan limits card, comparison): reword to "the plan windows Anthropic reports, such as the 7-day window and model limits" |
| README image | replace `docs/images/glance-*.webp` (the dropdown shows a 5-hour row today) and its alt text |

## Project Structure

### Documentation (this feature)

```text
specs/040-dynamic-plan-windows/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── usage-endpoint-limits.md
│   ├── config-and-last-good.md
│   └── dropdown-rows.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Snapshot/UsageSnapshot.swift        # SubscriptionStatus.windows, windowReport, accessors, effective(now:)
├── Subscription/ClaudeLimits.swift     # NEW: ClaudeLimit, group table, names, identities, ordering, builder, report
├── Dropdown/SectionNote.swift          # "No limits reported"
├── Subscription/UsageEndpointClient.swift  # decode limits leniently, top-level fallback leniently, call builder
├── Subscription/SubscriptionSource.swift   # window-set log line, summary line
├── Snapshot/RefreshCoordinator.swift   # "ok(...)" summary line, sevenDay alignment via accessor
├── Snapshot/LastGoodStore.swift        # windows key + legacy keys
├── Pace/ObservationLog.swift           # ClaudeWindow struct
├── Pace/Pace.swift                     # pace(of: ClaudeLimit)
├── Pace/PaceReading.swift, Pace/BurnRate.swift  # iterate windows
├── Notifications/ThresholdTracker.swift        # live keys from status
├── Config/HeadlineChoice.swift, Config/Configuration.swift  # .claude(ClaudeWindow), parse
└── Bar/HeadlineWindow.swift, Bar/BarLayout.swift, Bar/BarPresentation.swift  # resolution, tag, a11y
Sources/DemoMode/
├── Scenario.swift, ScenarioPlayer.swift, DemoSources.swift, ScenarioCoverage.swift
Sources/AgentTacho/
├── DropdownView.swift                  # ForEach over status.windows
└── AccountSettingsView.swift           # wording
Resources/demo/default.json, variants.json
Tests/UsageCoreTests/                   # new ClaudeLimitsTests; existing tests migrated
Tests/DemoModeTests/
docs/usage.md, docs/accounts-and-budgets.md, docs/configuration.md, README.md
specs/001, 010, 025, 027 amendments
```

**Structure Decision**: Existing layout. One new UsageCore file (`ClaudeLimits.swift`) holds the pure list logic so the endpoint client and the demo share it.

## Implementation phases

1. **Core list model (tests first)**: `ClaudeWindow` struct, `ClaudeLimit`, group table, naming, identities, ordering, builder from decoded entries and fallback, duplicate handling (research R2 to R5). Tests with the 2026-11-02 shape, a returning 5-hour group, an unknown group, two weekly kinds, two Fable limits, surface scope, missing kind and group, empty `limits`, fallback only.
2. **Status migration**: `SubscriptionStatus.windows` with accessors and temporary compatibility shims so every task keeps `make test` green; call sites move to the list story by story; the shims are removed at the end (tasks.md "Migration strategy").
3. **Endpoint decoding**: lenient `limits` entries (kind, group, percent, resets_at, scope model/surface, severity, is_active), lenient top-level objects, builder call; log signature and summary line (R10).
4. **Headline and thresholds**: `HeadlineChoice.claude(_)`, parse and stored values; resolution with default rule and fallback; tags and accessibility; threshold live keys from the status (R7, R8).
5. **Last-good**: `windows` key plus legacy keys, read both ways (R9).
6. **UI and wording**: `DropdownView` loops over windows (row type for plan windows and model limits, no pace for nil length), "No limits reported" state; Settings texts (R12).
7. **Demo**: scenario `limits` format, player changes by identity, `DemoSources` through the builder, coverage test update, `default.json` and `variants.json` (R11).
8. **Docs and spec amendments**: docs, README text, specs 001, 010, 025, 027 notes (FR-016, FR-019).
9. **Screenshots and site**: ask the maintainer before the capture run; recapture, review, site pull request (FR-021, AGENTS.md steps 4 to 7). This step needs the maintainer's go and is not done autonomously.

## Complexity Tracking

No constitution violations.
