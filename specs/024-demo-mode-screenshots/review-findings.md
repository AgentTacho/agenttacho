# Deep Review Findings

**Date:** 2026-10-18
**Branch:** 024-demo-mode-screenshots
**Rounds:** 2
**Gate Outcome:** PASS
**Invocation:** superpowers (after_implement quality gate)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 12 | 12 | 0 |
| Minor | 33 | 25 | 8 |
| Notable | 2 | - | 2 |
| **Total** | **47** | **37** | **10** |

Counts are after deduplication (the banner check was reported by Codex, Correctness and the spec review; the foreign banner by Security and Production Readiness; the relative target by Correctness and CodeRabbit; and so on).

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR yet), plus CodeRabbit and Codex. Copilot is not installed.

Test suites after the last round: `make test` 1444 UsageCore and 62 DemoMode tests, `make test-release` 253 tests, all passing. `make app` and `make app-demo` build; the regular binary links 0 DemoMode symbols.

## Important findings (all fixed)

### FINDING-1: Banner style not checked before changes (Codex P2, Correctness, spec review FR-018)
- **File:** scripts/screenshots/capture.sh preflight
- **What was wrong:** The preflight trusted an old `authorization granted` log line. A later switch to Alerts or turning notifications off was only noticed at the `alert` shot, after AgentTacho was quit and the appearance switched.
- **Resolution (round 1):** NotificationPresenter logs `[notifications] alert style banner|alert|none` after a granted authorization. After `make app-demo` the script launches the demo app briefly, before any change, and requires `alert style banner`; `--first-run` requires it too. Test: `test_screenshots_requires_banners`.

### FINDING-2: Alert shot could capture another app's banner (Security, Production Readiness)
- **File:** capture.sh `capture_pass`
- **What was wrong:** The first Notification Center window was captured, whoever's banner it showed. A Messages or Mail banner could reach the public landing page.
- **Resolution (round 1):** The script waits for this launch's `[notifications] sent:` line and requires `uihelper hastext` to find "<name> reached" in Notification Center before the capture. Test: `test_screenshots_foreign_banner_fails_the_alert`.

### FINDING-3: Region shots could include other windows (Security; Codex P2 in round 2)
- **File:** capture.sh `pace`/`prices`, uihelper.swift `covered`
- **What was wrong:** `screencapture -R` records whatever is on top.
- **Resolution:** Region shots wait until no banner is on screen and run `uihelper covered`, which fails naming the owner of any other app's window above the demo app's lowest window in the region (round 2: scans past the tooltip, Codex). Checked against real windows on this Mac. Test: `test_screenshots_covered_region_fails_the_shot`.

### FINDING-4: Second Ctrl-C during cleanup could leave dark mode on (Production Readiness)
- **Resolution (round 1):** cleanup ignores INT and TERM and restores the appearance first. Tests cover a dark start for success, failure and interrupt.

### FINDING-5: Appearance "Auto" not restorable (Production Readiness)
- **Resolution (round 1):** preflight refuses Auto with a message, before any change. Test: `test_screenshots_refuses_auto_appearance`.

### FINDING-6: AXPress fallback could undo an opened menu, and AX calls could stall (Production Readiness)
- **Resolution:** only failures other than success and cannotComplete fall back to Show Menu and a click (round 2 widened this so a dead press is not reported as done); a process-wide 2 s AX messaging timeout.

### FINDING-7: Tooltip detection could pick the status item window (Correctness)
- **Resolution (round 1):** the tooltip must be below the menu bar and within 100 pt of the hovered point; the test stub now lists a status item window and asserts the region starts at the plan.

### FINDING-8: Relative target resolved against the repository (Correctness, CodeRabbit)
- **Resolution (round 1):** made absolute before `cd`. Test: `test_screenshots_relative_target_is_taken_from_the_caller`.

### FINDING-9: Tests start only in light appearance (Test Quality)
- **Resolution:** `INITIAL_DARK` stub mode; `test_screenshots_restores_a_dark_appearance` covers success, a light-pass failure and an interrupt.

### FINDING-10: The last-frame wait was untested (Test Quality)
- **Resolution:** `NO_LAST_FRAME` stub mode with a stale line from an earlier launch; the run fails naming the timeout, captures nothing and keeps the target.

### FINDING-11: WebP validation was untested (Test Quality)
- **Resolution:** `DWEBP_FAIL_ON` stub; `test_screenshots_invalid_webp_keeps_the_target`.

### FINDING-12: Frame changes through the plan sources and SC-002 app branches untested (Test Quality)
- **Resolution:** `planSourcesFollowFrames`, `modelLimitsAreReported`, and `appDemoBranchesNameNoNetworkOrCredentialType`, which scans every `#if AGENTTACHO_DEMO` branch of the app (it caught a comment naming `UpdateClient`). SC-002 reworded to what is checked.

## Minor findings fixed

Conditional `shotContainer` (no extra accessibility containers in release builds); unused `statusItem` and `detailsMode` identifiers removed; one frame timing helper (`DemoSetup.frameRefreshDates`, `lastFrameDate`) for app and coverage; markers taken from `BarPresentation`; `AGENTTACHO_DEMO` defined by Package.swift together with the dependency (one switch); `DemoRun` dead state removed; `markingChecksOff` shared; `first_run` variable renamed; capture.sh takes names and ids from `lib.sh`; `build-app.sh` refuses `DEMO=1 DISTRIBUTION=1`; every capture step names the uncaptured shots; demo log lines on a timeout; log rollover; staged, signal-safe move into the target and staging cleanup; restart of the exact AgentTacho copy that ran; probe launch trapped; `resetsIn` must be positive; validation branch tests; prepare without imported prices; names check over every demo file with any separator; contract and FR-018 updated.

## Remaining Minor findings

- `agenttacho.claudePlan` and `agenttacho.paceMeter` are set on every Claude subscription section; with two Claude accounts the first one wins (Architecture). The default scenario has one.
- `ScenarioPlayer` is an actor without mutable state (Architecture).
- The scenario loader itself does not reject "Red Hat" or email addresses; the loader test does, as the contract says (CodeRabbit).
- `release.sh` does not re-check the built bundle's identity after `build-app.sh`; `build-app.sh` now refuses demo distribution builds and `release.sh` refuses `DEMO` (Security).
- `DemoRun` glue (scenario name choice) has no unit test; the timing it uses is now in tested core (Test Quality).
- Interrupt test with a pre-seeded target and restart are covered; a stale `.capture-staging` after a crash of the shell itself is not.
- The probe launch runs while AgentTacho still runs; the two apps never meet (separate bundle ids and folders), and the contract now describes it.
- Arc, Ghostty and other apps' windows under the Settings window are fine; a floating panel of another app over it fails the shot by design, which may need a retry.

## Notable observations

### NOTABLE-1
- **Category:** architecture
- **Description:** `shotBudgetOwner` lives in `BarLayout` though it serves the dropdown capture; `ScenarioCoverage` is test support shipped in the demo app; the demo build still constructs `CredentialAlertTracker`.
- **Rationale:** boundary tidiness for a later refactor.

### NOTABLE-2
- **Category:** production-readiness
- **Description:** The capture depends on macOS UI internals (Notification Center window layering, menu bar extras through Accessibility). The first real run (quickstart Q6) is the real test.

## Post-Fix Spec Coverage

No requirement code was removed; the two dropped identifiers were never used by the script and are not named in the spec. All FR-001 to FR-024 remain implemented (see review-code.md).

## Test Suite Results

| Round | Command | Result |
|-------|---------|--------|
| 1 | make test | 1444 + 62 passed |
| 1 | make test-release | 253 passed |
| 2 | make test-release | 253 passed |
