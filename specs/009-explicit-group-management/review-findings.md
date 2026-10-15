# Deep Review Findings

**Date:** 2026-10-15
**Branch:** 009-explicit-group-management
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 12 | 4 | 8 |
| Notable | 2 | - | 2 |
| **Total** | **15** | **5** | **10** |

**Agents completed:** 5/6 (Goal Alignment skipped, no PR found) + 2 external tools (CodeRabbit, Codex). Copilot skipped (disabled in config).
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 88
- **File:** Tests/UsageCoreTests/ArrangementReconcileTests.swift:371-387
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`undoRestoresARemovedGroup`, the only UsageCore check of FR-012, asserted `previous.settingsCandidate(applied: removed, undoTarget: previous) == previous`. With `undoTarget: previous`, this is `previous.reconcilingArrangement(previous: previous)`, which returns `self` at step 0. So the assertion could not fail, whatever `removingGroup` did.

**Why this matters:**
FR-012 requires Undo to restore the group's position, its members' membership and order, and their member shown-in-bar settings. The test looked thorough (both destinations, a shown share), but it proved nothing about the reconciliation path that runs when the user edits again inside the debounce window after an undo.

**How it was resolved:**
The passthrough assertion is kept and labelled as such. For each destination, the test now also checks:
- An unrelated edit after the undo keeps g at its position, with members m2 then m1, m1's share shown and m2's hidden.
- A structural edit after the undo (removing account b) runs the placement rules against the restored state: the order is `a, g, h`, g's members are still m2 then m1, and m1's share is still shown.
- The empty-group half also checks an edit after the undo.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/DropdownView.swift:92-95
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The hint "No accounts configured. Open Settings to add one." appeared only when there were no accounts and no groups. Since FR-001/FR-002, removing every account leaves the groups in place, so the hint never appeared again.

**Why this matters:**
A user with only empty groups saw no pointer to Settings. This is a stale invariant from spec 001 FR-019, and SC-004 expects the earlier behavior to hold.

**How it was resolved:**
The condition is now `configuration.accounts.isEmpty`, with a comment explaining why.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift:773-786
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`// MARK: Group lifecycle` headed a section that now holds only `removingAccount`, which no longer touches groups. `removingAccount` also created `copy` before its guard.

**Why this matters:**
The heading sent readers to the wrong place to audit the "only removingGroup deletes a group" invariant.

**How it was resolved:**
The MARK is renamed to `Account removal (spec 009 FR-002)`. The guard now returns `self`, and `copy` is created after it.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/ArrangementReconcileTests.swift:104-119, 250-259
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The test names `ownBudgetTakesThePlaceOfAPrunedGroup` and `reorderBaseWithMovedAccountAndPrunedGroup` kept the removed pruning concept alive.

**Why this matters:**
The names describe behavior that no longer exists.

**How it was resolved:**
The tests are renamed to `...ARemovedGroup` and `...AndRemovedGroup`, and the doc comment now says "removed".

### FINDING-5
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/DropdownView.swift:399-404, 430, 470
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`isGroup && members.isEmpty` was repeated with opposite polarity, and the `members` doc comment still said the list is empty only for an own budget.

**Why this matters:**
Future conditions can easily forget to combine both values.

**How it was resolved:**
A private `isEmptyGroup` property is used in both places, and the doc comment now mentions empty groups.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Config/GroupLifecycle.swift:6-16 (also Sources/AgentMeter/AccountSettingsView.swift:336-339, 504-511)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
The defaults of a new group ("Budget group", default icon, weekly, 60 USD, shown, 80/100) are written out separately in `addingGroup` and in the NewAccountSheet.

**Why this matters:**
FR-007 ties the two sets of defaults together, but nothing in the code enforces it. A change on one side would drift silently.

**What needs to happen:**
Add a shared `BudgetSettings.newDefault` / `BudgetGroup.defaultName` in UsageCore and use it in both places. This was not auto-fixed because it is a refactor of the pre-existing NewAccountSheet state.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/GroupLifecycle.swift:40-54
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
`removingGroup` builds the memberships `.ownBudget(removed.budget)` and `.group(id:, shownInBar: false)` itself. These are the same rules that `movingAccountToOwnBudget` and `movingAccountToGroup` already encode.

**Why this matters:**
These are two implementations of spec 004 FR-014/FR-016 that could drift apart.

**What needs to happen:**
Optionally build `removingGroup` from the existing move primitives. The behavior is equivalent today, and the GroupLifecycleTests pin it.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/DropdownView.swift:431, Sources/AgentMeter/AccountSettingsView.swift:681
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
The note "No accounts in this group yet" is written as a literal in two views.

**What needs to happen:**
Optionally share one constant.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentMeter/AccountSettingsView.swift:554-558, 582-589; Sources/AgentMeter/SettingsView.swift:102-109
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
Add and a confirmed Remove go through the 600 ms debounced apply. If the user presses Cmd-Z inside that window, the removal has no undo step yet. Undo then reverts the previous step and drops the pending removal.

**Why this matters:**
The remove dialog suggests Cmd-Z, so the user may press it quickly. The same window exists for every Settings edit, so this is a pre-existing pattern.

**What needs to happen:**
Apply discrete structural edits right away: pass an `applyNow` action into `GroupSettingsView`, or flush the pending apply before an undo runs. This touches the shared Settings apply and undo flow, so it is left for a separate change.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift:741-746; README.md
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
Empty groups are now routine. Older releases reject such a config, and their `ConfigStore.load()` falls back to the default configuration. On downgrade, the first edit in Settings would then overwrite `config.json`. The spec Assumptions expect the release notes to mention this, and nothing does yet.

**What needs to happen:**
Add a downgrade note to the release notes for this version (and optionally to the README): back up `config.json` before downgrading.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Arrangement.swift:220-240
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
In the `inPreviousOrder` comparator, the `(.some, nil)`, `(nil, .some)` and accounts-list tie-break branches are not exercised. Every test that reaches it moves members of a single group.

**What needs to happen:**
Add a reconcile test that, in one apply, moves members of two groups and an own-budget account into a third group.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/ArrangementEditorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
The edge case "Several empty groups: each is shown, ordered and editable on its own" has no ArrangementEditor test with adjacent empty group headers.

**What needs to happen:**
Add rows/move tests on `config().addingGroup(id: "x1").addingGroup(id: "x2")`.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/AccountSettingsView.swift:91-103
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
The branching logic behind the FR-016 account-removal message sits in a private SwiftUI property and is untested.

**What needs to happen:**
Optionally move the "group left empty" decision into UsageCore and test it.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Config/Arrangement.swift:206, 225, 247
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** `reconcilingArrangement` resolves `previous.arrangedEntries` three times per apply.
- **Rationale:** The cost is microseconds at realistic sizes, but the work is easy to share by computing the entries once.

### NOTABLE-2
- **File:** Tests/UsageCoreTests/ThresholdTrackerTests.swift:596-613
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The "never notifies" loop for an empty group cannot fail at 0%, because thresholds of 0 or below are normalized away. The second part of this observation was addressed in round 1: the undo of a removal into another group lacked a re-baseline test, and `destinationRebaselinesAfterUndo` now covers it.
- **Rationale:** The re-baseline half of the empty-group test is meaningful. The 0% half is informational.

## Post-Fix Spec Coverage

The fix round removed no implementation code. It made a condition change, a rename, a helper and new tests. Step 7b does not strictly apply, but coverage was rechecked anyway: all 16 FRs are still implemented (GroupLifecycle.swift addingGroup/removingGroup, Configuration.swift validate/removingAccount/moving*, Arrangement.swift reconcile/settingsCandidate, AccountSettingsView.swift Groups tab and RemoveGroupSheet, DropdownView.swift BudgetSection).

All spec requirements verified after fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| initial | make test | 0 | 0 | passed (680 tests) |
| 1 | make test | 0 | 0 | passed (681 tests) |

`make app` also builds after the fixes. The test suite passed in all fix rounds.

## External Tools

- CodeRabbit: 0 findings on the branch (`--base main --committed`), 0 on the fix round (`--uncommitted`).
- Codex: 0 findings on the branch (`--base main`), 0 on the fix round (`--uncommitted`).
- Copilot: skipped (disabled in config).
