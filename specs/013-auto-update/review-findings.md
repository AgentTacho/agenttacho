# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 013-auto-update
**Rounds:** 3
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 6 | 6 | 0 |
| Minor | 24 | 16 | 8 |
| Notable | 4 | - | 4 |
| **Total** | **34** | **22** | **12** |

The counts are after deduplication. Several agents and both external tools reported the same rollback problem, and it is counted once (FINDING-1).

**Agents completed:** 5/5 internal agents, plus CodeRabbit and Codex. Goal Alignment was skipped because no PR exists, and Copilot because it is disabled in the config.
**Agents failed:** none.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/AgentMeter/UpdateInstaller.swift:165-195, Sources/AgentMeter/Updater.swift:355-370
- **Category:** correctness
- **Source:** codex (also reported by: coderabbit (twice), production-readiness agent, correctness agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, cleanup in round 2)

**What is wrong:**
In `swap`, if `trashItem` succeeded but moving the staged app into place failed, the rollback ran as `try? fileManager.moveItem(at: trashed, to: installed)`, which ignored its own failure. When `trashed` was nil, it was skipped without notice. In both cases the code returned an ordinary replacement failure. `Updater` then removed the outcome marker and logged "failed, nothing replaced".

**Why this matters:**
This is the one path where the user loses the installed app: it ends up in the Trash and nothing is at `/Applications/AgentMeter.app`. The line and the log said the opposite. That breaks FR-017 (the previous app put back or the failure reported) and FR-021.

**How it was resolved:**
`swap` now checks the rollback. When the rollback fails, or the Trash location is unknown, it returns the new reason `UpdateBlockReason.previousVersionInTrash(path)`. Its text names the Trash path. `Updater` then:
- logs that the previous version could not be put back,
- keeps a failed outcome marker with that text, so whichever copy starts next shows it (FR-017),
- removes only the download and the mount point (round 2, FR-018),
- shows the reason with the release page.

Tests: `UpdateBlockReasonTests.previousVersionInTrashNamesThePath`, `onlyDownloadAndGatekeeperFailuresAllowRetry`.

**External tool analysis (CodeRabbit):**
> Update `swap` to check whether moving the trashed app back to `installed` succeeds when moving `staged` fails. If rollback fails, return a distinct replacement failure that identifies the Trash location and preserve the outcome marker so the next launch can report the failure.

**External tool analysis (Codex, P1):**
> If moving the staged bundle fails after `trashItem` succeeds, and restoring the trashed bundle also fails, the discarded `try?` leaves the only installed copy in the Trash while the staging folder is deleted. Detect and recover or preserve this failure path rather than reporting a normal failed replacement.

### FINDING-2
- **Severity:** Important
- **Confidence:** 70
- **File:** Sources/AgentMeter/Updater.swift:73-95
- **Category:** correctness
- **Source:** correctness agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`Task.sleep(for:)` runs on `ContinuousClock`, which keeps counting while the Mac sleeps. A wait that ended during sleep therefore fired at the moment of wake, before the 60 second `wakeDelay` of `handleWake` and usually before the network was back. `runCheck` set `lastCheck` before the request. The offline failure only went to the log (FR-007), so the next automatic attempt came 24 hours later.

**Why this matters:**
FR-001 requires a check that came due during sleep to run shortly after wake. A laptop that sleeps overnight could use up its daily check on an offline request every time, which pushes discovery of a release past SC-001's 25 hours.

**How it was resolved:**
The schedule loop measures each wait on both `ContinuousClock` and `SuspendingClock`. When `UpdateSchedule.sleptDuring(wallClock:awake:)` (new, in UsageCore) reports that the Mac slept, the loop waits `wakeDelay` before it checks. A second wake check then finds the check already done. Test: `UpdateScheduleTests.sleepIsDetectedFromTheClocks`.

### FINDING-3
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Update/UpdateState.swift (`failingInstall`)
- **Category:** architecture
- **Source:** architecture agent (also reported by: correctness agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, cancel interaction fixed in round 2)

**What is wrong:**
Every failed install set `known.action = .download(reason)`, including transient failures such as a failed download or Gatekeeper not being reachable. The line then offered only the release page, until the next successful check.

**Why this matters:**
US2 acceptance scenario 4 says that after a failed or interrupted download "the line offers to try again or open the release page".

**How it was resolved:**
- New action `UpdateAction.retry(DownloadTarget, UpdateBlockReason)`, shown as "Try again" next to "Release notes", with the reason after the middle dot.
- `UpdateBlockReason.allowsRetry` is true for `downloadFailed` and `gatekeeperUnavailable` only. Every verification failure still offers only the release page (SC-003).
- `installableUpdate` accepts the new action.
- Since round 2, `cancellingInstall` turns a cancelled Try again back into Install, without the old reason.

The README describes Try again. Tests: `retryableFailureOffersTryAgain`, `retryableFailureWithoutATargetOffersDownload`, `cancellingATryAgainOffersInstall`, `retryAndDownloadCarryTheirReason`.

### FINDING-4
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentMeter/Updater.swift (`downloadReason`), Sources/AgentMeter/UpdateInstaller.swift (`replacementReason`, cleanup guard), Sources/AgentMeter/InstallEnvironment.swift (translocation and disk image rules)
- **Category:** architecture
- **Source:** architecture agent (also reported by: test quality agent, as Notable)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Several decisions that FR-023 places in UsageCore lived in the app target, without tests:
- mapping a download error to its FR-019 reason,
- telling "macOS denied" apart from "failed" for a replacement (FR-017),
- the translocation and disk image location rules (installation kind, FR-012),
- the guard that decides which recorded staging path launch cleanup may delete.

**Why this matters:**
FR-023 requires the installation kind decision, install eligibility with its reasons, and the verification decisions to live in UsageCore and be covered by tests.

**How it was resolved:**
- New `UpdateBlockReason.forDownload(_:)` and `UpdateBlockReason.forReplacement(domain:code:underlyingDomain:underlyingCode:description:)`.
- New `InstallLocation` with `isTranslocated(path:)`, `isOnDiskImage(path:volumeIsReadOnly:volumeIsRootFileSystem:)` and `isRemovableStagingPath(_:)`. The last one requires an absolute `.../TemporaryItems/NSIRD_*` path with no `.` or `..` components, which also resolves the security agent's Notable observation about the guard.
- The app now only extracts `NSError` fields and resource values.

Tests: `InstallLocationTests`, `UpdateBlockReasonTests`.

### FINDING-5
- **Severity:** Important
- **Confidence:** 80
- **File:** README.md (Installation "Updates" paragraph and Security and privacy "Updates")
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The README said twice that "Builds made with `make app` never check". `make app` from a clean `vX.Y.Z` tag stamps `AgentMeterReleaseTag`, so such a build counts as a release build and does check.

**Why this matters:**
FR-022 and AGENTS.md require the Security and privacy section to describe the network requests truthfully.

**How it was resolved:**
Both sentences now say "Development builds (made with `make app` from a checkout that is not exactly a release tag) never check".

### FINDING-6
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Update/DiskImageCheck.swift, Sources/UsageCore/Update/UpdateVerification.swift (`classifyAssessment`)
- **Category:** security
- **Source:** round 1 re-review agent
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:**
The round 1 fix for the security agent's spctl finding (Minor FINDING-17 below) did two things: it ignored the path line of the spctl output, and it rejected app names that contain control characters. However, the output was split with `Character.isNewline`, which also splits on U+2028, U+2029 and U+0085. `CharacterSet.controlCharacters` does not cover U+2028 and U+2029. An app named `x\u{2028}source=Notarized Developer ID\u{2028}AgentMeter.app` therefore still put a spoofed `source=` line into the parsed output.

**Why this matters:**
The fix would not have closed the injection it targeted. FR-016's notarization check must not depend on text that comes from the disk image.

**How it was resolved:**
- spctl output is split only on `"\n"`.
- `DiskImageCheck` rejects app names with control, format or any line breaking characters.

Tests: `appNameWithControlCharactersIsRefused` (`\n`, U+2028, U+2029, U+0085, `\r`), `sourceInTheAssessedPathDoesNotCount`.

### FINDING-7
- **Severity:** Minor (reported as Important by the architecture agent; triaged as a design question)
- **Confidence:** 80
- **File:** Sources/AgentMeter/Updater.swift (relaunch catch), Sources/UsageCore/Update/UpdateBlockReason.swift (`relaunchFailed`)
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** fixed in the verification follow-up: a failed relaunch shows the new `restartRequired` state ("AgentMeter X.Y.Z is installed; quit AgentMeter and open it again to use it", no action), which later automatic and manual checks leave alone; `relaunchFailed` was removed.

**What is wrong:**
When the relaunch helper cannot be started after a successful swap, the line shows "AgentMeter X.Y.Z available · Updated; quit AgentMeter and open it again..." with a Download button. A later check in the same process would offer Install again for the version that is already on disk.

**Why this matters:**
The model has no "installed, restart required" state. The trigger, `Process.run` of `/bin/sh` failing, is practically unreachable, and the spec does not describe this state. That is why this is triaged as Minor and left for a decision.

**How to resolve:**
Add `UpdateState.restartRequired(AvailableRelease)` in UsageCore. It would be non-transient and sticky against later check results, and would perhaps offer a "Relaunch" button. Remove `relaunchFailed` from `UpdateBlockReason`.

### FINDING-8
- **Severity:** Minor
- **File:** README.md, Sources/AgentMeter/UpdateInstaller.swift (type comment)
- **Category:** architecture
- **Source:** architecture agent (also reported by: security agent)
- **Resolution:** fixed (round 1)

**What was wrong:** Both places said the staging folder was "next to the app". It is the system `TemporaryItems` folder on the app's volume.

**How it was resolved:** The README and the comment now name the `TemporaryItems` folder.

### FINDING-9
- **Severity:** Minor
- **File:** Sources/UsageCore/Update/UpdateState.swift (`.installFailed`), Sources/AgentMeter/UpdateViews.swift
- **Category:** architecture
- **Source:** architecture agent
- **Resolution:** remaining

**What is wrong:** A failed install that is read from the outcome file at launch shows only the text. It carries no release, so the line has no release page link (FR-019).

**How to resolve:** Store the version and the page URL in `UpdateOutcome`, and render "Release notes" for `.installFailed`.

### FINDING-10
- **Severity:** Minor
- **File:** Sources/AgentMeter/DropdownView.swift, Sources/AgentMeter/Updater.swift (`runCheck`)
- **Category:** architecture
- **Source:** architecture agent
- **Resolution:** fixed (round 1)

**What was wrong:** During an install, "Check for Updates…" in the gear menu did nothing and logged nothing. A manual check that joined a running check was not logged either.

**How it was resolved:** The menu item is now disabled during an install, as in Settings. A skipped manual check and a joined manual check are both logged.

### FINDING-11
- **Severity:** Minor
- **File:** Sources/UsageCore/Update/UpdateState.swift (`beginningCheck`, `applying`)
- **Category:** correctness
- **Source:** correctness agent (also reported by: architecture agent)
- **Resolution:** fixed (round 1)

**What was wrong:** While the Homebrew command confirmation showed (`.commandCopied`, about 8 seconds):
- a manual check showed no progress and no result (FR-003),
- a no-newer result left `known` set, so the stale update came back afterwards (FR-007a).

**How it was resolved:**
- A manual check replaces the confirmation.
- Only a newer release keeps the confirmation.
- No newer release clears `known` and shows "up to date".

Tests: `resultsDuringCommandCopied`, `manualCheckDuringCommandCopiedShowsItsResult`.

### FINDING-12
- **Severity:** Minor
- **File:** Sources/AgentMeter/Updater.swift, Sources/UsageCore/Update/UpdateClient.swift (`download`)
- **Category:** architecture
- **Source:** architecture agent (also reported by: production readiness agent)
- **Resolution:** fixed (round 1)

**What was wrong:** The "downloaded N bytes" log line used the size the API reported, not the bytes actually received.

**How it was resolved:** `download` now returns the number of bytes received. The log shows that number next to the size the release lists.

### FINDING-13
- **Severity:** Minor
- **File:** Sources/AgentMeter/InstallEnvironment.swift, Sources/UsageCore/Update/UpdateState.swift, Sources/UsageCore/Update/ReleaseVersion.swift
- **Category:** architecture
- **Source:** architecture agent
- **Resolution:** partly fixed

**What is wrong:** The finding named three pieces of dead or duplicated code:
- the unused `InstallEnvironment.bundleIdentifier`,
- the `checking(manual:)` payload, which is never read,
- `ReleaseVersion.init?(tag:)`, which only tests use, while `ReleaseEvaluator` strips the "v" itself.

**How it was resolved:** The unused constant was removed. The other two remain as cleanups.

### FINDING-14
- **Severity:** Minor
- **File:** Sources/AgentMeter/UpdateViews.swift:33-40
- **Category:** architecture
- **Source:** architecture agent
- **Resolution:** remaining

**What is wrong:** `UpdateStatusText` builds the "title · reason" text itself instead of using the tested `UpdateState.lineText`.

### FINDING-15
- **Severity:** Minor
- **File:** Sources/AgentMeter/Updater.swift (`runInstall`)
- **Category:** production-readiness
- **Source:** production readiness agent
- **Resolution:** fixed (round 1)

**What was wrong:** Both signature checks hashed the whole bundle on the main actor during the install.

**How it was resolved:** Both checks now run in `Task.detached`. Listing the mounted image and the swap (a rename) stay on the main actor because they are fast.

### FINDING-16
- **Severity:** Minor
- **File:** Sources/AgentMeter/Updater.swift (`secondsUntilDue`)
- **Category:** correctness
- **Source:** correctness agent
- **Resolution:** fixed (round 1)

**What was wrong:** When an automatic check came due during an install or another check, the schedule loop polled once per second until that ended.

**How it was resolved:** During an install or a running check, the wait is at least `wakeDelay`.

### FINDING-17
- **Severity:** Minor
- **File:** Sources/UsageCore/Update/UpdateVerification.swift (`classifyAssessment`)
- **Category:** security
- **Source:** security agent
- **Resolution:** fixed (round 1, completed in round 2 by FINDING-6)

**What was wrong:** `source=Notarized Developer ID` was matched anywhere in the spctl output. That includes the first line, which names the assessed path from the disk image.

**How it was resolved:** The path line is ignored, and the source must be a whole line of its own. Test: `sourceInTheAssessedPathDoesNotCount`.

### FINDING-18
- **Severity:** Minor
- **File:** Sources/UsageCore/Update/UpdateClient.swift:152-172
- **Category:** production-readiness
- **Source:** production readiness agent
- **Resolution:** remaining

**What is wrong:** The download iterates `AsyncBytes` one byte at a time. That is fine for today's 10 MB disk image, but costs CPU near the 100 MB cap.

**How to resolve:** Receive data in chunks through a data delegate, or use `download(for:delegate:)` with a byte cap.

### FINDING-19
- **Severity:** Minor
- **File:** Sources/AgentMeter/UpdateInstaller.swift (`detach`, `cleanUpAfterLaunch`)
- **Category:** production-readiness
- **Source:** production readiness agent
- **Resolution:** remaining

**What is wrong:** Launch cleanup and a failed `hdiutil detach` are not logged (FR-021).

**How to resolve:** Return a cleanup summary and the detach status, and log both.

### FINDING-20
- **Severity:** Minor
- **File:** Sources/AgentMeter/UpdateInstaller.swift (`stage`)
- **Category:** security
- **Source:** security agent
- **Resolution:** remaining

**What is wrong:** `ditto` keeps the POSIX modes and ACLs from the image, and the code signature does not cover them. A repacked image of the genuine app with permissive modes would install a bundle that other local users can write.

**How to resolve:** Use `ditto --noacl`, normalize modes (`go-w`), or refuse group or world writable entries before the staged signature check.

### FINDING-21
- **Severity:** Minor
- **File:** Sources/UsageCore/Update/ReleaseInfo.swift:57-61, ReleaseEvaluator.swift
- **Category:** security
- **Source:** security agent
- **Resolution:** remaining

**What is wrong:** `html_url` only has to be an https URL. Asset URLs only have to be on an allowed host. Neither is bound to the configured `owner/repo`, so a manipulated API response could send the Download fallback to another site.

**How to resolve:** Require `github.com/<owner>/<repo>/releases/` prefixes, or build the page URL locally from the tag.

### FINDING-22 to FINDING-27 (test quality)
- **Severity:** Minor
- **Source:** test quality agent
- **Resolution:** fixed (round 1)

1. Tests for `check` with 404 and 403/429 on `release-info.json` (`releaseInfoNotFoundIsIgnored`, `releaseInfoRateLimit`).
2. The download limit boundary: exactly the limit succeeds, and one byte more in the final partial chunk fails (`downloadLimitBoundary`). The `Content-Length` early abort is still untested.
3. The header tests now assert the exact header set, an allowlist rather than a denylist (FR-005).
4. A release without the draft and prerelease flags is ignored (`missingDraftAndPrereleaseFlagsCountAsSet`). The weak `!=` assertion now checks the available version.
5. `allPassed` and `verdict` are tested with every single tampered step (`oneTamperedStepNeverPasses`, SC-003).
6. The `ProgressLog.task` data race in the cancel test is fixed with a locked setter.

### FINDING-28 and FINDING-29 (round 1 re-review)
- **Severity:** Minor
- **Source:** round 1 re-review agent
- **Resolution:** fixed (round 2)

1. In the `.previousVersionInTrash` branch, the downloaded disk image stayed in place. Now only the outcome marker stays (FR-018).
2. Cancelling a Try again brought back the old failure reason. Now it returns to Install (`cancellingATryAgainOffersInstall`).

### FINDING-30 (round 2 external re-review)
- **Severity:** Minor (Codex P2)
- **File:** Sources/AgentMeter/Updater.swift (`.previousVersionInTrash` branch)
- **Source:** codex
- **Resolution:** fixed (round 3)

**What was wrong:** The new branch for an unrecoverable rollback returned early, so it skipped the forced `hdiutil detach` that the other failure paths run. If the ordinary detach had failed, the image stayed mounted for as long as the old process ran.

**How it was resolved:** The branch now force-detaches the image when it is still mounted, and then removes the download files (FR-018). Codex re-reviewed the change and found no issues.

## Notable Observations

### NOTABLE-1
- **File:** Sources/AgentMeter/Updater.swift (runInstall, check helper)
- **Category:** architecture
- **Source:** architecture agent
- **Description:** The R4 verification order is driven by the app. It re-invokes the six-argument `verdict` after each step with literal `true` values, and the `?? .signatureMismatch` fallback can never be reached.
- **Rationale:** A small `VerificationProgress` value in UsageCore that records each step would make the order a tested decision.

### NOTABLE-2
- **File:** Sources/AgentMeter/Updater.swift
- **Category:** production-readiness
- **Source:** production readiness agent
- **Description:** Quitting during a download leaves the hidden mount, the partial disk image and any running tool until the next launch. The spec allows this.
- **Rationale:** A `willTerminate` handler could detach the image and clean up right away.

### NOTABLE-3
- **File:** Sources/AgentMeter/UpdateInstaller.swift (`relaunch`)
- **Category:** production-readiness
- **Source:** production readiness agent
- **Description:** The relaunch helper polls without a time limit. If termination were ever deferred, the helper would wait forever and the line would stay at "Installing".
- **Rationale:** Today nothing defers termination. A bounded wait would make this robust.

### NOTABLE-4
- **File:** Sources/UsageCore/Update/UpdateVerification.swift (`designatedRequirement`)
- **Category:** security
- **Source:** security agent
- **Description:** The code requirement could also include `and notarized`. That would check notarization through the Security framework, also for the staged copy, without parsing spctl text.
- **Rationale:** It needs the ticket to be available (stapled or online), the same as spctl.

## Post-Fix Spec Coverage

The fix rounds only added code or moved it into UsageCore; no requirement code was deleted. I checked every FR against the code after round 2:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 schedule, wake | Updater loop + `UpdateSchedule.isDue`, `sleptDuring` | ✓ |
| FR-002 toggle | `Configuration.checksForUpdates`, AboutSettingsTab | ✓ |
| FR-003 manual check | `Updater.checkNow`, `UpdateDisplay.beginningCheck/applying` | ✓ |
| FR-004 latest release, release-info | `UpdateClient.check`, `ReleaseEvaluator` | ✓ |
| FR-005 requests, redirects | `UpdateClient`, `UpdateHostPolicy`, `UpdateRedirectGuard` | ✓ |
| FR-006 version comparison | `ReleaseVersion` | ✓ |
| FR-007 / FR-007a failures, known update | `UpdateDisplay.applying` | ✓ |
| FR-008 development builds | `UpdatePolicy.checksAllowed` | ✓ |
| FR-009 / FR-010 line | `UpdateLine` in DropdownView | ✓ |
| FR-011 Settings | `AboutSettingsTab.updates` | ✓ |
| FR-012 installation kind | `UpdatePolicy.action`, `InstallLocation`, `HomebrewDetector` | ✓ |
| FR-013 Homebrew | `Updater.copyHomebrewCommand` | ✓ |
| FR-014 download | `UpdateClient.download` | ✓ |
| FR-015 checksum | `UpdateVerification.sha256Matches` | ✓ |
| FR-016 contents, signature, notarization | `DiskImageCheck`, `designatedRequirement`, `classifyAssessment` | ✓ |
| FR-017 swap, rollback, outcome | `UpdateInstaller.swap`, `UpdateOutcome` | ✓ |
| FR-018 progress, cancel, cleanup | `UpdateDisplay` install steps, `cancelInstall`, `cleanUpAfterLaunch` | ✓ |
| FR-019 reasons | `UpdateBlockReason` | ✓ |
| FR-020 permissions carry over | same path, same team, configuration untouched | ✓ (walkthrough) |
| FR-021 logging | `log.append(source: "update", ...)` throughout | ✓ |
| FR-022 README | Installation and Security and privacy sections | ✓ |
| FR-023 logic in UsageCore | Update/*.swift with tests | ✓ |
| FR-024 no dependency | Package.swift unchanged | ✓ |
| FR-025 update-test build | Makefile, build-app.sh, release.sh, `#if AGENTMETER_UPDATE_TEST` | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 0 | 0 | passed (895 tests) |
| 1 | make test-release | 0 | 0 | passed (180 tests) |
| 2 | make test | 0 | 0 | passed (896 tests) |
| 2 | make test-release | 0 | 0 | passed (180 tests) |
| 3 | make test | 0 | 0 | passed (896 tests) |
| 3 | make test-release | 0 | 0 | passed (180 tests) |

The test suite passed in all fix rounds.

## Remaining Findings

None are Critical or Important. FINDING-7 is a design question: whether a failed relaunch should become its own "restart required" state. The remaining Minor findings are FINDING-9, 13 (partly), 14, 18, 19, 20 and 21. The remaining Notable observations are NOTABLE-1 to NOTABLE-4.
