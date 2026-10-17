# Deep Review Findings

**Date:** 2026-10-17
**Branch:** 023-rebrand-agenttacho
**Rounds:** 2 fix rounds (plus a final Minor-only polish commit)
**Gate Outcome:** PASS
**Invocation:** quality-gate (after `/speckit-implement`, via `speckit-spex-gates-review-code`)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 5 | 5 | 0 |
| Minor | 30 | 30 | 0 |
| Notable | 6 | - | 6 |
| **Total** | **41** | **35** | **6** |

Counts are after deduplication across the initial review and both re-reviews.

**Agents completed:** 5/6 internal (Goal Alignment skipped: no pull request yet), plus CodeRabbit and Codex. Copilot is disabled in the deep-review config. cc-review was not detected, so the built-in review ran.

| Source | Initial | Re-review 1 | Re-review 2 |
|--------|---------|-------------|-------------|
| Correctness | 1 Important, 1 Minor | 2 Minor (combined agent) | 0 |
| Architecture & Idioms | 4 Minor, 1 Notable | 1 Important, 3 Minor (combined agent) | 0 |
| Security | 1 Important, 2 Minor, 1 Notable | 2 Minor (combined agent) | 1 Minor |
| Production Readiness | 1 Important, 1 Notable | - | 0 |
| Test Quality | 8 Minor, 2 Notable | 1 Important, 4 Minor (combined agent) | 2 Minor |
| CodeRabbit | 1 Minor | 0 | 0 |
| Codex | 0 | 1 P2 (Important) | 0 |

## Findings

### FINDING-1 Legacy symlinks, FIFOs and folders copied as file system objects
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Config/LegacyDataMove.swift
- **Category:** security
- **Source:** security agent (also reported by: correctness agent)
- **Round found:** initial
- **Resolution:** fixed (round 1, hardened in round 2)

**What is wrong:** `FileManager.copyItem` copied a symlinked legacy file as a link, so `~/.config/agenttacho/config.json` could point at AgentMeter's file or dangle. A FIFO at a legacy name could block the launch.

**Why this matters:** It contradicted "byte for byte" (FR-010) and the README, and a dotfile-managed config would silently fall back to defaults.

**How it was resolved:** A new `RegularFile.read` (one descriptor, `O_NOFOLLOW | O_NONBLOCK`, `fstat` for a regular file, size checked before reading) is shared with `LastGoodStore.load`. `LegacyDataMove` resolves a link to its target first, then reads the bytes, and writes them to a 0600 temporary file before moving it into place. A folder, FIFO or dangling link becomes the failure `not a regular file`. Tests cover absolute and relative links, a FIFO with a time limit, a folder and a dangling link.

### FINDING-2 Only the first other running copy was handled
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/SingleInstance.swift
- **Category:** correctness
- **Source:** correctness agent (also reported by: CodeRabbit, production readiness agent)
- **Round found:** initial
- **Resolution:** fixed (round 1)

**What is wrong:** With both AgentMeter and another AgentTacho running, stopping AgentMeter let the new copy run next to the other AgentTacho.

**Why this matters:** Two AgentTacho copies would poll the same endpoints and write the same configuration (FR-012, single-instance rule).

**How it was resolved:** `ensure()` loops: after each stopped copy it looks again until none is left. The watched identifier set moved into UsageCore (`RunningInstance.watchedBundleIdentifiers(own:)`) with tests.

**External tool analysis (CodeRabbit):**
> Update the lookup and handling flow in `ensure()` to process every other running copy, rather than stopping after the first match. Repeat the lookup after successfully stopping a copy until none remain; preserve the existing failure and quit behavior.

### FINDING-3 The renamed notary profile could ship 0.5.0 un-notarized
- **Severity:** Important
- **Confidence:** 80
- **File:** scripts/release/release.sh
- **Category:** production-readiness
- **Source:** production readiness agent
- **Round found:** initial
- **Resolution:** fixed (round 1, aligned with the `ALLOW_TIER_DOWNGRADE` pattern in round 2)

**What is wrong:** A missing `agenttacho-notary` profile only warned, and the maintainer's keychain holds only the old profile.

**Why this matters:** Every user moving to AgentTacho installs 0.5.0 fresh, and Gatekeeper would block its first launch.

**How it was resolved:** A real Developer ID release without the profile stops before building and names the `store-credentials` command, unless `ALLOW_UNNOTARIZED=1` is set. With the opt-out it warns "(deliberate, ALLOW_UNNOTARIZED=1)". A dry run only warns that a real release would stop. FR-015, the release contract, the README and the Makefile were updated. This is a new release rule that the spec gained in review.

### FINDING-4 Dangling legacy links were silently treated as absent
- **Severity:** Important
- **Confidence:** 90
- **File:** Sources/UsageCore/Config/LegacyDataMove.swift
- **Category:** architecture
- **Source:** tests and architecture re-review (also reported by: correctness re-review, Codex P2)
- **Round found:** re-review 1
- **Resolution:** fixed (round 2)

**What is wrong:** The presence filter used `fileExists`, which follows links, so a dangling link was dropped without a log line, contrary to the doc comment and the contract.

**Why this matters:** A broken dotfile link gave defaults with no explanation in the log (FR-010, FR-011).

**How it was resolved:** Presence now uses `attributesOfItem` (lstat). A dangling link reaches the reader and is logged as `not a regular file`.

**External tool analysis (Codex):**
> When a legacy file name is a dangling symbolic link, `FileManager.fileExists` follows the link and returns false, so this filter drops it before `readRegularFile`. The move then returns `.nothingToMove` rather than recording the documented `not a regular file` failure.

### FINDING-5 The 16 MB size cap was untested
- **Severity:** Important
- **Confidence:** 90
- **File:** Tests/UsageCoreTests/LegacyDataMoveTests.swift
- **Category:** test-quality
- **Source:** tests and architecture re-review
- **Round found:** re-review 1
- **Resolution:** fixed (round 2)

**What is wrong:** Removing the size guard passed every test, and its reason was an inline literal.

**How it was resolved:** Added the `LegacyDataMove.tooLarge` constant, a sparse-file test above the limit, and `RegularFileTests` for the shared reader's limit.

### Minor findings (all fixed)

| # | File | Finding | Source | Resolution |
|---|------|---------|--------|------------|
| 6 | LegacyDataMove.swift | Copies kept the source's mode; README promises 0600 in a 0700 folder | security | Writes 0600; Application Support folder created 0700, an existing one only loses permissions; tests |
| 7 | LegacyDataMove.swift | A destination folder linked into a legacy folder would write there (FR-009) | security | Guard against the config, Application Support and Logs folders, resolving the deepest existing ancestor; tests for a direct link, a link to the log folder and a linked parent |
| 8 | LegacyDataMove.swift | The marker folder creation bypassed that guard | re-review 2 | Guarded; test with `~/.config` linked to the legacy log folder |
| 9 | LegacyDataMoveTests.swift | Failure paths did not check the marker folder and the later `.skipped` | test quality | Assertions added to both failure tests |
| 10 | LegacyDataMoveTests.swift | The replace branch was untested, also its metadata | test quality | Test with an existing 0644 file in a 0755 folder: bytes, 0600, 0700 |
| 11 | LegacyDataMoveTests.swift | The legacy snapshot missed root folder modes and modification times | test quality, architecture | Snapshot records mode and mtime of every folder, the roots included, and links |
| 12 | LegacyDataMoveTests.swift | Temporary homes were never removed | re-review 2 | `Home` is a class that removes its root in `deinit` |
| 13 | RegularFileTests.swift | The FIFO test had no time limit | re-review 2 | `.timeLimit(.minutes(1))` |
| 14 | RunningInstance.swift | The app name was spelled out twice | architecture | `ownAppName` and `legacyAppName` constants |
| 15 | RunningInstanceTests.swift | The legacy identifier set was decided in the untested AppKit layer | test quality | `watchedBundleIdentifiers(own:)` in UsageCore with tests |
| 16 | lib.sh | `OFFICIAL_GH_REPO` split a doc comment from its function; the header said "functions only" | architecture | Moved above the comment; header updated |
| 17 | render-dmg-backgrounds.swift | First-launch steps hardcoded the name next to the `appName` constant | architecture | Interpolated; regenerated backgrounds are byte-identical |
| 18 | run.sh, test_runner.sh | `SITE_REPO` and `ALLOW_UNNOTARIZED` were not reset, and the runner test did not check them | test quality | Added to the reset list and to the runner test |
| 19 | test_notes.sh | No test checked the brew install line (FR-014) | test quality | Assertions in both notes tests |
| 20 | test_names.sh | The name check ignored file names (FR-006) | test quality | File names checked, with a scratch-repo test; historical-folder fixture now has old names in paths |
| 21 | test_names.sh | "formerly AgentMeter" once near the top was untested (User Story 5) | test quality | Test: exactly once, within the first 10 lines |
| 22 | release.sh | `ALLOW_UNNOTARIZED` order and wording differed from `tier_guard`; weak opt-out test | architecture | Opt-out checked first, "deliberate" marker, full-text assertions, dry-run opt-out test |
| 23 | LegacyDataMove.swift, LastGoodStore.swift | Duplicated safe read had already drifted (no size pre-check) | architecture | Shared `RegularFile.read` used by both; LastGoodStore log texts unchanged (its tests pass) |
| 24 | LegacyDataMove.swift | Comment on the folder mode misdescribed the behavior | architecture | Reworded to the contract's rule |
| 25 | LegacyDataMoveTests.swift | `legacySnapshot` doc comment did not match its values | architecture | Rewritten with the snapshot change |
| 26-35 | various | Overlapping re-review reports of findings 6, 7, 10 and 20 to 23 | re-reviews | Fixed with the items above |

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/RunningInstance.swift and others
- **Category:** architecture
- **Source:** architecture agent
- **Description:** The bundle identifier and repository slug are spelled out in several places.
- **Rationale:** A UsageCore `AppIdentity` would leave one Swift place to change. Captured as `single-app-identity`.

### NOTABLE-2
- **File:** Sources/AgentTacho/SingleInstance.swift
- **Category:** security
- **Source:** security agent
- **Description:** Process control is limited to exactly the two watched identifiers, and `terminate()` runs only after the user confirms.
- **Rationale:** Verification note, nothing to change; not captured in the inbox.

### NOTABLE-3
- **File:** Sources/AgentTacho/SingleInstance.swift
- **Category:** production-readiness
- **Source:** production readiness agent
- **Description:** An AgentMeter started after AgentTacho, for example by its leftover login item, is not noticed.
- **Rationale:** Captured as `watch-for-a-late-agentmeter`; the README tells users to delete AgentMeter.app.

### NOTABLE-4
- **File:** scripts/release/tests/test_names.sh
- **Category:** test-quality
- **Source:** test quality agent
- **Description:** Stale detection works per allowlist line, not per alternative.
- **Rationale:** Captured as `allowlist-stale-alternatives`.

### NOTABLE-5
- **File:** Sources/AgentTacho/App.swift
- **Category:** test-quality
- **Source:** test quality agent
- **Description:** The move's position in `AppModel.init` (after the single-instance check, before the stores) is untested.
- **Rationale:** Captured as `startup-order-test`.

### NOTABLE-6
- **File:** Sources/UsageCore/Config/RegularFile.swift
- **Category:** correctness
- **Source:** re-review 2
- **Description:** In the rare grown-after-check case, the "too large" size is the capped read count, and a file deleted between the presence check and the read is logged as "not a regular file".
- **Rationale:** Log wording only; the comment was widened, nothing captured.

## Post-Fix Spec Coverage

The fix rounds rewrote the copy and `LastGoodStore.load`. Every requirement is still implemented and tested:

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-007 new folders | `Paths` | ✓ |
| FR-008 one-time copy before loading | `LegacyDataMove.run` in `AppModel.init` | ✓ |
| FR-009 old folders untouched | presence by lstat, destination and marker guards, snapshot tests | ✓ |
| FR-010 never partial, log per failure | 0600 temporary file, move or replace, cleanup, `RegularFile` failures | ✓ |
| FR-011 log of copied files | `logLines(for:)` | ✓ |
| FR-012 AgentMeter as another copy | `watchedBundleIdentifiers`, looped `ensure()` | ✓ |
| FR-015 notary profile | default `agenttacho-notary`, release stops without it | ✓ |
| spec 010 FR-018 last good read safety | `LastGoodStore.load` through `RegularFile`, same log texts | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test; make test-release | 0; 0 | 0 | passed (1458 tests; 228) |
| 2 | make test; make test-release | 0; 0 | 0 | passed (1466; 229) |
| polish | make test; make test-release | 0; 0 | 0 | passed (1467; 229) |

Inside each round, the name check failed a few times on new comments or test names that used the old name. Each was rewritten, or allowlisted when the requirement needs it, before the round closed.
