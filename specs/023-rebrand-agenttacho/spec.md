# Feature Specification: Rebrand AgentMeter to AgentTacho

**Feature Branch**: `023-rebrand-agenttacho`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Rebrand AgentMeter to AgentTacho in the app repository, from brainstorm/22-rebrand-agenttacho.md. Scope: the brainstorm's sections 'App', 'Release and distribution' and 'Repository and docs' (clean break: bundle id dev.rhuss.agenttacho, new data folders with a one-time copy of config.json, imported-prices.json and last-good.json from the old folders, DMG AgentTacho-<version>.dmg, cask agenttacho with the old cask renamed in rhuss/homebrew-tap, transfer rhuss/agentmeter to AgentTacho/agenttacho, make release starts the site deploy, first release 0.5.0). The site rename and local folder renames are out of scope. Supersedes spec 022."

The name AgentMeter belongs to another product in the same field (agentmeter.app, an AI agent usage tracker), so the app is renamed **AgentTacho** (brainstorm 22). This is a **clean break**: AgentTacho is a new app as far as macOS is concerned (its own bundle identifier, data folders, notification permission and login item), not an in-place rename of AgentMeter. The installed base of AgentMeter is about one person (every release is from 2026-10-15 and 2026-10-16, the repository has no stars or forks), so the move from AgentMeter to AgentTacho is a one-time manual install, made easy by a one-time copy of the user's settings.

Terms used below:

- **Old folders**: AgentMeter's data folders `~/.config/agentmeter/`, `~/Library/Logs/agentmeter/` and `~/Library/Application Support/agentmeter/`.
- **New folders**: `~/.config/agenttacho/`, `~/Library/Logs/agenttacho/` and `~/Library/Application Support/agenttacho/`.
- **Carried-over files**: `config.json` and `imported-prices.json` (configuration folder) and `last-good.json` (Application Support folder).
- **Official repository**: the GitHub repository whose releases the app checks (spec 013 FR-004) and to which `make release` publishes (spec 005). It changes from `rhuss/agentmeter` to `AgentTacho/agenttacho`.
- **Site repository**: `AgentTacho/agenttacho.github.io` with the workflow `deploy.yml`.
- **Name check**: a search of the repository for "AgentMeter" and "agentmeter" (any case), outside `specs/`, `brainstorm/` and `docs/superpowers/`.

## Clarifications

### Session 2026-10-16

- Q: Should AgentTacho tell the user about the rename on its first launch after copying AgentMeter's settings? → A: No. No in-app notice; the README's moving instructions are enough, and the log records the copy (FR-011, FR-027).

### Session 2026-10-17

- Q: How are requirements checked that only a release from `main` can meet? → A: FR-019, SC-004 and SC-005 move to "After the merge" groups with unchanged numbers. They are checked with the 0.5.0 release (T043, T044), not by the verification before the merge (evolved during finish, after the repository transfer of FR-020 and FR-021 was done).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Everything the user sees says AgentTacho (Priority: P1)

A user installs AgentTacho from its DMG or with `brew install --cask rhuss/tap/agenttacho`. The DMG, the app in the Applications folder, the menu bar item's accessibility name, the dropdown, Settings, the About tab, notifications, update messages and alerts all say AgentTacho. Nothing in the app says AgentMeter. Links in the app lead to `github.com/AgentTacho/agenttacho`; the sponsor link still leads to `github.com/sponsors/rhuss`.

**Why this priority**: The rename exists to stop being confused with another product; a single leftover "AgentMeter" in the app undoes that.

**Independent Test**: Build the app, open every screen and trigger each notification and update state in a test build; run the name check on the sources and resources.

**Acceptance Scenarios**:

1. **Given** a fresh build, **When** the user opens the dropdown, every Settings tab and the About tab, **Then** each names the app AgentTacho and none says AgentMeter.
2. **Given** a fresh build, **When** a threshold notification, a credential notification and each update state appear, **Then** their texts say AgentTacho.
3. **Given** a fresh build, **When** the user opens the repository, new issue, security statement and release page links, **Then** each URL names `AgentTacho/agenttacho`, and the sponsor link is `https://github.com/sponsors/rhuss`.
4. **Given** the DMG of a release, **When** it is opened, **Then** its file name, volume name, background and app are named AgentTacho.

---

### User Story 2 - Moving from AgentMeter keeps the user's setup (Priority: P1)

A user who ran AgentMeter installs AgentTacho and opens it. AgentTacho finds no configuration of its own, finds AgentMeter's, and copies the user's settings, imported prices and last good values once. The user sees their accounts, groups, budgets, thresholds and menu bar arrangement exactly as before, with values shown at once from the last good file. AgentMeter's folders stay untouched, so AgentMeter still works if the user opens it again. If AgentMeter is still running, AgentTacho says so and offers to stop it, as it does today for a second copy of itself.

**Why this priority**: Without the copy, a clean break means rebuilding accounts, groups and budgets by hand, which turns a rename into a chore.

**Independent Test**: With a home directory that holds only the old folders, start AgentTacho and compare its configuration with AgentMeter's; check the old folders byte for byte before and after.

**Acceptance Scenarios**:

1. **Given** the old configuration folder holds `config.json` and `imported-prices.json`, the old Application Support folder holds `last-good.json`, and no new configuration folder exists, **When** AgentTacho starts, **Then** the new folders hold copies of those three files and AgentTacho shows the same accounts, groups, budgets and menu bar arrangement as AgentMeter did.
2. **Given** the copy happened, **When** the user compares the old folders with before, **Then** every file in them is unchanged and none was added or removed.
3. **Given** a new configuration folder already exists (even an empty one), **When** AgentTacho starts, **Then** it copies nothing, whatever the old folders hold.
4. **Given** only some carried-over files exist in the old folders, **When** AgentTacho starts for the first time, **Then** it copies those that exist and starts with defaults for the rest.
5. **Given** AgentMeter is running, **When** AgentTacho starts, **Then** it shows the alert it shows for another running copy, naming AgentMeter with its version and location, and offers to stop it and continue, or to quit.

---

### User Story 3 - A release publishes AgentTacho to its new home (Priority: P1)

The maintainer runs `make release` for 0.5.0. It builds AgentTacho, creates `AgentTacho-0.5.0.dmg`, publishes the GitHub release "AgentTacho 0.5.0" in `AgentTacho/agenttacho` with the DMG, its checksum file and `release-info.json`, starts the site deploy, and updates the tap: a new cask `agenttacho`, with the old cask `agentmeter` renamed to it, so that `brew upgrade` moves an AgentMeter install to AgentTacho.

**Why this priority**: Nothing reaches users without a release; the release tooling must produce the new names end to end.

**Independent Test**: Run the release script tests with stubbed `gh` and tap repository; check the DMG name, the release title, `release-info.json`, the cask, the cask rename entry and the order of steps.

**Acceptance Scenarios**:

1. **Given** the tag `v0.5.0` on the official repository, **When** `make release` runs, **Then** the GitHub release in `AgentTacho/agenttacho` is titled "AgentTacho 0.5.0" and has the assets `AgentTacho-0.5.0.dmg`, `AgentTacho-0.5.0.dmg.sha256` and `release-info.json` naming that DMG.
2. **Given** that release, **When** the tap is updated, **Then** `rhuss/homebrew-tap` has a cask `agenttacho` that downloads from `https://github.com/AgentTacho/agenttacho/releases/download/v0.5.0/AgentTacho-0.5.0.dmg`, and a cask rename entry from `agentmeter` to `agenttacho`.
3. **Given** a Mac with the cask `agentmeter` installed, **When** the user runs `brew upgrade` after the release, **Then** Homebrew installs AgentTacho under the cask name `agenttacho` and removes the AgentMeter app it installed.
4. **Given** a release marked latest, **When** `make release` has published it, **Then** it starts `deploy.yml` in the site repository once, before the cask update, and says so.
5. **Given** starting the site deploy fails, **When** `make release` reaches that step, **Then** it prints a warning with the command to start it by hand, still updates the cask, and its exit status does not change because of that failure.

---

### User Story 4 - Installed AgentMeter copies point to AgentTacho (Priority: P2)

A user still runs AgentMeter 0.4.1. After the repository transfer and the 0.5.0 release, AgentMeter's update check reaches the new repository through GitHub's redirect and reports "AgentMeter 0.5.0 available" with a link to the release page. One-click install is not offered (0.4.1 looks for a DMG named AgentMeter), so the user downloads AgentTacho from the page.

**Why this priority**: The old app cannot install the new one, but it must not go silent; pointing to the release is enough for an installed base of about one.

**Independent Test**: After the transfer, request the old API path and an old asset URL with redirects followed; after the release, let an installed 0.4.1 check for updates.

**Acceptance Scenarios**:

1. **Given** the transfer and rename are done, **When** the old API path `api.github.com/repos/rhuss/agentmeter/releases/latest` is requested and redirects are followed, **Then** the answer is the latest release of `AgentTacho/agenttacho`, and every hop is on a host the update host policy allows.
2. **Given** the transfer is done, **When** the old download URL of the 0.4.1 DMG is requested and redirects are followed, **Then** the DMG downloads with success.
3. **Given** AgentTacho 0.5.0 is released, **When** an installed AgentMeter 0.4.1 checks for updates, **Then** it shows that 0.5.0 is available with a link to its release page.

---

### User Story 5 - The repository and its docs carry the new name (Priority: P2)

A visitor arrives at `github.com/AgentTacho/agenttacho` (or follows an old `rhuss/agentmeter` link and is redirected there). The README introduces AgentTacho, says once that it was formerly called AgentMeter, explains how to move from AgentMeter, and its "Security and privacy" section names the new folders and the new update request. AGENTS.md and the contribution notes say AgentTacho.

**Why this priority**: Docs are the first thing a visitor reads, but they can follow the code by a few hours without harm.

**Independent Test**: Read the README and AGENTS.md; run the name check and review each remaining match.

**Acceptance Scenarios**:

1. **Given** the README, **When** a reader looks for the old name, **Then** it appears in exactly one sentence near the top ("formerly AgentMeter") and in the moving-from-AgentMeter instructions, which name the old app and folders.
2. **Given** the README's "Security and privacy" section, **When** it describes the update check and the files AgentTacho writes, **Then** it names `https://api.github.com/repos/AgentTacho/agenttacho/releases/latest` and the new folders, and says that AgentTacho reads the old folders once and never writes to them.
3. **Given** the repository settings after the transfer, **When** a visitor opens the repository, **Then** its homepage field names `https://agenttacho.github.io`.

---

### Edge Cases

- **Both old and new configuration exist**: AgentTacho uses its own and ignores the old folders, so a user who already set up AgentTacho never has it overwritten.
- **A carried-over file is unreadable or invalid**: the copy is byte for byte; validation happens when AgentTacho loads the file, with today's handling of an invalid configuration (spec 001) and an unusable last-good file (spec 010). The copy itself does not judge content.
- **A copy fails half way** (for example, the disk is full): AgentTacho does not leave a partial file under a carried-over name; it starts with defaults for that file and logs which copy failed. Because the new configuration folder now exists, it does not try again on the next start; the README says how to repeat the move by hand.
- **The configuration names AgentMeter's folders**: values in `config.json` that are paths under the old folders, if any, are not rewritten; the carried-over files are copied as they are.
- **Notification permission and launch at login**: macOS keeps both per app, so AgentTacho asks for notification permission again, and launch at login is off until the user turns it on in Settings > General. AgentMeter's login item stays registered until AgentMeter is deleted; the README's moving instructions say so.
- **AgentMeter and AgentTacho both run**: both would poll the same endpoints and send the same notifications; the single-instance alert (User Story 2, scenario 5) prevents this unless the user chooses to quit AgentTacho instead.
- **Credentials**: AgentTacho reads the agents' credentials the way AgentMeter did (spec 006, the `security` tool for the Claude keychain item), so a change of bundle identifier needs no new keychain approval.
- **Development builds and update-test builds**: `make app` and `make app-update-test` produce `AgentTacho.app`; the update-test source parsing (spec 013 FR-025) is unchanged apart from its Info.plist key name.
- **A newer AgentMeter release appears**: none is planned; the old cask is renamed, so the tap no longer offers AgentMeter.
- **Spec 022's worktree**: its uncommitted draft is superseded; the repository transfer requirements it held (redirect check, site deploy trigger) are part of this spec.

## Requirements *(mandatory)*

### Functional Requirements

**Name and identity**

- **FR-001**: The app's display name, bundle name and executable MUST be AgentTacho, and the app bundle MUST be `AgentTacho.app`.
- **FR-002**: Every user-facing text (menu bar accessibility name, dropdown, Settings, About, notifications, update states and block reasons, alerts, the Homebrew command shown in the update line) MUST say AgentTacho instead of AgentMeter. The update request's `User-Agent` MUST be `AgentTacho/<version>`.
- **FR-003**: The bundle identifier MUST be `dev.rhuss.agenttacho`. Names derived from it (the temporary update folder, the cask's `uninstall quit` and `zap` entries, notification and defaults identifiers that contain the old name) MUST use the new name.
- **FR-004**: The app's own Info.plist keys (version display, commit, build date, release tag, signing, notarized, update source) MUST carry the AgentTacho prefix instead of the AgentMeter prefix, read and written consistently by the build scripts and the app.
- **FR-005**: The app's links MUST name `https://github.com/AgentTacho/agenttacho` (repository, new issue, latest release page, security statement with `#security-and-privacy`). The sponsor link MUST stay `https://github.com/sponsors/rhuss`.
- **FR-006**: Image assets, asset catalog names and icon master file names MUST carry the new name; the images themselves (mascot, app icon, menu bar glyphs) MUST stay as they are.

**Data folders and the one-time move**

- **FR-007**: AgentTacho MUST keep its configuration, imported prices, log and last good values in the new folders, with the same file names as today.
- **FR-008**: At startup, after the running-copy check of FR-012 and before loading its configuration, AgentTacho MUST copy each carried-over file that exists in the old folders to the same name in the new folders, if and only if the new configuration folder does not exist yet. It MUST create the new folders as needed. Logs MUST NOT be copied.
- **FR-009**: AgentTacho MUST NOT create, change, rename or delete anything in the old folders, at any time.
- **FR-010**: A carried-over file MUST appear in the new folder only complete, never partial. If a copy fails, AgentTacho MUST start with defaults for that file and write one log line naming the file and the reason.
- **FR-011**: The log MUST record, once, which files were copied from the old folders.
- **FR-027**: The copy MUST NOT show any notice, notification or dropdown line; besides the log line of FR-011, it is silent. The README's moving instructions (FR-023) explain it.

**Running alongside AgentMeter**

- **FR-012**: At startup, AgentTacho MUST treat a running AgentMeter (bundle identifier `dev.rhuss.agentmeter`) like another running copy of itself (today's single-instance alert): it shows the other app's name, version and location, and offers to stop it and continue, or to quit. This check MUST run before the copy of FR-008, so that AgentMeter is no longer writing its files while they are copied; if the user quits, nothing is copied.

**Release and distribution**

- **FR-013**: The release MUST produce `AgentTacho-<version>.dmg` with the volume name AgentTacho and DMG backgrounds that show `AgentTacho.app`; `release-info.json` MUST name that DMG, and the app's update check MUST expect that name.
- **FR-014**: The GitHub release title and release notes MUST say AgentTacho; the install command in the release notes and README MUST be `brew install --cask rhuss/tap/agenttacho`.
- **FR-015**: The release scripts' default app repository MUST be `AgentTacho/agenttacho`; the tap MUST stay `rhuss/homebrew-tap`. Both stay overridable for testing as today. The default notarization keychain profile MUST be `agenttacho-notary`; the README's release section says how to store it once. Because the profile's name changes, a release (not a dry run) with a Developer ID certificate MUST stop before building when the profile is missing, naming the command that stores it, unless `ALLOW_UNNOTARIZED=1` is set (added in code review).
- **FR-016**: The tap update MUST write the cask `agenttacho` (download URL under `AgentTacho/agenttacho`, homepage `https://github.com/AgentTacho/agenttacho`, app `AgentTacho.app`, uninstall and zap entries for the new identifier and folders) and MUST add a rename entry from `agentmeter` to `agenttacho` in the tap, so that Homebrew moves existing installs. The old cask file MUST be removed from the tap in the same change. The rename entry and the removal happen once, with the first AgentTacho cask update; later cask updates MUST leave them as they are.
- **FR-017**: The app MUST recognise a Homebrew install by the cask `agenttacho` and `AgentTacho.app`, and show `brew upgrade --cask agenttacho`.
- **FR-018**: Right after publishing a release marked latest, and before the cask update, `make release` MUST start `deploy.yml` in `AgentTacho/agenttacho.github.io` once and report it. It MUST NOT start it for a release that is not the latest or when the app repository is overridden for testing. If starting it fails, `make release` MUST print a warning naming the command to start it by hand, MUST still update the cask, and MUST NOT change its exit status because of that failure.

**Repository**

- **FR-020**: With the maintainer's explicit approval, `rhuss/agentmeter` MUST be transferred to the organization `AgentTacho` and renamed `agenttacho`, before this change is merged to `main`.
- **FR-021**: Right after the transfer, and before 0.5.0 is released, the maintainer MUST verify with requests that follow redirects that the old latest-release API path answers with the new repository's latest release and that the old 0.4.1 download URLs (DMG and `release-info.json`) succeed, with every hop on a host the update host policy allows. The commands and results are recorded in this feature's quickstart. If either check fails, 0.5.0 is not released until the cause is found. The local clone's `origin` is then set to the new URL.
- **FR-022**: After the transfer, the repository's homepage MUST be `https://agenttacho.github.io`, and the README MUST state that no new repository named `rhuss/agentmeter` may be created, because that ends GitHub's redirect.

**Docs and leftovers**

- **FR-023**: README and AGENTS.md MUST say AgentTacho. The README MUST mention the old name once near the top ("formerly AgentMeter") and MUST have short moving-from-AgentMeter instructions: install AgentTacho, open it (settings are copied once), allow notifications, turn on launch at login if wanted, delete `AgentMeter.app` (or run `brew upgrade`), and optionally delete the old folders by hand.
- **FR-024**: The README's "Security and privacy" section MUST name the new folders, the new update request URL, and the one-time read of the old folders (FR-008, FR-009), in the same change as the code.
- **FR-025**: Doc comments, log texts and script output that name the app MUST say AgentTacho. References to historical specs keep their numbers. Historical specs, brainstorms and `docs/superpowers/` keep the old name.
- **FR-026**: After this change, the name check MUST find the old name only in: the old-folder paths and old bundle identifier used by FR-008 and FR-012, the cask rename entry (FR-016), the README sentences required by FR-022 and FR-023, test fixtures for those, and links to other projects. `.github/FUNDING.yml` stays `github: rhuss`.

**After the merge (release steps)**

These requirements can only be met by a release tagged on `main`, so they are checked when that release is made (tasks T043 and T044, quickstart Q5 to Q7), not by the verification before the merge.

- **FR-019**: The first release under the new name MUST be 0.5.0.

### Key Entities

- **Old folders / new folders**: AgentMeter's and AgentTacho's data locations; the old ones are only ever read, once.
- **Carried-over files**: `config.json`, `imported-prices.json`, `last-good.json`; copied byte for byte on the first start without a new configuration folder.
- **Official repository**: `AgentTacho/agenttacho`; source of update checks, target of releases and app links. `rhuss/agentmeter` remains only as GitHub's redirect.
- **Cask**: `agenttacho` in `rhuss/homebrew-tap`, with a rename entry from `agentmeter`.
- **Site repository**: `AgentTacho/agenttacho.github.io`, whose deploy `make release` starts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user moving from AgentMeter sees all their accounts, groups, budgets, thresholds and menu bar arrangement in AgentTacho on first launch, with no manual re-entry, and values appear without waiting for a refresh.
- **SC-002**: The old folders are byte-for-byte identical before and after AgentTacho's first and later starts.
- **SC-003**: The name check finds 0 matches outside the exceptions listed in FR-026.
- **SC-006**: All tests pass (`make test`, `make test-release`), and no release fails because of the site deploy trigger.

After the merge (checked with the 0.5.0 release, tasks T043 and T044, not by the verification before the merge):

- **SC-004**: The 0.5.0 release in `AgentTacho/agenttacho` has exactly the three assets named in User Story 3, and `brew upgrade` on a Mac with the `agentmeter` cask ends with AgentTacho installed and AgentMeter removed.
- **SC-005**: An installed AgentMeter 0.4.1 reports 0.5.0 as available within one update check after the release.

## Assumptions

- The maintainer owns the `AgentTacho` organization (created 2026-10-16; it already holds `agenttacho.github.io`) and approves the transfer; the `gh` token can create releases in it and start workflows in the site repository.
- GitHub keeps redirecting web, API, download and git URLs of a repository that was transferred and renamed, as long as no new repository takes the old name; the update host policy checks hosts only (spec 013), so redirects within the allowed GitHub hosts are accepted by installed copies.
- Homebrew taps support renaming a cask through a rename file in the tap, and `brew upgrade` then installs the renamed cask and removes the artifacts of the old one. This is checked in the plan; if it behaves differently, the README's moving instructions cover the manual path.
- The images are reused as they are (brainstorm 22); screenshots that show the old name are replaced later by the demo screenshots (landing plan, stream B).
- The site's rename, the local folder renames, the domain and a trademark search are outside this spec (brainstorm 22).
- This change lands after `021-recover-stuck-offline`, which touches many of the same files; the rename is applied on top of it.
- The maintainer stores the notarization credentials once under the new profile name `agenttacho-notary` before releasing 0.5.0; the old profile can be removed afterwards.
