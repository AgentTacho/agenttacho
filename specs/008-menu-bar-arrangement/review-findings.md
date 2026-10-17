# Deep Review Findings

**Date:** 2026-10-15
**Branch:** 008-menu-bar-arrangement
**Rounds:** 1 (with two follow-up passes on the fixes)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 6 | 6 | 0 |
| Minor | 12 | 6 | 6 |
| Notable | 8 | - | 8 |
| **Total** | **26** | **12** | **14** |

**Agents completed:** 5/5 internal (Goal Alignment skipped, no PR found) + 2 external tools (CodeRabbit, Codex). Copilot is disabled in the config.
**Agents failed:** none. The first CodeRabbit call failed on an unsupported `--files` flag (CLI 0.7.6). It was rerun with `--committed --base main`.

## Findings

### FINDING-1
- **Severity:** Important (reported as Minor; raised because it breaks FR-014)
- **Confidence:** 80
- **File:** Sources/AgentTacho/SettingsView.swift:101-133
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Suppose the user pressed Undo and then made any edit within the 600 ms debounce, for example a rename or a change to the refresh interval. The draft then no longer equalled the undo target, and it was reconciled against `applied`, which was still the configuration the user had just undone. The placement rules treated the reverted structure as a fresh change. Here is the sequence the agent reproduced with a probe test. Start from `[b, a, g, h]`, move b into g, press Undo, then change the refresh interval. The result was `[a, g, b, h]` instead of `[b, a, g, h]`.

**Why this matters:**
FR-014 says Undo restores the previous state. Here an unrelated keystroke right after Cmd-Z moved entries silently. No undo step was registered, so the user could not get the order back.

**How it was resolved:**
The candidate logic is now a pure UsageCore function, `Configuration.settingsCandidate(applied:undoTarget:)`. It prunes empty groups, then reconciles against `undoTarget ?? applied`. An undo target applied unchanged still passes through untouched (step 0 of `reconcilingArrangement`). `SettingsView.applyNow` uses this function and clears `undoTarget` only after a successful apply. The new test `editAfterUndoKeepsTheRestoredOrder` fails against the old baseline (mutation checked).

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/SettingsView.swift:120-127
- **Category:** external
- **Source:** coderabbit (re-review of round 1)
- **Round found:** 1 (re-review)
- **Resolution:** fixed (round 1)

**What is wrong:**
After an Undo restored A, an edit to C made within the debounce was saved without any undo step, because the `restoringUndo` flag suppressed registration for whatever was applied next. A later Cmd-Z then skipped A.

**Why this matters:**
The user cannot undo back to the state they saw before their edit (FR-014).

**How it was resolved:**
The `restoringUndo` flag is gone. `applyNow` computes `shown = undoTarget ?? applied` and registers an undo step that restores `shown` whenever the applied candidate differs from it. So applying an undo exactly as restored registers nothing, and any edit on top of it can be undone back to the restored state.

**External tool analysis (CodeRabbit):**
> Update the undo handling around `applyNow()` so `undoTarget` remains available until registration is decided, and skip registration only when saving the undo restoration itself. If the user edits restored configuration A to C before the debounce expires, register an undo step that restores A rather than the prior configuration B.

### FINDING-3
- **Severity:** Important
- **Confidence:** 82
- **File:** Tests/UsageCoreTests/ArrangementEditorTests.swift:197-216
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`isShownInBar` was only checked in its true state for Claude and Codex subscription rows. A getter that always returned true for these kinds would have passed.

**Why this matters:**
FR-012 and US3 need the checkbox to reflect a setting changed in an editor.

**How it was resolved:**
`writesTheSameSettingAsTheEditors` now asserts the hidden state through the getter for every kind and for the member share. A new test, `readsAHiddenSettingFromTheEditors`, starts with hidden subscription and Codex settings.

### FINDING-4
- **Severity:** Important
- **Confidence:** 78
- **File:** Tests/UsageCoreTests/ArrangementEditorTests.swift:158-170
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The only test for a group and an account sharing an id used two entries, where every move is a swap. A regression to id-only lookups in `shift`, in drag moves, or in the FR-006 anchor would have passed.

**Why this matters:**
US1 scenario 5 and the edge case about shared ids name this case explicitly.

**How it was resolved:**
The new test `sharedIdMovesActOnTheNamedKindOnly` uses three entries and two members. It covers dragging each kind, Move Up/Down on each kind, and FR-006 placement after the group (not after the same-id account).

### FINDING-5
- **Severity:** Important
- **Confidence:** 78
- **File:** Tests/UsageCoreTests/ArrangementReconcileTests.swift:119-147
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
No fixture left more than one member in the old group, so "the remaining members keep their order" (FR-007, FR-008) was never checked.

**Why this matters:**
A regression back to accounts-list order would have gone unnoticed.

**How it was resolved:**
The new test `remainingMembersKeepTheirStoredOrder` stores members as `[m3, m2, m1]`, which is the reverse of the accounts list. It then removes m2 and, separately, moves m2 to another group, and checks that the remaining stored order is `[m3, m1]`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/ArrangementTests.swift:76-103
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Only malformed elements were tested. An `arrangement` value of the wrong shape (a number, a string, an array, null, or `entries`/`members` of the wrong type) depends on two `try?` guards that no test covered.

**Why this matters:**
If either guard were dropped, a hand edit like `"arrangement": 42` would make the whole configuration invalid, which breaks FR-011.

**How it was resolved:**
A new parameterized test, `malformedArrangementShapesAreIgnored`, has 11 shapes. For each one it decodes a full `Configuration`, validates it, and expects the default order.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Bar/ArrangementEditor.swift:12-17
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Member row ids were `"member:<groupId>/<accountId>"`. Ids from a hand-edited configuration may contain `/`, so group `a/b` with member `c` collided with group `a` with member `b/c`.

**Why this matters:**
Duplicate identities in a reorderable SwiftUI List give undefined selection behaviour, and Move Up/Down could act on the wrong row.

**How it was resolved:**
Member row ids are now `"member:<accountId>"`. That is unique because an account belongs to at most one group, and it stays stable across moves. A test was added and data-model.md was updated.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 92
- **File:** Sources/AgentTacho/DropdownView.swift:362
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

**What is wrong / how resolved:** The `BudgetSection.members` doc comment still said "accounts-list order". It now says member order (FR-003).

### FINDING-9
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/SettingsView.swift:25-28
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

**What is wrong / how resolved:** The `undoTarget` comment claimed the target "was reconciled when it was first applied", which is not true for a loaded configuration. The comment was rewritten together with the FINDING-1/2 fix.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/ArrangementReconcileTests.swift:61-82
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong / how resolved:** Only a new Claude subscription was tested for FR-005. The new test `everyKindOfNewEntryGoesLast` also covers a Codex subscription, an own-budget account, and a new group with a stored order.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/SettingsView.swift:110-114
- **Category:** external
- **Source:** coderabbit (second pass on the fixes)
- **Resolution:** fixed (round 1)

**What is wrong / how resolved:** If an Undo was followed by an edit straight back to the applied state, nothing was written and no undo step was left. The no-write branch now also registers an undo back to the restored state when it differs.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/SettingsView.swift:82-89
- **Category:** correctness
- **Source:** re-review agent
- **Resolution:** fixed (round 1)

**What is wrong / how resolved:** A hand-edited `config.json` adopted by the reload handler could leave a stale `undoTarget` behind after a failed save. The reload branch now clears `undoTarget`.

## Remaining Findings (Minor, not blocking)

### FINDING-13
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/Arrangement.swift:58-65
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `Lossy<Value>` duplicates the private `Lenient<T>` in Sources/UsageCore/Subscription/UsageEndpointClient.swift:144-149.
- **Action needed:** Share one internal helper. This is cosmetic, and both copies behave the same.

### FINDING-14
- **Severity:** Minor
- **File:** Sources/UsageCore/Bar/BarLayout.swift:61-86
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The shown-in-bar mapping exists both in `BarLayout.segments` and in `Configuration.isShownInBar(_:)`.
- **Action needed:** Make `segments` use `isShownInBar`, so the checkbox and the bar cannot drift apart if a new account kind is added.

### FINDING-15
- **Severity:** Minor
- **File:** Sources/UsageCore/Bar/ArrangementEditor.swift, Sources/UsageCore/Config/Arrangement.swift, Sources/AgentTacho/MenuBarSettingsTab.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The kind-qualified id string is built in two places. `isEntry` means two different things (an account predicate and a row case). The app module adds its own private `isMember`.
- **Action needed:** Put `id` on `EntryRef`, make the row helpers public, and rename the account predicate.

### FINDING-16
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/Arrangement.swift:203
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `reordered` is also true when the arrangement was cleared, not only when it was reordered.
- **Action needed:** Rename it to `arrangementChanged`.

### FINDING-17
- **Severity:** Minor
- **File:** Sources/AgentTacho/App.swift:164-180, Sources/UsageCore/Config/Configuration.swift:637-639
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** The diagnostic log does not say when the order changed, when an order was first stored, or when a hand-edited arrangement was dropped or partly ignored.
- **Action needed:** Add an "order changed / order stored" suffix to the save log line, and log one informational line when a stored arrangement had references ignored.

### FINDING-18
- **Severity:** Minor
- **File:** Sources/AgentTacho/SettingsView.swift:101-150
- **Category:** test-quality
- **Source:** re-review agent
- **Description:** The undo-registration decision (`shown`, when to register, when to clear `undoTarget`) still lives in SwiftUI state and has no unit test. Only `settingsCandidate` is tested.
- **Action needed:** Extract a small pure apply-state type into UsageCore and test the undo sequences.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Config/Arrangement.swift:203-244
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** Suppose a drag in the Menu Bar tab and a structural edit to the same account land in the same 600 ms debounce. The FR-006/FR-007 placement then overrides where the user dropped the account.
- **Rationale:** This is unlikely through the UI, but the drop would be lost silently. One option is to flush the pending apply before a reorder.

### NOTABLE-2
- **File:** Sources/UsageCore/Config/Arrangement.swift:271-326, Sources/UsageCore/Bar/ArrangementEditor.swift:3-23
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The config layer depends on `ArrangementRow`, a settings-row type that lives under `Bar/`.
- **Rationale:** The layering is inverted, and the folder names no longer say where things live.

### NOTABLE-3
- **File:** Sources/UsageCore/Config/Arrangement.swift:131-174
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The idiom `x.asArrangement(x.arrangedEntries)` appears five times, and `asArrangement` never uses `self`.
- **Rationale:** A `resolvedArrangement` property would shrink the API.

### NOTABLE-4
- **File:** Sources/AgentTacho/MenuBarSettingsTab.swift, Sources/UsageCore/Bar/ArrangementEditor.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** One body evaluation of the Menu Bar tab resolves `arrangedEntries` about five times, and every snapshot invalidates the whole List.
- **Rationale:** This is negligible at realistic sizes, but the cost grows quadratically.

### NOTABLE-5
- **File:** Sources/UsageCore/Config/Arrangement.swift:49-55
- **Category:** security
- **Source:** security-agent
- **Description:** The stored arrangement is not size-bounded. A hand-edited list with many junk references is kept and walked on every render until the next structural edit.
- **Rationale:** Only the local user can write the file, so this is self-inflicted slowness.

### NOTABLE-6
- **File:** Tests/UsageCoreTests/ArrangementReconcileTests.swift:72-82
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** `additionMatchingTheDefaultKeepsNothingStored` locks in that no arrangement is stored when the resolved order equals the default order. Read literally, FR-004a says the order must be stored on the first change covered by FR-005 to FR-008.
- **Rationale:** The bar and the dropdown cannot tell the difference. This is a spec-evolution candidate (see REVIEW-CODE.md).

### NOTABLE-7
- **File:** Sources/AgentTacho/DropdownView.swift:97-106
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The dropdown section order, Unassigned staying last (FR-003), and SC-001 (bar order equals dropdown order) are view-level and have no unit test of their own. Both views do iterate `arrangedEntries`, which is tested.
- **Rationale:** A refactor of the view could break them without any test failing.

### NOTABLE-8
- **File:** Sources/AgentTacho/SettingsView.swift:137-146
- **Category:** correctness
- **Source:** re-review agent
- **Description:** Redo is never available in Settings, because the undo closure registers no inverse step. This was already the case before this feature. FR-014 asks only for Undo.
- **Rationale:** Users may expect Cmd-Shift-Z to work.

## Post-Fix Spec Coverage

The fix round removed the `restoringUndo` flag from SettingsView. The code that replaced it still implements FR-014.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 | `Configuration.arrangedEntries` (Arrangement.swift) | ✓ |
| FR-002 | `BarLayout.segments` | ✓ |
| FR-003 | `DropdownView` `ForEach(configuration.arrangedEntries)`, Unassigned last | ✓ |
| FR-004, FR-004a | Optional `Configuration.arrangement`, `reconcilingArrangement` store decision | ✓ |
| FR-005 to FR-008 | `reconcilingArrangement` placement rules | ✓ |
| FR-009 | `MenuBarSettingsTab`, second tab in `SettingsView` | ✓ |
| FR-010, FR-010a | `ArrangementEditor.move/moveUp/moveDown/canMove*`, buttons with Option-Command-Up/Down | ✓ |
| FR-011 | Lossy `Arrangement.init(from:)`, tolerant `arrangedEntries` | ✓ |
| FR-012 | `isShownInBar` / `settingShownInBar` | ✓ |
| FR-013 | Preview with `BarLayout.segments` on the draft | ✓ |
| FR-014 | `settingsCandidate`, `undoTarget`, `registerUndo(restoring: shown)` | ✓ |
| FR-015 | Accounts and Groups tabs unchanged | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (620 tests) |
| 1 | make test | 0 | 0 | passed (628 tests) |
| 1 (follow-ups) | make test, make app | 0 | 0 | passed (628 tests), app built |

Test suite passed in all fix rounds. A mutation check confirmed that the new undo test fails against the old baseline.
