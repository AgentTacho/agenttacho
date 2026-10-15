# Feature Specification: macOS Distribution (Signed DMG and Homebrew Cask)

**Feature Branch**: `005-macos-distribution`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "macOS distribution for AgentMeter: signed drag-to-Applications DMG published as a GitHub release, and a Homebrew cask in rhuss/homebrew-tap. Tiered signing (Developer ID with notarization when available, else a stable self-signed certificate, else ad-hoc), development builds use the same identity selection, DMG background with the one-time first-launch step for non-notarized builds, app icon, version from git tag, GitHub release with checksum, cask update, README installation section, release steps scriptable for later CI." Source brainstorm: `brainstorm/04-macos-distribution.md`.

## Clarifications

### Session 2026-10-14

- Q: How is the stable self-signed identity found by the build? → A: By the certificate name, default "AgentMeter Signing", overridable per build.
- Q: How does the build number increase from release to release? → A: It is the number of commits reachable from the built commit.
- Q: Which version does an untagged development build report? → A: The nearest tag's version with a "-dev" suffix, or "0.0.0-dev" when no tag exists. (Refined in spec review: the bundle field stays numeric; "-dev" appears in the app's own version display, see FR-008.)

### Spec review 2026-10-14 (decisions)

- The first-launch step for builds that are not notarized is needed after each install or upgrade, not once.
- The release refuses a tag that is not pushed to `origin` or points to another commit there.
- Developer ID without a notarization profile releases as "Developer ID, not notarized" with a warning; the profile default name is "agentmeter-notary".
- GitHub releases are created as drafts and published after all uploads succeed.
- A cask-only command finishes a failed cask update; the tap is always cloned fresh.
- Dry runs work on any commit and only warn about preflight problems.
- Only the DMG is promised to open offline when notarized.
- The cask has no relaunch step of its own; Homebrew itself reopens an app that `uninstall quit:` closed during `brew upgrade`, so the caveats say that AgentMeter is quit before an upgrade and opened again afterwards (revised after the code review, FINDING-24).
- The self-signed certificate is created with a 10-year validity and moved between machines as a `.p12` file.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install from a downloaded DMG (Priority: P1)

A person who does not build software downloads `AgentMeter-X.Y.Z.dmg` from the project's GitHub releases page, opens it, drags AgentMeter to Applications, and launches it. The DMG window shows the app with its icon, a shortcut to Applications, and, when the build is not notarized by Apple, short instructions for the first launch after each install or upgrade.

**Why this priority**: This is the core of the feature. Without a downloadable, installable artifact nobody besides the author can use AgentMeter.

**Independent Test**: Produce a release DMG on the author's Mac, copy it to a Mac or user account that has never run AgentMeter, open it, install by dragging, follow the on-screen first-launch instructions, and confirm the menu bar item appears.

**Acceptance Scenarios**:

1. **Given** a release DMG, **When** the user opens it, **Then** a window shows the AgentMeter app icon, an Applications shortcut, and a background that tells the user to drag the app onto Applications.
2. **Given** a DMG built without Apple notarization, **When** the user opens it, **Then** the background also explains the first-launch step needed after each install or upgrade for macOS 14 and for macOS 15 or later, plus the command-line alternative.
3. **Given** a notarized DMG, **When** the user opens it, **Then** the background shows no first-launch workaround instructions.
4. **Given** the app was dragged to Applications, **When** the user completes the first-launch step (non-notarized) or simply opens it (notarized), **Then** AgentMeter starts and its item appears in the menu bar.
5. **Given** the mounted DMG in Finder, **When** the user looks at the volume, **Then** the volume shows the AgentMeter icon.

---

### User Story 2 - Install and upgrade with Homebrew (Priority: P2)

A Homebrew user runs `brew install --cask rhuss/tap/agentmeter` and gets AgentMeter in Applications. Later, `brew upgrade --cask agentmeter` installs a newer release. `brew uninstall --zap --cask agentmeter` removes the app and its configuration and log files.

**Why this priority**: Homebrew is the preferred installation path for many developers who use coding agents, and it makes upgrades a single command. It depends on the release artifacts from User Story 1.

**Independent Test**: After a release, tap the repository on a clean machine or account, install the cask, launch the app, publish a second release, upgrade, and confirm the new version runs.

**Acceptance Scenarios**:

1. **Given** a published release and an updated cask, **When** the user runs the install command, **Then** AgentMeter is installed into Applications from the release DMG and the download's checksum is verified.
2. **Given** a non-notarized release, **When** the installation finishes, **Then** Homebrew shows a caveat with the first-launch step needed after each install or upgrade.
3. **Given** an installed older version, **When** a newer release is published and the user upgrades, **Then** the newer version replaces the old one, and a running AgentMeter is quit before the upgrade and opened again afterwards (for a release that is not notarized, macOS asks for the first-launch step first).
4. **Given** an installed app, **When** the user uninstalls with zap, **Then** the app, the configuration directory `~/.config/agentmeter`, the log directory `~/Library/Logs/agentmeter` and the preferences file `~/Library/Preferences/dev.rhuss.agentmeter.plist` are removed.

---

### User Story 3 - Permissions survive rebuilds and upgrades (Priority: P2)

Once a user (or the developer) has allowed notifications and enabled start at login, those choices stay in effect after the app is replaced by a rebuilt or newer version signed with the same identity. Today every rebuild is treated by macOS as a new app, so notification permission is silently lost and threshold banners never appear.

**Why this priority**: Without it, every update breaks threshold notifications and start at login, which are core behaviors of the app. It is also the open idea-inbox item `stable-signing-identity`.

**Independent Test**: With a stable signing identity available, build and launch the app, grant notifications and enable start at login, rebuild (or install the next release), launch again, and confirm a threshold notification is delivered and the login item is still active without new prompts.

**Acceptance Scenarios**:

1. **Given** a stable signing identity (Developer ID or self-signed) and notification permission granted, **When** the app is rebuilt or upgraded and relaunched, **Then** notifications are still delivered without a new permission prompt.
2. **Given** start at login enabled, **When** the app is rebuilt or upgraded, **Then** start at login is still enabled.
3. **Given** the signed app, **When** its signature requirement is inspected, **Then** it identifies the app by bundle identifier and signing certificate, not by a hash of this particular build.
4. **Given** no stable identity is available, **When** the app is built, **Then** the build still succeeds with an ad-hoc signature and the output states that permissions will not persist across rebuilds.

---

### User Story 4 - Publish a release with one command (Priority: P1)

The maintainer tags a version and runs one command. It builds the app with the version from the tag, signs it with the best available identity, creates the DMG, notarizes it when possible, publishes a GitHub release with the DMG and its checksum, and updates the Homebrew cask.

**Why this priority**: Users can only receive what the maintainer can reliably produce. One command keeps releases repeatable and is the basis for later automation.

**Independent Test**: On the maintainer's Mac, create a tag on a clean tree, run the release command, and verify the GitHub release, the attached DMG and checksum, and the cask commit in the tap.

**Acceptance Scenarios**:

1. **Given** a clean working tree whose HEAD carries tag `vX.Y.Z`, **When** the maintainer runs the release command, **Then** the app reports version X.Y.Z, the DMG is named `AgentMeter-X.Y.Z.dmg`, and a GitHub release `vX.Y.Z` exists with the DMG and its SHA-256 attached.
2. **Given** a Developer ID certificate and notarization credentials, **When** the release runs, **Then** the app and DMG are signed with Developer ID, the DMG is notarized and stapled, and the release notes state "notarized".
3. **Given** only the self-signed certificate, **When** the release runs, **Then** the release is signed with it, is not notarized, uses the background with first-launch instructions, and the release notes say so.
4. **Given** no certificate at all, **When** the release runs, **Then** it stops before publishing, unless the maintainer explicitly allows an ad-hoc release.
5. **Given** a successful GitHub release, **When** the release command finishes, **Then** the cask in the tap repository has the new version and checksum, committed and pushed.
6. **Given** the release command, **When** it runs without a terminal (for example from a script), **Then** it completes without interactive prompts.

---

### User Story 5 - Find installation instructions (Priority: P3)

A visitor reading the README sees the app icon and an installation section covering the DMG download, Homebrew, and the first-launch step needed after each install or upgrade.

**Why this priority**: Documentation is needed for adoption but delivers no value without the artifacts.

**Independent Test**: Read the README on GitHub and follow the installation section without other help.

**Acceptance Scenarios**:

1. **Given** the README, **When** a visitor reads the installation section, **Then** it lists the download link to the latest release, the Homebrew command, and the first-launch step for builds that are not notarized.
2. **Given** the README, **When** the maintainer looks for release instructions, **Then** it explains how to create the self-signed certificate once and how to run a release.

### Edge Cases

- The tag `vX.Y.Z` already has a GitHub release: the release command stops without changing anything, unless the maintainer explicitly asks to replace the release assets.
- HEAD is not tagged, the tag does not match `vX.Y.Z`, the tag is not pushed to `origin` (or points elsewhere there), or the working tree has uncommitted changes: the release command stops before building, with a message naming the problem.
- Notarization is rejected by Apple or times out: the release stops before publishing and shows Apple's log location; nothing is uploaded.
- The Homebrew tap repository cannot be cloned or pushed: the GitHub release stays published, the cask update is reported as failed, and the output names the cask-only command (FR-021a) to finish it.
- An upload to the GitHub release fails: the release stays a draft, invisible to users, and the output says how to retry or delete it.
- A Developer ID certificate is present but no notarization profile: the release continues as "Developer ID, not notarized" with a warning (FR-014a).
- The configured self-signed certificate is missing from the keychain on a second machine: the build falls back to ad-hoc for development builds and states it; releases stop as in User Story 4 scenario 4.
- The user already has a development build of AgentMeter running from another location: installing the release does not need to manage it; the README notes that only one copy should run.
- The app icon file is missing: the build fails with a clear message, because a release without an icon is not acceptable.
- A release switches signing tier (for example the first Developer ID release after self-signed releases): macOS sees a new signing identity once, so users grant notifications and enable start at login again after that upgrade; later releases on the same tier keep them.
- A user on an Intel Mac or macOS 13 tries to install: the cask declares the supported architecture and minimum macOS version, and the app's minimum system version prevents launch on older macOS.

## Requirements *(mandatory)*

### Functional Requirements

**Signing**

- **FR-001**: Every app bundle build (development and release) MUST select its signing identity in this order: Developer ID Application certificate, then a stable self-signed code-signing certificate found by name (default "AgentMeter Signing", overridable per build), then ad-hoc.
- **FR-002**: The build MUST print which signing tier it used.
- **FR-003**: Builds signed with the first two tiers MUST carry a designated requirement based on the bundle identifier and the signing certificate (for Developer ID, the team identifier), not on a hash of the build, so macOS recognizes rebuilds and newer versions as the same app.
- **FR-004**: The maintainer MUST be able to override the identity selection explicitly (for example to force ad-hoc).
- **FR-005**: Release builds signed with Developer ID MUST be built with the hardened runtime and a secure timestamp, as notarization requires.

**App bundle**

- **FR-006**: The app bundle MUST contain the AgentMeter icon from `Resources/icons/macos/AgentMeter.icns` and reference it as its icon. If the icon file is missing, the build MUST fail with a message naming the file.
- **FR-007**: The app bundle's short version MUST be the release version from the tag, and its build number MUST be the number of commits reachable from the built commit, so it increases with every release.
- **FR-008**: Development builds (an untagged commit, or a tagged commit with uncommitted changes) MUST still build. The bundle's short version stays numeric (the nearest `vX.Y.Z` tag's version, or "0.0.0" when there is none), and the app's own version display shows it with a "-dev" suffix (for example "0.2.0-dev").

**DMG**

- **FR-009**: The release MUST produce a compressed, read-only DMG named `AgentMeter-X.Y.Z.dmg` containing the app and a shortcut to `/Applications`.
- **FR-010**: Opening the DMG MUST show a window with a background image, the app icon and the Applications shortcut arranged for drag-and-drop installation.
- **FR-011**: For builds that are not notarized, the DMG background MUST show the first-launch step needed after each install or upgrade: on macOS 14, Control-click AgentMeter in Applications and choose Open; on macOS 15 and later, open it once and then choose "Open Anyway" in System Settings, Privacy & Security; alternatively the command `xattr -dr com.apple.quarantine /Applications/AgentMeter.app`.
- **FR-012**: For notarized builds, the DMG background MUST NOT show the first-launch workaround.
- **FR-013**: The DMG volume MUST show the AgentMeter icon.
- **FR-014**: When Developer ID and notarization credentials are available, the DMG MUST be signed, notarized and stapled so the DMG itself opens offline without Gatekeeper warnings. (The app copied out of it is checked online on first launch; stapling the app is not required.)
- **FR-014a**: Notarization credentials MUST be read from a notarization keychain profile found by name (default "agentmeter-notary", overridable per release). When a Developer ID certificate is present but the profile is missing, the release MUST warn, continue as "Developer ID, not notarized", and use the not-notarized DMG background, release notes and cask caveats.

**Release**

- **FR-015**: One release command MUST perform, in order: preflight checks, build, sign, DMG creation, optional notarization, GitHub release creation as a draft, upload of the DMG and a SHA-256 checksum file, publishing the draft only after all uploads succeeded, and the cask update.
- **FR-016**: The preflight MUST stop the release when the working tree is dirty, HEAD has no `vX.Y.Z` tag, the tag does not exist on the `origin` remote or points to a different commit there, the GitHub release for the tag already exists (unless the maintainer explicitly requests replacing its assets), or no non-ad-hoc identity is available (unless ad-hoc is explicitly allowed).
- **FR-017**: The release notes MUST state the signing tier and whether the DMG is notarized, and for non-notarized releases include the first-launch step.
- **FR-018**: The release command MUST run without interactive prompts when all inputs are provided, so a future CI job can call it.
- **FR-019**: A dry-run mode MUST build, sign and create the DMG locally without publishing anything or touching the tap. It MUST work on any commit (untagged or with uncommitted changes, using the development version) and report preflight problems as warnings instead of stopping.

**Homebrew**

- **FR-020**: The tap repository `rhuss/homebrew-tap` MUST contain a cask `agentmeter` that installs `AgentMeter.app` from the release DMG, verifies its SHA-256, and declares Apple Silicon and macOS 14 or newer as requirements.
- **FR-021**: The release command MUST update the cask's version and checksum in a fresh temporary clone of the tap repository, then commit and push it. The cask is updated only when the release is the latest published release; for an older one (replacing the assets of an old tag) the cask stays unchanged and the command says so. The checksum in the cask MUST equal the SHA-256 of the published DMG: the release command checks it against the final (stapled) DMG, the cask-only command against the downloaded DMG asset (added after the code review, FINDING-29 and FINDING-32).
- **FR-021a**: A separate cask-only command MUST update the cask for an already published release (reading version and checksum from that release), so a failed cask update can be finished without re-running the release.
- **FR-022**: For non-notarized releases, the cask MUST show caveats with the first-launch step needed after each install or upgrade.
- **FR-023**: The cask MUST support `zap` removal of `~/.config/agentmeter`, `~/Library/Logs/agentmeter` and `~/Library/Preferences/dev.rhuss.agentmeter.plist`.
- **FR-024**: The cask MUST stop a running AgentMeter before upgrading or uninstalling. Homebrew opens the app again after a successful `brew upgrade`; the caveats, the release notes and the README say so. For releases that are not notarized, the first-launch step is still needed after each install or upgrade (FR-022).

**Documentation**

- **FR-025**: The README MUST contain an installation section (DMG download, Homebrew command, first-launch step, a note that only one copy of AgentMeter should run at a time) and a maintainer section (creating the self-signed certificate once with a 10-year validity, exporting it as a `.p12` file and importing it on a second machine or a future CI runner, optional Developer ID and notarization profile setup, running a release, a dry run and the cask-only update).

### Key Entities

- **Signing tier**: The kind of identity used for a build: Developer ID (notarizable), self-signed (stable, not notarizable; this tier covers any certificate that is not a Developer ID Application certificate), or ad-hoc (changes every build). Determines persistence of permissions, notarization, DMG background variant and cask caveats.
- **Release**: A version `X.Y.Z` from a git tag, with its DMG, SHA-256, signing tier, notarization status and release notes.
- **DMG background variant**: The image shown in the DMG window; one variant with first-launch instructions (not notarized) and one without (notarized).
- **Cask**: The Homebrew definition in the tap repository pointing at the release DMG with version and checksum, plus caveats and zap paths.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A person who has never built AgentMeter can go from opening the release page to a running menu bar item in under 3 minutes, using only the instructions shown in the DMG window or the README.
- **SC-002**: A Homebrew user installs AgentMeter with one command and upgrades it with one command.
- **SC-003**: After granting notifications once, a user of a stable-signed build receives threshold notifications after 3 consecutive rebuilds or upgrades without being asked again.
- **SC-004**: The maintainer publishes a complete release (GitHub release, DMG, checksum, cask update) with a single command and no manual edits.
- **SC-005**: A release with a problem detected in preflight (dirty tree, missing tag, existing release without an explicit replace request) changes nothing on GitHub or in the tap in 100% of cases.
- **SC-006**: When Developer ID credentials are added later, the next release is notarized without changes to the release procedure beyond configuring the credentials.

## Assumptions

- AgentMeter supports Apple Silicon and macOS 14 or newer only, as today; no universal (Intel) build in this feature.
- The maintainer does not currently have a Developer ID certificate; the self-signed tier is the default release path, and the Developer ID path must work once credentials are configured, but cannot be verified end to end until then.
- The maintainer creates the self-signed certificate once by following documented steps; the build does not create certificates itself.
- GitHub releases on `rhuss/agentmeter` are the download location, and the GitHub command-line client is authenticated on the maintainer's Mac.
- The tap repository `rhuss/homebrew-tap` already exists and is used for other projects; the release adds a `Casks/` directory if missing.
- Updates are delivered by Homebrew or by downloading a new DMG; an in-app updater is out of scope.
- A CI workflow is out of scope; the release command is designed so one can call it later.
- The official `homebrew/cask` repository is out of scope.
- The cask only prints caveats; it does not remove the quarantine attribute on the user's behalf.
- The DMG backgrounds are prepared images (one per variant) stored in the repository, not rendered per release; they do not show the version number.
