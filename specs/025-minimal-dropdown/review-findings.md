# Deep Review Findings

**Date:** 2026-10-18
**Branch:** 025-minimal-dropdown
**Rounds:** 1, plus a fix round for four findings the user chose to fix
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 20 | 11 | 9 |
| Notable | 1 | - | 1 |
| **Total** | **22** | **12** | **10** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR) + 2 external tools (CodeRabbit, Codex). Copilot disabled in config.
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift (WindowRow, CodexWindowRow, LimitRowLayout, BudgetBarRow)
- **Category:** architecture
- **Source:** architecture-agent (also reported by: test-quality-agent as Notable)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The "reset text, not started, or nothing" rule of FR-008 and the FR-006 accessibility labels were decided in the SwiftUI layer: copied into two row types, built twice for windows and budgets, and derived separately for the visible text and the VoiceOver label. The Codex row used its own inline lookup of the observed window.

**Why this matters:** Constitution II requires logic in UsageCore with tests. None of these rules had a test, and the visible text and the label could drift apart.

**How it was resolved:** New `RowText` in `Sources/UsageCore/Dropdown/RowText.swift` decides the reset text, its tooltip and the accessibility label for window rows (`RowText.window`) and budget lines (`RowText.budget`) from one choice of reset text. `CodexLimitsEntry.observedWithReset(_:)` owns the Codex lookup. The views only render the result. `RowTextTests` covers reset, absolute tooltip, not started, reset since, unavailable, pace summary without a note, limit reached, budget line with and without a pace, and the Codex lookup. Behavior is unchanged (checked by the re-review against HEAD).

### FINDING-2
- **Severity:** Minor
- **File:** specs/013-auto-update/contracts/update-ui.md:27-29
- **Category:** external
- **Source:** coderabbit
- **Resolution:** fixed (round 1)

**What is wrong:** The contract still described a "Gear menu" with "Check for Updates…".
**Why this matters:** Contradicts FR-028 and the FR-033 amendments.
**How it was resolved:** The section now says the gear menu was removed by spec 025 FR-028 and the check exists only in Settings > About.

**External tool analysis (CodeRabbit):**
> Remove the stale "Gear menu" requirement from the contract, including its placement of "Check for Updates…" between "About AgentTacho" and "Settings…". If retaining the section, replace it with a brief note that the gear menu was removed by spec 025 FR-028 and update checks are available only in Settings > About.

### FINDING-3
- **Severity:** Minor
- **File:** Sources/DemoMode/ScenarioCoverage.swift:89-100
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** fixed (round 1)

**What is wrong:** `absoluteTimeOwners` counted every account with an absolute value, including group members whose value does not apply (FR-021).
**Why this matters:** The FR-035 coverage could pass or fail on a format the dropdown never shows.
**How it was resolved:** It now reads the effective format of the arranged sections (`Configuration.timeFormat(for:)`); `absoluteTimeOwnersFollowTheEffectiveFormat` pins it (re-review finding).

### FINDING-4
- **Severity:** Minor
- **File:** Sources/UsageCore/Snapshot/RefreshPaceStatus.swift:3-6
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

**What is wrong:** The doc comment still placed the pace line under "Last refreshed".
**How it was resolved:** Reworded to the tooltip and accessibility value of FR-025.

### FINDING-5
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/TimeTextTests.swift (absoluteMidnightResetOmitsTheTime)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:** The `days != 0` guard for midnight resets on the same day or an earlier day had no test.
**Why this matters:** Budget resets are always at local midnight; deleting the guard would not fail any test.
**How it was resolved:** Added today-midnight and yesterday-midnight expectations.

### FINDING-6
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/TimeTextTests.swift (calendarDaysAcrossTheClockChange)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:** Only the autumn clock change was tested, where a seconds-based day count also passes.
**How it was resolved:** Added `calendarDaysAcrossTheSpringClockChange` (Berlin, 28 Mar 2027).

### FINDING-7
- **Severity:** Minor
- **File:** Sources/UsageCore/Dropdown/RowBar.swift:74 (tests: RowBarTests)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:** The tick clamp to 0...1 had no test.
**How it was resolved:** Added `tickIsClampedToTheBar`.

### FINDING-8
- **Severity:** Minor
- **File:** Sources/AgentTacho/DropdownView.swift (LimitRowLayout, BudgetBarRow, ModelLimitRow)
- **Category:** architecture
- **Source:** re-review (round 1)
- **Resolution:** remaining

**What is wrong:** "unavailable", "Limit reached", the budget amount line ("<spent> of <budget>/<period>") and the model-limit name tooltip are still string literals built in the view; "unavailable" and "Limit reached" also appear in `RowText`'s label.
**What needs to happen:** Optionally extend `RowText` with `status`, `limitNote` and an amount line built from the entry, and move the model tooltip into core. Behavior is correct today.

### FINDING-9
- **Severity:** Minor
- **File:** Sources/UsageCore/Update/UpdateState.swift:105-152, 169-286; Sources/AgentTacho/Updater.swift:137-148
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (user decision, commit f6ca65e); the DropdownView comment part was fixed in round 1

**What is wrong:** `CheckOrigin.dropdown`, `showsResultOnLine` and the dropdown branch of `joining` have no production caller since FR-028; several comments still describe checks from the gear menu.
**How it was resolved:** The case, `showsResultOnLine` and the dropdown join rule were removed with their spec 013 tests; `CheckOrigin` is `automatic` or `settings`, and `markingDevelopmentBuild` and `markingDemoBuild` lost their origin. The launch path stays: a failed install reported by the previous run shows on the update line until the dropdown closes (`installFailureFromThePreviousRunShowsUntilDismissed`, `settingsCheckEndsTheLaunchFailureOnTheLine`). Spec 013 FR-003, its data model and contracts/update-ui.md were amended citing spec 025; the idea inbox entry `remove-dropdown-check-origin` was removed.

### FINDING-10
- **Severity:** Minor
- **File:** Sources/AgentTacho/DropdownView.swift:26-32
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** fixed (user decision, commit 6abaf90)

**What is wrong:** The comment says SwiftUI pauses the 30 s `TimelineView` while the panel is hidden. A standalone NSPanel probe kept ticking after `orderOut`; the real MenuBarExtra panel was not measured.
**Why this matters:** Up to 2,880 invisible re-renders a day; times can be up to 30 s old on open.
**How it was resolved:** The `TimelineView` is gone. The dropdown keeps its reference time `now` and an open flag as view state: opening the panel (first `onAppear`, then becoming key) sets `now` at once, and a `.task(id: isOpen)` updates it every 30 s until the panel resigns key, which cancels the task. The view keeps its identity, so an expanded Details section stays open. The comment and research R8 describe this.

### FINDING-11
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/TimeFormatResolution.swift:21-31
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** remaining

**What is wrong:** The load note for an unknown `timeFormat` does not name the account or group.
**What needs to happen:** Pass the owner id into `decodeTimeFormat` and include it in the note.

### FINDING-12
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/Configuration.swift:745-747 (`clipped`), used by TimeFormatResolution.swift:27-29
- **Category:** security
- **Source:** security-agent
- **Resolution:** remaining (pre-existing helper)

**What is wrong:** `clipped` counts grapheme clusters, so a value with many combining marks is not bounded in the diagnostic log.
**Why this matters:** A hand-edited config can push oversized lines into the log and rotate history out. Local, self-inflicted.
**What needs to happen:** Clip by Unicode scalars or UTF-8 bytes and add a test.

### FINDING-13
- **Severity:** Minor
- **File:** Sources/DemoMode/ScenarioCoverage.swift:94-117
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

**What is wrong:** `paceStates` still derives paces from the effective-status accessors, while the dropdown and `attentionRows` use `paceReading(for:)` over `paceKeys`.
**What needs to happen:** Derive pace states from `paceKeys` and `paceReading`, then check whether the older accessors can become internal.

### FINDING-14
- **Severity:** Minor
- **File:** Sources/UsageCore/Dropdown/RowBar.swift:15-93
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (user decision, commit b943ada)

**What is wrong:** `RowBar` stores the pace twice (`note` and `summaryPace`), and public memberwise initializers allow a note with a neutral tone.
**How it was resolved:** `RowBar` stores the fill, the over-limit decision and the `PaceReading` once, and derives `tick`, `tone`, `note` and the accessibility summary from them. Its initializer is private, so only `RowBar.make` and `RowBar.budget` build a bar; `PaceNote` is built only by `RowBar`. `tickToneNoteAndSummaryShareOneReading` checks the invariants over a grid of readings.

### FINDING-15
- **Severity:** Minor
- **File:** Sources/UsageCore/Dropdown/FooterText.swift:30-39; Sources/AgentTacho/DropdownView.swift (`UsageFormat.tokens`)
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

**What is wrong:** `DetailsTotal.weekly` duplicates the compact token format of `UsageFormat.tokens` and lives in FooterText.swift.
**What needs to happen:** One core token formatter used by both; move `DetailsTotal` to its own file.

### FINDING-16
- **Severity:** Minor
- **File:** scripts/screenshots/uihelper.swift:16-23, 42-43, 135-141, 233-240, 284-286
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

**What is wrong:** The `hover` subcommand and the `press ... --in` scope have no caller after the capture changes.
**What needs to happen:** Remove them and their usage text (capture tooling only).

### FINDING-17
- **Severity:** Minor
- **File:** Sources/AgentTacho/DropdownView.swift (BudgetSection header and bar); Sources/UsageCore/Dropdown/RowBar.swift:76
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (user decision, commit a08aab8)

**What is wrong:** The budget header percent uses Decimal rounding (`entry.percent`), the bar's red decision Double rounding of `entry.usedPercent`; at a .5 boundary they could disagree (header 99%, red bar).
**How it was resolved:** `RowBar.budget(_:reading:)` takes the `GroupEntry`: the fill is the unrounded share, the tone is over the limit exactly when `entry.percent`, the header's value, is 100 or more. `BudgetSection` uses it. `budgetToneAtTheHalfPercentBoundary` (99.5% reads 100% with a red bar, 99.4% reads 99% without) and `budgetToneFollowsTheHeaderPercent` were written first.

### FINDING-18
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/TimeTextTests.swift, FooterTextTests.swift, RowBarTests.swift, SectionNoteTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

**What is wrong:** All formatter tests use en_US and compute expectations with the same format styles, so ignoring the `locale` input would pass on an en_US machine.
**What needs to happen:** Add one non-en_US case per formatter with literal expectations.

### FINDING-19
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/PaceReadingTests.swift:26-131
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

**What is wrong:** `reading.burn == snapshot.burnRate(for:)` compares a value with itself, since `burnRate(for:)` now returns `paceReading(for:)?.burn`.
**What needs to happen:** Use an independent oracle (`BurnRate.compute` with explicit inputs) or drop the self-comparisons.

### FINDING-20
- **Severity:** Minor
- **File:** Tests/DemoModeTests/DefaultScenarioTests.swift:78, 90
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

**What is wrong:** The two-member group and the absolute-times checks read the scenario configuration, not the played snapshot.
**What needs to happen:** Count members with a `tokenAccounts` entry in the snapshot, and assert the absolute section has a reset time.

### FINDING-21
- **Severity:** Minor
- **File:** Tests/DemoModeTests/DefaultScenarioTests.swift; Sources/DemoMode/ScenarioCoverage.swift
- **Category:** correctness
- **Source:** re-review (round 1)
- **Resolution:** fixed (round 1)

**What is wrong:** The new effective-format logic of `absoluteTimeOwners` had no test that fails on a revert.
**How it was resolved:** Added `absoluteTimeOwnersFollowTheEffectiveFormat`.

## Notable Observations

### NOTABLE-1
- **File:** Sources/AgentTacho/DropdownView.swift (BudgetSection `members.count >= 2`); Sources/DemoMode/ScenarioCoverage.swift (`singleMemberGroups`)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The FR-010 member-line rule lives in the view and is repeated in the coverage report; the FR-006 label part is now in `RowText` (FINDING-1).
- **Rationale:** A shared core helper (for example `showsMemberLines(memberCount:)`) would let the coverage test catch a view regression.

## Post-Fix Spec Coverage

The fix round moved code from the view into UsageCore and removed only the view's own copies. Every FR was re-checked: FR-006 and FR-008 are now implemented in `RowText` and rendered unchanged; all other FRs keep their implementation. All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 0 (before fixes) | make test | 0 | 0 | passed (1520 + 63) |
| 1 | make test | 0 | 0 | passed (1531 + 64) |
| 1 | make app, make app-demo | 0 | 0 | built |
| 1 | make test-release | 0 | 0 | passed (252) |
| 2 (FINDING-9, 10, 14, 17) | make test | 0 | 0 | passed (1530 + 64) |
| 2 | make test-release | 0 | 0 | passed (252) |
| 2 | make app, make app-demo | 0 | 0 | built |

Test suite passed in all fix rounds. Round 2 removed five dropdown-origin tests and added four RowBar tests.

## Remaining Findings

No Critical or Important findings remain. The 9 remaining Minor findings (FINDING-8, FINDING-11 to FINDING-13, FINDING-15, FINDING-16, FINDING-18 to FINDING-20) are listed above. FINDING-9, FINDING-10, FINDING-14 and FINDING-17, which needed a human decision, were fixed after the user chose to fix all four.
