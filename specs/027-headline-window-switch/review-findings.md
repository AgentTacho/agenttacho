# Deep Review Findings

**Date:** 2026-10-19
**Branch:** 027-headline-window-switch
**Rounds:** 2 (initial review, fix round 1, fix round 2)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 17 | 12 | 5 |
| Notable | 3 | 1 | 2 |
| **Total** | **22** | **15** | **7** |

**Agents completed:** 5/6 (Goal Alignment skipped: no pull request yet) + 2 external tools (CodeRabbit, Codex); Copilot disabled in config.
**Agents failed:** none. The first CodeRabbit call used `--files`, which CLI 0.7.6 no longer has; it was rerun with `--base main --committed` (spec artifacts in its file list were not reported on).

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/App.swift:292-309 (with Sources/UsageCore/Config/ConfigStore.swift:97-104)
- **Category:** production-readiness
- **Source:** production-readiness agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit cbe2970)

**What is wrong:** `setHeadline` built the new configuration from `AppModel.configuration`, the copy from the last refresh, and saved it with `ConfigStore.save`. Hand edits are read only at the next refresh, so a click between a hand edit and that refresh wrote the old copy plus the click over the edit. A broken file the user was fixing was replaced with the last valid configuration. `save` then stored the new modification date, so nothing noticed or logged the loss.

**Why this matters:** silent loss of the user's own file edit, made likely because the dropdown shows the invalid-file error and the user then clicks a row.

**How it was resolved:** new `ConfigStore.update(_:)` in UsageCore reads the file (only when its date changed), applies the change and writes under one lock; a read error (broken file, file gone after a load) is thrown and nothing is written; an unchanged result writes nothing. `setHeadline` uses it. Tests: `updateKeepsAHandEditMadeSinceTheLastRead`, `updateLeavesABrokenFileAlone`, `updateWithoutAChangeWritesNothing`, `updateDoesNotRecreateAMissingFile`, `updateKeepsTheLoadNotesOfAHandEdit`.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/App.swift:302
- **Category:** external
- **Source:** codex (round 1 re-review)
- **Round found:** 2
- **Resolution:** fixed (round 2, commit 6457996)

**What is wrong:** after the FINDING-1 fix, `setHeadline` assigned the whole configuration read from disk to `AppModel.configuration`. A hand edit found there was adopted without the side effects `saveConfiguration` and the refresh path apply (timer re-arm, login item, updater).

**Why this matters:** the app could show an edited configuration while running with the old settings until the next refresh.

**How it was resolved:** the in-memory configuration now takes only the click (`configuration.settingHeadline(...)`); the hand edit stays in the file and the next refresh's `apply(_:)` picks it up with its side effects, as before this spec.

**External tool analysis (Codex):**
> If the config file was hand-edited since the last refresh, this assigns the entire disk configuration but skips the side effects in `saveConfiguration` (such as restarting the timer when `refreshIntervalSeconds` or `adaptiveRefresh` changed, and applying login or updater settings). The app can then display the edited configuration while continuing to run with stale settings.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/App.swift:303-305
- **Category:** security
- **Source:** security agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit cbe2970)

**What is wrong:** the log line of a click wrote the stored value unclipped; a model name comes from the provider and has no length limit. **Why it matters:** the project rule (spec 012 FR-003) keeps free-form values in the log to 32 characters. **Resolution:** the line uses `Configuration.clipped`, now public.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Pace/Pace.swift:208-211, 245-255; Sources/UsageCore/Snapshot/UsageSnapshot.swift:53-57
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 8e1258e), partly

**What is wrong:** the doc comments of `sevenDayPace`, `barWindow` and `SubscriptionStatus.barPercent` still stated the pre-027 rule ("the bar marker follows it", "the 5-hour window never stands in"). `CodexLimitsEntry.barPercent(now:)` and `barPace(now:)` have no production callers left. **Resolution:** the three comments now name the headline rule (spec 027 FR-005, FR-007). The two unused helpers were removed during verification (846eda0); their tests now check the default window through `HeadlineWindow.codex`.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Bar/HeadlineWindow.swift:124-136, 175-179
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 8e1258e)

**What is wrong:** the Codex default window was defined twice (`windows.last` in `codex(...)`, `barWindow` in `choice(forCodex:)`). **Why it matters:** if one changed, the `●` row and the clear-on-click rule would disagree. **Resolution:** both use `entry.barWindow(now:)`.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift:175-189; Sources/DemoMode/ScenarioCoverage.swift:95-113; Sources/UsageCore/Bar/BarLayout.swift:166, 195
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** three call sites each pick the snapshot inputs for `HeadlineWindow.claude` / `.codex`; the dropdown's copy is untested SwiftUI code. **What is needed:** an optional `HeadlineWindow.resolve(account:snapshot:)` in UsageCore used by all three. Mechanical refactor; behavior is the same today.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Bar/BarLayout.swift:171-186; Sources/UsageCore/Bar/HeadlineWindow.swift:112-117
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** the "no tag before the first values or when not signed in" rule is written in both `BarLayout.subscriptionItem` and `HeadlineWindow.header`. Both are tested and agree. **What is needed:** optionally take the bar tag from `HeadlineWindow.header(...)?.tag`. Mechanical.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Bar/BarPresentation.swift (accessibilityText); Sources/UsageCore/Bar/HeadlineWindow.swift (`isDefault`)
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `windowName` is gated on `tag != nil` twice, and `ResolvedHeadline.isDefault` is read only by tests. Redundant but harmless. Mechanical.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/HeadlineChoice.swift:76-90
- **Category:** architecture
- **Source:** architecture agent (also reported by: test-quality agent)
- **Round found:** 1
- **Resolution:** partly fixed (round 1, commit 8e1258e: round-trip test added); conformance kept

**What is wrong:** the `Codable` conformance exists only to keep the settings structs' synthesized `Codable` compiling; it throws on unknown values, unlike the tolerant `Account` decoding. **Resolution:** a round-trip and throw test now pins its behavior. Dropping `Codable` from `SubscriptionSettings` / `CodexSubscriptionSettings` and the conformance is an optional cleanup.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/DropdownView.swift:595-600, 623-628, 668-673, 1056-1061
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** the switch is passed as `isHeadline: Bool?` plus `onSelect: (() -> Void)?` through four views. **What is needed:** optionally one `HeadlineSwitch?` value. Mechanical.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/DropdownView.swift (LimitRowLayout `@State isHovered`)
- **Category:** production-readiness
- **Source:** production-readiness agent (also noted below threshold by the correctness agent)
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** the MenuBarExtra keeps its content alive between openings. If the panel closes while the pointer is on a non-headline row (Esc, Cmd-Tab), `onHover(false)` may never arrive, so the row can show the highlight and `○` on the next opening until the pointer crosses it. **What is needed:** reset `isHovered` when the panel closes (pass the dropdown's `isOpen` down, or listen for `didResignKeyNotification`). Needs a check in the real app during the walkthrough, since whether AppKit sends the exit event is not visible from the code.

### FINDING-12 to FINDING-17
- **Severity:** Minor
- **Category:** test-quality
- **Source:** test-quality agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 8e1258e)

1. Tautological assertions in `modelLimitFallsBackAndReturns` and `codexWindowFallsBack` (a value-type configuration compared with itself): removed; the recovery assertions prove FR-006.
2. No Codex negative for level and fast burn: `codexLevelAndBurnFollowTheHeadline`.
3. The 7-day critical rule untested with "5h --" and with a reset 7-day window: `sevenDayCriticalRuleEdges`.
4. Reset windows at 0% only tested for the Claude 5-hour resolver; a stored Codex choice that became the only window untested: `resetModelLimitShowsZeroWithTag`, `resetFiveHourWindowShowsZeroWithTag`, `chosenWindowBecomesTheOnlyOne`.
5. The demo coverage test did not check the Claude Max value under the tag: `CoverageReport.barValues`, `barValues["acc-max"] == "58%"`.
6. `HeadlineChoice` `Codable` untested: `codableRoundTrip` (see FINDING-9).

### FINDING-18, FINDING-19
- **Severity:** Minor
- **Category:** correctness / test-quality
- **Source:** re-review agent (fix round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2, commit 6457996)

1. When `update` returned nil, `setHeadline` left the in-memory configuration alone even if the click changed it there: resolved by the FINDING-2 change (the in-memory choice is set independently of the write).
2. `ConfigStore.update`'s comment ignored the first-launch case (no load yet: the default file is created first) and two paths had no tests: comment corrected; `updateDoesNotRecreateAMissingFile` and `updateKeepsTheLoadNotesOfAHandEdit` added.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Bar/HeadlineWindow.swift
- **Category:** architecture
- **Source:** architecture agent
- **Description:** about half of `HeadlineWindow` serves the dropdown, but it lives under `Bar/`.
- **Rationale:** worth a neutral folder or a split if it grows. Captured as `headline-window-module-placement`.

### NOTABLE-2
- **File:** Sources/AgentTacho/SettingsView.swift:96-103
- **Category:** correctness
- **Source:** re-review agent
- **Description:** while Settings has unapplied edits, a hand edit picked up by a refresh is carried over only for the headline choices, so the next Settings apply writes over the rest of it.
- **Rationale:** older than this spec. Captured as `settings-pending-edit-overwrites-hand-edit`.

### NOTABLE-3 (addressed)
- **File:** Sources/UsageCore/Config/ConfigStore.swift (`update`)
- **Category:** correctness
- **Source:** re-review agent
- **Description:** the `change` closure runs under the non-recursive lock and must not call into the store. Documented in the doc comment.

## Goal Alignment

Skipped: no pull request exists for the branch yet.

## Post-Fix Spec Coverage

No implementation code was removed by the fix rounds (only two tautological test assertions). All FR-001 to FR-016 remain implemented as recorded in REVIEW-CODE.md.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (1629 + 64) |
| 1 | make test | 0 | 0 | passed (1638 + 64) |
| 2 | make test | 0 | 0 | passed (1640 + 64) |

`make test-release`: 252 passed (baseline and after round 1). `make app` built after rounds 1 and 2.

## Remaining Findings

No Critical or Important findings remain. The five remaining Minor findings (FINDING-6, 7, 8, 10: mechanical refactors; FINDING-11: hover state after a close, to be checked in the walkthrough) and the optional cleanups kept in FINDING-4 and FINDING-9 do not block the gate.
