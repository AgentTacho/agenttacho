# Feature Specification: Name the app AgentTacho

**Feature Branch**: `023-rebrand-agenttacho`

**Created**: 2026-10-16

**Status**: Complete (released as 0.5.0 on 2026-10-17)

**Input**: User description: "Name the app AgentTacho in the app repository, from brainstorm/22-rebrand-agenttacho.md. Scope: the brainstorm's sections 'App', 'Release and distribution' and 'Repository and docs' (bundle id dev.rhuss.agenttacho, data folders named agenttacho, DMG AgentTacho-<version>.dmg, cask agenttacho in AgentTacho/homebrew-tap, repository AgentTacho/agenttacho, make release starts the site deploy, first release 0.5.0). The site and the maintainer's local folders are out of scope."

The app is called **AgentTacho** (brainstorm 22). "Agent" names what it watches, and "Tacho" (the German everyday word for a speedometer, close to the American "tach") matches the gauge mascot, so the imagery fits the name. AgentTacho has its own identity as far as macOS is concerned: its bundle identifier, data folders, notification permission and login item all carry the name.

Terms used below:

- **Data folders**: `~/.config/agenttacho/`, `~/Library/Logs/agenttacho/` and `~/Library/Application Support/agenttacho/`.
- **Official repository**: the GitHub repository whose releases the app checks (spec 013 FR-004) and to which `make release` publishes (spec 005): `AgentTacho/agenttacho`.
- **Site repository**: `AgentTacho/agenttacho.github.io` with the workflow `deploy.yml`.

## Clarifications

### Session 2026-10-17

- Q: How are requirements checked that only a release from `main` can meet? → A: FR-019, SC-004 and SC-005 move to "After the merge" groups with unchanged numbers. They are checked with the 0.5.0 release (T043, T044), not by the verification before the merge.
- Q: What happens to the requirements for settings from the earlier app? → A: The one-time settings copy, the detection of a running copy of the earlier app, the Homebrew entry that moved installs of the earlier cask, and the check for the earlier name in the repository were removed at the maintainer's request. FR-008 to FR-012, FR-021, FR-022, FR-026 and FR-027 are gone; FR-016 covers only the cask `agenttacho`.
- Q: Where does the cask live? → A: In its own tap `AgentTacho/homebrew-tap` (`brew install --cask agenttacho/tap/agenttacho`), next to the app repository. `rhuss/homebrew-tap` keeps the formulae of other projects and no longer holds a cask of this app.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Everything the user sees says AgentTacho (Priority: P1)

A user installs AgentTacho from its DMG or with `brew install --cask agenttacho/tap/agenttacho`. The DMG, the app in the Applications folder, the menu bar item's accessibility name, the dropdown, Settings, the About tab, notifications, update messages and alerts all say AgentTacho. Links in the app lead to `github.com/AgentTacho/agenttacho`; the sponsor link leads to `github.com/sponsors/rhuss`.

**Why this priority**: The name is the first thing a user meets; every screen has to carry it the same way.

**Independent Test**: Build the app, open every screen and trigger each notification and update state in a test build.

**Acceptance Scenarios**:

1. **Given** a fresh build, **When** the user opens the dropdown, every Settings tab and the About tab, **Then** each names the app AgentTacho.
2. **Given** a fresh build, **When** a threshold notification, a credential notification and each update state appear, **Then** their texts say AgentTacho.
3. **Given** a fresh build, **When** the user opens the repository, new issue, security statement and release page links, **Then** each URL names `AgentTacho/agenttacho`, and the sponsor link is `https://github.com/sponsors/rhuss`.
4. **Given** the DMG of a release, **When** it is opened, **Then** its file name, volume name, background and app are named AgentTacho.

---

### User Story 2 - A release publishes AgentTacho (Priority: P1)

The maintainer runs `make release` for 0.5.0. It builds AgentTacho, creates `AgentTacho-0.5.0.dmg`, publishes the GitHub release "AgentTacho 0.5.0" in `AgentTacho/agenttacho` with the DMG, its checksum file and `release-info.json`, starts the site deploy, and writes the cask `agenttacho` to the tap.

**Why this priority**: Nothing reaches users without a release; the release tooling must produce the names end to end.

**Independent Test**: Run the release script tests with stubbed `gh` and tap repository; check the DMG name, the release title, `release-info.json`, the cask and the order of steps.

**Acceptance Scenarios**:

1. **Given** the tag `v0.5.0` on the official repository, **When** `make release` runs, **Then** the GitHub release in `AgentTacho/agenttacho` is titled "AgentTacho 0.5.0" and has the assets `AgentTacho-0.5.0.dmg`, `AgentTacho-0.5.0.dmg.sha256` and `release-info.json` naming that DMG.
2. **Given** that release, **When** the tap is updated, **Then** `AgentTacho/homebrew-tap` has a cask `agenttacho` that downloads from `https://github.com/AgentTacho/agenttacho/releases/download/v0.5.0/AgentTacho-0.5.0.dmg`, and no other cask in the tap is touched.
3. **Given** the cask is published, **When** a user runs `brew install --cask agenttacho/tap/agenttacho`, **Then** Homebrew installs `AgentTacho.app`.
4. **Given** a release marked latest, **When** `make release` has published it, **Then** it starts `deploy.yml` in the site repository once, before the cask update, and says so.
5. **Given** starting the site deploy fails, **When** `make release` reaches that step, **Then** it prints a warning with the command to start it by hand, still updates the cask, and its exit status does not change because of that failure.

---

### User Story 3 - The repository and its docs carry the name (Priority: P2)

A visitor arrives at `github.com/AgentTacho/agenttacho`. The README introduces AgentTacho, and its "Security and privacy" section names the data folders and the update request. AGENTS.md and the contribution notes say AgentTacho.

**Why this priority**: Docs are the first thing a visitor reads, but they can follow the code by a few hours without harm.

**Independent Test**: Read the README and AGENTS.md; open the repository page.

**Acceptance Scenarios**:

1. **Given** the README and AGENTS.md, **When** a reader looks for the app's name, **Then** both call it AgentTacho throughout.
2. **Given** the README's "Security and privacy" section, **When** it describes the update check and the files AgentTacho writes, **Then** it names `https://api.github.com/repos/AgentTacho/agenttacho/releases/latest` and the data folders.
3. **Given** the repository settings, **When** a visitor opens the repository, **Then** its homepage field names `https://agenttacho.github.io`.

---

### Edge Cases

- **Notification permission and launch at login**: macOS keeps both per bundle identifier, so AgentTacho asks for notification permission on its first launch, and launch at login is off until the user turns it on in Settings > General.
- **Credentials**: AgentTacho reads the agents' credentials through the `security` tool for the Claude keychain item (spec 006), so the bundle identifier plays no part in keychain approval.
- **Development builds and update-test builds**: `make app` and `make app-update-test` produce `AgentTacho.app`; the update-test source parsing (spec 013 FR-025) reads the Info.plist key `AgentTachoUpdateSource`.
- **A release without the notarization profile**: a Developer ID release stops before building and names the command that stores the profile (FR-015), so a release is never shipped un-notarized by accident.

## Requirements *(mandatory)*

### Functional Requirements

**Name and identity**

- **FR-001**: The app's display name, bundle name and executable MUST be AgentTacho, and the app bundle MUST be `AgentTacho.app`.
- **FR-002**: Every user-facing text (menu bar accessibility name, dropdown, Settings, About, notifications, update states and block reasons, alerts, the Homebrew command shown in the update line) MUST say AgentTacho. The update request's `User-Agent` MUST be `AgentTacho/<version>`.
- **FR-003**: The bundle identifier MUST be `dev.rhuss.agenttacho`. Names derived from it (the temporary update folder, the cask's `uninstall quit` and `zap` entries, notification and defaults identifiers) MUST use it.
- **FR-004**: The app's own Info.plist keys (version display, commit, build date, release tag, signing, notarized, update source) MUST carry the `AgentTacho` prefix, read and written consistently by the build scripts and the app.
- **FR-005**: The app's links MUST name `https://github.com/AgentTacho/agenttacho` (repository, new issue, latest release page, security statement with `#security-and-privacy`). The sponsor link MUST be `https://github.com/sponsors/rhuss`.
- **FR-006**: Image assets, asset catalog names and icon master file names MUST carry the name AgentTacho; the images themselves (mascot, app icon, menu bar glyphs) stay as they are.

**Data folders**

- **FR-007**: AgentTacho MUST keep its configuration (`config.json`), imported prices (`imported-prices.json`), log (`usage.log`) and last good values (`last-good.json`) in the data folders: `~/.config/agenttacho/` for the configuration and imported prices, `~/Library/Logs/agenttacho/` for the log, `~/Library/Application Support/agenttacho/` for the last good values.

**Release and distribution**

- **FR-013**: The release MUST produce `AgentTacho-<version>.dmg` with the volume name AgentTacho and DMG backgrounds that show `AgentTacho.app`; `release-info.json` MUST name that DMG, and the app's update check MUST expect that name.
- **FR-014**: The GitHub release title and release notes MUST say AgentTacho; the install command in the release notes and README MUST be `brew install --cask agenttacho/tap/agenttacho`.
- **FR-015**: The release scripts' default app repository MUST be `AgentTacho/agenttacho`; the tap MUST be `AgentTacho/homebrew-tap`. Both stay overridable for testing. The default notarization keychain profile MUST be `agenttacho-notary`; the README's release section says how to store it once. A release (not a dry run) with a Developer ID certificate MUST stop before building when the profile is missing, naming the command that stores it, unless `ALLOW_UNNOTARIZED=1` is set (added in code review).
- **FR-016**: The tap update MUST write the cask `agenttacho` in `AgentTacho/homebrew-tap` (download URL under `AgentTacho/agenttacho`, homepage `https://github.com/AgentTacho/agenttacho`, app `AgentTacho.app`, uninstall and zap entries for the bundle identifier and the data folders). It MUST NOT add, change or remove any other cask or file in the tap.
- **FR-017**: The app MUST recognise a Homebrew install by the cask `agenttacho` and `AgentTacho.app`, and show `brew upgrade --cask agenttacho`.
- **FR-018**: Right after publishing a release marked latest, and before the cask update, `make release` MUST start `deploy.yml` in `AgentTacho/agenttacho.github.io` once and report it. It MUST NOT start it for a release that is not the latest or when the app repository is overridden for testing. If starting it fails, `make release` MUST print a warning naming the command to start it by hand, MUST still update the cask, and MUST NOT change its exit status because of that failure.

**Repository**

- **FR-020**: The repository MUST be `AgentTacho/agenttacho`, with the homepage `https://agenttacho.github.io`. The local clone's `origin` is `git@github.com:AgentTacho/agenttacho.git`.

**Docs**

- **FR-023**: README and AGENTS.md MUST say AgentTacho, with download and Homebrew lines for `AgentTacho-<version>.dmg`, `brew install --cask agenttacho/tap/agenttacho` and `brew upgrade --cask agenttacho`.
- **FR-024**: The README's "Security and privacy" section MUST name the data folders and the update request URL `https://api.github.com/repos/AgentTacho/agenttacho/releases/latest`, in the same change as the code.
- **FR-025**: Doc comments, log texts and script output that name the app MUST say AgentTacho. References to other specs keep their numbers. `.github/FUNDING.yml` stays `github: rhuss`.

**After the merge (release steps)**

These requirements can only be met by a release tagged on `main`, so they are checked when that release is made (tasks T043 and T044, quickstart Q3 to Q5), not by the verification before the merge.

- **FR-019**: The first release under the name AgentTacho MUST be 0.5.0.

### Key Entities

- **Data folders**: AgentTacho's configuration, log and Application Support folders, all named `agenttacho`.
- **Official repository**: `AgentTacho/agenttacho`; source of update checks, target of releases and app links.
- **Cask**: `agenttacho` in `AgentTacho/homebrew-tap`.
- **Site repository**: `AgentTacho/agenttacho.github.io`, whose deploy `make release` starts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every screen, notification, alert and link of a fresh build names AgentTacho or `AgentTacho/agenttacho` (apart from the sponsor link).
- **SC-006**: All tests pass (`make test`, `make test-release`), and no release fails because of the site deploy trigger.

After the merge (checked with the 0.5.0 release, tasks T043 and T044, not by the verification before the merge):

- **SC-004**: The 0.5.0 release in `AgentTacho/agenttacho` has exactly the three assets named in User Story 2, and `brew install --cask agenttacho/tap/agenttacho` installs it as `/Applications/AgentTacho.app`.
- **SC-005**: An installed AgentTacho 0.5.0 asks `AgentTacho/agenttacho` for the latest release and reports that it is up to date.

## Assumptions

- The maintainer owns the `AgentTacho` organization, which holds `agenttacho` and `agenttacho.github.io`; the `gh` token can create releases in it and start workflows in the site repository.
- The images are reused as they are (brainstorm 22); the README screenshots are replaced later by the demo screenshots (landing plan, stream B).
- The site, the maintainer's local folders, the domain and a trademark search are outside this spec (brainstorm 22).
- This change lands after `021-recover-stuck-offline`, which touches many of the same files.
- The maintainer stores the notarization credentials once under the profile name `agenttacho-notary` before releasing 0.5.0.
