# Code Review: Auto-Update

**Spec:** specs/013-auto-update/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 96%** (after the fix loop)

- Functional Requirements: 25/26 fully compliant (FR-001 to FR-025 plus FR-007a). FR-019 has one minor deviation on the line shown after a failed install from the previous run.
- Edge Cases: 16/16 (100%)
- Acceptance Scenarios: 21/21 (100%). They are automated where they concern UsageCore decisions. The real install, relaunch, Homebrew and permission checks (US2 1 and 5, US3, SC-002, SC-004) are walkthrough items.
- Success Criteria:
  - SC-003, SC-005, SC-006 and SC-007 are supported by code and tests.
  - SC-001 is supported by the schedule and the wake handling.
  - SC-002 and SC-004 are manual walkthrough checks by definition.

The first spec compliance pass scored 96%, which cleared the 95% gate for the deep review. The deep review then found more deviations:
- the rollback failure in FR-017 was not reported,
- US2 scenario 4 had no "try again",
- FR-023 decision logic sat in the app target,
- FR-022 README statements were inaccurate.

All of them were fixed in the fix loop.

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 first check 5 min after launch, then every 24 h wall clock, a check due during sleep runs shortly after wake, nothing on disk | `UpdateSchedule.isDue`, `sleptDuring`; Updater schedule loop (sleep detection, `wakeDelay`), `handleWake`; `lastCheck` in memory only | Compliant (wake fix in round 1) |
| FR-002 toggle, on by default, persists | `Configuration.checksForUpdates` (lenient, default true), About tab toggle on the draft, `Updater.apply(automatic:)` | Compliant |
| FR-003 manual check from gear menu and Settings, result on the line and in Settings | `Updater.checkNow`, `UpdateDisplay.beginningCheck/applying/dismissingTransient`, DropdownView `didResignKey` | Compliant (copied-command interaction fixed) |
| FR-004 latest published release only, release-info version equals tag, otherwise ignored, unusable fields give Download | `UpdateClient.check`, `GitHubRelease`, `ReleaseInfo`, `ReleaseEvaluator` | Compliant |
| FR-005 no credentials or identifiers, `AgentMeter/X.Y.Z`, HTTPS, no cookies or cache, redirect allowlist | ephemeral session, `makeRequest`, `UpdateHostPolicy`, `UpdateRedirectGuard`; exact header set tested | Compliant |
| FR-006 numeric `X.Y.Z` comparison | `ReleaseVersion` | Compliant |
| FR-007 automatic failures only logged, regular interval | `applying(.failure, manual: false)`, `lastCheck` set per attempt | Compliant |
| FR-007a known update stays until a successful check says otherwise | `UpdateDisplay.known`, `lineState`, `settingsKnownUpdate` | Compliant |
| FR-008 development builds never check | `UpdatePolicy.checksAllowed`, `markingDevelopmentBuild` | Compliant |
| FR-009 quiet line above the footer with action and Release notes | `UpdateLine` in DropdownView | Compliant |
| FR-010 no menu bar item, notification or window | none added | Compliant |
| FR-011 Settings > About mirror | `AboutSettingsTab.updates`, `settingsText`, `settingsKnownUpdate` | Compliant |
| FR-012 installation kinds and exactly one action | `UpdatePolicy.action`, `InstallLocation`, `HomebrewDetector` (Caskroom link checked against a live install) | Compliant |
| FR-013 Homebrew copies the command with the hint | `Updater.copyHomebrewCommand`, `UpdateState.commandCopied` | Compliant |
| FR-014 HTTPS download under the redirect rule, 100 MB cap | `UpdateClient.download` (API size, Content-Length, streamed bytes) | Compliant |
| FR-015 SHA-256 match | `UpdateInstaller.sha256`, `UpdateVerification.sha256Matches` | Compliant |
| FR-016 one app, bundle identifier, version, valid signature, notarized, same team | `DiskImageCheck`, `designatedRequirement`, `checkSignature` (strict, nested), `classifyAssessment` (hardened in rounds 1 and 2) | Compliant |
| FR-017 swap, Trash, relaunch after exit, rollback, denied means Download, outcome file | `UpdateInstaller.swap/relaunch`, `UpdateBlockReason.forReplacement`, `UpdateOutcome` | Compliant (unrecoverable rollback now reported, round 1). The swap runs inside AgentMeter before it quits, which the clarification on FR-017 allows. |
| FR-018 progress, single install, Cancel while downloading or verifying, cleanup | install steps, `installTask` guard, `cancelInstall`, `cleanUpAfterLaunch`, `removeDownloadFiles` | Compliant |
| FR-019 reasons distinguished, release page offered | `UpdateBlockReason` (all listed reasons, plus `previousVersionInTrash`), `.download`/`.retry` actions | Minor deviation: the failure read from the outcome file at launch (`.installFailed`) shows the reason without a release page link until the next check (review-findings FINDING-9) |
| FR-020 permissions and configuration carry over | same path and team, configuration untouched | Compliant (walkthrough check) |
| FR-021 every check and install step logged | `log.append(source: "update", ...)` for checks, kind, each verification step, swap, relaunch, cancel, launch outcome | Compliant (launch cleanup itself is not logged, FINDING-19, Minor) |
| FR-022 README Security and privacy and Installation | both sections; corrected in round 1 (development builds, staging folder, Try again) | Compliant |
| FR-023 decisions in UsageCore with tests | `Sources/UsageCore/Update/*`, including the new `InstallLocation`, `forDownload` and `forReplacement` | Compliant (round 1) |
| FR-024 no new dependency, no signing change | Package.swift unchanged; CryptoKit and Security are system frameworks | Compliant |
| FR-025 update-test build | `make app-update-test`, `-DAGENTMETER_UPDATE_TEST`, `#if` around the source override, `make app` unsets the flag, `release.sh` refuses it | Compliant |

### Error Handling

Every FR-019 reason has its own `UpdateBlockReason` case and text:
- offline, rate limit, server error and malformed response map to `UpdateClientError`. They only reach the log for automatic checks and become a short error for manual ones.
- download, checksum, Gatekeeper, contents, signature and replacement failures leave the installed app unchanged and offer the release page.
- download failures and Gatekeeper not reachable also offer "Try again".
- an unrecoverable rollback names the Trash location and keeps the outcome marker.

### Edge Cases

All 16 are handled:
- **Offline and rate limits:** treated as failures (FR-007, FR-007a).
- **Restart frequency:** one check per launch plus one per day.
- **Missing or unusable release information:** ignored, or offered as Download.
- **Lagging tap:** the Homebrew hint.
- **Unnotarized release:** offered as Download.
- **Oversized or redirected download:** aborted.
- **Double Install:** the `installTask` guard.
- **Quit during download:** cleanup at the next launch.
- **Failed replacement:** rollback, or a Trash path when the rollback fails.
- **Relaunch:** after the old process exits.
- **Newer release while one is shown:** the line shows the newer one.
- **Manual install, or running version newer than the release:** no line.
- **Unexpected disk image contents:** refused.

### Extra Features (Not in Spec)

- "Try again" after a failed download or Gatekeeper not reachable. US2 scenario 4 asks for it, but the FRs and the contract do not name it. Spec evolution candidate: mention it in FR-019 and contracts/update-ui.md.
- The `previousVersionInTrash` reason. It reports the FR-017 rollback failure precisely.
- Gatekeeper not reachable is its own reason (`gatekeeperUnavailable`), separate from "not notarized".

### Spec-Declared Constants

The spec has no `## Constants` section. Skipped.

## Code Quality Notes

The decisions are in UsageCore and are tested in depth (896 tests in total):
- version, release parsing, policy and installation kind, display state machine, verification verdicts, host policy, Homebrew detection, location rules, reasons.

The app layer runs the network, the tools and the file operations. Tools run with absolute paths and argument arrays. The relaunch helper passes the PID and path as positional parameters. Code requirement inputs are allowlisted. In `UpdateInstaller.run`, NSLock is used from an async context, which produces Swift 6 mode warnings. This predates this review and is noted for later.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- FR-019 and contracts/update-ui.md: name the "Try again" action for retryable failures, and the `previousVersionInTrash` reason.
- Decide whether a failed relaunch gets its own "restart required" state (review-findings FINDING-7).

### Optional Improvements
- Show a release page link with a launch-time install failure (FINDING-9).
- Read the download in chunks (FINDING-18). Log launch cleanup and detach failures (FINDING-19).
- Normalize permissions of the staged copy (FINDING-20). Bind `html_url` and asset URLs to `owner/repo` (FINDING-21).
- Small cleanups (FINDING-13, FINDING-14) and the four Notable observations in brainstorm/idea-inbox.md.

## Conclusion

The implementation covers every requirement of spec 013. The deep review passed after three fix rounds:
- All six Important findings were fixed: the unreported rollback failure, the check at the moment of wake, the missing Try again, FR-023 logic in the app, the README statements, and a Unicode line separator bypass found during re-review.
- No Critical or Important findings remain.

## Deep Review Report

**Gate: PASS** (after fix round 3). Full details: `specs/013-auto-update/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 5 | 5 | 0 | completed |
| Architecture & Idioms | 12 | 7 | 5 (4 Minor, 1 Notable) | completed |
| Security | 6 | 3 | 3 (2 Minor, 1 Notable) | completed |
| Production Readiness | 6 | 2 | 4 (2 Minor, 2 Notable) | completed |
| Test Quality | 7 | 6 | 1 (partly, Content-Length branch untested) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review (round 1 fixes) | 3 | 3 | 0 | completed |
| CodeRabbit (external) | 2 | 2 | 0 | completed (branch, round 1 and round 2 fixes: 0 new) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 2 | 2 | 0 | completed (branch, rounds 1 to 3) |
| Test Suite (regression) | 0 | 0 | 0 | passed (896 tests, 180 release tests) |
| **Total (raw)** | **43** | **30** | **13** | |

After deduplication: 34 findings. That is 0 Critical, 6 Important (all fixed), 24 Minor (16 fixed, 8 remaining) and 4 Notable. The rollback issue was reported by Codex, CodeRabbit (twice), Production Readiness and Correctness, and is counted once.

MVP: Architecture & Idioms (12 findings)

Key fixes applied:
1. **Unrecoverable rollback** (Codex, CodeRabbit, production, correctness; FR-017, FR-018):
   - It is now reported as `previousVersionInTrash` with the Trash path.
   - The failed outcome marker is kept.
   - The image is force-detached and the download removed.
2. **Check at wake** (correctness; FR-001): a check that came due during sleep now waits `wakeDelay` after wake, using a `ContinuousClock` vs `SuspendingClock` comparison in UsageCore. Polling while an install runs is gone.
3. **Try again** (architecture, correctness; US2 scenario 4): offered after a failed download or when Gatekeeper is not reachable. A cancelled retry returns to Install.
4. **FR-023 logic moved to UsageCore** (architecture, test quality): `forDownload`, `forReplacement` and `InstallLocation`, with tests. Launch cleanup deletes only `.../TemporaryItems/NSIRD_*` paths.
5. **spctl output parsing hardened** (security, re-review; FR-016): the path line is ignored, lines split on `\n` only, and app names with control or line breaking characters are refused.
6. **README** (architecture, security; FR-022): development builds, the staging folder location, and Try again.
7. **Copied-command and gear-menu behavior** (correctness, architecture; FR-003, FR-007a): the copied Homebrew command no longer swallows check results, and the gear-menu check is disabled and logged during an install.
8. **Tests** (test quality):
   - release-info 404 and 403/429
   - the 100 MB boundary
   - the exact header allowlist
   - missing draft flags
   - every single tampered step against `allPassed` (SC-003)
   - a race in the cancel test
9. **Smaller fixes:** signature checks moved off the main actor, and the received byte count is logged.

Remaining findings: none Critical or Important. One design question remains (FINDING-7, a restart-required state after a failed relaunch). Eight Minor findings remain; see Recommendations.

Post-fix spec coverage: 26/26 requirements verified.

Notable observations: 4 captured to brainstorm/idea-inbox.md.
