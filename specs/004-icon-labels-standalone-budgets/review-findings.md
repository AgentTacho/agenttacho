# Deep Review Findings

**Date:** 2026-10-14
**Branch:** 004-icon-labels-standalone-budgets
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline stage 7)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 20 | 4 | 16 |
| Notable | 4 | - | 4 |
| **Total** | **25** | **5** | **20** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR found) plus one narrowed re-review after the fix round.
**External tools:** CodeRabbit failed twice ("Review failed: Failed to start review", service side); Codex failed (usage limit reached until 2026-10-17); Copilot skipped (disabled in config).
**Fix commit:** b5aa587 `fix: reject duplicate ids and show a placeholder for unknown member shares`

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Config/Configuration.swift:560-620 (trap at Sources/UsageCore/Snapshot/RefreshCoordinator.swift:213)
- **Category:** security (input validation)
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `validate()` never checked that account ids or group ids are unique. Two hand-edited subscription accounts with one id and different credential directories passed validation, and the next full refresh trapped in `Dictionary(uniqueKeysWithValues:)`. Duplicate token-based ids silently shadowed each other in the new id-keyed structures (`budgetOwners`, `accountBudgets`, `budgetOwner(forAccount:)`).

**Why this matters:** A single typo in a hand-edited file crashed the app on every launch until fixed by hand, instead of being rejected as invalid (spec 001 FR-033).

**How it was resolved:** `validate()` now rejects duplicate account ids and duplicate group ids with the new `ConfigurationError.Kind.duplicateId`. A group and an account may still share an id, since budget owners, the threshold tracker and the snapshot keep the kinds apart (data-model BudgetOwner). The refresh coordinator uses `Dictionary(_:uniquingKeysWith:)` as defense in depth. Configs written by the app use UUIDs, so FR-006 is unaffected. Test: `ConfigurationTests.rejectsDuplicateIds`.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/UsageSnapshot.swift:202-206, Sources/UsageCore/Bar/BarLayout.swift:89-97, Sources/AgentTacho/DropdownView.swift:352-354
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** fixed (round 1)

**What is wrong:** `memberPercent` returned 0 for an account the group entry was not computed for (a snapshot from before the account joined, or a stale carried-over entry after a failed log refresh). The bar showed a real-looking `0%` instead of the FR-018 placeholder, and the dropdown showed `$25.00 (0%)`.

**How it was resolved:** `memberPercent` returns `Int?`. The bar shows `…` with the group's stale flag and the dropdown omits the percent when it is nil. A member with zero spend still shows `0%`. Test added in `BarLayoutTests.memberValuesAndLevels`.

### FINDING-3
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/Configuration.swift:574, 824-825
- **Category:** architecture (naming)
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

The icon-not-in-catalog error kind was still named `invalidLabel`. Renamed to `unknownIcon`.

### FINDING-4
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/Configuration.swift:279-281, 311-312
- **Category:** architecture (comment accuracy)
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

Two `BudgetPeriod` doc comments still described groups only. Reworded to cover own budgets.

### FINDING-5
- **Severity:** Minor
- **File:** README.md:67, 77
- **Category:** architecture (documentation)
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

The README said the week fallback applies to weekly groups only and that an unpriced model marks "its group total" incomplete. Both now include own budgets.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift:625-631
- **Category:** security (numeric bounds)
- **Source:** security-agent
- **Resolution:** remaining

A hand-edited budget such as `1e-20` passes `> 0`, and the percent overflows to a garbage Int in the bar and notifications. Nothing crashes. Suggested fix: a minimum of one cent (and maybe a ceiling) in `checkBudget`, or clamping in `PercentFormatter`. Not fixed because it adds a validation rule the spec does not define (FR-009 says "greater than 0").

### FINDING-7
- **Severity:** Minor
- **File:** Sources/AgentTacho/NotificationPresenter.swift:64-68, 108
- **Category:** correctness
- **Source:** re-review agent
- **Resolution:** remaining

Notification dedup and identifiers use `entityId + windowKind + threshold` with no owner scope. A hand-edited group and own-budget account sharing an id, crossing the same threshold in the same second, would replace one notification with the other. Suggested fix: carry the scope in `ThresholdCrossing`, or reject group/account id overlap in `validate()`. Needs a human decision (see REVIEW-CODE.md).

### FINDING-8
- **Severity:** Minor
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:114-116, Sources/UsageCore/Snapshot/RefreshCoordinator.swift:353-359, Sources/AgentTacho/DropdownView.swift:77-87
- **Category:** architecture (duplication)
- **Source:** architecture-agent
- **Resolution:** remaining

The `owner.kind == .group ? snapshot.groups : snapshot.accountBudgets` split is repeated, and the dropdown re-implements the own-budget filter instead of iterating `budgetOwners`. Suggested: `UsageSnapshot.budgetEntry(for:)`.

### FINDING-9
- **Severity:** Minor
- **File:** Sources/UsageCore/Snapshot/UsageSnapshot.swift:166, Sources/UsageCore/Snapshot/Aggregator.swift:31-34, Sources/UsageCore/Bar/BarLayout.swift:58
- **Category:** architecture (naming)
- **Source:** architecture-agent
- **Resolution:** remaining

`GroupEntry` also holds own budgets, `groupWindow` serves every owner, and `BarLayout.segments` returns `[BarItem]`. Suggested renames: `BudgetEntry`, `budgetWindow`, `items`.

### FINDING-10
- **Severity:** Minor
- **File:** Sources/AgentTacho/IconPickerSheet.swift:9, Sources/AgentTacho/SettingsView.swift:479-484
- **Category:** architecture (YAGNI)
- **Source:** architecture-agent
- **Resolution:** remaining

`IconPickerSheet` still takes `Binding<String?>` from the removed "No icon" button, so `IconField` needs an adapter that ignores nil. Suggested: make it `Binding<String>`.

### FINDING-11
- **Severity:** Minor
- **File:** Sources/AgentTacho/AccountSettingsView.swift:281, 343, 392-408, Sources/UsageCore/Config/Configuration.swift:756
- **Category:** architecture (duplication)
- **Source:** architecture-agent
- **Resolution:** remaining

New-budget defaults (weekly, $60, shown, `[80, 100]`) and the caption "80% and 100%" are repeated. Suggested: `BudgetSettings.newDefault`.

### FINDING-12
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/Configuration.swift:742-746
- **Category:** architecture (complexity)
- **Source:** architecture-agent
- **Resolution:** remaining

`budgetOwner(forAccount:)` uses a hard-to-read `Bool == Bool` predicate. Suggested: switch on `settings.membership`.

### FINDING-13
- **Severity:** Minor
- **File:** Sources/AgentTacho/IconFont.swift:55-73
- **Category:** architecture (naming)
- **Source:** architecture-agent
- **Resolution:** remaining

`labelText` and `pickerText` keep label-era names; `pickerText` returns `some View`, not `Text`. Suggested: `iconText`, `pickerItem`.

### FINDING-14
- **Severity:** Minor
- **File:** Sources/UsageCore/Snapshot/Aggregator.swift:42-47
- **Category:** production-readiness (performance)
- **Source:** production-agent
- **Resolution:** remaining

`budgetOwner(forAccount:)` rebuilds `budgetOwners` per token account (quadratic, negligible at current sizes). Suggested: compute owners once per aggregation.

### FINDING-15
- **Severity:** Minor
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:353-362
- **Category:** production-readiness (observability)
- **Source:** production-agent
- **Resolution:** remaining

The refresh log line does not include member shares or the member set, so a reported bar share (SC-004) cannot be checked against the log.

### FINDING-16
- **Severity:** Minor
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:112-119
- **Category:** production-readiness (observability)
- **Source:** production-agent
- **Resolution:** remaining

Skipped old-member-set snapshots and member-set re-baselines (FR-015) are not logged.

### FINDING-17
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift:924-1001
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

No test reads the refresh log to confirm owners are named by name, not icon (FR-004).

### FINDING-18
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/Configuration.swift:742-746
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

No test for `budgetOwner(forAccount:)` when a group and an own-budget account share an id.

### FINDING-19
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/ThresholdTrackerTests.swift:331-359
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

FR-015 race coverage is one-directional; own-budget period switch and old-period skip for `accountBudgets` are untested.

### FINDING-20
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift:49-54, 151-160
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

No single test mixes own budgets after shown group members in the accounts list (full FR-020 ordering).

### FINDING-21
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift:163-182
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

Member shares are only tested with exact divisions; no rounding-boundary case (SC-004, FR-018 styling on the rounded value).

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:359-361
- **Category:** security
- **Source:** security-agent
- **Description:** The log now writes full user-chosen names. `DiagnosticLog.append` escapes control characters, so log forging is mitigated.
- **Rationale:** Keep all log writes going through `DiagnosticLog.append`.

### NOTABLE-2
- **File:** Sources/AgentTacho/IconFont.swift:43-54, 66-74
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** `pickerText` builds a new NSImage per picker item on every settings re-render.
- **Rationale:** A small main-actor cache keyed by icon and size would avoid it.

### NOTABLE-3
- **File:** Sources/UsageCore/Config/Configuration.swift:323-357, 370-393, 705-709
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `BudgetGroup` mirrors `BudgetSettings` field by field with a computed bridge.
- **Rationale:** A new budget field must be added in many places for groups; storing `BudgetSettings` directly with flat JSON keys would remove the duplication.

### NOTABLE-4
- **File:** Sources/AgentTacho/DropdownView.swift:336, Sources/AgentTacho/AccountSettingsView.swift:392-412
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The US2 summary string and the FR-013 creation defaults live in the untested app target.
- **Rationale:** Moving them into UsageCore helpers would make them testable.

## Post-Fix Spec Coverage

The fix round removed no feature code (one `?? 0` default became an optional return, callers updated). All spec requirements verified after the fix loop: FR-001 to FR-020 and FR-018a remain implemented.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (343 tests) |
| 1 | make test | 0 | 0 | passed (344 tests) |

Test suite passed in all fix rounds.
