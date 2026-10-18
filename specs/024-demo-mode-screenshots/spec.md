# Feature Specification: Demo build and screenshot capture

**Feature Branch**: `024-demo-mode-screenshots`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "Stream B in docs/superpowers/plans/2026-10-16-landing-site.md." The brief there: a dev-only demo build for marketing screenshots (brainstorm 18, section "2. Demo mode"). `make app-demo` builds "AgentTacho Demo" with its own bundle identifier and a compile-time flag; the demo build registers one demo source instead of the five real sources, reads JSON scenario files with timed frames and an observation history (refined during planning: no injected history, see FR-010), uses its own home for config, last-good values and log, and makes no keychain read and no network request. Scenarios cover the shot list in the brainstorm. A capture script in `scripts/screenshots/` quits the real AgentTacho, launches the demo app in English, opens the dropdown, the pace tooltip and the Settings tabs, waits for the notification, and captures light and dark WebP at 2x into a target directory, restoring the system appearance afterwards.

The landing page (`AgentTacho/agenttacho.github.io`) needs screenshots that show every current feature with made-up data: colored levels, the pace meter, the `↗` and `↑` markers, budgets, a shared budget group, alerts. The current screenshot shows the maintainer's real usage, real account names and German number formats, so it cannot be used. This spec adds a separate demo build of AgentTacho that shows a scripted story instead of real data, and a script that drives it and writes the eleven screenshots the site expects, each in a light and a dark variant.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the demo story in a separate demo app (Priority: P1)

The maintainer runs `make app-demo` and opens "AgentTacho Demo". The menu bar shows the demo story: a Claude Max subscription, a ChatGPT Plus subscription for Codex, and a shared monthly "Company budget" with a building icon that holds a Vertex account and an OpenAI API account. The dropdown, the details table and every Settings tab show the same made-up accounts, groups, budgets and prices. Nothing in the demo app comes from the maintainer's agents, keychain or network, and the installed AgentTacho keeps its own settings, values and log untouched.

**Why this priority**: Every screenshot depends on it. A demo app on its own already lets the maintainer take screenshots by hand.

**Independent Test**: Build the demo app on a Mac where AgentTacho is installed and configured, open it, and compare: the demo app shows only the scenario's accounts; the installed app's configuration, last good values, log and preferences are unchanged; the demo app's log shows no request and no credential read.

**Acceptance Scenarios**:

1. **Given** a checkout of the repository, **When** the maintainer runs `make app-demo`, **Then** an app named "AgentTacho Demo" with its own bundle identifier is built next to the regular dev build, and `make app` keeps building the regular app without demo code.
2. **Given** the demo app is open, **When** the maintainer looks at the menu bar and the dropdown, **Then** they see the demo story with normal, orange and red entries, three pace states (on pace, behind, ahead), one entry with `↗`, one with `↑`, and a budget near or over its limit.
3. **Given** the installed AgentTacho is configured with real accounts, **When** the demo app runs and quits, **Then** the installed app's configuration file, imported prices, last good values, log and preferences are byte for byte the same as before.
4. **Given** the demo app is running, **When** it refreshes, opens Settings, or the maintainer chooses "Check for Updates…" or "Import from LiteLLM", **Then** it makes no network request and reads no keychain item, credential file or agent data folder.

---

### User Story 2 - A scripted change fires a real alert (Priority: P2)

A few seconds after launch, the demo story moves on: one plan window crosses its alert threshold and a real macOS notification appears, so the "Alerts and colors" card can show the actual banner. The pace meters and the burn-rate markers come from the app's own logic applied to the scenario's values, so they look exactly as they would with real use.

**Why this priority**: The alert banner and the pace markers are two of the nine feature cards, and both need values that change over time. Without timed frames and carefully chosen values they cannot be shown honestly.

**Independent Test**: Launch the demo app with the default scenario and wait; the notification arrives within the time the scenario states, and the pace tooltip shows the projection that the scenario's values imply.

**Acceptance Scenarios**:

1. **Given** the default scenario and notification permission granted to the demo app, **When** the demo app has run for the scenario's crossing time, **Then** one threshold notification for the scripted entry appears, and no other notification appears.
2. **Given** the default scenario, **When** the dropdown opens, **Then** the pace meters and the `↗` and `↑` markers show the states the scenario was written to produce.
3. **Given** a scenario whose times are relative to launch, **When** it is launched on any day, **Then** reset times, the per-day trend and dates read as current (for example "resets in 2 h"), never as a fixed past date.

---

### User Story 3 - One command captures every screenshot (Priority: P3)

The maintainer runs the capture script with the site's image folder as the target. The script quits the real AgentTacho, builds and launches the demo app in English, opens the dropdown, hovers the pace meter, opens the Settings tabs, waits for the notification, and writes all eleven screenshots in light and dark, 22 WebP files at 2x. Afterwards the system appearance is what it was before, and the real AgentTacho runs again if it ran before.

**Why this priority**: It makes the screenshots reproducible: after any UI change the site can be refreshed with one command instead of an afternoon of manual cropping.

**Independent Test**: Run the script against an empty directory; it holds exactly the 22 expected files afterwards, the system appearance is unchanged, and running the script again produces the same set.

**Acceptance Scenarios**:

1. **Given** the needed permissions are granted, **When** the maintainer runs the script with a target directory, **Then** the directory holds `<stem>-light.webp` and `<stem>-dark.webp` for each of the eleven stems in FR-019, and the script lists them.
2. **Given** the system is in light appearance with German region settings, **When** the script finishes, **Then** every image shows English text and US number and date formats, and the system is back in light appearance.
3. **Given** the script fails or is interrupted halfway, **When** it stops, **Then** the system appearance is restored, the demo app is quit, and the target directory holds no partial set: either all files of the run or the files that were there before.
4. **Given** a permission the script needs is missing, **When** it starts, **Then** it names the permission and where to grant it, and stops before changing the appearance or quitting the real AgentTacho.

---

### User Story 4 - Release builds stay free of demo code (Priority: P4)

The maintainer can trust that nothing of the demo reaches users: release builds, DMGs and the Homebrew cask never contain the demo source, the scenarios or the demo identity, and the release script refuses to run with the demo flag set.

**Why this priority**: It keeps the README's "Security and privacy" section true without changes. It is small, but a mistake here would ship fake usage numbers to users.

**Independent Test**: Run the release script tests; a demo flag makes `make release` fail with a clear message, and a release-mode build contains no scenario files and no demo identity.

**Acceptance Scenarios**:

1. **Given** the demo flag is set in the environment, **When** the maintainer runs `make release` or `make dmg`, **Then** it stops with an error that release builds never carry the demo flag.
2. **Given** a regular `make app` build, **When** its bundle is inspected, **Then** it holds no scenario files and its bundle identifier is the regular one.

---

### Edge Cases

- The real AgentTacho is not running: the script skips quitting and restarting it.
- The real AgentTacho does not quit (for example a modal dialog is open): the script stops with a message and changes nothing.
- An earlier demo app is still running: the script quits it before launching a fresh one, so every run starts from the scenario's first frame.
- The scenario file is missing or invalid: the demo app shows the problem in the dropdown and the log and stays empty; it never falls back to the real sources.
- A frame's offset is already in the past when the app starts (slow launch): the frame applies at once.
- Notification permission for the demo app is missing or denied: the preflight check of FR-018 stops the run before anything changes. A Focus mode that hides the banner anyway: the script reports that the `alert` shot could not be taken and fails the run (no partial set).
- A frame applies while shots are being taken: cannot happen, because every capture starts after the scenario's last frame (FR-021).
- The main display is not a 2x (Retina) display: the script stops with a message instead of writing 1x images.
- The menu bar has no room for the demo item (too many items or a notch): the script reports that the menu bar item could not be found.
- The target directory already holds images from an earlier run: they are replaced only after the whole run succeeds.
- The system appearance switch fails: the script stops and restores whatever it changed.
- The maintainer presses Ctrl-C during a capture: same as a failure, appearance restored, demo app quit, target unchanged.

## Requirements *(mandatory)*

### Functional Requirements

**Demo build and identity**

- **FR-001**: `make app-demo` MUST build a separate app named "AgentTacho Demo" with the bundle identifier `dev.rhuss.agenttacho.demo`, compiled with a demo compile-time flag, in the same build folder as the regular dev build. It MUST use its own name and identifier for notification permission, preferences and the running-instance check, so the demo app and the installed AgentTacho can run side by side without seeing each other.
- **FR-002**: Only `make app-demo` MUST compile with the demo flag. `make app`, `make dmg`, `make release` and `make cask` MUST NOT, and `make release` MUST refuse to run when the demo flag is set in the environment, the same way it refuses the update-test flag today. The demo flag and the update-test flag MUST NOT be combined in one build.
- **FR-003**: Release builds MUST NOT contain the demo source, the scenario files or the demo identity. The scenario files are bundled into the demo app only.
- **FR-004**: The demo app MUST mark itself as the demo build in the About tab and in its log. The menu bar item, the dropdown and the other Settings tabs MUST NOT show a demo marker, so the screenshots look like the real app.

**Isolation from the maintainer's data**

- **FR-005**: The demo app MUST keep its configuration, imported prices, last good values and log under its own folders named `agenttacho-demo`, apart from AgentTacho's `agenttacho` folders. It MUST NOT read or write any file of the installed AgentTacho.
- **FR-006**: The demo app MUST register only demo sources in place of the five real sources: one each for Claude plan windows, Codex plan limits and usage records, all driven by the same scenario. It MUST NOT read the keychain, credential files, `~/.claude`, `~/.codex` or OpenCode's data.
- **FR-007**: The demo app MUST make no network request: no usage endpoint, no automatic or manual update check, no LiteLLM download. "Check for Updates…" reports that updates are off in the demo build. "Import from LiteLLM" opens its usual preview, filled from a made-up price list bundled with the scenarios.
- **FR-008**: The demo app MUST NOT register itself as a login item and MUST NOT send credential notifications.
- **FR-009**: Each launch MUST start from the scenario: the demo app writes the scenario's configuration and imported prices to its own folders on launch, replacing what an earlier demo run left there, and starts without saved last good values. Changes made in the demo Settings last only until the next launch.

**Scenarios**

- **FR-010**: Scenarios MUST be JSON files in the repository (one file per scenario). A scenario holds the configuration (accounts, groups with their icon, budgets, menu bar entries and their order), plan windows per subscription account (used percent, window length, reset time), token usage records (day, model, project, harness, account, tokens) for the details table and the budgets, and a list of timed frames. The app's observation log is never seeded: the values are chosen so the app's own pace and burn-rate logic produces the intended states from the current values alone.
- **FR-011**: All times in a scenario MUST be offsets relative to the demo app's launch (for example "resets in 2 h 10 min", "3 days ago"), so a scenario looks current on any day.
- **FR-012**: A frame MUST name an offset in seconds after launch and the plan window values it changes. The demo app MUST apply each frame within 2 seconds of its offset and refresh, so the threshold logic sees the change like a real refresh (the first observation stays the baseline).
- **FR-013**: The scenario MUST be chosen by a launch argument naming it; without the argument the demo app uses the scenario named `default`. A missing or invalid scenario MUST be reported in the dropdown and the log, with the parse error, and the app stays empty.
- **FR-014**: The `default` scenario MUST tell the demo story of brainstorm 18: a Claude Max subscription, a ChatGPT Plus subscription for Codex, and a monthly "Company budget" group with a neutral building icon holding a Vertex account and an OpenAI API account. Further accounts may be added where the bar needs more entries. Together its values MUST show: normal (uncolored), orange and red entries in the bar; one pace meter on pace, one behind, one ahead; one entry with `↗` and one with `↑`; a budget near or over its limit; model names in the details table that are all priced, by the built-in price table or by the scenario's imported prices, so every row is priced and no budget is marked incomplete; usage from Claude Code, Codex and OpenCode on the Harnesses tab; and one frame, at most 20 seconds after launch, that crosses an alert threshold.
- **FR-015**: Scenarios MUST use invented names only. They MUST NOT contain "Red Hat" (in any spelling), real email addresses or real organization names.
- **FR-016**: `make test` MUST load every bundled scenario and fail on a parse error. For the `default` scenario it MUST check the coverage of FR-014 through the same logic that computes levels, pace states, markers and threshold crossings in the app, and check FR-015.

**Capture script**

- **FR-017**: A capture script in `scripts/screenshots/` MUST take the target directory as its only required argument and create it if it does not exist. It MUST run `make app-demo` before capturing, so the screenshots always come from the current sources.
- **FR-018**: Before it changes anything, the script MUST check what it needs: the tools it uses, Accessibility and Screen Recording permission for the terminal, notification permission for the demo app with banners allowed (read from the alert style the demo app logs during a short launch before any change), the Light or Dark appearance setting (Auto cannot be restored), and a 2x main display. For each missing item it names the item and where to grant or install it, then stops. When the demo app has never asked for notification permission, the script offers a separate first-run step that launches the demo app so macOS shows its permission prompt; it never captures while that prompt can appear.
- **FR-019**: The script MUST write exactly these eleven stems, each as `<stem>-light.webp` and `<stem>-dark.webp` at 2x, 22 files in total:

  | Stem | Content |
  |---|---|
  | `menubar` | Menu bar item only, mixed levels, on a transparent background (drawn by the demo app from the same bar label view, so no wallpaper or other menu bar items show) |
  | `plan-limits` | Claude plan section with pace meters |
  | `pace` | Pace meter with its tooltip |
  | `budget` | Budget row near or over its limit |
  | `groups` | Settings > Groups with "Company budget" |
  | `details` | Details table (models) with the per-day trend |
  | `alert` | Notification banner |
  | `prices` | Settings > Prices with the Import menu open or an import preview |
  | `menubar-settings` | Settings > Menu Bar with the live bar preview |
  | `harnesses` | Details table on the Harnesses tab (Claude Code, Codex, OpenCode) |
  | `dropdown` | Full dropdown |

- **FR-020**: The script MUST quit a running AgentTacho before launching the demo app, and launch the demo app with English language and the `en_US` locale. At the end it MUST quit the demo app and start AgentTacho again if it was running before.
- **FR-021**: The script MUST capture each stem in light and in dark appearance by switching the system appearance, and MUST restore the original appearance at the end, after a failure and after an interrupt. It runs the scenario once per appearance: switch the appearance, launch the demo app fresh, wait until the last frame has applied, capture `alert` from that launch's notification, then capture the other stems, quit the demo app. So both variants of a stem show the same values, and each variant of `alert` shows its own banner.
- **FR-022**: The script MUST write into a temporary directory and move the files into the target only when all 22 exist and are valid WebP images. A failed run MUST leave the target directory as it was, and MUST name the stems it could not capture.
- **FR-023**: The script MUST print the written files with their pixel sizes at the end.

**Documentation**

- **FR-024**: The README's development section MUST describe `make app-demo`, the scenario files and the capture script, including the one-time permissions. The README's "Security and privacy" section MUST stay as it is, because release builds contain no demo code (FR-003).

### Key Entities

- **Scenario**: a named, made-up state of AgentTacho over the first minutes after launch. Holds a configuration, imported prices, plan windows, token usage records and frames; all times relative to launch.
- **Frame**: a change to plan window values at an offset after launch, used to make a threshold crossing happen while the app runs.
- **Shot**: one screenshot stem from FR-019, captured in light and dark.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After the one-time permissions, one run of the capture script produces all 22 files in under 5 minutes with no manual step.
- **SC-002**: The demo app makes no network request and no credential read. `make test` checks that the demo build's source setup creates no network-bound source and no credential reader, and that the app's demo branches name no update client, price download, credential reader or networking type. During one capture run, `nettop` shows zero connections for the demo app's process and `fs_usage` shows no access to the keychain, `~/.claude`, `~/.codex` or OpenCode's data.
- **SC-003**: After a demo run, the installed AgentTacho's configuration, imported prices, last good values, log and preferences are byte for byte unchanged (checksums before and after).
- **SC-004**: The system appearance after a run equals the one before in every case: success, failure and Ctrl-C.
- **SC-005**: The `default` scenario passes the coverage check of FR-016, and every bundled scenario loads.
- **SC-006**: A release build and its DMG contain no scenario file and no demo identity, and `make release` with the demo flag set fails; both covered by `make test-release`.
- **SC-007**: In a review of all 22 images, the maintainer finds no real name, no German number or date format and no clipped UI.

## Assumptions

- The capture runs on the maintainer's Apple Silicon Mac with a built-in Retina display, macOS 14 or later, and Focus modes off; the script does not support other setups.
- The maintainer grants Accessibility and Screen Recording permission to the terminal and notification permission to the demo app once, when asked.
- Crop sizes are not fixed: each shot is the window or region that holds its content, and the site shows it in a fixed image area. Stream C's Task 9 reviews the result.
- Scenario numbers are the builder's call, within the coverage of FR-014.
- The capture script uses tools available through Homebrew (for example for WebP encoding and UI scripting); FR-018 makes a missing one visible.
- More than one scenario is allowed but not required; the `default` scenario must cover the whole shot list.
- The site repository and its Task 9 (swapping in the screenshots, launch) are out of scope.
