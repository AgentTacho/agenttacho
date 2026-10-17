# Code Review: macOS Distribution (Signed DMG and Homebrew Cask)

**Spec:** specs/005-macos-distribution/spec.md
**Date:** 2026-10-14
**Branch:** 005-macos-distribution
**Reviewer:** Claude (speckit-spex-gates-review-code, ship pipeline stage 7)
**Scope:** `git diff main...HEAD` without `specs/` and `brainstorm/`: Makefile, Resources/Info.plist and DMG backgrounds, packaging/homebrew/agenttacho.rb.tmpl, scripts/release (build-app.sh, dmg-settings.py, lib.sh, make-dmg.sh, notarize.sh, release.sh, update-cask.sh, render-dmg-backgrounds.swift, tests), Sources (App.swift, SettingsView.swift, AppVersionInfo.swift, removed UsageCore.swift), Tests/UsageCoreTests, README.md

## Compliance Summary

**Overall Score: 100%** after the fix loop (97% before: 37 of 38 checked items)

- Functional Requirements: 27/27 (FR-001 to FR-025, including FR-014a and FR-021a)
- Edge Cases: 11/11 (the upload-failure case only named the delete command before the fix loop; it now names retry and delete)
- Success Criteria: SC-004 and SC-005 are covered by the stubbed release-flow and preflight tests. SC-002 follows from the cask. SC-001 and SC-003 need a second Mac or account and a real certificate; they were not measured here. SC-006 (Developer ID path) is covered by stubbed tests only, as the spec's assumptions state.
- Spec-declared constants: the spec has no `## Constants` section, so this check was skipped.

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| FR-001 identity order | lib.sh select_identity, codesigning_identities | Compliant | Untrusted self-signed identities are accepted on purpose |
| FR-002 print tier | build-app.sh `signing:` line | Compliant | Tested in test_build_scripts.sh |
| FR-003 certificate-based requirement | build-app.sh requirement check; lib.sh requirement_is_certificate_based | Compliant | cdhash requirement stops the build |
| FR-004 explicit override | `SIGN_IDENTITY` (name, SHA-1 or `-`) | Compliant | |
| FR-005 hardened runtime, timestamp for Developer ID | lib.sh codesign_flags | Compliant | Also applied to dev builds (NOTABLE-7) |
| FR-006 icon, fail when missing | build-app.sh; Info.plist CFBundleIconFile | Compliant | |
| FR-007 version and commit-count build number | lib.sh version_info; PlistBuddy stamping | Compliant | Shallow clones now stop a release |
| FR-008 dev builds, numeric short version, "-dev" display | version_info dev mode; AppVersionInfo label in Settings and log | Compliant | |
| FR-009 compressed read-only DMG with Applications link | make-dmg.sh, dmg-settings.py (UDZO) | Compliant | |
| FR-010 window with background and icons | dmg-settings.py layout; committed backgrounds | Compliant | |
| FR-011 first-launch text for non-notarized | background-unnotarized.png via render-dmg-backgrounds.swift | Compliant | |
| FR-012 no workaround for notarized | background-notarized.png; lib.sh dmg_background | Compliant | |
| FR-013 volume icon | dmg-settings.py `icon` | Compliant | |
| FR-014 signed, notarized, stapled DMG | make-dmg.sh signing; notarize.sh submit, staple, validate; checksum retaken | Compliant | |
| FR-014a profile by name, warn and continue when missing | lib.sh notary_profile_state; release.sh | Compliant | Other notarytool errors now stop instead of downgrading |
| FR-015 step order with draft and late publish | release.sh | Compliant | Also uploads release-info.json |
| FR-016 preflight stops | lib.sh preflight | Compliant | Extra checks: gh auth, tap reachability, shallow clone (NOTABLE-2) |
| FR-017 notes state tier and notarization | lib.sh release_notes | Compliant | |
| FR-018 no prompts | noninteractive wrapper, `</dev/null`, GH_PROMPT_DISABLED, BatchMode | Compliant | codesign key access documented via set-key-partition-list |
| FR-019 dry run | release.sh --dry-run (`make dmg`) | Compliant | Notes no longer claim notarization in a dry run |
| FR-020 cask with sha256, arm64, Sonoma | packaging/homebrew/agenttacho.rb.tmpl | Compliant | |
| FR-021 fresh clone, commit, push | update-cask.sh | Compliant | |
| FR-021a cask-only command | `make cask VERSION=X.Y.Z` | Compliant | Refuses draft releases |
| FR-022 caveats for non-notarized | lib.sh cask_caveats | Compliant | |
| FR-023 zap paths | template `zap trash:` | Compliant | |
| FR-024 quit before upgrade or uninstall, no relaunch by the cask | template `uninstall quit:` | Compliant | Homebrew itself reopens quit apps after `brew upgrade`, so the caveat wording needs spec evolution (FINDING-24) |
| FR-025 README sections | README.md Installation, Releasing (maintainer) | Compliant | |

### Edge Cases

All 11 are handled: existing release (stops unless `REPLACE=1`), untagged, non-matching, unpushed or moved tag and dirty tree (preflight), notarization rejection or timeout (notarize.sh stops before anything is uploaded and names the log), tap clone or push failure (published release kept, `make cask` named), upload failure (draft kept, retry and delete named), Developer ID without profile (warning, not notarized), missing self-signed certificate on a second machine (ad-hoc for dev builds, release stops), another running copy (README note), missing icon (build fails naming the file), signing tier switch (README), Intel or macOS 13 (cask `depends_on`, `LSMinimumSystemVersion`).

### Extra Features (Not in Spec)

- `release-info.json` release asset: carries version, checksum, tier and notarization so the cask-only command can render the cask without rebuilding. Helpful; part of the contracts.
- Preflight checks for `gh` authentication, tap reachability and shallow clones: keep a release from publishing when a later step would fail. Spec evolution candidate for FR-016.
- `make backgrounds`, `make test-release`: maintenance targets.
- Version label in Settings and the launch log line: the "app's own version display" FR-008 refers to.

## Code Quality Notes

The release scripts share one function library with a stub-based test suite (120 tests) that runs under the macOS Bash 3.2. The fix loop made build-app.sh and make-dmg.sh testable through `RELEASE_ROOT`, so every script now has direct tests. Remaining quality items are listed in review-findings.md (FINDING-24 to FINDING-40).

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- FR-024: Homebrew reopens a running AgentTacho after `brew upgrade`; the caveats, release notes and README should say so (FINDING-24).
- FR-016: name the gh authentication, tap reachability and shallow clone checks (NOTABLE-2).

### Optional Improvements
- The 17 remaining Minor findings and 7 Notable observations in review-findings.md.

## Conclusion

Compliance is 100% after the fix loop and no Critical or Important findings remain. Ready for verification. One wording conflict between FR-024 and current Homebrew behavior is recorded as a spec evolution candidate.

## Deep Review Report

**Gate: PASS** (after fix round 2)
**Agents completed:** 5/5 internal + 2 re-review agents (rounds 1 and 2)
**Skipped:** Goal Alignment (no PR found), Copilot (disabled in config)
**Failed:** Codex (usage limit, no findings)
**CodeRabbit:** 3 runs completed (1 Minor finding in the initial run, 0 in both re-review runs; the first attempt with `--files` failed because CLI 0.7.6 has no such option, so `--committed --base main` was used)

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 8 | 8 | 0 |
| Minor | 32 | 15 | 17 |
| Notable | 8 | 1 | 7 |
| **Total** | **48** | **24** | **24** |

Review Agents:

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     5 |     4 |         1 | completed |
| Architecture & Idioms   |    11 |     4 |         7 | completed |
| Security                |     6 |     1 |         5 | completed |
| Production Readiness    |     8 |     4 |         4 | completed |
| Test Quality            |    12 |     5 |         7 | completed |
| Re-review (round 1)     |     4 |     4 |         0 | completed |
| Re-review (round 2)     |     4 |     4 |         0 | completed |
| Goal Alignment          |     0 |     0 |         0 | skipped (no PR found) |
| CodeRabbit (external)   |     1 |     1 |         0 | completed (3 runs) |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled in config) |
| Codex (external)        |     0 |     0 |         0 | failed (usage limit) |
| Test Suite (regression) |     0 |     0 |         0 | passed (338 Swift tests, 120 release tests) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |    51 |    27 |        24 |           |

The per-agent rows count three findings more than once (the draft-failure message from Correctness, Architecture and Production Readiness; the cask-only draft check from Correctness and Production Readiness). The severity table is deduplicated. Remaining counts include Notable observations. Test Quality's partly fixed items (runner isolation, cask assertions) count as remaining.

Agent Leaderboard MVP: Test Quality (12 findings)

Key fixes applied:
1. Notarization profile check distinguishes "missing" from service, network and credential errors; a real release stops instead of silently publishing as not notarized (correctness).
2. dmgbuild dependencies `ds_store` and `mac_alias` pinned for uvx (security).
3. Builds for distribution refuse SwiftPM's native resource accessor, which would crash on users' Macs; local builds only warn (production-readiness, regression fix in round 2).
4. `make cask` refuses draft releases; a shallow clone stops a release; `version_info` fails on git errors instead of writing an empty build number (correctness, production-readiness).
5. Dry runs no longer claim "notarized" in notes and release info; one notarization predicate drives background and notes (architecture).
6. Draft failure message names retry and delete with `-R` (spec edge case, three agents).
7. build-app.sh and make-dmg.sh honor `RELEASE_ROOT` and got direct tests for tier flags, plist stamping, requirement check, backgrounds and checksums (test-quality).
8. Release-flow tests for the checksum after stapling, REPLACE on draft or missing releases and notary errors, each checked with a mutation (test-quality).

Post-fix spec coverage: 27/27 requirements verified, all covered.

Notable observations: 7 captured to brainstorm/idea-inbox.md

Details: specs/005-macos-distribution/review-findings.md

### Post-review fixes

After the gate passed, the maintainer decided the ambiguous findings and asked for all remaining Minor findings (FINDING-24 to FINDING-40) to be fixed; review-findings.md lists each resolution with its commit (`9ef8c76`, `7ecf2a3`, `6dc3873`, `9a854a6`, `faae03c`, `6819789`, `0498b05`).

- FR-024 evolved: `brew upgrade` quits AgentTacho and Homebrew opens it again afterwards (verified in the local Homebrew 7.0.9 source, `Cask::Upgrade.reopen_apps_after_upgrade`); caveats, notes and README say so.
- FR-021 extended: the release checks the checksum in release-info.json against the stapled DMG, `make cask` against the downloaded DMG asset, and the cask only moves to the latest published release.
- One `release_defaults` in lib.sh; the Makefile passes variables only through the environment, and git gets `--` before repository arguments (a `TAP_REPO` starting with `--upload-pack=` was executable before).
- Failed remote commands name their reason; the README imports the `.p12` without passwords on the command line.
- Test runner: `assert_status` runs with errexit, one-line tests are discovered, `GIT_*` and stub variables are isolated. 35 new tests (155 in total).

Severity totals after these fixes: Minor 32 found, 32 fixed; 7 Notable observations remain (unchanged). Final runs: `make test` (338 tests), `make test-release` (155 tests), `make app SIGN_IDENTITY=-` and `make dmg` all exit 0.
