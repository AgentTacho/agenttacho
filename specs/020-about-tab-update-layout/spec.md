# Feature Specification: About Tab Update Layout

**Feature Branch**: `020-about-tab-update-layout`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "About tab update layout (from brainstorm/20-about-tab-update-layout.md). Settings > About drops the 'Updates' heading and the Signing row, and shows a centered 'Check for Updates…' button with the update status below it in secondary text; an available update shows its actions on that line. 'Check for updates automatically' moves to a new 'Updates' section in Settings > General after 'Launch'. Spec 013 FR-002 and FR-011 are updated accordingly; update logic and the dropdown's update line stay unchanged."

This feature rearranges two Settings tabs. Settings > About shows the running build (version, commit, build date, signing), an update block (spec 013 FR-011) and the changes of this release. The **update block** today is a heading "Updates", the update status (for example "Up to date (checked 14:02)"), an optional second line for a known update kept after a failed manual check (spec 013 FR-007a), and a row with the "Check for Updates…" button next to the "Check for updates automatically" toggle. The **toggle** is a stored preference (`checksForUpdates`, spec 013 FR-002). The **signing row** shows the build's signing tier ("Developer ID, notarized", "self-signed", "ad-hoc"), stamped into the bundle at build time; the updater also reads that stamp to choose how an update is installed (spec 013 FR-012).

## Clarifications

### Session 2026-10-16

- Q: Should About's status line say so when automatic update checks are off? → A: No. The status keeps today's wording ("Not checked yet" before the first check); the toggle is one tab away in General and the manual check works regardless.
- Q: Should the status line use smaller text than the body or body-size text in a secondary color? → A: Body-size text in the secondary color, so error texts and the action links stay readable; the action links keep their link style.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A quieter About tab (Priority: P1)

A user opens Settings > About to see which version they run and whether it is current. Below the version, commit and build date they find one "Check for Updates…" button, centered, and directly under it a short status line in secondary text, such as "Up to date (checked 14:02)". There is no "Updates" heading, no toggle and no signing row. When an update is available, the status line names it and offers its actions (for example "AgentMeter 0.5.0 available  Install · Release notes"), so the user can install it from here as before.

**Why this priority**: This is the reason for the feature: the About tab carries less text while keeping everything a user needs to check for and install an update.

**Independent Test**: Open Settings > About in a release build, read the tab top to bottom, press "Check for Updates…" and watch the status line change; with a newer release published (or simulated), confirm the status line offers the install action and the release notes.

**Acceptance Scenarios**:

1. **Given** a release build, **When** Settings > About is shown, **Then** the release data lists Version, Commit and Built, and no Signing row.
2. **Given** Settings > About is shown, **When** the user looks at the update block, **Then** it consists of a centered "Check for Updates…" button followed by the status line below it, with no "Updates" heading and no "Check for updates automatically" toggle.
3. **Given** no check has run in this session, **When** Settings > About is shown, **Then** the status line reads "Not checked yet".
4. **Given** a successful check found no newer release at 14:02, **When** Settings > About is shown, **Then** the status line reads "Up to date (checked 14:02)".
5. **Given** a newer release is known, **When** Settings > About is shown, **Then** the status line names the release and shows the same actions as today (the install action for this installation, and "Release notes").
6. **Given** a newer release is known and a later manual check failed, **When** Settings > About is shown, **Then** the error shows on the status line and the known update stays on a second line below it with its actions, as today.
7. **Given** an update is downloading, verifying or installing, **When** Settings > About is shown, **Then** "Check for Updates…" is disabled and the status line shows the progress (with "Cancel" while downloading or verifying), as today.

---

### User Story 2 - The automatic check is a General setting (Priority: P1)

A user who wants AgentMeter to stop checking GitHub daily opens Settings > General, where all other preferences live, and finds an "Updates" section right after "Launch" with "Check for updates automatically". They switch it off and apply the change like every other setting; after a restart the setting is still off.

**Why this priority**: Without it, removing the toggle from About would leave the automatic check without a switch in the app.

**Independent Test**: Open Settings > General, find the "Updates" section after "Launch", switch the toggle off, apply, quit and relaunch, and confirm the toggle is still off and the configuration file has `checksForUpdates: false`.

**Acceptance Scenarios**:

1. **Given** Settings > General is shown, **When** the user scrolls through the sections, **Then** an "Updates" section with "Check for updates automatically" follows the "Launch" section.
2. **Given** the toggle is on, **When** the user switches it off, **Then** the change becomes part of the unsaved Settings changes and is applied or discarded with them, as every other General setting.
3. **Given** the user switched the toggle off and applied, **When** AgentMeter restarts, **Then** the toggle is still off and no automatic check runs.
4. **Given** the configuration file sets `checksForUpdates` to false by hand, **When** Settings > General is shown, **Then** the toggle is off.
5. **Given** automatic checks are off, **When** the user presses "Check for Updates…" in Settings > About or in the dropdown's gear menu, **Then** the check runs and reports its result as today.

---

### Edge Cases

- A development build (one that never checks, spec 013): the About tab shows the button and status line as the update block does today for such a build; only the heading, toggle and signing row are gone.
- A build without stamped release data (`swift run`): the About tab shows only the rows it has, as today; there is no Signing row in any case.
- A long error text on the status line wraps under the button and stays centered, as the status text does today; it is not truncated.
- Automatic checks are off: the status line keeps today's wording ("Not checked yet" before the first check) and adds no note about the setting.
- The Settings window at its smallest size: the About tab still fits or scrolls as today; the change removes content and adds none.
- The toggle in General and a hand edit of the configuration file disagree while Settings is open: the existing reload rules for the Settings draft apply, as for every other General setting.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Settings > About MUST NOT show an "Updates" heading.
- **FR-002**: Settings > About MUST NOT show the build's signing tier. The signing stamp MUST stay in the bundle and MUST still be used to choose the install action (spec 013 FR-012).
- **FR-003**: Settings > About MUST show the "Check for Updates…" button horizontally centered, below the release data, with the update status line directly below the button. The status line(s) MUST be centered and wrap without truncation.
- **FR-004**: The status line MUST use body-size text in the secondary color (its action links keep their link style) and the existing settings wording of every update state (for example "Not checked yet", "Checking for updates…", "Up to date (checked HH:MM)", "AgentMeter X.Y.Z available", "Development build: updates are not checked", progress and error texts) together with the state's actions (install action, "Try again", "Release notes", "Cancel", "Release page"), as Settings > About shows them today.
- **FR-005**: A known update kept next to a failed manual check (spec 013 FR-007a) MUST appear as a second status line below the first, with its actions.
- **FR-006**: "Check for Updates…" in Settings > About MUST stay disabled while an install runs, and its result MUST show in Settings only, as today (spec 013 FR-003).
- **FR-007**: Settings > About MUST NOT show the "Check for updates automatically" toggle.
- **FR-008**: Settings > General MUST show a section titled "Updates", placed directly after the "Launch" section, containing the toggle "Check for updates automatically".
- **FR-009**: The toggle in General MUST read and write the same stored setting as before (`checksForUpdates`, default on), through the Settings draft, so it is applied, discarded and persisted like every other General setting.
- **FR-010**: The dropdown's update line, the gear menu's "Check for Updates…", and all update logic (schedule, check, install) MUST stay unchanged.
- **FR-011**: Spec 013 MUST be updated wherever it places the toggle in Settings > About: FR-002 and FR-011, the user story narrative and acceptance scenario that switch the toggle (they point to Settings > General), and the "Settings > About" section of `contracts/update-ui.md` (toggle in General, no "Updates" heading, button above the status).
- **FR-012**: The README MUST describe the new places in every passage that mentions them: the update check paragraph in the usage section, the configuration reference for `checksForUpdates`, the Settings tab overview of About (no signing, no toggle) and General (the toggle), the update check bullet in "Security and privacy", and the release data paragraph, which MUST say the signing stamp is read by the updater rather than shown in About.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The About tab shows two fewer text rows than before (the "Updates" heading and the Signing row), and its update block holds one control (the button) instead of two.
- **SC-002**: The automatic update check can be switched off in Settings > General, in the "Updates" section directly after "Launch", without visiting About (checked in the walkthrough).
- **SC-003**: Every update state that Settings > About could show before (not checked, checking, up to date, available with each install action, downloading, verifying, installing, failed check, failed install, known update next to a failed check) still shows on the status line with the same text and actions.
- **SC-004**: All existing automated tests pass, and the stored `checksForUpdates` value round-trips through the General toggle (on, off, relaunch) with no change to the configuration format.

## Assumptions

- The "Updates" section in General holds only the toggle, without a caption, like the one-toggle "Launch" and "Notifications" sections.
- The order of the About tab otherwise stays: icon, name, tagline, release data, update block, "What's new", links, footer.
- The "About AgentMeter" entry in the dropdown's gear menu keeps opening the About tab.
- No change to the configuration file format or its default values.
