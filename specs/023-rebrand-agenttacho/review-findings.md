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
| Important | 1 | 1 | 0 |
| Minor | 7 | 7 | 0 |
| Notable | 2 | - | 2 |
| **Total** | **10** | **8** | **2** |

Findings about features removed on 2026-10-17 (see the spec's Clarifications) are no longer listed; the counts cover the rest.

**Agents completed:** 5/6 internal (Goal Alignment skipped: no pull request yet), plus CodeRabbit and Codex. Copilot is disabled in the deep-review config. cc-review was not detected, so the built-in review ran.

## Findings

### FINDING-1 A missing notary profile could ship 0.5.0 un-notarized
- **Severity:** Important
- **Confidence:** 80
- **File:** scripts/release/release.sh
- **Category:** production-readiness
- **Source:** production readiness agent
- **Round found:** initial
- **Resolution:** fixed (round 1, aligned with the `ALLOW_TIER_DOWNGRADE` pattern in round 2)

**What is wrong:** A missing `agenttacho-notary` profile only warned.

**Why this matters:** Every user installs 0.5.0 fresh, and Gatekeeper would block the first launch of an un-notarized build.

**How it was resolved:** A real Developer ID release without the profile stops before building and names the `store-credentials` command, unless `ALLOW_UNNOTARIZED=1` is set. With the opt-out it warns "(deliberate, ALLOW_UNNOTARIZED=1)". A dry run only warns that a real release would stop. FR-015, the release contract, the README and the Makefile were updated. This is a new release rule that the spec gained in review.

### Minor findings (all fixed)

| # | File | Finding | Source | Resolution |
|---|------|---------|--------|------------|
| 2 | LastGoodStore.swift, RegularFile.swift | The safe read of `last-good.json` had no size check before reading | architecture | `RegularFile.read` (one descriptor, `O_NOFOLLOW` and `O_NONBLOCK`, `fstat` for a regular file, size checked before reading) used by `LastGoodStore.load`; log texts unchanged (its tests pass) |
| 3 | RegularFileTests.swift | The reader's size limit was untested | test quality | `RegularFileTests` for the limit |
| 4 | RegularFileTests.swift | The FIFO test had no time limit | re-review 2 | `.timeLimit(.minutes(1))` |
| 5 | lib.sh | `OFFICIAL_GH_REPO` split a doc comment from its function; the header said "functions only" | architecture | Moved above the comment; header updated |
| 6 | render-dmg-backgrounds.swift | First-launch steps hardcoded the name next to the `appName` constant | architecture | Interpolated; regenerated backgrounds are byte-identical |
| 7 | run.sh, test_runner.sh | `SITE_REPO` and `ALLOW_UNNOTARIZED` were not reset, and the runner test did not check them | test quality | Added to the reset list and to the runner test |
| 8 | test_notes.sh | No test checked the brew install line (FR-014) | test quality | Assertions in both notes tests |
| 9 | release.sh | `ALLOW_UNNOTARIZED` order and wording differed from `tier_guard`; weak opt-out test | architecture | Opt-out checked first, "deliberate" marker, full-text assertions, dry-run opt-out test |

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/RunningInstance.swift and others
- **Category:** architecture
- **Source:** architecture agent
- **Description:** The bundle identifier and repository slug are spelled out in several places.
- **Rationale:** A UsageCore `AppIdentity` would leave one Swift place to change. Captured as `single-app-identity`.

### NOTABLE-2
- **File:** Sources/UsageCore/Config/RegularFile.swift
- **Category:** correctness
- **Source:** re-review 2
- **Description:** In the rare grown-after-check case, the "too large" size is the capped read count.
- **Rationale:** Log wording only; the comment was widened, nothing captured.

## Post-Fix Spec Coverage

Every requirement is still implemented and tested after the fix rounds:

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-007 data folders | `Paths` | ✓ |
| FR-015 notary profile | default `agenttacho-notary`, release stops without it | ✓ |
| spec 010 FR-018 last good read safety | `LastGoodStore.load` through `RegularFile`, same log texts | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test; make test-release | 0; 0 | 0 | passed |
| 2 | make test; make test-release | 0; 0 | 0 | passed |
| polish | make test; make test-release | 0; 0 | 0 | passed |
