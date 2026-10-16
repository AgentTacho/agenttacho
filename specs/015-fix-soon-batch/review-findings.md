# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 015-fix-soon-batch
**Rounds:** 3
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 22 | 13 | 9 |
| Notable | 8 | 1 | 7 |
| **Total** | **33** | **17** | **16** |

**Agents completed:** 5/6 (Goal Alignment skipped: no PR found), plus CodeRabbit (3 runs) and Codex (3 of 4 runs; the round 3 run failed on a usage limit)
**Agents failed:** none (Codex round 3: failed, usage limit)

Two findings were merged during dedup: the README wording finding (Security and Architecture) and the budget-owner alternation observation (Correctness, merged into FINDING-21).

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** scripts/release/tests/run.sh:122
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The release test runner unset every release variable except the new `ALLOW_TIER_DOWNGRADE`.

**Why this matters:** With `ALLOW_TIER_DOWNGRADE=1` in the caller's environment, `make test-release` leaked it into every isolated test, so the guard tests that expect a stop would fail. The suite would also no longer verify the guard (FR-017).

**How it was resolved:** Added the variable to the runner's unset list, and added it to `test_runner_unsets_git_and_stub_variables`.

**External tool analysis (Codex):**
> When callers have `ALLOW_TIER_DOWNGRADE=1` in their environment, `make test-release` leaks it into every isolated release test because `run.sh` does not unset the new release variable. Add it to the runner's release-variable unset list.

### FINDING-2
- **Severity:** Important
- **Confidence:** 90
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift (requireTables)
- **Category:** security
- **Source:** re-review round 1
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** The round 1 virtual table check matched `CREATE VIRTUAL` at the start of the stored schema text. A crafted file can write `CREATE<TAB>VIRTUAL`, `CREATE  VIRTUAL` or `CREATE/**/VIRTUAL`. SQLite still loads that text as a virtual table, but the check classified it as an ordinary table.

**Why this matters:** FR-008 is about crafted files, and one schema edit got past the check. That also made the README claim untrue.

**How it was resolved:** The kind now comes from SQLite's parsed schema (`pragma_table_list WHERE schema = 'main'`), which reports `virtual`, `view` and `table` separately. A test byte-patches the stored text to use a tab, and I checked by hand that the patched table still loads as a virtual table.

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift (readRows)
- **Category:** security
- **Source:** re-review round 2
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** `pragma_table_list` sets up the column count of every virtual table in the schema, which calls each module's `xConnect`, and it ignores errors. So the table check itself ran fts5, fts3 or rtree code on the file's shadow-table data.

**Why this matters:** The guard ran the very code that FR-008 keeps away from the reader.

**How it was resolved:** `sqlite3_drop_modules(db, nil)` now runs right after opening, before `trusted_schema=OFF` and the table check. AgentMeter's queries use no virtual tables. The new test `virtualTableModuleCodeNeverRuns` registers a counting module `prob` and patches `message` to use it, then expects the refusal and zero connects. A control test shows that a plain connection does call the module. A mutation check (the drop disabled) makes the test fail. The table check also moved inside the read transaction (FINDING-25).

### FINDING-4
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift (requireTables)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, completed by FINDING-2 and FINDING-3)

**What is wrong:** Virtual tables are listed with type `table` in `sqlite_schema`, so an fts5 `message` passed the check.

**Why this matters:** A virtual table runs module code on data from the file.

**How it was resolved:** Virtual tables are now refused (see FINDING-2, FINDING-3), with a new fts5 test.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 75
- **File:** README.md:131, 166
- **Category:** security (also reported by: architecture-agent)
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, updated in round 3)

**What is wrong:** The README said that code stored in the database file is "switched off". `trusted_schema=OFF` only refuses functions that are not innocuous.

**Why this matters:** The "Security and privacy" section must stay true (FR-011, AGENTS.md).

**How it was resolved:** The README now says that stored code cannot call functions that are unsafe for untrusted files, that virtual table modules are switched off, and that `message` and `session` must be ordinary tables.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 88
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift (requireTables)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The `names` parameter and the SQL each named the two tables, and the two lists could drift apart.

**Why this matters:** A third name would always fail with "no such table".

**How it was resolved:** The function reads all main-schema tables and checks the lowercased `names`.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 82
- **File:** scripts/release/lib.sh:173-221
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `unusable_developer_ids` copies the `security find-identity` parser of `codesigning_identities`.

**Why this matters:** If one copy changes and the other does not, the guard and the identity selection could disagree.

**How it was resolved:** Not fixed. This is a refactor with no behavior change, and both copies are covered by tests in test_signing.sh. It is a candidate for a later cleanup.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 72
- **File:** scripts/release/build-app.sh:92-100
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** build-app.sh writes the guard condition of `tier_guard` again.

**Why this matters:** The rule lives in two places.

**How it was resolved:** Not fixed. This is a refactor with no behavior change. The build warning is tested in test_build_scripts.sh.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 78
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:49-57
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The Claude and Codex session configurations each carry their own 45 and 30 literals.

**Why this matters:** FR-010 requires the two limits to be equal, and nothing ties them together.

**How it was resolved:** Not fixed. Both values are 45 today and tested per client. A shared factory is a refactor beyond this batch.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 78
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Bare FR citations next to spec 015 citations pointed at the wrong spec.

**Why this matters:** AGENTS.md requires accurate requirement citations.

**How it was resolved:** Every citation in those blocks now names its spec.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:97-99
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The comment said a member set change "resets" the state, but a member set change now re-baselines.

**Why this matters:** In this file a reset notifies from 0, so the comment pointed the wrong way.

**How it was resolved:** Reworded to "re-baselines" and cited spec 015 FR-002.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:252-268
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `evaluate` looks up `states[key]` twice.

**Why this matters:** It is a readability issue only.

**How it was resolved:** Not fixed. The behavior is correct and covered by the reset tests.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 70
- **File:** scripts/release/release.sh:2, 8-13
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The header had an ambiguous FR citation and an over-long line.

**Why this matters:** Spec 005 and spec 015 both have an FR-015 and an FR-016.

**How it was resolved:** The header now cites spec 005 and is re-wrapped.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/BudgetPeriodFilterTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The FR-005 test used groups without thresholds, so it could never see a crossing.

**Why this matters:** The FR-005 assertions passed vacuously.

**How it was resolved:** The group now has thresholds 80 and 95 and a prior weekly baseline. The test expects no crossing after the switch, a baseline at 85 and `[95]` at 96.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/UsageEndpointClientTests.swift:240-248
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** SC-005 is checked through the session configuration only, not with a request that never finishes.

**Why this matters:** The test would not notice if the limit were set but not applied.

**How it was resolved:** Not fixed. A real 45-second test is too slow for the suite. The production client uses `defaultSession` (App.swift), and URLSession enforces `timeoutIntervalForResource`.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 75
- **File:** scripts/release/tests/test_release_flow.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The only failing-replacement test failed on the first upload and did not pin the draft order.

**Why this matters:** SC-006 is about a set that no longer matches after a partial upload.

**How it was resolved:** Added a draft-before-upload order check, a later-asset failure test (`release-info.json`) and a publish failure test.

### FINDING-17
- **Severity:** Minor
- **Confidence:** 80
- **File:** scripts/release/tests/test_signing.sh:127-132
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The dedupe test had no duplicate line in its fixture.

**Why this matters:** The "once per hash" behavior was untested.

**How it was resolved:** The same expired identity is now listed twice, and the test expects one output line.

### FINDING-18
- **Severity:** Minor
- **Confidence:** 70
- **File:** scripts/release/tests/test_preflight.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The tier guard was only tested through `preflight`, never through `release.sh` end to end.

**Why this matters:** A change that exports `SIGN_IDENTITY` before preflight would skip the guard without any test failing.

**How it was resolved:** Three `run_release` tests: the stop before build with no GitHub calls, the opt-out building self-signed, and the dry run warning while it falls back.

### FINDING-19
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/ThresholdTrackerTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The reset suite covers the Codex weekly window but not the Codex 5-hour window.

**Why this matters:** SC-001 names every window kind.

**How it was resolved:** Not fixed. Both Codex windows go through the same `evaluate` path with the same tolerance and differ only in their key. It is a candidate for a follow-up test.

### FINDING-20
- **Severity:** Minor
- **Confidence:** 75
- **File:** scripts/release/release.sh (on_exit)
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** After a failed replacement of a published release, the output did not say that the release had been public, or that its downloads were now unavailable.

**Why this matters:** The maintainer could not tell that users were affected.

**How it was resolved:** A `was_published` flag adds a note line. Tests check that the note appears and that it is absent for a release that was a draft all along.

### FINDING-21
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:225-240
- **Category:** production-readiness (also reported by: correctness-agent, as a Notable)
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** Claude and budget-owner windows use tolerance 0. A reset time that flips across a minute rounding boundary is now a reset (it notifies) instead of a silent re-baseline.

**Why this matters:** If such flips happened, they could cause repeated notifications.

**How it was resolved:** Not fixed. `normalizedReset` rounds to the minute, and the endpoint's jitter is sub-second around whole hours, so no flip occurs in practice. A tolerance for Claude windows would change the spec's reset definition, so this is a spec evolution candidate.

### FINDING-22
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:233-239
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** An earlier known end of a Claude window is ignored (`.older`). If the Claude login behind an account changes, notifications can stay silent until the old end passes.

**Why this matters:** It could cause missed notifications for up to one window.

**How it was resolved:** Not fixed. The spec's window reset definition requires ignoring earlier ends for subscription windows. This is a spec evolution candidate (for example, re-baseline on a credential directory change).

### FINDING-23
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:228-232
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** A weekly budget window that moves because its source changed counts as a reset and can notify. The source can change from the fallback calendar window to the aligned window after launch, or when the alignment account changes.

**Why this matters:** It could cause a notification for a threshold that was already exceeded at launch.

**How it was resolved:** Not fixed. The spec defines a budget-owner reset as any different window start or end. Treating a change of window source as a re-baseline needs a spec update.

### FINDING-24
- **Severity:** Minor
- **Confidence:** 70
- **File:** scripts/release/tests/test_release_flow.sh
- **Category:** test-quality
- **Source:** re-review round 1
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** The test for "no note on a draft" did not check where the run failed.

**Why this matters:** The test could pass if the run failed for an unrelated reason.

**How it was resolved:** It now asserts the upload failure message first.

### FINDING-25
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift (readRows)
- **Category:** correctness
- **Source:** re-review round 2
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** The table check ran before `BEGIN`, outside the read snapshot.

**Why this matters:** The schema could change between the check and the reads.

**How it was resolved:** The check now runs after `BEGIN`.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift:339-371
- **Category:** security
- **Source:** security-agent
- **Description:** The connection sets no `SQLITE_LIMIT_LENGTH` and no progress handler. Huge stored values or expensive innocuous expressions can exhaust memory or stall a refresh.
- **Rationale:** SQLite's own guidance for untrusted databases recommends both.

### NOTABLE-2
- **File:** scripts/release/release.sh (on_exit)
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The `published` exit phase now only covers a failed draft switch, and the later `phase="published"` assignment is dead.
- **Rationale:** The implicit meaning is easy to break in the next change.

### NOTABLE-3
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift, LogDirectoryScanner.swift, Attribution.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The scanner keeps its own copy of the canonical path function that dedup and attribution use.
- **Rationale:** FR-006 attribution depends on the copies staying identical.

### NOTABLE-4
- **File:** Sources/AgentMeter/SettingsView.swift:218-221
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The settings caption does not mention that credential directories are scanned automatically.
- **Rationale:** It still invites the double entry that FR-006 makes unnecessary.

### NOTABLE-5
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:237-239
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** "Older" observations are ignored with no limit and no log line.
- **Rationale:** Silent suppression is hard to diagnose.

### NOTABLE-6
- **File:** scripts/release/release.sh:150-156
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** With GitHub's immutable releases, the draft switch always fails, and the retry advice loops.
- **Rationale:** The message could point to a new patch version instead.

### NOTABLE-7
- **File:** scripts/release/lib.sh (tier_guard), release.sh
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** The "deliberate tier downgrade" statement only appears in preflight, not in the final `done:` line.
- **Rationale:** It scrolls away during a long release.

NOTABLE-8 (re-review round 3: the `requireTables` comment named shadow tables, which cannot occur) was fixed in the comment and is not captured.

## Post-Fix Spec Coverage

The fix loop removed only the text-based virtual table check, which was replaced by the parsed-schema check. All spec requirements were verified after the fix loop.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 to FR-003 | ThresholdTracker.classify / evaluate | ✓ |
| FR-004, FR-005 | UsageSnapshot.droppingBudgetPeriodMismatches, RefreshCoordinator | ✓ |
| FR-006, FR-007 | SessionLogSource.directories(for:) | ✓ |
| FR-008, FR-009 | OpenCodeSource.readRows (drop_modules, trusted_schema=OFF, requireTables) | ✓ |
| FR-010 | UsageEndpointClient.defaultSession | ✓ |
| FR-011 | README How it works, Security and privacy | ✓ |
| FR-012 to FR-015 | lib.sh unusable_developer_ids, tier_guard, preflight; build-app.sh | ✓ |
| FR-016 | release.sh draft switch, latest flag | ✓ |
| FR-017 | test_preflight.sh, test_release_flow.sh, test_signing.sh | ✓ |

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test / make test-release | 0 / 0 | 0 | passed (911 / 194) |
| 1 | make test / make test-release | 0 / 1 then 0 | 1 (own new assertion, message wording) | fixed, passed (912 / 200) |
| 2 | make test | 1 then 0 | 1 (test fixture: writable_schema refused) | fixed, passed (912 / 200) |
| 3 | make test / make test-release | 0 / 0 | 0 | passed (914 / 200) |

Both failures came from new tests and were fixed in the same round. No regression in existing tests.

## Remaining Findings

No Critical or Important findings remain. The nine remaining Minor findings (FINDING-7, 8, 9, 12, 15, 19, 21, 22, 23) are refactors, slow-test trade-offs, or behavior the spec's reset definition prescribes. FINDING-21, 22 and 23 are spec evolution candidates.
