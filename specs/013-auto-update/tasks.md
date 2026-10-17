# Tasks: Auto-Update

**Input**: Design documents from `/specs/013-auto-update/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/update-requests.md, contracts/update-ui.md, contracts/make-targets.md, quickstart.md

**Tests**: Included (AGENTS.md: write the test first). Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task before its implementation and confirm it fails once the package compiles. Build and test only through `make test` and `make test-release`.

**Global constraints** (from plan.md):
- All decisions in `Sources/UsageCore/Update/`, covered by tests; the app target only runs tools, touches files and renders (FR-023).
- No new package dependency, no new signing key (FR-024). No credentials, cookies or identifiers in update requests; user agent `AgentTacho/X.Y.Z` only; redirects only to the four allowed GitHub hosts (FR-005).
- Nothing is replaced unless every step of research R4 passes (SC-003).
- No em dash or en dash characters anywhere. Doc comments cite spec 013 FR ids (for example `spec 013 FR-016`).
- AgentTacho never writes to the agents' files; for an update it writes only its own bundle, `$TMPDIR/dev.rhuss.agenttacho-update/` and the Trash.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 (notice), US2 (one-click install), US3 (Homebrew), US4 (control the check), US5 (builds that cannot update)

---

## Phase 1: Setup

- [X] T001 Run `make test` and `make test-release` and confirm all existing suites pass (baseline).
- [X] T002 [P] Create fixtures in `Tests/UsageCoreTests/Fixtures/update/`: `releases-latest.json` (GitHub API shape with `tag_name` `v0.3.0`, `html_url`, `draft` false, `prerelease` false, assets `AgentTacho-0.3.0.dmg` size 10485760, `AgentTacho-0.3.0.dmg.sha256`, `release-info.json`, each with an https `browser_download_url`), `releases-latest-no-info.json` (no release-info asset), `release-info.json` (valid, developer-id, notarized, 64 hex sha256), `release-info-self-signed.json`, `release-info-bad-version.json` (`0.3`), `release-info-bad-sha.json` (sha256 `xyz`), `release-info-wrong-dmg.json` (`AgentTacho-0.2.9.dmg`). Fixtures are copied by the existing `.copy("Fixtures")` rule in Package.swift.

---

## Phase 2: Foundational (blocking): versions, release evaluation, policy, state

- [X] T003 [P] Create `Tests/UsageCoreTests/ReleaseVersionTests.swift`: parses `0.3.0`, `10.0.12`; rejects `v0.3.0`, `0.3`, `0.3.0-dev`, `0.3.0.1`, `a.b.c`, empty, leading or trailing spaces; `init?(tag:)` accepts `v0.3.0` and `0.3.0`, rejects `vv0.3.0`; ordering is numeric per part (`0.10.0 > 0.9.9`, `1.0.0 > 0.99.99`, equal versions are not greater); `description` round trips (spec 013 FR-006).
- [X] T004 Create `Sources/UsageCore/Update/ReleaseVersion.swift`: `public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible` with `major`, `minor`, `patch`, `init?(_:)`, `init?(tag:)`. T003 passes.
- [X] T005 [P] Create `Tests/UsageCoreTests/ReleaseEvaluatorTests.swift` covering decoding and evaluation with the T002 fixtures (data-model.md ReleaseCheckResult): valid release 0.3.0 vs running 0.2.1 gives `.available` with a `DownloadTarget` (url of `AgentTacho-0.3.0.dmg`, size, lowercase sha256) and `infoProblem == nil`; running 0.3.0 or 0.4.0 gives `.notNewer`; no release-info asset, unreadable info JSON, bad info version, info version `0.3.1` while the tag is `v0.3.0`, `draft` true, `prerelease` true each give `.ignored`; self-signed info gives `.available` with `download == nil` and `infoProblem == .releaseNotNotarized`; bad sha256, wrong dmg name, dmg asset missing, or asset size above 100 MB give `download == nil` and `.releaseInfoIncomplete` (or `.downloadTooLarge` for the size); a `browser_download_url` that is not https or whose host fails `UpdateHostPolicy.allows(_:)` (for example `https://example.com/AgentTacho-0.3.0.dmg`) is treated as missing (spec 013 FR-004, FR-006, FR-014).
- [X] T006 Create `Sources/UsageCore/Update/UpdateBlockReason.swift` first (`public enum UpdateBlockReason: Error, Equatable, Sendable` with all cases of data-model.md and a `text` property), then `Sources/UsageCore/Update/ReleaseInfo.swift` (`GitHubRelease`, `GitHubAsset`, `ReleaseInfo` with lenient per-field decoding, `ReleaseInfo.maximumBytes = 65_536`, `DownloadTarget.maximumBytes = 104_857_600`) and `Sources/UsageCore/Update/ReleaseEvaluator.swift` (`ReleaseCheckResult`, `AvailableRelease`, `DownloadTarget`, `ReleaseEvaluator.evaluate(release:info:runningVersion:)`; `info` is optional for the "no asset" and "unreadable" cases). T005 passes.
- [X] T007 [P] Create `Tests/UsageCoreTests/UpdateHostPolicyTests.swift` for `UpdateHostPolicy.allows(_:)` (used for every starting URL and every redirect): allows `https` URLs on `api.github.com`, `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`; rejects `http://github.com`, `raw.githubusercontent.com`, `evil-github.com`, `github.com.evil.com`, uppercase-host variants are normalized and allowed, URLs without a host (spec 013 FR-005).
- [X] T008 Create `Sources/UsageCore/Update/UpdateHostPolicy.swift` with `public enum UpdateHostPolicy { static let allowedHosts; static func allows(_ url: URL) -> Bool }`. T007 passes.
- [X] T009 [P] Create `Tests/UsageCoreTests/UpdatePolicyTests.swift` for `UpdatePolicy.checksAllowed(context:)` and `UpdatePolicy.action(context:release:)` (data-model.md InstallContext, UpdateAction, UpdateBlockReason): development build (no release tag, no update-test flag) is not allowed to check; update-test build is allowed; eligible release build in a writable folder with a download target gives `.install`; Homebrew-managed gives `.homebrew` even when also read-only or translocated; then in order: translocated gives `.download(.translocated)`, read-only volume gives `.download(.runsFromDiskImage)`, bundle or parent not writable gives `.download(.notWritable)`, running signing self-signed, ad-hoc, nil, or developer-id without notarized stamp, or missing team identifier gives `.download(.runningNotNotarized)` (update-test build needs only a team identifier and developer-id signing), release with `download == nil` gives `.download(infoProblem)`; `runningVersion == nil` (no parseable `CFBundleShortVersionString`) disallows checks. Also test each `UpdateBlockReason.text` for the exact wording in data-model.md and contracts/update-ui.md, including the User Story 5 texts "Move AgentTacho to Applications to install updates", "AgentTacho cannot replace itself in this folder" and "This build cannot verify updates" (spec 013 FR-008, FR-012, FR-019; User Story 5 scenarios 1 to 4).
- [X] T010 Create `Sources/UsageCore/Update/UpdatePolicy.swift` with `InstallContext` (including `runningVersion: ReleaseVersion?`), `UpdateAction`, `UpdatePolicy`. T009 passes.
- [X] T011 [P] Create `Tests/UsageCoreTests/UpdateStateTests.swift` for `UpdateState`, `CheckOutcome` and `UpdateDisplay` (data-model.md, contracts/update-ui.md): line text and visibility for every state; `UpdateDisplay.applying(_:manual:at:)` keeps a known `available` on a failed automatic check (FR-007a), records `checkFailed` only for manual checks (FR-003, FR-007), clears `available` on `.notNewer`, replaces an older available version with a newer one; a result arriving during `downloading`, `verifying` or `installing` leaves the state unchanged, and during `commandCopied` only updates the release; manual `upToDate`, `checkFailed`, `developmentBuild` and `checking(manual: true)` show on the line until `dismissingTransient()` (called when the dropdown closes) while `state` (shown in Settings) keeps them until the next check; `developmentBuild` text; downloading text with whole percent; `commandCopied` text includes the Homebrew hint (FR-013).
- [X] T012 Create `Sources/UsageCore/Update/UpdateState.swift` with the types and signatures of data-model.md UpdateState. T011 passes.

**Checkpoint**: release evaluation, policy and state are complete and tested; no I/O yet.

---

## Phase 3: User Story 1 - Learn that a newer version exists (P1) MVP

**Goal**: A release build checks GitHub 5 minutes after launch and every 24 hours, and shows "AgentTacho X.Y.Z available" with Release notes in the dropdown and in Settings > About; "Check for Updates…" checks on demand.

**Independent Test**: quickstart.md section 2 steps 1 to 4 (or a stubbed source in tests): the line appears for a newer release, not for an equal one, and Release notes opens the release page.

- [X] T013 [P] [US1] Create `Tests/UsageCoreTests/UpdateScheduleTests.swift`: no last check: not due before launch + 300 s, due at exactly 300 s; with last check: not due at +86 399 s, due at +86 400 s; a `now` far after the last check (sleep across days) is due; a `lastCheck` later than `now` (clock moved back) is due (spec 013 FR-001, research R9).
- [X] T014 [US1] Create `Sources/UsageCore/Update/UpdateSchedule.swift` with `firstCheckDelay = 300`, `interval = 86_400`, `isDue(now:launchedAt:lastCheck:)`. T013 passes.
- [X] T015 [P] [US1] Create `Tests/UsageCoreTests/UpdateClientTests.swift` (check part) with a `URLProtocol` stub registered on a test `URLSessionConfiguration`: request 1 goes to `https://api.github.com/repos/<owner>/<repo>/releases/latest` with `User-Agent: AgentTacho/0.2.1`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, and no `Authorization` or `Cookie` header; request 2 fetches the release-info asset URL; HTTP 404 on request 1 maps to "no release" (`.notNewer`); 403 and 429 map to a rate-limit error; 500 maps to an HTTP error; a redirect to an allowed host is followed, a redirect to `https://example.com` fails with `unexpectedHost`; a starting URL outside the allowlist is never requested; a `releases/latest` body above 1 MB and a release-info body above 64 KB fail with `tooLarge`; a missing release-info asset returns the release without info (contracts/update-requests.md; spec 013 FR-004, FR-005).
- [X] T016 [US1] Create `Sources/UsageCore/Update/UpdateClient.swift`: `public struct UpdateClient: Sendable` with `init(owner:repo:appVersion:session:)`, `static let defaultSession` (ephemeral, `urlCache = nil`, `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `reloadIgnoringLocalAndRemoteCacheData`, 30 s request timeout), a host check with `UpdateHostPolicy.allows` on every starting URL and every redirect (delegate), body caps of 1 MB for `releases/latest` and 64 KB for release info, `UpdateClientError` (`network`, `httpStatus`, `rateLimited`, `unexpectedHost`, `tooLarge`, `decoding`), and `check(runningVersion:) async throws -> ReleaseCheckResult` (requests 1 and 2, then `ReleaseEvaluator`). Doc comments cite FR-004, FR-005. T015 passes.
- [X] T017 [US1] Create `Sources/AgentTacho/InstallEnvironment.swift`: `InstallEnvironment.current() -> InstallContext` gathering `runningVersion` from `CFBundleShortVersionString` (not the display version, which is `X.Y.Z-dev` for local builds), release tag and signing stamps from `AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])`, the team identifier from `SecCodeCopySelf`, `SecCodeCopyStaticCode` and `SecCodeCopySigningInformation` with the `kSecCSSigningInformation` flag (`kSecCodeInfoTeamIdentifier`), translocation from the `/AppTranslocation/` path test (`SecTranslocateIsTranslocatedURL` is not in the public SDK headers and is not used), `volumeIsReadOnly`, writability of the bundle and its parent (`FileManager.isWritableFile`), `isHomebrewManaged: false` for now (US3 fills it), and `isUpdateTestBuild` from `#if AGENTTACHO_UPDATE_TEST`; `InstallEnvironment.releaseSource` returns `("rhuss", "agenttacho")`, and under `#if AGENTTACHO_UPDATE_TEST` only, the Info.plist key `AgentTachoUpdateSource` when it is a valid `owner/repo` (spec 013 FR-012, FR-025; research R5, R6, R11).
- [X] T018 [US1] Create `Sources/AgentTacho/Updater.swift`: `@MainActor final class Updater: ObservableObject` with `lastSuccessfulCheck: Date?`, `launchedAt`, `lastCheck`; `start()` runs a loop that sleeps at most 3600 s and checks when `UpdateSchedule.isDue` (wall clock `Date()`), `handleWake()` re-evaluates 60 s after wake; `@Published display: UpdateDisplay` instead of a bare state; `checkNow(manual:)` refuses for development builds (`.developmentBuild`, no request, FR-008), runs `UpdateClient.check`, computes the action with `UpdatePolicy.action(context: InstallEnvironment.current(), release:)` and applies the `CheckOutcome` with `UpdateDisplay.applying(_:manual:at:)`; only one check at a time; every check logs to the diagnostic log with source `update` (versions, installation kind, action or reason, error) (spec 013 FR-001, FR-003, FR-007, FR-007a, FR-021; research R9, R13).
- [X] T019 [US1] Wire the updater in `Sources/AgentTacho/App.swift`: create one `Updater` with the app's `DiagnosticLog`, start it after launch, call `handleWake()` from the existing `NSWorkspace.didWakeNotification` observer, and pass it to the dropdown and to `Sources/AgentTacho/SettingsView.swift`, which passes it (and, from T039 on, `draft: $draft`) to `AboutSettingsTab` (today `AboutSettingsTab()` takes no arguments, SettingsView.swift:66).
- [X] T020 [US1] Add the update line to `Sources/AgentTacho/DropdownView.swift` (contracts/update-ui.md): one line above the footer for visible states, secondary style, `Release notes` and the action buttons open the release page with `NSWorkspace.shared.open`; call `dismissingTransient()` when the dropdown closes, detected with `NSWindow.didResignKeyNotification` on the dropdown's existing hosting window (`onDisappear` is unreliable for the menu bar window); add `Check for Updates…` to the gear menu between About and Settings (spec 013 FR-003, FR-009, FR-010).
- [X] T021 [US1] Add an "Updates" group to `Sources/AgentTacho/AboutSettingsTab.swift`: status text (available version with action and Release notes, "Up to date (checked HH:mm)", "Not checked yet", "Development build: updates are not checked", or the last error) and a `Check for Updates…` button (spec 013 FR-011).

**Checkpoint**: US1 works with the Download action for every installation (install and Homebrew actions arrive in US2 and US3).

---

## Phase 4: User Story 2 - Install the update with one click (P1)

**Goal**: Install downloads, verifies (research R4), replaces the app in place, puts the old one in the Trash and relaunches; Cancel and rollback work.

**Independent Test**: quickstart.md section 2 steps 5 and 6.

- [X] T022 [P] [US2] Create `Tests/UsageCoreTests/DiskImageCheckTests.swift`: the real layout (`AgentTacho.app`, `Applications` symlink, `.background`, `.DS_Store`, `.VolumeIcon.icns`, `.fseventsd`, `.Trashes`) passes and returns `AgentTacho.app`; no app, two apps, wrong bundle identifier, wrong version, missing bundle identifier fail with `.unexpectedContents` and a detail naming the problem (spec 013 FR-016).
- [X] T023 [US2] Create `Sources/UsageCore/Update/DiskImageCheck.swift` with `DiskImageEntry` and `DiskImageCheck.check(entries:expectedBundleID:expectedVersion:)`. T022 passes.
- [X] T024 [P] [US2] Create `Tests/UsageCoreTests/UpdateVerificationTests.swift` for `UpdateVerification.verdict(...)`: all steps passing gives nil; each tampered case returns its reason and stops at the first failure in R4 order: checksum mismatch (`.checksumMismatch`), DMG not "Notarized Developer ID" (`.diskImageNotNotarized`), contents failure (passes its reason through), signature or team requirement failure (`.signatureMismatch`), app assessment not notarized (`.appNotNotarized`), assessment unavailable (`.gatekeeperUnavailable`), staged copy signature failure (`.signatureMismatch`); also `UpdateVerification.classifyAssessment(output:exitStatus:)` returns `.notarized` for `source=Notarized Developer ID` with status 0, `.unavailable` when the output contains `override=security disabled` (Gatekeeper turned off) or the status is non-zero and the output mentions a failed ticket lookup or network error (test inputs: `override=security disabled`, `Could not validate ticket: network unavailable`), and `.notNotarized` for `source=Developer ID`, `source=Unnotarized Developer ID`, `rejected` and other non-zero statuses; `UpdateVerification.designatedRequirement(bundleID:team:)` produces the exact requirement string of research R4 step 5; `UpdateVerification.sha256Matches(actualHex:expectedHex:)` compares case-insensitively and rejects lengths other than 64 (spec 013 FR-015, FR-016, SC-003).
- [X] T025 [US2] Create `Sources/UsageCore/Update/UpdateVerification.swift`. T024 passes.
- [X] T026 [P] [US2] Create `Tests/UsageCoreTests/UpdateOutcomeTests.swift` and `Sources/UsageCore/Update/UpdateOutcome.swift`: JSON round trip of `{from, to, result, reason}`, unknown `result` decodes as failed, `UpdateOutcome.fileName = "outcome.json"`, `UpdateOutcome.folderName = "dev.rhuss.agenttacho-update"` (research R10).
- [X] T027 [US2] Extend `Tests/UsageCoreTests/UpdateClientTests.swift` (download part): `download(_ target:to:progress:)` writes the body to the destination, reports increasing progress fractions, sends the same headers as the check, follows an allowed redirect, fails with `unexpectedHost` for a disallowed one, fails with `tooLarge` before downloading when `target.size` exceeds 100 MB and while streaming when the received bytes exceed 100 MB, and stops when the task is cancelled (spec 013 FR-014, FR-018).
- [X] T028 [US2] Implement `download(_:to:progress:)` in `Sources/UsageCore/Update/UpdateClient.swift` using `URLSession.bytes(for:delegate:)` into a `FileHandle`, with the byte limit and `Task.checkCancellation()`. T027 passes.
- [X] T029 [US2] Create `Sources/AgentTacho/UpdateInstaller.swift` (research R4, R8, R10): `prepareFolder()` (create or clean `$TMPDIR/dev.rhuss.agenttacho-update/`); `sha256(of:)` with CryptoKit streaming; `assess(path:type:)` running `/usr/sbin/spctl --assess --type <open|execute> [--context context:primary-signature] --verbose=2` and returning status and combined output; `attach(dmg:)`/`detach(mountPoint:)` with `/usr/bin/hdiutil attach -readonly -nobrowse -noautoopen -mountpoint`; `entries(of:)` building `[DiskImageEntry]` (reading each `.app`'s Info.plist); `checkSignature(app:requirement:)` with `SecStaticCodeCreateWithPath` and `SecStaticCodeCheckValidityWithErrors` (`kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode`); `stage(app:besides:)` with `/usr/bin/ditto` into `FileManager.url(for: .itemReplacementDirectory, ...)`, then `checkSignature` again on the staged copy (closes the gap between check and use); `swap(installed:staged:)` doing `trashItem` then `moveItem`, moving the trashed bundle back on failure and mapping `EPERM`/`NSFileWriteNoPermissionError` to `.replacementDenied`, other errors to `.replacementFailed`, and removing the staging folder afterwards in every case; `writeOutcome(_:)`; every tool run keeps its `Process` so `cancel()` can terminate a running `spctl`, `hdiutil` or `ditto`; `relaunch(appPath:)` starting `/bin/sh -c 'while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2"' sh <pid> <path>` and then `NSApplication.shared.terminate(nil)`. All tool runs use absolute paths and argument arrays (no shell interpolation of paths). Each step's result is fed into `UpdateVerification.verdict`; nothing is staged or swapped unless the verdict is nil (SC-003).
- [X] T030 [US2] Add the install pipeline to `Sources/AgentTacho/Updater.swift`: `install()` only from `.available(_, .install(target))`, single flight (FR-018), states downloading (progress), verifying, installing; `cancelInstall()` cancels the task during download or verification, terminates a running tool process through `UpdateInstaller.cancel()`, detaches and cleans up, and returns to `available` (FR-018); a failed swap leaves the running app as it is (it never quit) and shows the reason (FR-017 as amended); any failure detaches, cleans up, logs, and sets `available` with `.download(reason)` (FR-019); success writes the outcome and relaunches (FR-017, FR-020). Add `cleanUpAfterLaunch()` (called from `start()`): read, log and delete `outcome.json` and show a failure reason from it on the line, force-detach a leftover mount, remove the update folder and any leftover staging folder (research R10). Log every step with source `update` (FR-021).
- [X] T031 [US2] Show Install, Cancel and progress in `Sources/AgentTacho/DropdownView.swift` and `Sources/AgentTacho/AboutSettingsTab.swift` per contracts/update-ui.md (Install disabled while an install runs).

**Checkpoint**: one-click install works end to end with the update-test build (Phase 8) per quickstart.md.

---

## Phase 5: User Story 3 - Homebrew users upgrade through Homebrew (P2)

**Goal**: A cask install shows "Upgrade with Homebrew", which copies the command with the hint, and never downloads or changes anything.

**Independent Test**: quickstart.md section 3.

- [X] T032 [P] [US3] Create `Tests/UsageCoreTests/HomebrewDetectorTests.swift`: with a resolver closure returning symlink targets for `<prefix>/Caskroom/agenttacho/<version>/AgentTacho.app`: target equal to the running path (after standardizing and resolving `/private` and trailing slashes) is managed; a target pointing elsewhere (for example `~/Applications/AgentTacho.app` while running from `/Applications`), no Caskroom folder, or a non-symlink entry is not managed; both prefixes `/opt/homebrew` and `/usr/local` are searched (spec 013 FR-012, research R7).
- [X] T033 [US3] Create `Sources/UsageCore/Update/HomebrewDetector.swift` with `HomebrewDetector.prefixes`, `isManaged(runningAppPath:listVersions:resolveLink:)` (closures injected), and `HomebrewDetector.live` helpers using `FileManager.contentsOfDirectory` and `destinationOfSymbolicLink`. T032 passes.
- [X] T034 [US3] Use `HomebrewDetector` in `Sources/AgentTacho/InstallEnvironment.swift` for `isHomebrewManaged`.
- [X] T035 [US3] In `Sources/AgentTacho/Updater.swift` add `copyHomebrewCommand()`: puts `brew upgrade --cask agenttacho` on `NSPasteboard.general`, sets `commandCopied` and returns to `available` after 8 seconds; it never downloads or touches files (FR-013, SC-006). Wire the "Upgrade with Homebrew" button in `Sources/AgentTacho/DropdownView.swift` and `Sources/AgentTacho/AboutSettingsTab.swift`.

---

## Phase 6: User Story 4 - Control the update check (P2)

**Goal**: "Check for updates automatically" (default on) in Settings > About; off means no automatic request.

**Independent Test**: quickstart.md section 4, first bullet.

- [X] T036 [P] [US4] Add tests to `Tests/UsageCoreTests/ConfigurationTests.swift`: `checksForUpdates` is true when the key is absent, false when `false`, true when the value is not a boolean (lenient, the rest of the configuration still loads), round trips through encode and decode, and toggling it does not change `dataRelevant()` (spec 013 FR-002, research R12).
- [X] T037 [US4] Add `checksForUpdates` to `Sources/UsageCore/Config/Configuration.swift` (property, init parameter with default `true`, coding key, lenient `(try? container.decodeIfPresent(Bool.self, forKey:)) ?? true` like `arrangement`, not the strict `showsRunOutMarker` decoding; encoded on save; neutralized in `dataRelevant()` like the other display-only settings). T036 passes.
- [X] T038 [US4] In `Sources/AgentTacho/Updater.swift` read the setting: the automatic loop runs only while `checksForUpdates` is true; App.swift calls `updater.apply(configuration:)` on configuration changes to start or stop the loop; manual checks always run (FR-002, FR-003, SC-005).
- [X] T039 [US4] Add the toggle "Check for updates automatically" to the Updates group in `Sources/AgentTacho/AboutSettingsTab.swift`, bound to `draft.checksForUpdates` (passed in from `SettingsView.swift` as `draft: $draft`) and auto-applied like the other Settings drafts.

---

## Phase 7: User Story 5 - Builds that cannot update themselves (P3)

**Goal**: Development builds never check; DMG, translocated, unwritable and non-notarized running builds get Download with a reason.

**Independent Test**: quickstart.md section 2 step 6 and section 4, second bullet.

- [X] T040 [US5] In `Sources/AgentTacho/DropdownView.swift` and `Sources/AgentTacho/AboutSettingsTab.swift`, render the `.download(reason)` action as `Download` with the reason after a middle dot, truncated with a tooltip showing the full reason, and the `developmentBuild` message after a manual check (contracts/update-ui.md; spec 013 FR-008, FR-019).
- [X] T041 [US5] In `Sources/AgentTacho/Updater.swift`, log the installation facts (release or development build, signing, team present, Homebrew, translocated, read-only, bundle and parent writable) with each check, so a Download reason can be traced in the diagnostic log (spec 013 FR-021).

---

## Phase 8: Update-test build (FR-025)

- [X] T042 Add tests to `scripts/release/tests/test_build_scripts.sh` and `scripts/release/tests/test_makefile.sh` (follow their existing helpers): `make app-update-test` without `UPDATE_SOURCE` or with an invalid value fails; build-app.sh with `UPDATE_TEST=1` passes `-Xswiftc -DAGENTTACHO_UPDATE_TEST` and stamps `AgentTachoUpdateSource`; without `UPDATE_TEST` neither appears; `make app` with `UPDATE_TEST=1` in the environment does not pass it on; release.sh (including `--dry-run`) dies with "UPDATE_TEST is set; release builds never carry the update-test flag" when `UPDATE_TEST` is set (contracts/make-targets.md).
- [X] T043 Implement in `scripts/release/build-app.sh` (validate `UPDATE_SOURCE`, extra swift build flag, Info.plist key, log line), `scripts/release/release.sh` (guard before any work) and `Makefile` (`app:` runs build-app.sh under `env -u UPDATE_TEST -u UPDATE_SOURCE`; `app-update-test` target, `UPDATE_TEST`/`UPDATE_SOURCE` passed only through the environment like the other variables, added to `.PHONY`). T042 passes with `make test-release`.

---

## Phase 9: Polish & cross-cutting

- [X] T044 Update `README.md` (spec 013 FR-022, contracts/update-requests.md): Installation explains the update line for DMG installs (Install) and Homebrew installs (copy `brew upgrade`), and how to turn the check off; "Security and privacy": add the GitHub requests (hosts, frequency, no credentials or usage data, user agent, how to turn off) to "Where the tokens go" / a new "Updates" paragraph, correct the sentence "No other server receives anything... The only other download is LiteLLM's price list", describe the verification chain (checksum, Gatekeeper notarization, same Developer ID team), state that AgentTacho reads Homebrew's Caskroom record of its cask and writes only its own bundle, a temporary folder and the Trash during an update; add the `checksForUpdates` key to the configuration section; document `make app-update-test` in "Releasing (maintainer)".
- [X] T045 [P] Check all new and changed files for em dash and en dash characters (`rg -n "\x{2014}|\x{2013}" Sources Tests scripts README.md Makefile specs/013-auto-update`) and for spec 013 FR citations in the doc comments of every new public type.
- [X] T046 Run `make test` and `make test-release`; both pass.
- [X] T047 Run `make app` and confirm the app builds, starts, shows no update line, and "Check for Updates…" reports the development build message with no `update` request in `~/Library/Logs/agenttacho/usage.log` (SC-007).

---

## Dependencies & Execution Order

- Phase 1 then Phase 2 (blocks everything).
- US1 (Phase 3) needs Phase 2. US2 (Phase 4) needs US1 (Updater, client, line). US3 and US4 need US1 only and can run in parallel with US2. US5 needs US1 (and shows its value with US2).
- Phase 8 is independent of the Swift work and can run any time after Phase 1; the end-to-end check of US2 needs it.
- Polish last.

## Parallel Examples

- Phase 2: T003, T005, T007, T009, T011 (separate test files) in parallel; then their implementations.
- US2: T022, T024, T026 in parallel; T027 after T016.
- After US1: US3 (T032 to T035) and US4 (T036 to T039) in parallel with US2.

## Implementation Strategy

1. MVP: Phases 1 to 3 (notice with Release notes and Download for everyone).
2. Add US2 (one-click install) and Phase 8 to test it end to end.
3. Add US3 and US4, then US5 polish of reasons.
4. README and final checks.

## Implementation notes

- **Order**: T007/T008 (host policy) ran before T005/T006, because the evaluator uses `UpdateHostPolicy`. Checkpoint 1 ran after T016, because the T015 tests only compile with the client.
- **Observation instead of ObservableObject**: `Updater` is `@Observable` like `AppModel`, and lives on `AppModel` (`model.updater`), so the dropdown and Settings reach it without extra parameters.
- **Shared views**: the line, status text and buttons are in `Sources/AgentTacho/UpdateViews.swift`, used by `DropdownView` and `AboutSettingsTab` (T020, T021, T031, T035, T040).
- **Extra core transitions** (FR-023): `UpdateDisplay` also has `known`, `settingsKnownUpdate`, `installableUpdate`, `startingInstall()`, `withInstallStep(_:)`, `cancellingInstall()`, `failingInstall(_:)`, `copyingHomebrewCommand()`, `endingCommandCopied()` and `showingInstallFailure(_:)`, all tested. `UpdateState` gains `installFailed(String)` for an outcome marker from the previous run (FR-017), and `UpdateBlockReason` gains `relaunchFailed`.
- **FR-007a and manual checks**: a failed manual check shows its error on the line until the dropdown closes and then falls back to the known update; Settings shows the error and the known update with its action. Install also starts from the known update in that state (checkpoint 2).
- **FR-001 and manual checks**: only automatic checks move the schedule, so "Check for Updates…" in the first 5 minutes does not replace the check after launch (checkpoint 2; research R9 said "last check attempt").
- **Tag and version**: the release-info version must equal the tag without "v" as text (`v0.3.00` does not match `0.3.0`). A release-info asset without a usable URL counts as unreadable (release ignored); a URL outside the allowlist fails the check with `unexpectedHost`.
- **Download limit**: `UpdateClient.download` takes `maximumBytes` (default 100 MB) so the streaming cap is tested with small bodies.
- **Tool output**: `UpdateInstaller` writes tool output to a file in the update folder instead of a pipe, so a helper process that inherits the descriptor cannot block the read.
- **Error reasons per step**: opening the image maps to `unexpectedContents`, staging to `replacementFailed`, reading the download to `downloadFailed`, a failed relaunch after a successful swap to the `restartRequired` state (it was the `relaunchFailed` reason until the verification follow-up).
- **T040, T041**: covered by the US1 work (`UpdateStatusText` and `InstallContext.logSummary` in every check log line).
- **T047**: `make app` builds and signs (Developer ID). The launch check is left for the walkthrough because an installed AgentTacho was running, and a second copy would show the single-instance prompt.
- **README**: "Releases up to 0.3.1 have no updater" (v0.3.1 is the latest tag).
