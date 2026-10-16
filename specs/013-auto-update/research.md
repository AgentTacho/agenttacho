# Research: Auto-Update

Decisions for spec 013. Each entry: decision, rationale, alternatives.

## R1: Where the check reads the release

**Decision**: Two requests per check. First `GET https://api.github.com/repos/rhuss/agentmeter/releases/latest` (returns the newest published, non-draft, non-prerelease release: `tag_name`, `html_url`, `assets[].name`, `assets[].size`, `assets[].browser_download_url`). Then `GET` the `browser_download_url` of the asset named `release-info.json`, which redirects from `github.com` to the release asset host. The DMG URL comes from the asset whose name equals `release-info.json`'s `dmg` field.

**Rationale**: The API gives the tag (needed for FR-004's version equality), the release page and the asset sizes in one documented, unauthenticated call (60 requests per hour per IP, far above one per day). `releases/latest` already excludes drafts and prereleases (FR-004).

**Alternatives**: `https://github.com/rhuss/agentmeter/releases/latest/download/release-info.json` (one request, but the tag is only visible in the redirect chain, and an HTML redirect is a weaker contract); an appcast file (needs a new release artifact, FR-024).

## R2: Redirect policy and request hygiene

**Decision**: A dedicated ephemeral `URLSession` (no URL cache, no cookie storage, `reloadIgnoringLocalAndRemoteCacheData`) and a task delegate that allows a redirect only when the new URL is `https` and its host is in the allowlist `api.github.com`, `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`; otherwise it returns `nil` and the request fails with a redirect error (FR-005, FR-014). Headers: `User-Agent: AgentMeter/X.Y.Z`, `Accept: application/vnd.github+json` for the API call. No `Authorization` header, ever. The allowlist check is a pure function in `UsageCore` (`UpdateHostPolicy`).

**Rationale**: Mirrors the existing `RedirectRefuser` pattern of `UsageEndpointClient`, but GitHub asset downloads need exactly one cross-host redirect. An explicit list keeps the README statement exact.

**Alternatives**: suffix match on `githubusercontent.com` (would admit `raw.githubusercontent.com` and user content hosts; rejected).

## R3: Download size limit

**Decision**: Reject before download when the API's asset `size` exceeds 100 MB; during download, a `URLSessionDownloadDelegate`/bytes loop aborts once received bytes exceed 100 MB (the server's size could lie). The release-info.json fetch is limited to 64 KB.

**Rationale**: FR-014; the DMG is about 10 MB today.

## R4: Verification chain

**Decision**: In this order, stopping at the first failure (FR-015, FR-016, SC-003):
1. SHA-256 of the downloaded file (CryptoKit `SHA256`) equals `release-info.json`'s `sha256` (lowercase hex compare).
2. Gatekeeper assessment of the DMG with its stapled ticket: `/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 <dmg>`; exit status 0 and output containing `source=Notarized Developer ID`.
3. Mount read-only and hidden: `/usr/bin/hdiutil attach -readonly -nobrowse -noautoopen -mountpoint <tmp>/mnt <dmg>`.
4. Contents: exactly one top-level `*.app` directory; other entries (the `Applications` symlink, `.background`, `.DS_Store`, `.VolumeIcon.icns`, `.fseventsd`, `.Trashes`) are ignored. Its `CFBundleIdentifier` equals the running app's, its `CFBundleShortVersionString` equals the release version.
5. Code signature of that app with the Security framework: `SecStaticCodeCreateWithPath` and `SecStaticCodeCheckValidityWithErrors` with `kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode` against the requirement `identifier "<bundle id>" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "<running team>"` (Developer ID Application issued by Apple, same team).
6. Gatekeeper assessment of the app: `spctl --assess --type execute --verbose=2 <app>` reports `source=Notarized Developer ID` (the DMG's notarization covers the nested app; the ticket is found online, and we are online right after the download).

7. After staging (R8 step 1), step 5 runs again on the staged copy, closing the gap between check and use.

The decision logic (which step failed, which reason) is a pure function `UpdateVerification.verdict(...)` over the step results, in `UsageCore`; running the tools is app-side. An `spctl` result that says assessments are disabled, or that fails with a network or ticket lookup error, is classified as "unavailable" and shown as `gatekeeperUnavailable` instead of "not notarized" (nothing is replaced either way). Starting URLs from the API (release info, DMG) must also pass `UpdateHostPolicy`, not only redirects.

**Rationale**: The checksum ties the file to the published release information; the signature and notarization tie the app to the same Developer ID team even if GitHub or the release information were compromised (the real trust anchor). `spctl` is Apple's own Gatekeeper decision and needs no private API.

**Alternatives**: `SecAssessmentCreate` (deprecated API surface); checking only the checksum (trusts GitHub alone; rejected); checking the `notarized` keyword in the code requirement (requires a stapled ticket on the app itself, which releases do not have).

## R5: The running app's identity

**Decision**: Team identifier from `SecCodeCopySelf`, `SecCodeCopyStaticCode` and `SecCodeCopySigningInformation` with the `kSecCSSigningInformation` flag (`kSecCodeInfoTeamIdentifier` is only returned with that flag). Running version from `CFBundleShortVersionString` (the display version is `X.Y.Z-dev` for local builds). Release build and notarized flag from the bundle stamps `AgentMeterReleaseTag` and `AgentMeterSigning`/`AgentMeterNotarized` that build-app.sh already writes (`AppVersionInfo`). The running app is eligible for one-click install only with a release tag, `developer-id` signing, the notarized stamp and a non-empty team identifier.

**Rationale**: The team must come from the real signature (it is the anchor for R4 step 5); the stamps only gate eligibility.

## R6: Installation location facts

**Decision**: Facts gathered app-side, judged in `UsageCore` (`InstallContext` to `UpdateAction`):
- translocated: the bundle path contains `/AppTranslocation/` (`SecTranslocateIsTranslocatedURL` exists only as a symbol in `Security.tbd`, not in the public SDK headers, so it is not used; a translocated copy also lives on a read-only nullfs mount, which the next check catches);
- disk image or read-only volume: `URLResourceValues.volumeIsReadOnly`, plus the bundle path starting with `/Volumes/` while not on the boot volume;
- writable: `FileManager.isWritableFile(atPath:)` for both the bundle and its parent folder (FR-012);
- owner: covered by the writability test (an app owned by root or another user is not writable; no admin prompt, spec Assumptions).

## R7: Homebrew detection

**Decision**: Homebrew leaves a symlink `<prefix>/Caskroom/agentmeter/<version>/AgentMeter.app` pointing at the installed app (verified on a real 0.2.1 install: `-> /Applications/AgentMeter.app`) plus `.metadata/INSTALL_RECEIPT.json`. An installation is Homebrew-managed when, for a prefix in `/opt/homebrew` and `/usr/local`, some `Caskroom/agentmeter/*/AgentMeter.app` symlink resolves (standardized, symlinks resolved) to the running bundle's path (FR-012, review M9). The matching is a pure function over `(candidate symlink targets, running path)`; reading the directory is a small injected closure.

**Rationale**: Path match avoids treating a disk image copy as Homebrew-managed just because a cask was once installed.

**Alternatives**: `brew list --cask` (spawns Homebrew, slow, needs PATH); receipt JSON (records the app name, not the target folder).

## R8: Replacement, relaunch and App Management

**Decision**: AgentMeter replaces its own bundle in-process while still running, then relaunches:
1. Stage: `ditto` the verified app from the mounted image into a staging folder on the destination volume (`FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)`), then detach the image.
2. Swap: `FileManager.trashItem(at: appURL)` (keeps the resulting Trash URL), then `moveItem(staged, appURL)`. If the move fails, move the trashed bundle back to `appURL` (rollback) and report "replacement failed" with the system error (FR-017).
3. Record: write `outcome.json` (from version, to version, result) into the update folder (R10).
4. Relaunch: start `/bin/sh -c 'while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2"' sh <pid> <appPath>` with `Process`, then `NSApplication.shared.terminate`. The new app starts only after the old process exited (FR-017, spec 005 single instance).

A running process may move its own bundle: the executable stays mapped. Because the bundle is modified by AgentMeter itself, signed by the same team as the old and the new bundle, macOS's App Management protection (macOS 13+) does not prompt (review I6). If the system still denies a step (`NSFileWriteNoPermissionError` or `EPERM`), the rollback runs and the reason "macOS did not allow AgentMeter to replace itself" is shown with "Download" (FR-017).

**Rationale**: Doing the file operations before quitting means failures are reported by the still running app, and no helper binary or privileged process is needed (FR-024). Consequence for FR-017 (amended in the spec): on a failed swap the previous app is put back while the old process keeps running, so nothing needs to be "started again"; the outcome file only carries a successful update to the new process (and a failure if the process ends unexpectedly between swap and relaunch). The two claims that are not documented by Apple (no App Management prompt for a same-team self-replacement; the `/bin/sh` relauncher outliving an app started as a login item) are checked in quickstart.md section 2 step 5.

**Alternatives**: a helper script that replaces the bundle after quit (attributed to `/bin/sh`, may trigger the App Management prompt; failures would have no UI); `FileManager.replaceItemAt` (does not put the old version into the Trash, which the spec asks for).

## R9: Scheduling

**Decision**: An app-side loop wakes at most every hour (and on `NSWorkspace.didWakeNotification`, 60 s after wake so the network is up) and asks the pure `UpdateSchedule.isDue(now:launchedAt:lastCheck:)`: the first check is due 5 minutes after launch, later ones 24 hours of wall-clock time (`Date`) after the last check attempt (FR-001). Nothing is persisted. Disabling the toggle stops the loop; enabling it restarts it with `lastCheck` unchanged.

**Rationale**: The loop sleeps on the suspending clock, whose deadlines do not pass while the Mac sleeps, so a wait never ends at the moment of wake before the network is up; the wake notification restarts the loop with a 60 s wait. Re-evaluating wall-clock time hourly and on wake keeps SC-001 for laptops that sleep at night (review I5).

## R10: Temporary files and the outcome marker

**Decision**: One folder per user, `FileManager.default.temporaryDirectory/dev.rhuss.agentmeter-update/`, holding `download.dmg`, the mount point `mnt/` and `outcome.json`. On launch, AgentMeter reads and deletes `outcome.json` (logs it; shows "Updated to X.Y.Z" in the log only, or the failure reason on the update line), detaches a leftover mount (`hdiutil detach -force`) and removes the folder (FR-018, review N2). The staging folder of R8 is removed explicitly right after the swap (success or failure) and, if still present, during launch cleanup.

## R11: Update-test build

**Decision**: `make app-update-test UPDATE_SOURCE=<owner>/<repo>` runs build-app.sh with `UPDATE_TEST=1`, which adds `-Xswiftc -DAGENTMETER_UPDATE_TEST` and stamps `AgentMeterUpdateSource` into Info.plist. Code under `#if AGENTMETER_UPDATE_TEST` reads that key as the release source and treats the build as eligible without release tag and notarized stamp (Developer ID signature and team are still required). release.sh refuses to run when `UPDATE_TEST` is set; `make app` never sets it (FR-025). End-to-end test procedure in quickstart.md.

**Rationale**: The flag cannot reach a published release, and nothing a user can configure changes the source (FR-025).

## R12: Configuration key

**Decision**: `Configuration.checksForUpdates: Bool`, JSON key `checksForUpdates`, default `true`, decoded leniently (`try? decodeIfPresent ?? true`, like `arrangement`), written on save, neutralized in `dataRelevant()` so toggling it does not trigger a data refresh. Settings > About binds the toggle to the draft, which Settings auto-applies (FR-002).

## R13: Logging

**Decision**: Source `update` in the diagnostic log: check start and result (versions, installation kind, action, reason), each install step and its outcome, launch cleanup and outcome marker (FR-021). No URLs with query strings, no headers.
