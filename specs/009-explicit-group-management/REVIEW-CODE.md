# Code Review: Explicit Group Management

**Spec:** specs/009-explicit-group-management/spec.md
**Date:** 2026-10-15
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 16/16 (100%)
- Edge Cases: 8/8 (100%)
- Success Criteria: 4/4 (100%)
- Contract (contracts/groups-tab.md): compliant

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 empty group valid | Configuration.swift `validate()` no longer throws `emptyGroup`; the kind is removed | Compliant |
| FR-002 no implicit deletion | `removingAccount`, `movingAccountToOwnBudget`, `movingAccountToGroup` keep the group; `settingsCandidate` no longer prunes | Compliant |
| FR-003 deletion only by Remove | `removingGroup(id:destination:)` is the only code path that drops a group | Compliant |
| FR-004 empty group keeps settings and position | group fields untouched; reconcile keeps its entry (ArrangementReconcileTests) | Compliant |
| FR-005 0% in bar, dropdown header and note | Aggregator yields a zero entry; BarLayout shows "0%" normal, placeholder before refresh; DropdownView `BudgetSection` shows the header, the note, and no members or breakdown | Compliant |
| FR-006 no notification, re-baseline | ThresholdTracker member-set comparison; tests for refill, own budgets, destination | Compliant |
| FR-007 Add with defaults, last, selected | `addingGroup(id:)` plus the Groups tab Add button sets the selection; reconcile places it last | Compliant |
| FR-008 Remove... enabled with selection, none selected after | `.disabled(selectedGroup == nil)`, `selection = nil` in onRemove | Compliant |
| FR-009 plain confirmation for empty group | RemoveGroupSheet `members.isEmpty` branch names the group | Compliant |
| FR-010 member list, one destination, Groups tab order, cancel | RemoveGroupSheet lists members, picker "Own budgets" plus `draft.groups` filtered in order; Cancel only dismisses | Compliant |
| FR-011 disappears everywhere, order kept, member placement | removingGroup plus reconcile `inPreviousOrder`; tracker drops the key | Compliant |
| FR-012 Undo restores | Settings undo restores the full previous configuration; tests strengthened in review | Compliant |
| FR-013 membership only from account side; editor note | GroupEditor lists members read-only, with the "No accounts in this group yet" note | Compliant |
| FR-014 new-account sheet "New group" kept | NewAccountSheet unchanged | Compliant |
| FR-015 caption text | exact text in GroupSettingsView | Compliant |
| FR-016 account removal message | `removalMessage` adds "The group \"<name>\" stays, without accounts." for the last member | Compliant |

### Edge Cases

All 8 edge cases are handled: the only group removed (picker offers only "Own budgets"), a destination with a different period (allowed), the new-account sheet listing empty groups (`ForEach(draft.groups)`), a hand-edited empty group (decode test), threshold state, a new account joining an empty group, removing the last member with Remove, and several empty groups.

### Extra Features (Not in Spec)

- `removingGroup` falls back to own budgets when the destination is the removed group or an unknown id. This is defensive and supports SC-003. Helpful.
- The dropdown hint "No accounts configured" now depends on accounts alone (review fix). This keeps the SC-004 behavior.

### Spec-Declared Constants

The spec has no `## Constants` section. Skipped.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- None.

### Optional Improvements
- Share the new-group defaults between `addingGroup` and the NewAccountSheet (FINDING-6).
- Apply Add and Remove right away, without the debounce, so a quick Cmd-Z undoes them (FINDING-9).
- Add a downgrade note to the release notes (FINDING-10).

## Conclusion

The code implements every requirement of the spec. Deep review ran and passed after one fix round.

## Deep Review Report

**Gate: PASS** (after fix round 1). Full details: `specs/009-explicit-group-management/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 1 | 1 | 0 | completed |
| Architecture & Idioms | 6 | 3 | 3 (Minor) | completed |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 3 | 0 | 3 (2 Minor, 1 Notable) | completed |
| Test Quality | 5 | 1 | 4 (3 Minor, 1 Notable) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch and fixes) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed (branch and fixes) |
| Test Suite (regression) | 0 | 0 | 0 | passed (681 tests) |
| **Total** | **15** | **5** | **10** | |

By severity: 0 Critical, 1 Important (fixed), 12 Minor (4 fixed), 2 Notable.

MVP: Architecture & Idioms (6 findings)

Key fixes applied:
1. The FR-012 undo test was a tautology (step 0 passthrough). It now also checks edits after the undo, unrelated and structural, against the restored order, the member order and the shown-in-bar settings (test quality).
2. A new test covers the destination group re-baselining after the undo of a removal into another group (test quality, FR-012).
3. The dropdown's "No accounts configured" hint now appears whenever no account exists, even when empty groups remain (correctness).
4. `BudgetSection` has a new `isEmptyGroup` helper, and its doc comment is corrected (architecture).
5. The MARK heading and the `removingAccount` guard are cleaned up, and the stale "pruned" test names are renamed (architecture).

Post-fix spec coverage: 16/16 requirements verified.

Notable observations: 2 captured to brainstorm/idea-inbox.md.
