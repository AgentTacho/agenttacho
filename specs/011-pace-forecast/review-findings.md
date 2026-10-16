# Deep Review Findings

**Date:** 2026-10-15
**Branch:** 011-pace-forecast
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 (FINDING-3 resolved by a user decision and spec evolution) |
| Minor | 6 | 4 | 2 |
| Notable | 2 | 1 (comment) | 1 |
| **Total** | **11** | **7** | **4** |

**Agents completed:** 5/5 internal (Goal Alignment skipped, no PR found) + 2 external tools (CodeRabbit, Codex). Copilot is disabled in the config.
**Agents failed:** none.

The third Important finding (FINDING-3) asked for behavior the spec did not define (withholding a run-out that has already passed at the snapshot time). It was triaged as a spec evolution candidate during the review and resolved afterwards: the user added the rule to FR-005. The correctness agent reported the same observation as Notable for that reason.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 78
- **File:** Sources/AgentMeter/DropdownView.swift:323-332, Sources/UsageCore/Bar/BarLayout.swift:152-154, 175-177
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 0a5c949)

**What is wrong:**
The window length (5 hours or 7 days) and the observation time (`fetchedAt`, `observation.observedAt`) were picked in two places, `BarLayout` and the SwiftUI `SubscriptionSection` / `CodexPlanSection`. The FR-001 mapping from row to window length lived only in untested app code.

**Why this matters:**
FR-017 puts the pace computation in the tested core. Two copies of the input selection can drift, so the bar marker and the dropdown line could disagree.

**How it was resolved:**
New core accessors `SubscriptionStatus.fiveHourPace(now:)`, `sevenDayPace(now:)`, `pace(of:now:)` and `CodexLimitsEntry.pace(of:now:)`, `barPace(now:)` choose the length and observation time. `BarLayout` and `DropdownView` call them. A new test checks the 5-hour and 7-day lengths and the fetch time.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift:385-412
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 0a5c949)

**What is wrong:**
Every marker test used an observation time equal to the snapshot time. The tests would have passed if `BarLayout` used `snapshot.generatedAt` instead of the fetch or observation time.

**Why this matters:**
FR-002 requires the pace at the observation time. Codex `.localOnly` and `.newerSnapshot` entries are not stale and can be hours older than the snapshot, so a regression would change the marker silently.

**How it was resolved:**
`markerUsesTheObservationTime` covers Claude and Codex (`.localOnly`) in both directions: observed during the hold back (no marker, would show one at snapshot time) and observed ahead with the snapshot behind (marker, would show none at snapshot time). The Codex fixture takes an `observedAt` parameter.

### FINDING-3
- **Severity:** Important (triaged: spec evolution candidate)
- **Confidence:** 80
- **File:** Sources/UsageCore/Pace/Pace.swift:59-66
- **Category:** production-readiness
- **Source:** production-readiness-agent (related: correctness-agent, Notable)
- **Round found:** 1
- **Resolution:** fixed after review: the user chose to add the rule to FR-005; `Pace.compute` drops a run-out at or before the snapshot time; test `runOutAtOrBeforeTheSnapshotTimeDoesNotCount`

**What is wrong:**
The run-out is computed at the observation time and only compared with the reset. With an old observation whose window has not reset, the run-out can already be in the past at the snapshot time. The dropdown then shows "runs out" with a past time (time only when it was earlier today, which reads like a future time). For Codex `.localOnly` and `.newerSnapshot` entries, which are not marked stale, the bar marker also shows until the window resets, even with no usage since.

**Why this matters:**
A forecast naming a passed time, and a marker that does not clear during a long idle period, confuse users. Local-only Codex is a supported mode.

**How to resolve:**
The spec does not cover this case. FR-002 and the edge case "time passing while the dropdown is open" pin the pace to the observation time, and FR-005 compares only with the reset. A fix would add a rule such as "a run-out at or before the snapshot time does not count" to FR-005 or FR-007, then require `candidate > now` in `Pace.compute` with a test using an old Codex observation. This changes specified behavior, so it was not applied automatically.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/AgentMeter/DropdownView.swift:261-282
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 0a5c949)

**What is wrong:** `runOutText` duplicated `resetText` except for the local midnight branch.

**How it was resolved:** `resetText` keeps only the midnight branch and delegates the rest to `runOutText`. Behavior is unchanged.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/AgentMeter/DropdownView.swift:290-294
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `PaceLine.windowIndent = 68` assumes the 60 pt title width (a literal repeated in three rows) plus an 8 pt default `HStack` spacing that SwiftUI does not document. The comment says it aligns with the percent column, but it aligns with the left edge of a right-aligned frame.

**What needs to happen:** A shared title width constant, explicit `HStack(spacing: 8)` and a reworded comment. Layout only, no behavior impact.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/Configuration.swift:646-647
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `showsRunOutMarker` is decoded strictly. A hand-edited non-Bool value rejects the whole file. The other presentation-only key, `arrangement`, is decoded leniently (spec 008 FR-011). The README configuration section does not mention the key.

**What needs to happen:** Optional: decode with `try?` and fall back to true, and document the key in the README. Other plain Bool keys (for example `startAtLogin`) are decoded strictly too, so the current code is consistent with them.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/PaceTests.swift:50-64
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 0a5c949)

**What is wrong:** No test asserted that the first delta beyond the band (+6) gets a run-out or a marker.

**How it was resolved:** `firstAheadDeltaHasARunOut` (56% and 55.5% at half the window) and `firstAheadDeltaGetsTheMarker` (31% at 25% elapsed).

### FINDING-8
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/PaceTests.swift:41-55
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 0a5c949)

**What is wrong:** Rounding of fractional negative deltas at the band edge was untested.

**How it was resolved:** `negativeFractionalDeltasRoundAwayFromZero`: 44.6% gives -5 (on pace), 44.5% and 44.1% give 6% behind.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/PaceTests.swift (round 1 addition)
- **Category:** test-quality
- **Source:** re-review (round 1)
- **Round found:** 2 (re-review)
- **Resolution:** fixed (commit 0a5c949)

**What is wrong:** The "no observation" Codex assertion only exercised `barPace`, which returns nil from an empty window list, so the nil-observation branch of `pace(of:now:)` was untested.

**How it was resolved:** Separate test `codexEntryWithoutObservationHasNoPace` passes a valid window directly to `pace(of:now:)`.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Pace/Pace.swift:59-66
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** A run-out can be in the past at the snapshot time for an old, non-stale observation. Same observation as FINDING-3.
- **Rationale:** The spec does not address it; worth a spec rule.

### NOTABLE-2
- **File:** Sources/UsageCore/Pace/Pace.swift:59-66
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The `candidate < resetsAt` guard cannot be reached once the status is ahead (ahead implies a run-out before the reset). The edge case "projection runs out exactly at or after the reset" is enforced by the math, not by a reachable branch.
- **Rationale:** A future test named after that edge case would pass for the wrong reason. Resolved with a comment on the guard.

## Goal Alignment

Skipped (no PR found for the branch).

## Post-Fix Spec Coverage

The fix round removed no behavior; it moved input selection into core accessors with the same arguments. All 17 functional requirements remain implemented (verified by the round 1 re-review and the test suite).

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (722 tests) |
| 1 | make test | 0 | 0 | passed (728 tests) |

`make build` (release, includes the app target) also passed after the fixes.

## External Tools

| Tool | Scope | Findings | Status |
|------|-------|----------|--------|
| CodeRabbit | branch vs main (committed), then round 1 uncommitted | 0, 0 | completed |
| Codex | branch vs main, then round 1 uncommitted | 0, 0 | completed |
| Copilot | | | skipped (disabled in config) |

## Remaining Findings

- FINDING-3 (Important): resolved after review by spec evolution of FR-005 and a one-line check with a test.
- FINDING-5, FINDING-6 (Minor): optional cleanups.
