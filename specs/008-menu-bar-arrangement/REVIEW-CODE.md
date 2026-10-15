# Code Review: Menu Bar Arrangement

**Spec:** specs/008-menu-bar-arrangement/spec.md
**Date:** 2026-10-15
**Reviewer:** Claude (speckit.spex-gates.review-code)
**Diff:** `git diff main...HEAD` (branch 008-menu-bar-arrangement)

## Compliance Summary

**Overall Score: 98% (49/50)**

- Functional Requirements: 16/17 (FR-004a has a minor deviation in wording; nothing observable changes)
- Edge Cases: 13/13 (100%)
- Acceptance Scenarios: 15/15 (100%)
- Success Criteria: 5/5 (100%)

`make test` baseline was 620 tests in 68 suites, all passing. After the deep review fixes it is 628 tests, all passing, and `make app` builds.

## Detailed Review

### Functional Requirements

| FR | Implementation | Status | Notes |
|----|----------------|--------|-------|
| FR-001 | `Arrangement` (entries plus per-group members) and `Configuration.arrangedEntries` in `Sources/UsageCore/Config/Arrangement.swift` | Compliant | Entry refs are kind-qualified |
| FR-002 | `BarLayout.segments` iterates `arrangedEntries`. Members follow their group in member order; when the group is hidden, its shown members take the group's position | Compliant | |
| FR-003 | `DropdownView.content` uses `ForEach(configuration.arrangedEntries)`; `BudgetSection` gets members in member order; Unassigned is rendered last | Compliant | |
| FR-004 | Optional `Configuration.arrangement`, encoded only when set. `reconcilingArrangement` step 0 returns the config unchanged when the order and structure are unchanged. `dataRelevant()` ignores the arrangement | Compliant | Loading never writes; a checkbox or rename stores nothing |
| FR-004a | `reconcilingArrangement` step 3 stores the order when one was stored before, when the arrangement was edited, or when the result differs from the default order | Minor deviation | When nothing is stored and the resolved order equals the default order (for example a new group added last), nothing is stored. The bar, the dropdown and later placements behave exactly as if the order had been stored, so only the file differs. The spec text says "MUST first store the order currently in effect". |
| FR-005 | New entries are appended after the base order; new members are appended last in their group | Compliant | |
| FR-006 | Step 2.2: placed right after the former group, or at the group's old position via the nearest earlier surviving entry when `pruningEmptyGroups` deleted it | Compliant | |
| FR-007 | Steps 2.1 and 2.3: the account is removed from its old place and appended last in the new group | Compliant | |
| FR-008 | Resolution drops refs that are no longer entries or members | Compliant | |
| FR-009 | `MenuBarSettingsTab` is the second tab (`SettingsView`). Each row shows icon, name and kind caption; members are indented. Neither-entry-nor-member accounts and Unassigned are not listed | Compliant | |
| FR-010 | `ArrangementEditor.move` uses `onMove` semantics. Member moves are allowed only within their group, entry moves only before an entry row or at the end, and a group carries its member block | Compliant | |
| FR-010a | Move Up/Move Down buttons with Option-Command-Up/Down Arrow. `canMoveUp`/`canMoveDown` are false with no selection and at either end of a level | Compliant | |
| FR-011 | Lossy decoding (`Lossy`, `try?` on the whole key). `arrangedEntries` ignores unknown, duplicate and wrong-level refs and appends missing items in default order | Compliant | Now tested for 11 malformed shapes |
| FR-012 | `isShownInBar` / `settingShownInBar` write the same fields as the editor toggles, through the shared draft | Compliant | |
| FR-013 | The preview uses `BarLayout.segments(snapshot:configuration: draft)` and the same renderer, with the same placeholder when empty | Compliant | Warning styling is carried by the glyph prefix, as in the real bar |
| FR-014 | The draft is applied with a debounce, and every applied change registers an undo step | Compliant after fix | The deep review fixed a case where an edit made right after Undo was judged against the undone state |
| FR-015 | Accounts and Groups tabs are unchanged | Compliant | |

### Edge Cases

All 13 edge cases trace to `reconcilingArrangement`, `arrangedEntries` or `ArrangementEditor`, and each one has a unit test: new entry, new member, leaving a group (with and without the group being deleted), joining a group, moving group to group, removal, hand edits, no stored order, wrong-level ids, shared ids, invalid accounts and Unassigned, empty bar placeholder, and the only row at its level.

### Extra Features (Not in Spec)

- **No-op guard against rewriting a stale hand-edited order** (step 0). This supports FR-004 and is helpful.
- **Rows of hidden entries drawn in secondary color.** This comes from the tab contract, so it is not scope creep.

### Spec-Declared Constants

The spec has no `## Constants` section. Check skipped.

## Recommendations

### Critical (Must Fix)

- None.

### Spec Evolution Candidates

- FR-004a and the "No stored order" edge case: say that the order is stored on the first change only when the resulting order differs from the default. A result equal to the default is indistinguishable in the bar and the dropdown.

### Optional Improvements

- See the remaining Minor findings in `review-findings.md`: share the lenient decoder, use one shown-in-bar mapping, unify the row helpers, log order changes, and add unit tests for the undo-registration decision.

## Conclusion

Compliance is 98%, above the 95% threshold for the deep review. The one deviation is in wording only and changes no observable behavior. It is a candidate for spec evolution.

## Deep Review Report

**Gate: PASS** (after fix round 1 and two follow-up passes on the fixes). Full details: `specs/008-menu-bar-arrangement/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 2 | 1 | 1 (Notable) | completed |
| Architecture & Idioms | 8 | 2 | 6 (4 Minor, 2 Notable) | completed |
| Security | 2 | 1 | 1 (Notable) | completed |
| Production Readiness | 2 | 0 | 2 (1 Minor, 1 Notable) | completed |
| Test Quality | 7 | 5 | 2 (Notable) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 2 | 2 | 0 | completed (0 on the branch, 2 on the fixes, 0 on the final diff) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed (branch and fixes) |
| Re-review round 1 | 3 | 1 | 2 (1 Minor, 1 Notable) | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed (628 tests) |
| **Total** | **26** | **12** | **14** | |

After deduplication: 6 Important (all fixed), 12 Minor (6 fixed), 8 Notable.

MVP: Test Quality (7 findings)

Key fixes applied:
1. An edit made right after Undo is now reconciled against the restored state, through the new pure `Configuration.settingsCandidate(applied:undoTarget:)` (correctness). FR-014.
2. Undo registration now restores what the user saw (`undoTarget ?? applied`), so an edit on top of an undo can be undone. The `restoringUndo` flag is removed. The stale `undoTarget` is cleared on a config reload (CodeRabbit, re-review). FR-014.
3. Member row ids are now `member:<accountId>`, so they cannot collide for ids containing `/` (security). FR-010a.
4. New tests cover:
   - the hidden state of every shown-in-bar getter
   - shared-id moves among three entries
   - the stored order of the remaining members
   - malformed arrangement shapes
   - every kind of new entry
   - edits after an undo
   - group pruning in `settingsCandidate`

   (test quality) FR-005, FR-007, FR-008, FR-011, FR-012, US1-5.
5. A stale `BudgetSection` comment and the `undoTarget` comment were corrected (architecture).

Post-fix spec coverage: 17/17 requirements verified. The removed `restoringUndo` flag was replaced, and FR-014 is still covered.

Notable observations: 8 captured to brainstorm/idea-inbox.md.
