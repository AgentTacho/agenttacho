# Tasks: Fix-Soon Review Batch

**Input**: Design documents from `specs/015-fix-soon-batch/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/release-command.md, quickstart.md

**Tests**: Required. AGENTS.md asks for test-first development of all `UsageCore` logic; test tasks come before their implementation and must fail first. Swift tests run only with `make test`, release script tests only with `make test-release`.

**Organization**: One phase per user story (US1 app correctness, US2 hardening, US3 release safety), then documentation. The stories touch different files and can be done in any order.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story from spec.md (US1 to US3)

## Conventions for every task

- Doc comments cite the spec requirements they implement (for example `spec 015 FR-001`).
- No em dash or en dash characters anywhere (code, comments, docs, commit messages).
- Every phase ends with a checkpoint: `make test` passes (Phases 2 and 3) or `make test-release` passes (Phase 4). Fix failures before the next phase.
- Commit after each phase with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.

---

## Phase 1: Setup

- [X] T001 Run `make test` and `make test-release` once in the worktree root to confirm the baseline passes before any change (no file changes).

---

## Phase 2: User Story 1 - Correct notifications and labels (Priority: P1)

**Goal**: A window reset notifies thresholds already exceeded; a period-mismatched carried-over budget entry is not shown; Claude subscription credential directories are scanned.

**Independent Test**: The tests of T002, T004 and T006 pass; see spec.md US1 scenarios 1 to 9.

### Threshold reset (FR-001 to FR-003, research R1)

- [X] T002 [P] [US1] In `Tests/UsageCoreTests/ThresholdTrackerTests.swift`, write the failing tests first:
  - for each window kind (Claude 5-hour, Claude 7-day, a Codex plan window, a weekly group, a monthly account with its own budget): an observation below 80 in the old window, then the first observation of the new window (a later window end; for the budget owners also a case with only a moved window start) at 85 produces exactly one crossing for 80; at 97 with thresholds 80 and 95 produces two crossings; at 30 produces none and a later 82 in the same window produces one;
  - a reset seen only after one or more refreshes without a usable value (stale entry, missing subscription entry) still notifies (FR-003);
  - thresholds edited in the same refresh as a reset: the edited thresholds decide the crossings;
  - no notification for the five re-baseline events: first observation after launch, period switch (spec 003 FR-017), member set change (spec 004 FR-015) including a member set change in the same refresh as a window reset (FR-002), Codex live-limits toggle, preliminary saved values (spec 010 FR-019);
  - Codex windows: a reset time that differs within `codexResetTolerance` is not a reset; a window without reset time (`.distantFuture`) that then gets one at 85 does not notify; alternating ends A, B, A, B (B later than A by more than the tolerance, values above a threshold) notifies exactly once; an observation with an earlier end is ignored (no crossing, and a following observation of the later window compares against the kept state);
  - a Codex window that appears for the first time while running records a baseline.
  Update the existing tests that encode the old rule. They are `smallResetDifferencesDoNotRebaseline` (expects no crossing at 96 after a 600 s move), the `shifted` part of `newMonthResetsStateWithABaseline` and `movedWindowStartWithTheSameEndResetsState`; check every other test that observes a new window above a threshold (`windowEndChangeResetsState` and the 5-hour reset test near line 111 reset to 10% and 5% and should still pass). Keep their names meaningful.
- [X] T003 [US1] In `Sources/UsageCore/Notifications/ThresholdTracker.swift`, change `evaluate`: check the member set first (different `memberIds` replaces the state with `lastPercent == nil`, as today). Otherwise classify a window change: for budget owners (non-nil `windowStart`) any change of start or end is a reset; for subscription and Codex windows only a known end (not `.distantFuture`) later than the recorded known end by more than the tolerance is a reset. On a reset keep the key, store the new window and set `lastPercent = 0` before comparing; for subscription and Codex windows, an earlier known end is ignored (return no crossings, keep the state unchanged); a change to or from `.distantFuture` replaces the state with `lastPercent == nil` as today. Update the type and method doc comments (spec 015 FR-001, FR-002; spec 001 FR-028/FR-029 as amended; research R1). Run `make test`.

### Period-mismatched carried-over entries (FR-004, FR-005, research R2)

- [X] T004 [P] [US1] Write the failing tests: a pure filter test in a new `Tests/UsageCoreTests/BudgetPeriodFilterTests.swift` that `droppingBudgetPeriodMismatches(configuration:)` on a snapshot with a weekly group entry and a configuration where that group is monthly keeps no entry for it, keeps matching entries, and does the same for `accountBudgets`; and a coordinator test in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`: refresh with a weekly group, then switch the group to monthly while the record source fails (a window-sensitive stub source that throws, as the existing carry-over tests use; an OpenCode batch issue does not trigger the carry-over); the snapshot has no group entry, and the tracker sends no notification; after the source recovers the monthly entry is present. Add a `BarLayout` test (existing bar layout test file) that a budget owner without an entry shows the `…` placeholder and no level.
- [X] T005 [US1] Implement the filter as `public func droppingBudgetPeriodMismatches(configuration: Configuration) -> UsageSnapshot` on `UsageSnapshot` in `Sources/UsageCore/Snapshot/UsageSnapshot.swift` and call it in `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` right after the carry-over block (`if recordSourceFailed`), before the log loop. Update the carry-over comment that says carried-over entries keep their old period (spec 015 FR-004, FR-005). Run `make test`.

### Credential directories in the scan set (FR-006, FR-007, research R3)

- [X] T006 [P] [US1] In `Tests/UsageCoreTests/LogIndexTests.swift` (next to the existing `directories(for:)` test), write the failing tests: a Claude subscription account's credential directory is included without being listed in `logDirectories`; a directory named in both settings appears once; `~/.claude` as credential directory appears once with the default; a symlink and a path with `..` to an already listed directory appear once; a missing credential directory does not make `collect` throw when another directory is scannable; sessions in a credential-only directory are attributed to that account by the directory tie-breaker (spec 001 FR-013); `collect` totals are equal whether the directory is listed only as credential directory or also as extra directory (SC-003). The existing assertion near `LogIndexTests.swift:410` must keep passing (paths returned in their expanded spelling).
- [X] T007 [US1] In `Sources/UsageCore/Logs/SessionLogSource.swift`, extend `directories(for:)`: default, `logDirectories`, then every Claude subscription account's `credentialDirectory`, deduplicated with `Attributor.canonical` (Attribution.swift) as the key while returning the first expanded spelling. Update the doc comment (spec 015 FR-006, FR-007). Run `make test`.

**Checkpoint**: `make test` passes; commit `fix(core): notify after window resets, hide period-mismatched budgets, scan credential directories`.

---

## Phase 3: User Story 2 - Safer reads and requests (Priority: P2)

**Goal**: The OpenCode reader cannot be made to run schema-defined code; the Claude request has a 45 s total limit.

**Independent Test**: The tests of T008 and T010 pass; see spec.md US2 scenarios 1 to 3.

- [X] T008 [P] [US2] In `Tests/UsageCoreTests/OpenCodeSourceTests.swift`, write the failing tests (SC-004, FR-008, FR-009):
  - a database where `message` (and, as a second case, `session`) is a view: the read fails through the table check, and a SQL function registered through the connection hook and referenced by the view never ran (counter stays 0);
  - a database where `message` is a real table whose `data` column is a `VIRTUAL` generated column calling the registered counter function: `readRows` fails with SQLite's "unsafe use of" error, the counter stays 0, and the OpenCode source reports it through the existing failed-read path. Control case on a plain `sqlite3_open_v2` connection in the test (not through `readRows`), with the function registered and `trusted_schema` left on: selecting `data` runs the function (counter > 0), so the test cannot pass vacuously;
  - a normal database reads exactly the rows it read before (existing fixtures).
- [X] T009 [US2] In `Sources/UsageCore/Logs/OpenCodeSource.swift`, change `readRows` to `readRows(path:from:liveSince:connectionHook: ((OpaquePointer) throws -> Void)? = nil)`: after opening, call the hook (test seam, `nil` in production), then run `PRAGMA trusted_schema=OFF`, then check in `sqlite_schema` that `message` and `session` have type `table`, throwing `SQLiteError` otherwise. Doc comment cites spec 015 FR-008 and research R4 (why not `SQLITE_DBCONFIG_DEFENSIVE`). Run `make test`.
- [X] T010 [P] [US2] In `Tests/UsageCoreTests/UsageEndpointClientTests.swift`, write the failing test that `UsageEndpointClient.defaultSession.configuration.timeoutIntervalForResource == 45` (FR-010), and assert the 30 s request timeout on the `URLRequest` captured by the existing stub protocol (it is set on the request, not on the session).
- [X] T011 [US2] In `Sources/UsageCore/Subscription/UsageEndpointClient.swift`, set `configuration.timeoutIntervalForResource = 45` in `defaultSession` and extend its doc comment (spec 015 FR-010). Run `make test`.

**Checkpoint**: `make test` passes; commit `fix(core): harden the OpenCode read and bound the Claude request time`.

---

## Phase 4: User Story 3 - Releases cannot silently downgrade or lose their DMG (Priority: P2)

**Goal**: An expired or revoked Developer ID stops a release unless explicitly allowed; replacing a published release goes through a draft.

**Independent Test**: The tests of T012, T014 and T016 pass with `make test-release`; see contracts/release-command.md.

- [X] T012 [P] [US3] In `scripts/release/tests/test_signing.sh`, add tests for a new `unusable_developer_ids` function (expired and revoked Developer ID lines are listed with their problem; not-trusted Developer ID and self-signed lines are not), and keep `select_identity` returning self-signed for the expired and revoked cases (selection is unchanged; rename the two `..._falls_through_to_self_signed` tests if their names suggest the release passes).
- [X] T013 [US3] In `scripts/release/lib.sh`, implement `unusable_developer_ids` next to `codesigning_identities` (same `security find-identity -p codesigning` parsing; prints `hash<TAB>name<TAB>expired|revoked`), with a header comment citing spec 015 FR-012.
- [X] T014 [US3] Move `stub_identities` from `scripts/release/tests/test_signing.sh` into `scripts/release/tests/helpers.sh` (each test file is sourced on its own by `run.sh`, and `stub_security` only offers self-signed and Developer ID listings), keeping `test_signing.sh` working. Then in `scripts/release/tests/test_preflight.sh`, add tests following contracts/release-command.md (including the "expired Developer ID only, no opt-out" row and its next-tier wording): expired Developer ID plus self-signed stops a release with a message naming the certificate, the problem and both remedies; revoked likewise; the dry run only warns and the warning says a real release would stop unless `ALLOW_TIER_DOWNGRADE=1` is set; `ALLOW_TIER_DOWNGRADE=1` passes with the deliberate-downgrade warning; a forced `SIGN_IDENTITY` passes without the stop; expired Developer ID without a self-signed certificate and `ALLOW_TIER_DOWNGRADE=1` still stops for ad-hoc unless `ALLOW_ADHOC=1`; a valid Developer ID next to an expired one passes; no Developer ID at all behaves as before. In `scripts/release/tests/test_build_scripts.sh`, add that `build-app.sh` with an empty `SIGN_IDENTITY` falls back and prints a warning naming the unusable certificate, and prints no such warning with a forced `SIGN_IDENTITY`. In `scripts/release/tests/test_makefile.sh`, add `ALLOW_TIER_DOWNGRADE` to `RELEASE_VARS`.
- [X] T015 [US3] Implement the guard in `scripts/release/lib.sh` `preflight` (after the identity selection, before the ad-hoc check, only when `SIGN_IDENTITY` is empty), the development-build warning in `scripts/release/build-app.sh` (only when `SIGN_IDENTITY` is empty), and `ALLOW_TIER_DOWNGRADE ?=` plus the export in `Makefile`; mention the variable in the `release.sh` header comment. Messages as in contracts/release-command.md. Run `make test-release`.
- [X] T016 [P] [US3] In `scripts/release/tests/test_release_flow.sh`, change `test_replace_on_published_release_clobbers_assets` and `test_replace_failure_on_published_release_says_published` to the new flow: the recorded `gh` calls show `gh release edit <tag> --draft=true` before the first upload; on an upload failure there is no `--draft=false` call and the error is the draft message (retry or delete); on success `--draft=false` is called with `--latest` when `<tag>` is the highest among the published tags and itself, `--latest=false` otherwise, and the cask update decision is unchanged (`test_replace_on_older_release_leaves_cask_unchanged` still passes). Add: a retry on a draft of an older tag while `GH_RELEASE_TAGS` (or the stub's equivalent) contains a newer tag publishes with `--latest=false`; a new release that is the highest publishes with `--latest`. Extend `stub_gh` in `scripts/release/tests/helpers.sh` if the tag list needs a canned answer.
- [X] T017 [US3] Implement in `scripts/release/release.sh`: compute `is_latest` by version (published tags from `gh release list --exclude-drafts --json tagName` plus `$tag`, through `highest_release_tag`); for an existing published release with `REPLACE=1`, switch it to a draft (`step="switching the release to a draft"`) and set `phase="draft"` before uploading with `--clobber`; every publish (new, replacement, retry of a draft) passes `--latest` when `is_latest`, else `--latest=false`. Update the header comment (spec 015 FR-016). Run `make test-release`.

**Checkpoint**: `make test-release` passes; commit `fix(release): guard the signing tier and replace published releases through a draft`.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T018 [P] Update `README.md`: in "Security and privacy", the agent session data row also names each Claude subscription account's Claude Code directory, the OpenCode row says the database is read with untrusted schema code disabled, and "Where the tokens go" says both requests give up after 45 seconds (FR-011); in the maintainer release section, describe `ALLOW_TIER_DOWNGRADE=1` and that replacing a published release turns it into a draft until the uploads succeed (FR-013, FR-016); in the configuration notes, say a credential directory no longer needs to be listed again under extra Claude Code directories.
- [X] T019 Run `make test`, `make test-release` and `make app`; scan all changed files for em and en dash characters (U+2014, U+2013), for example with `rg -n "[\x{2013}\x{2014}]"` over the changed files; fix anything found; commit `docs: document spec 015 changes`.

---

## Dependencies & Execution Order

- T001 first.
- US1, US2 and US3 are independent of each other; within each, the test task precedes its implementation (T002 then T003, T004 then T005, T006 then T007, T008 then T009, T010 then T011, T012 then T013, T014 then T015 (needs T013), T016 then T017).
- T018 after all stories (documents the final behavior); T019 last.

## Parallel Examples

- US1: T002, T004 and T006 touch different test files and can be written together.
- US2: T008 and T010 in parallel.
- US3: T012 and T016 in parallel; T014 moves `stub_identities` into `helpers.sh`, so it runs after T012 (which edits `test_signing.sh`) and touches `helpers.sh` like T016 (coordinate the two edits).

## Implementation Strategy

- MVP: Phase 2 (US1), the user-visible fixes.
- Then US2 and US3 in either order, then the README.
- Each phase is committed on its own so a review can follow the three themes separately.
