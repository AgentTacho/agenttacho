# Deep Review Findings

**Date:** 2026-10-20
**Branch:** 030-threshold-levels-direction
**Rounds:** 1 fix round, plus 1 re-review
**Gate Outcome:** PASS
**Invocation:** quality-gate (speckit-spex-ship, review-code stage)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 4 | 4 | 0 |
| Minor | 11 | 9 | 2 |
| Notable | 5 | - | 5 |
| **Total** | **20** | **13** | **7** |

Counts are after merging duplicates. Correctness FINDING-1 duplicates FINDING-1 below. Test-quality FINDING-5 duplicates FINDING-9.

**Agents completed:** 5/5 internal agents (Goal Alignment skipped, no PR), plus CodeRabbit and Codex, each run on the branch and again on the fix commits.
**Agents failed:** none. The first CodeRabbit call used an unsupported `--files` flag; the rerun with `--base main --committed` completed.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 90
- **File:** Sources/UsageCore/Notifications/ThresholdDisplay.swift:9-22, 67-72 (called from Sources/AgentTacho/SettingsView.swift)
- **Category:** security
- **Source:** security-agent (also reported by: correctness-agent, as Minor)
- **Round found:** 1
- **Resolution:** fixed (round 1, 45addb3)

**What is wrong:**
`shown(stored:)`, `stored(entered:)` and `furtherThresholds` computed `100 - x` with Swift's trapping subtraction. Nothing bounded `x`. A threshold near `Int.min` in the configuration file, or typed into a field, crashed Settings in direction remaining. The last case needs no file edit: type the value in direction used, then switch to Remaining.

**Why this matters:**
A menu bar app that crashes on a mistyped field fails silently. The hand-edited case crashes again every time Settings opens.

**How it was resolved:**
Both conversions clamp the operand to +/- one billion first (`PercentFormatter.clamped`), the same bound `PercentFormatter.rounded` already uses. `furtherThresholds` goes through `shown`. Tests cover `Int.min`, `Int.min + 99`, `Int.max` and `Int.max - 99` in both directions.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Bar/DirectedPercent.swift:25-27; Sources/UsageCore/Snapshot/UsageSnapshot.swift:584-590
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 84f86ee)

**What is wrong:**
`PercentFormatter.rounded(spent:budget:)` converted with `NSDecimalNumber.intValue`, which wraps silently on overflow. A tiny `budgetUSD` (validation only checks `> 0`) with an ordinary spend gave a value near `Int.min`. `DirectedPercent.value` then computed `100 - usedPercent` and trapped.

**Why this matters:**
In direction remaining this runs on every refresh for the bar, the header and the rows, so the app would crash-loop at launch.

**How it was resolved:**
The Decimal ratio is clamped to +/- one billion before the conversion, the same as the Double path. `DirectedPercent.value` also clamps before subtracting. Tests cover the wrapped inputs the agent found and `Int.min`/`Int.max` used percents.

### FINDING-3
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Bar/LevelThresholds.swift; Sources/UsageCore/Bar/BarLayout.swift; Sources/UsageCore/Dropdown/RowBar.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 2e25713)

**What is wrong:**
The real-limit half of the level rule (FR-003) had no single home. `LevelThresholds.level` returned normal for a nil value before it looked at `atRealLimit`. `subscriptionLevel`, `codexLevel`, `memberItem` and `budgetItem` each computed `overLimit` on their own. `RowBar.make` needed a ternary to work around the early return.

**Why this matters:**
FR-001 asks for one level rule. With five copies, the level and the "over limit" wording could drift apart the next time FR-003 changes.

**How it was resolved:**
`LevelThresholds.decide(usedPercent:atRealLimit:)` returns a `LevelDecision` with both the level and `overLimit`, and a real limit is critical even without a value. Every caller uses it, and the workaround is gone. Behavior is unchanged: the re-review checked each caller, and the existing level tests pass unchanged.

### FINDING-4
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/ThresholdTrackerTests.swift (missing test)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, d5df4f1)

**What is wrong:**
SC-004 and US4 scenarios 3 and 4 require unit tests showing that the direction never changes when a notification fires. Only the stored-threshold half was tested.

**Why this matters:**
The tracker takes the whole `Configuration`. A later change that reads the direction would break SC-004 and no test would catch it.

**How it was resolved:**
`directionNeverChangesWhenCrossingsFire` feeds one series to three trackers: one in direction used, one in remaining, and one that switches between refreshes. It asserts that all three produce identical crossings (80 and 100 for a group and the 7-day window).

### FINDING-5
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/Configuration.swift:938-943 (shown in the Settings "Not applied" banner)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining (needs a human decision)

**What is wrong:**
In direction remaining, entering 100 or more stores 0 or less. The editor then shows "Use whole numbers below 100.", but the save banner says "Thresholds of X must be whole-number percents greater than 0 (got 0)". The banner talks in used percent about a number the user never typed.

**Why this matters:**
The two messages disagree. That works against the one language FR-015 and US4 ask for, though the field-level message is correct and nothing is stored.

**How it was resolved:**
Not fixed; see Remaining Findings.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Bar/BarLayout.swift:86-91
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 2e25713)

**What is wrong:** `BarLayout.warningThreshold(_:)` had no production caller and duplicated `LevelThresholds.warning`.
**Why this matters:** Two copies of the warning derivation can diverge.
**How it was resolved:** Removed. Its test now checks `LevelThresholds([]).warning == 80`, pinned to the literal after the re-review (bd40e66).

### FINDING-7
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Bar/HeadlineWindow.swift:54-67
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 2e25713)

**What is wrong:** `HeadlineHeader.overLimit` was stored but never read; the dropdown header speaks no level word (FR-005 asks only for its color).
**Why this matters:** It was a YAGNI field, and one more copy of `overLimit` to keep in sync.
**How it was resolved:** Removed. The header tests check the bar entry's `overLimit` instead.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/DemoMode/ScenarioCoverage.swift (`thresholdCriticalRows`)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The coverage check rebuilds the dropdown's list of rows by hand, along with the lookup of which owner's thresholds apply. DropdownView and BarLayout each do the same lookup separately.
**Why this matters:** If the dropdown adds a row kind, the FR-020 check could keep passing while the dropdown behaves differently.
**How it was resolved:** Not fixed. The fix is a shared UsageCore list of dropdown rows with their `RowBar` inputs. That restructures the dropdown, which is beyond a review fix. The same drift risk was noted for spec 028 (`section-stripes-single-entry-point` in the idea inbox).

### FINDING-9
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/SettingsView.swift (`invalid`, `value(at:)`)
- **Category:** architecture
- **Source:** architecture-agent (also reported by: test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, 45addb3)

**What is wrong:** The editor's validity rule and its slot merge (empty removes the slot, further thresholds kept) lived untested in the SwiftUI layer, contrary to FR-018.
**How it was resolved:** Both moved to `ThresholdDisplay.hasInvalidStored` and `ThresholdDisplay.replacing`, with tests that include US4 scenario 2 (enter 30 left, store 70). Validity is checked against the old direction-dependent rule for -5...105.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Dropdown/BudgetAmountLine.swift:15-19; Sources/UsageCore/Bar/HeadlineWindow.swift; Sources/UsageCore/Bar/BarLayout.swift; three test doc comments
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 2e25713)

**What is wrong:** Doc comments cited internal review ids ("M-7 decision", "I-4 decision", "review-plan decision") instead of spec requirements (constitution II).
**How it was resolved:** They now cite FR-012, FR-005 and the spec's edge case for a budget without a positive amount.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/AgentTacho/DropdownView.swift (BudgetSection)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, a69f117)

**What is wrong:** Each render built the budget's `RowBar` twice, once for the header tone and once for the bar row, so the pace reading ran twice.
**How it was resolved:** It is now built once per render (`let budgetBar = entry.map(bar)`) and shared by both.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/RowBarTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 2e25713)

**What is wrong:** No test covered a reached Codex limit with a non-finite used percent (FR-003).
**How it was resolved:** `reachedLimitWithoutAFinitePercentIsCritical` checks critical, the red tone and percent, and an empty bar in both directions.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/ConfigurationTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, d5df4f1)

**What is wrong:** The fallback for an unreadable `displayDirection` was tested, but its diagnostic notes were not.
**How it was resolved:** `fallbackLeavesANote` asserts the exact note for unknown strings, a wrong case, a number and null, and that a missing key or a valid value leaves no note.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 2e25713)

**What is wrong:** No test exercised a member share at or above 100% (FR-004's "over limit" wording).
**How it was resolved:** `memberKeepsTheGroupsThresholds` now checks a member at 110% ("over limit 110%") next to one at 80% that is critical from the group's thresholds ("critical 80%").

### FINDING-15
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift:205-207
- **Category:** test-quality
- **Source:** re-review agent
- **Round found:** 2 (re-review)
- **Resolution:** fixed (bd40e66)

**What is wrong:** After FINDING-6, the default-threshold test compared the constant with itself.
**How it was resolved:** It now compares with the literal 80.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Bar/BarLayout.swift:56-71
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `BarItem` takes its value already in the display direction but derives its glyph from a `direction` parameter that defaults to `.used`.
- **Rationale:** A new call site could mix a remaining value with a used glyph. Captured as `bar-item-direction-default`.

### NOTABLE-2
- **File:** Sources/UsageCore/Config/Configuration.swift:760-775
- **Category:** security
- **Source:** security-agent
- **Description:** Confirmed clean: `displayDirection` decoding is defensive, log notes are clipped and kept to one line, there are no new file writes or network calls (no constitution III update needed), and the demo data has no real names.
- **Rationale:** Informational; not captured to the inbox.

### NOTABLE-3
- **File:** Sources/AgentTacho/App.swift:269-270
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** The settings-save log line does not name the direction. Captured as `log-direction-on-settings-save`.

### NOTABLE-4
- **File:** Sources/UsageCore/Config/ConfigStore.swift:132-139
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** An older version saves only the keys it knows, so a downgrade followed by an upgrade resets the direction to used. Captured as `downgrade-drops-global-keys`.

### NOTABLE-5
- **File:** Sources/AgentTacho/NotificationPresenter.swift:183-193
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** That queued crossings use the direction at posting time rests on the presenter, which no test covers; the UsageCore text logic is covered. Captured as `notification-queue-direction-test`.

## Post-Fix Spec Coverage

The fix round removed code (`BarLayout.warningThreshold`, `HeadlineHeader.overLimit`, the `RowBar.make` ternary), so coverage was checked again. All 21 functional requirements remain implemented. The re-review agent traced every caller of the changed level rule: FR-001 to FR-006 behave exactly as before, FR-015 now goes through `ThresholdDisplay.replacing` and `hasInvalidStored`, and FR-009 and FR-012 keep their texts with clamped arithmetic.

All spec requirements verified after fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (1723 + 66) |
| 1 | make test | 0 | 0 | passed (1731 + 66); `make build` also clean |
| re-review fix | make test | 0 | 0 | passed (1731 + 66) |

Test suite passed in all fix rounds.

## Remaining Findings

- **FINDING-5** (Minor, needs a human decision): the save banner reports a remaining-mode entry of 100 or more in used percent ("got 0"). Options:
  - (a) Leave it. The field's own message is correct and nothing invalid is stored.
  - (b) Hide `.threshold` errors from the "Not applied" banner while the editor shows its own message.
  - (c) Phrase the configuration error through `ThresholdDisplay` in the current direction.

  Recommendation: (a) for this feature, possibly (b) later.
- **FINDING-8** (Minor, unambiguous but structural): share one list of dropdown rows and owner thresholds between DropdownView, BarLayout and ScenarioCoverage. Better done in its own change.
