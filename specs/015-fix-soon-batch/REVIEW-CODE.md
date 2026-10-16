# Code Review: Fix-Soon Review Batch

**Spec:** specs/015-fix-soon-batch/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 17/17 (100%)
- Edge Cases: 15/15 (100%)
- Acceptance Scenarios: 20/20 (100%), automated in Swift Testing and the release shell tests
- Success Criteria: SC-001 to SC-004 and SC-006 covered by tests; SC-005 covered by a configuration test (the 45-second limit on the session), not by a trickling server

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 window reset compares with 0, one notification per crossed threshold | `ThresholdTracker.classify` returns `.reset`, `evaluate` sets `lastPercent = 0` and the new window (`Sources/UsageCore/Notifications/ThresholdTracker.swift`) | Compliant |
| FR-002 re-baseline events keep the baseline and win over a reset | no state on launch, period switch (new key per window kind), member set change classified first as `.rebaseline`, Codex toggle (key per live setting), preliminary Claude values skipped | Compliant |
| FR-003 reset recognized across refreshes without usable values | state kept through `liveKeys` while entries are stale, unavailable or missing | Compliant |
| FR-004 period-mismatched carried-over entries show the waiting presentation | `UsageSnapshot.droppingBudgetPeriodMismatches` called in the `recordSourceFailed` branch of `RefreshCoordinator` | Compliant |
| FR-005 no level, notification or baseline for such entries | entry removed, so `BarLayout` shows the placeholder and the tracker skips the owner | Compliant |
| FR-006 credential directories scanned once, canonical comparison | `SessionLogSource.directories(for:)` with `Attributor.canonical` (symlinks resolved, standardized) | Compliant |
| FR-007 missing credential directory skipped silently | the scanner skips missing directories as for extra directories (tested) | Compliant |
| FR-008 hardened OpenCode read; refusal is a failed read | `sqlite3_drop_modules`, `PRAGMA trusted_schema=OFF` and `requireTables` (parsed schema via `pragma_table_list`, ordinary tables only) in `OpenCodeSource.readRows`; errors flow into the existing source error path | Compliant (hardened further in review rounds 1 to 3) |
| FR-009 same records for a normal database | unchanged queries; `normalDatabaseReadsItsRows` | Compliant |
| FR-010 45-second total limit on the Claude request | `timeoutIntervalForResource = 45` on `UsageEndpointClient.defaultSession`; 30-second request timeout kept | Compliant |
| FR-011 README "Security and privacy" | data table and "Where the tokens go" updated (hardened read, 45 seconds, credential directory logs) | Compliant |
| FR-012 release stops on expired or revoked Developer ID without a usable one | `unusable_developer_ids` and `tier_guard` in `scripts/release/lib.sh`, called from `preflight`; skipped for a forced `SIGN_IDENTITY`; not-trusted stays usable | Compliant |
| FR-013 `ALLOW_TIER_DOWNGRADE=1` opt-out, deliberate-downgrade output, ad-hoc still needs `ALLOW_ADHOC`, Makefile and README | `tier_guard` warning; independent ad-hoc check; Makefile export; README table row | Compliant |
| FR-014 development builds and dry runs only warn | `build-app.sh` warning; dry-run warning with the "a real release would stop" sentence | Compliant |
| FR-015 no Developer ID at all behaves as today | `tier_guard` returns without unusable certificates | Compliant |
| FR-016 published release replaced through a draft; latest by version | `release.sh`: `gh release edit --draft=true` before uploads, `highest_release_tag` over published tags plus itself, `--latest` or `--latest=false` on every publish | Compliant |
| FR-017 release tests | `test_preflight.sh`, `test_release_flow.sh`, `test_signing.sh`, `test_build_scripts.sh` (old fall-through expectations changed to the stop) | Compliant |

### Edge Cases

All 15 are handled. A reset while the entry is stale notifies on the first good value. Edited thresholds apply on the reset refresh. Codex ends within the tolerance are the same window, alternating ends notify once for the later window, and the earlier end is ignored (`.older`). Gaining or losing a reset time re-baselines. A time zone move of a budget window is a reset. A reset that coincides with a re-baseline event does not notify. Period-mismatched entries show no level. Own-budget accounts are handled like groups. Missing credential directories are skipped, `~/.claude` as credential directory is read once, and symlink or `..` spellings are deduplicated. Member-set carry-over keeps today's stale presentation (out of scope, unchanged). A valid Developer ID next to an expired one is used. `ALLOW_TIER_DOWNGRADE=1` without a self-signed certificate still stops on the ad-hoc check. The opt-out never forces a fallback. A draft replacement is unchanged apart from the latest decision.

### Error Handling

A refused OpenCode database throws `SQLiteError`, which the source reports as a failed read with stale values. A failing draft switch leaves the release published and the exit trap says so. A failing upload after the switch leaves a draft with retry and delete instructions. A failing `gh release list` stops before anything changes on GitHub.

### Extra Features (Not in Spec)

- `connectionHook` on `OpenCodeSource.readRows`: a test seam (nil in production) used to register a side-effecting function for SC-004. Helpful, not user-visible.
- The latest decision also applies to a replacement of a draft. The spec requires it for every publish (FR-016), so this is in scope.

### Spec-Declared Constants

The spec has no `## Constants` section. Skipped.

## Code Quality Notes

The window classification is a small enum with one decision function, which keeps the reset, older, re-baseline and same cases readable. Claude reset times are normalized before they reach the tracker, so a jittering `resets_at` does not turn into repeated resets. The tier guard reuses the parser of `codesigning_identities`.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- Claude and budget-owner window identity (review-findings FINDING-21, 22, 23): tolerance 0 for Claude windows, ignoring an earlier Claude end after a login change, and a change of the weekly window's source counting as a reset. All three follow the spec's literal reset definition. Revisit them if they show up in use.

### Optional Improvements
- Share the identity parser and the tier guard predicate between lib.sh and build-app.sh (FINDING-7, 8).
- One shared session factory for the Claude and Codex usage requests (FINDING-9).
- A Codex 5-hour subject in the reset suite (FINDING-19) and a fast behavioral timeout test (FINDING-15).
- Seven Notable observations were captured to brainstorm/idea-inbox.md.

## Conclusion

The code implements every requirement of the spec. Deep review passed after three fix rounds. All three Important findings were fixed. Two of them came from re-reviewing the OpenCode hardening, which now drops virtual table modules and classifies tables from SQLite's parsed schema.

## Deep Review Report

**Gate: PASS** (after fix round 3). Full details: `specs/015-fix-soon-batch/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 3 | 0 | 3 (2 Minor, 1 Notable merged into FINDING-21) | completed |
| Architecture & Idioms | 12 | 5 | 7 (4 Minor, 3 Notable) | completed |
| Security | 3 | 2 | 1 (Notable) | completed |
| Production Readiness | 5 | 1 | 4 (1 Minor, 3 Notable) | completed |
| Test Quality | 6 | 4 | 2 (Minor) | completed |
| Re-review rounds 1 to 3 | 5 | 5 | 0 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch, round 1 and round 3 fixes) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 1 | 1 | 0 | completed (branch, rounds 1 and 2); round 3 failed (usage limit) |
| Test Suite (regression) | 0 | 0 | 0 | passed (914 Swift tests, 200 release tests) |
| **Total** | **35 (33 after dedup)** | **18** | **17** | |

By severity: 0 Critical, 3 Important (all fixed), 22 Minor (13 fixed, 9 accepted), 8 Notable (1 fixed, 7 captured).

MVP: Architecture & Idioms (12 findings)

Key fixes applied:
1. The release test runner clears `ALLOW_TIER_DOWNGRADE`, so the guard tests cannot be skewed by the caller's environment (Codex).
2. OpenCode hardening:
   - `message` and `session` must be ordinary tables. The kind comes from SQLite's parsed schema, so oddly spelled `CREATE VIRTUAL TABLE` text cannot hide a virtual table (security, re-review).
   - `sqlite3_drop_modules` keeps every virtual table module from running, including during the table check. A test proves zero connects, a control test shows the module would run otherwise, and a mutation check confirmed it (re-review).
   - The check runs inside the read transaction.
3. The README's OpenCode wording now states what the hardening really does (security, architecture; FR-011).
4. A failed replacement of a published release now notes that its downloads are unavailable until a retry publishes it (production).
5. New and stronger tests:
   - FR-005 notifications.
   - Replacement draft order, a later-asset failure and a publish failure.
   - The tier guard end to end through `release.sh`.
   - Identity dedupe (test quality).
6. Spec citations in ThresholdTracker and release.sh name their spec (architecture).

Remaining findings: none Critical or Important.

Post-fix spec coverage: 17/17 requirements verified.

Notable observations: 7 captured to brainstorm/idea-inbox.md.
