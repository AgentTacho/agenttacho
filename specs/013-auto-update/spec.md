# Feature Specification: Auto-Update

**Feature Branch**: `013-auto-update`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Auto-update for AgentMeter (from brainstorm/13-auto-update.md). An own small updater with no new dependencies. A background check about once a day (on by default, Settings toggle, plus \"Check for Updates…\") against the latest published GitHub release of rhuss/agentmeter. When a newer version exists, a quiet line at the bottom of the dropdown (\"AgentMeter X.Y.Z available\") with an install action and a Release notes link, mirrored in Settings. DMG installs: one click downloads the DMG, verifies the published SHA-256 and that the app inside is notarized and signed by the same Developer ID team as the running app, replaces the app and relaunches (permissions and start at login carry over). Falls back to the release page with a reason when running from the DMG, a translocated path, an unwritable location, or when verification fails. Homebrew installs are detected and get a `brew upgrade --cask agentmeter` action instead. Development builds never replace themselves. Logic (version comparison, release parsing, install-kind detection, verification decisions) in UsageCore with tests. README Security and privacy section updated for the new request and the verification. Out of scope: beta channels, delta updates, silent installs, notifications or update window, skip this version."

AgentMeter is published as a notarized Developer ID disk image on GitHub releases (spec 005) and as a cask in `rhuss/homebrew-tap`. Homebrew users get new versions with `brew upgrade`, but people who installed from the disk image only learn about a release by looking at GitHub, so they stay on old builds. This feature lets an installed AgentMeter notice a newer release on its own, tell the user quietly in the dropdown, and install it with one click when it was installed from the disk image. Homebrew installs keep Homebrew as their update channel. The check is a new request to GitHub, which the README's "Security and privacy" section must describe, and which the user can turn off.

## Clarifications

### Session 2026-10-16

- Q: Does the 24-hour interval survive a restart, or does every launch check once? → A: Every launch checks once after a short delay, then every 24 hours while running; no check time is stored on disk (FR-001).
- Q: When a later automatic check fails, does an already shown update line disappear? → A: No. A known update stays shown until a successful check reports no newer release or the running version is no longer older (FR-007a).
- Q: What is the size limit for a downloaded disk image? → A: 100 MB, about ten times the current disk image (FR-014).
- Q: Can the user cancel a running install? → A: Yes, while downloading and verifying; once the replacement starts it runs to completion or rolls back (FR-018).
- Q: Where does the result of a manual check appear when nothing is available or the check fails? → A: On the dropdown's update line (and in Settings > About) until the dropdown closes or the next check; an available update stays as usual (FR-003).
- Q: Which version source counts, and what if release-info.json is missing (review I3)? → A: The version in release-info.json, which must equal the tag without "v"; otherwise, or when the file or its version is missing, the release is ignored. A valid newer version with other unusable fields is offered as "Download" only (FR-004).
- Q: Is the 24-hour interval wall-clock time or uptime (review I5)? → A: Wall-clock time; a check due during sleep runs shortly after wake (FR-001).
- Q: How is the macOS "modify apps" permission prompt avoided (review I6)? → A: The replacement is done by AgentMeter or a process attributed to the same team; if macOS denies it, roll back and offer "Download" (FR-017).
- Q: When does a Homebrew cask record count, and what if the tap lags (review M9)? → A: Only when the cask's installed app path is the running app's path; with a lagging tap the line stays and notes Homebrew may take longer (FR-012, Edge Cases).
- Q: How can one-click install be tested before two releases contain it? → A: A separate update-test build target with a compile-time flag that allows a test release source and exempts it from FR-008; make release and make app never set it; tests may inject a source (FR-025).
- Q: How does the relaunched app learn why a replacement failed (review N2)? → A: The replacing process leaves the outcome in the update's temporary folder; the next app start reads, logs, shows and deletes it (FR-017).
- Q: When does the Homebrew "may take longer" note appear (review N3)? → A: Always, as a hint after the command is copied (FR-013).

### Session 2026-10-16 (verify)

Changes from the verification pass, so the spec describes what the implementation intentionally does:

- FR-003: the transient result on the dropdown line ("Checking", "up to date", an error) belongs to checks started from the dropdown's gear menu; a check started from Settings > About shows its result in Settings only, so it never appears on the line later.
- FR-012: besides "Install", "Upgrade with Homebrew" and "Download", the line offers "Try again" after a download failure or when Gatekeeper could not be reached (US2 scenario 4), with the release page still available. If the installation changed since the check (moved, or now managed by Homebrew), clicking Install shows the new action instead.
- FR-016: the app must be the only app bundle at the top level of the disk image; app bundles nested elsewhere are never copied.
- FR-017: the order is: the verified app is staged and swapped in while AgentMeter still runs (the previous app goes to the Trash), then AgentMeter quits and the new version starts after the old process exited. On a failed swap the previous app is put back and AgentMeter keeps running.
- FR-019: a verification step that could not run at all (a system tool that could not be started) is reported as "The update could not be verified", not as a failed replacement; nothing was replaced.
- FR-025: the update-test build is exempt from FR-008 and from the notarization stamp of the running build that FR-012 requires for Install; it still needs a Developer ID signature and a team identifier (research R11).
- Key Entities, Update state: there is no separate "cancelled" state, Cancel returns to "update available"; "install failed (reason, from the previous run)" with a "Release page" link is added.
- Verification follow-up: an automatic check keeps a previous run's install failure on the line until the dropdown closes; a failed relaunch shows "AgentMeter X.Y.Z is installed; quit AgentMeter and open it again to use it" with no action; the disk image is deleted before the relaunch; staging happens in a folder on the installed app's volume.
- Edge Cases: no published release (HTTP 404) counts as up to date; a release that becomes ignored clears a known update; the "relaunch failed" and "previous version in the Trash" outcomes are described.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Learn that a newer version exists (Priority: P1)

A user installed AgentMeter 0.2.1 from the disk image a month ago. Version 0.3.0 has been released since. Without this feature they would never know. After this feature, within a day of the release, the bottom of the dropdown shows a quiet line "AgentMeter 0.3.0 available" with a "Release notes" link that opens the release page, so the user can read what changed and install it by hand if they prefer.

**Why this priority**: Knowing that an update exists is the minimum that keeps users from running outdated builds; every other story builds on this notice.

**Independent Test**: Run a release build of an older version with a newer release published (or a test release source), wait for the check or choose "Check for Updates…", and verify that the dropdown line appears with the new version and that "Release notes" opens that release's page.

**Acceptance Scenarios**:

1. **Given** a release build of 0.2.1 and a published release 0.3.0, **When** the daily check runs, **Then** the dropdown shows "AgentMeter 0.3.0 available" with an install action and a "Release notes" link.
2. **Given** a release build of 0.3.0 and the latest published release is 0.3.0, **When** the check runs, **Then** the dropdown shows no update line.
3. **Given** the latest release on GitHub is a draft or a prerelease with a higher version, **When** the check runs, **Then** it is ignored and no update line appears.
4. **Given** an update line is shown, **When** the user clicks "Release notes", **Then** the release's GitHub page opens in the default browser.
5. **Given** an update line is shown, **When** the user opens Settings > About, **Then** the same available version, the install action and the release notes link appear there.

---

### User Story 2 - Install the update with one click (Priority: P1)

The same user clicks "Install" on the update line. AgentMeter downloads the new disk image, checks that it is exactly the published file and that the app inside is notarized and signed by the same developer as the running app, replaces itself in the Applications folder and starts again as 0.3.0. Notification permission and start at login keep working without any new prompt.

**Why this priority**: The user asked for one-click installs; without it the notice alone still leaves the manual quit, download, drag and reopen steps that keep people on old builds.

**Independent Test**: Install an older notarized release into `/Applications`, publish (or serve from a test release source) a newer notarized release, click Install, and verify that the app relaunches as the new version from the same location, that the old copy is in the Trash, and that notification permission and start at login are still granted.

**Acceptance Scenarios**:

1. **Given** a notarized Developer ID release build in a writable Applications folder and a newer notarized release, **When** the user clicks Install, **Then** the dropdown line shows the download and install progress, the app quits, the new version starts from the same location, and the old version is in the Trash.
2. **Given** the downloaded disk image does not match the published SHA-256, **When** the install runs, **Then** nothing is replaced, the line says the download could not be verified, and offers the release page instead.
3. **Given** the app inside the downloaded disk image is signed by a different developer team, is not notarized, or has an invalid signature, **When** the install runs, **Then** nothing is replaced and the line says why and offers the release page.
4. **Given** the download fails or is interrupted, **When** the install runs, **Then** the installed app stays unchanged, temporary files are removed, and the line offers to try again or open the release page.
5. **Given** the install succeeded, **When** the new version starts, **Then** the existing configuration, notification permission and start at login are unchanged.

---

### User Story 3 - Homebrew users upgrade through Homebrew (Priority: P2)

A user installed AgentMeter with `brew install --cask rhuss/tap/agentmeter`. When a newer release exists, they see the same dropdown line, but its action says "Upgrade with Homebrew". Clicking it copies `brew upgrade --cask agentmeter` to the clipboard and tells them to run it in a terminal, so AgentMeter never replaces a Homebrew-managed app behind Homebrew's back.

**Why this priority**: Homebrew already updates the app; this story only makes the notice useful and safe for Homebrew installs, so it ranks below the disk image path.

**Independent Test**: With AgentMeter installed through the tap's cask and a newer release published, verify that the line appears with "Upgrade with Homebrew", that clicking it puts the command on the clipboard with a confirmation, and that AgentMeter never downloads or replaces anything itself.

**Acceptance Scenarios**:

1. **Given** an installation managed by the Homebrew cask and a newer release, **When** the check runs, **Then** the dropdown line shows "AgentMeter X.Y.Z available" with "Upgrade with Homebrew" and "Release notes".
2. **Given** the Homebrew line is shown, **When** the user clicks "Upgrade with Homebrew", **Then** `brew upgrade --cask agentmeter` is on the clipboard and the line confirms it was copied, with the hint to try again later if Homebrew finds nothing new yet.
3. **Given** a Homebrew-managed installation, **When** any update action is used, **Then** AgentMeter does not download a disk image and does not modify the installed app.
4. **Given** the user ran `brew upgrade` and the new version started, **When** the next check runs, **Then** the line is gone.

---

### User Story 4 - Control the update check (Priority: P2)

A user who wants no automatic requests to GitHub turns off "Check for updates automatically" in Settings > About. AgentMeter then contacts GitHub only when they choose "Check for Updates…" from the dropdown's gear menu or the button in Settings. A user who wants to know right away after a release announcement uses "Check for Updates…" without waiting for the daily check.

**Why this priority**: The automatic check is on by default; turning it off and checking on demand keeps the user in control of the new outbound request, which the security statement promises.

**Independent Test**: Turn the automatic check off, restart, observe for more than a day of simulated time that no update request is made, then choose "Check for Updates…" and verify that exactly one check runs and reports its result.

**Acceptance Scenarios**:

1. **Given** a fresh installation, **When** the user opens Settings > About, **Then** "Check for updates automatically" is on.
2. **Given** the automatic check is off, **When** AgentMeter runs for any length of time, **Then** it makes no update request on its own.
3. **Given** any setting of the toggle, **When** the user chooses "Check for Updates…", **Then** a check runs immediately and its result is shown: the update line, "AgentMeter is up to date", or a short error.
4. **Given** the user changes the toggle, **When** AgentMeter restarts, **Then** the setting is kept.

---

### User Story 5 - Builds that cannot update themselves (Priority: P3)

A developer runs a build made with `make app` from a checkout, and a user runs AgentMeter straight from the opened disk image without copying it. Neither must be replaced by a release. The development build does not check at all and says so when asked; the release build in an unusual location still sees that a newer release exists, with a release page link and a short reason why one-click install is not available.

**Why this priority**: These are rare situations, but replacing a development build or writing into a disk image would be wrong or impossible; a clear fallback is enough.

**Independent Test**: With a newer release published, run a copy started from the mounted disk image and a copy in a folder the user cannot write to, and verify that each shows the line with "Download" (release page) and a reason and never offers or runs Install; run a development build and verify that it makes no request and "Check for Updates…" reports that development builds are not checked.

**Acceptance Scenarios**:

1. **Given** a development build (no release tag in the bundle), **When** a check runs, **Then** no update line appears and "Check for Updates…" reports "Development build: updates are not checked" without contacting GitHub.
2. **Given** a release build started from the mounted disk image or from a translocated location, **When** a newer release exists, **Then** the line offers "Download" (the release page) with the reason "Move AgentMeter to Applications to install updates".
3. **Given** a release build in a location the user cannot write to (for example an app owned by another user), **When** a newer release exists, **Then** the line offers "Download" with the reason that AgentMeter cannot replace itself there.
4. **Given** a running release build that is self-signed, ad-hoc signed or not notarized, **When** a newer release exists, **Then** the line offers "Download" with a reason, because the running app cannot prove the new one comes from the same developer.

---

### Edge Cases

- **Offline or GitHub unreachable during an automatic check**: no new line and no error in the dropdown (an update found earlier stays shown); the failure goes to the diagnostic log and the next automatic check happens at the regular interval. A manual check shows a short error.
- **AgentMeter restarts often** (log out, reboot): each launch makes one check after a short delay, so requests stay at about one per launch plus one per day of uptime.
- **GitHub rate limit or an unexpected response**: treated like an unreachable server.
- **No published release** (GitHub answers that there is no latest release): counts as up to date, like a successful check that finds nothing newer.
- **A known update's release becomes ignored** (for example it was turned back into a draft, or its release information was removed): the next successful check clears the line, as if nothing newer existed (FR-007a).
- **Release information missing or without a usable version** (file absent, not parseable, version not in `X.Y.Z` form, or version not equal to the release tag without "v"): the release is ignored; no update line (FR-004).
- **Release information with a valid, newer version but other fields unusable** (disk image name not matching the version, missing or malformed checksum, missing signing data): the line shows with "Download" only and the reason "release information incomplete" (FR-004, FR-019).
- **The Homebrew tap lags behind the GitHub release** (the cask update failed or is still pending): AgentMeter cannot tell; the line stays with "Upgrade with Homebrew", and the hint shown after copying the command (FR-013) covers this case; the line disappears once the running version is current.
- **Release that is not notarized or not Developer ID signed**: no one-click install; "Download" with a reason.
- **Download larger than 100 MB or redirected to a host outside the allowed GitHub hosts**: aborted, nothing replaced, reason shown.
- **The user clicks Install twice or opens a second dropdown**: only one download and install runs at a time.
- **The user quits AgentMeter during the download**: the download is abandoned, temporary files are removed on the next launch, and the installed app is unchanged.
- **The replacement fails after the old app was moved** (for example the disk is full): the previous app is put back in place and AgentMeter keeps running; the line reports the failure and offers the release page.
- **The previous app cannot be put back** after a failed replacement: the line says that the previous version is in the Trash (with its location when known), and the next start of AgentMeter shows the same reason (FR-017).
- **The new version is in place but cannot be started**: the line says the update is installed and asks the user to quit AgentMeter and open it again.
- **Relaunch and single-instance handling** (spec 005): the relaunch starts the new version only after the old process has exited (FR-017), so the single-instance prompt does not appear.
- **A newer release appears while an older update is shown**: the line shows the newest version.
- **The user installed the update by hand while the line was shown**: the line disappears at the next check or launch because the running version is no longer older.
- **The running version is newer than the latest release** (for example a release build of an unreleased tag): no line.
- **The release's disk image contains no app or more than one app bundle, or the app has the wrong bundle identifier or version**: verification fails, nothing is replaced. The Applications link and the background files of the real disk image are expected and ignored.

## Requirements *(mandatory)*

### Functional Requirements

**Checking for updates**

- **FR-001**: When the automatic check is on, a release build MUST check for a newer release once 5 minutes after each launch (not at launch itself) and then every 24 hours of wall-clock time while it runs; a check that came due while the Mac was asleep MUST run shortly after wake. The time of the last check MUST NOT be stored on disk.
- **FR-002**: The automatic check MUST be on by default and MUST be switchable off and on in Settings > About ("Check for updates automatically"); the setting MUST persist across restarts.
- **FR-003**: Users MUST be able to start a check at any time with "Check for Updates…" in the dropdown's gear menu and with a button in Settings > About, regardless of the toggle; a manual check MUST report its result ("AgentMeter X.Y.Z available", "AgentMeter is up to date", or a short error) in Settings > About, and a check started from the dropdown MUST also report it on the dropdown's update line. On the dropdown line, "Up to date" and errors of a check from the dropdown stay visible until the dropdown closes or the next check completes; a check started from Settings > About MUST NOT put "Up to date" or an error on the line. Settings > About keeps the last result until the next check. An available update is shown on the line whatever started the check.
- **FR-004**: The check MUST read only the latest published release of `rhuss/agentmeter` on GitHub (no drafts, no prereleases) and its release information file (version, disk image name, SHA-256, signing tier, notarization, spec 005 `release-info.json`), plus the release page address. The release's version MUST come from the release information file and MUST equal the release tag without "v"; otherwise, or when the file is missing or has no valid version, the release MUST be ignored. A release with a valid, newer version but other unusable fields MUST be offered as "Download" only.
- **FR-005**: Update requests (the check and the download) MUST NOT carry credentials, cookies, account names, usage data or any identifier of the user or the machine; their user agent MUST be `AgentMeter/X.Y.Z` only. They MUST use HTTPS, MUST NOT store cookies or a response cache on disk, and MUST follow redirects only over HTTPS to an explicit list of GitHub hosts (`api.github.com`, `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`); any other redirect aborts the request.
- **FR-006**: A release MUST count as newer only when its version (`X.Y.Z`, compared numerically part by part) is higher than the running app's version; anything that does not parse as `X.Y.Z` MUST be ignored.
- **FR-007**: Failures of an automatic check (offline, rate limit, server error, malformed response) MUST NOT show anything in the dropdown and MUST be written to the diagnostic log; the next automatic check MUST happen at the regular interval.
- **FR-007a**: A known newer release MUST stay shown when a later check fails; it MUST disappear only when a successful check finds no newer release or the running version is no longer older.
- **FR-008**: A development build (no release tag in its bundle) MUST NOT check for updates, automatically or manually; "Check for Updates…" MUST say that development builds are not checked.

**Showing an update**

- **FR-009**: When a newer release is known, the dropdown MUST show one quiet line at its bottom, above the footer actions: "AgentMeter X.Y.Z available", one action fitting the installation (FR-012), and a "Release notes" link that opens the release page in the default browser.
- **FR-010**: The update line MUST NOT appear in the menu bar, MUST NOT trigger a macOS notification and MUST NOT open a window on its own.
- **FR-011**: Settings > About MUST show the same information: the current version, the available version (or "up to date" with the time of the last successful check in this session, or "Not checked yet" before the first check), the action and the release notes link, next to the toggle and the "Check for Updates…" button.

**Installation kinds and actions**

- **FR-012**: AgentMeter MUST determine its installation kind and offer exactly one action:
  - **One-click install** ("Install"): a release build signed with Developer ID and notarized, not managed by Homebrew, running from a location it can replace (not a disk image, not a translocated path, and both the app bundle and its parent folder writable by the user), and a newer release whose information says Developer ID and notarized with a valid checksum.
  - **Homebrew** ("Upgrade with Homebrew"): an installation managed by the Homebrew cask `agentmeter`, that is, Homebrew's record of the cask exists and the app path it installed is the running app's path.
  - **Download** ("Download", opens the release page): every other case, with a short reason (FR-019).
  - **Try again** (after a failed install only): when a one-click install failed for a reason that may pass on a second try (the download failed, or Gatekeeper could not be reached), the line offers "Try again" with the reason in place of "Install" (US2 scenario 4); the release page stays available through "Release notes".

  The action is decided again when Install is clicked; if the installation changed since the check (it was moved, or Homebrew now manages it), the line shows the new action instead of starting the install.
- **FR-013**: For a Homebrew installation, the action MUST copy `brew upgrade --cask agentmeter` to the clipboard and confirm it on the line, with the hint that Homebrew may need a little longer to offer a new release ("If Homebrew finds nothing new yet, try again later"); AgentMeter MUST NOT run Homebrew, download a disk image or change the installed app.

**One-click install**

- **FR-014**: Install MUST download the release's disk image over HTTPS from GitHub under the redirect rule of FR-005, and MUST abort when the download exceeds 100 MB.
- **FR-015**: Before anything is replaced, the downloaded disk image MUST match the SHA-256 from the release information exactly.
- **FR-016**: Before anything is replaced, the app in the disk image MUST be the only app bundle at the top level of the disk image (app bundles nested elsewhere in the image are not considered and never copied), MUST carry the bundle identifier of the running app and the release's version, MUST have a valid code signature that passes the system's Gatekeeper assessment as notarized, and MUST be signed by the same Developer ID team as the running app.
- **FR-017**: When all checks pass, AgentMeter MUST copy the verified app into a staging folder on the same volume as the installed one, check the copy again, and, while it still runs, move the previous app to the Trash and put the new one in its place at the same path. Only then MUST AgentMeter quit, and the new version MUST start only after the old process has exited. If the swap fails, the previous app MUST be put back in place and AgentMeter keeps running; if the previous app cannot be put back, the line MUST say that it is in the Trash. If the new version is in place but cannot be started, the line MUST ask the user to quit and open AgentMeter again. The replacement MUST be performed by AgentMeter or by a process macOS attributes to the same Developer ID team, so that macOS does not ask for permission to modify apps; if macOS denies the replacement anyway, AgentMeter MUST roll back and offer "Download" with that reason. The process doing the replacement MUST leave the outcome in the update's temporary folder, and the app that starts afterwards (new or restored) MUST read it, log it, show a failure reason on the update line, and delete it.
- **FR-018**: While an install runs, the update line MUST show its progress (downloading with progress, verifying, installing) and further Install clicks MUST have no effect. A "Cancel" action MUST stop the install while it downloads or verifies, leaving the installed app unchanged; once the replacement has started it runs to completion or rolls back (FR-017). Temporary files (download, mounted image) MUST be removed after success, failure, or on the next launch after an interruption.
- **FR-019**: When any check fails or the install cannot run, nothing MUST be replaced, and the line MUST show a short reason and offer the release page; the reasons MUST distinguish at least: running from a disk image or translocated location, location not writable, running build not Developer ID notarized, release not Developer ID notarized, release information incomplete or inconsistent, download failure, download too large or from an unexpected host, checksum mismatch, Gatekeeper not reachable, a verification step that could not run, disk image contents unexpected (app count, bundle identifier, version), signature or team mismatch, replacement failed.
- **FR-020**: Notification permission, start at login and the configuration MUST keep working after a one-click install without new prompts (same path, same signing team, configuration not touched).

**Logging, security statement and structure**

- **FR-021**: Every check and every install step MUST be logged in the diagnostic log (time, versions, installation kind, outcome or reason), without any credential.
- **FR-022**: The README's "Security and privacy" section MUST describe, in the same change: the request to GitHub (what is asked, which hosts, how often, that it carries no credentials or usage data, how to turn it off), how a downloaded update is verified before it replaces the app, that AgentMeter reads Homebrew's record of its cask, and that the only files it writes for an update are its own app bundle, a temporary folder and the Trash. The sentence saying that no other server receives anything and that the price list is the only other download MUST be corrected. The "Installation" section MUST explain the update line for disk image and Homebrew installs.
- **FR-023**: Version comparison, release information parsing, installation kind decision, install eligibility with its reasons, and the verification decisions MUST live in `UsageCore` and be covered by tests; the app target MUST only perform the network, file and process operations and show the UI.
- **FR-024**: The feature MUST NOT add a third-party dependency and MUST NOT require a new signing key or changes to how releases are signed.
- **FR-025**: To test the check and the one-click install end to end, a separate update-test build (its own make target, compiled with an update-test flag) MAY read a test release source (for example a scratch GitHub repository) and is exempt from FR-008 and from the notarization stamp of the running build that FR-012 requires for "Install"; it still MUST have a Developer ID signature and a team identifier. Unit and app-layer tests MAY inject a release source. `make release` and `make app` MUST NOT set the flag, and a build without it MUST always use `rhuss/agentmeter` and MUST NOT read any setting that changes the release source.

### Key Entities

- **Release information**: the latest published release as AgentMeter sees it: version, disk image name, SHA-256 of the disk image, signing tier, notarized flag, release page address, disk image download address.
- **Installation kind**: how the running AgentMeter was installed and where it runs: release build or development build, signing (Developer ID notarized or not), Homebrew-managed or not, and its location (Applications or elsewhere, writable or not, disk image or translocated).
- **Update state**: what the update line and Settings show: not checked yet, development build (not checked), checking, up to date (with the last check time), check failed (short error), update available (version, action, reason when the action is Download or Try again), command copied (Homebrew), downloading (progress), verifying, installing, install failed (reason, from the previous run, with a "Release page" link), and restart required (the new version is installed but did not start; no action, and later checks leave it alone). There is no separate "cancelled" state: Cancel returns to "update available". A failed install in this run returns to "update available" with "Download" or "Try again" and the reason, for example "The update could not be verified" when a verification step could not run.
- **Update setting**: the user's choice for the automatic check (on by default), kept in AgentMeter's configuration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A disk image installation that runs and is online shows the update line within 25 hours after a new release is published, without any user action.
- **SC-002**: From clicking Install to the new version running takes under one minute on a typical broadband connection, with no further click or prompt.
- **SC-003**: In tests with tampered inputs (wrong checksum, different signing team, not notarized, unsigned, extra or missing app in the image, wrong bundle identifier or version), no installation is ever replaced: 0 of all tampered cases.
- **SC-004**: After a one-click install, notification permission and start at login still work in 100% of tested updates between Developer ID notarized releases.
- **SC-005**: With the automatic check turned off, AgentMeter makes 0 update requests over a full day of running unless the user chooses "Check for Updates…".
- **SC-006**: A Homebrew installation is never modified by AgentMeter: 0 downloads and 0 file changes in its app bundle across all update actions.
- **SC-007**: A development build makes 0 update requests.

## Assumptions

- Releases keep publishing `release-info.json`, the disk image and its `.sha256` file as assets, as defined by spec 005; no change to the release process is needed for this feature.
- The project's Developer ID team (EC5BHUKA6K) signs all future releases; a change of team would require a manual install once.
- Homebrew installs are recognized from Homebrew's own record of the `agentmeter` cask in the standard Homebrew locations; a Homebrew installed in a non-standard prefix may be treated as a disk image installation, in which case one-click install still verifies everything but bypasses Homebrew's bookkeeping.
- The Homebrew action copies the command instead of running it, because running Homebrew from a menu bar app needs a shell environment, may ask for a password and would hide its output.
- When the app is owned by another user or root, AgentMeter falls back to "Download" instead of asking for administrator rights.
- No "skip this version", beta channel, delta update, silent install, notification or update window is part of this feature (brainstorm 13 Out of Scope).
- The release page and the release information are public and need no GitHub account; unauthenticated GitHub rate limits are far above one request per day.
- A release older than this feature (up to 0.3.1) cannot update itself; the first one-click update is possible from the first release that contains this feature.
