# Feature Specification: Site Reframe Screenshots

**Feature Branch**: `031-site-reframe-screenshots`

**Created**: 2026-10-20

**Status**: Draft

**Input**: Brainstorm 30 (`brainstorm/30-site-reframe-screenshots.md`): phase 2 of the landing page reframe. The site moves from nine feature cards to six; the app's capture produces the two new card images ("Usage at a glance" and "Same provider, more than once") and stops producing the images the site no longer uses.

## Context

The landing page (`AgentTacho/agenttacho.github.io`) is being reframed from a feature catalogue to a focused positioning page (site design `docs/superpowers/specs/2026-10-20-messaging-reframe-design.md` in the site repository). Its new six-card grid needs two images that do not exist yet, and five of today's images (plus the full dropdown) are no longer referenced. The site ships its restructure first (phase 1) with placeholder images; this feature is phase 2 on the app side: the demo scenario, the capture script, its tests and the docs that describe the screenshot set.

Today's capture writes eleven stems in light and dark (22 files): `menubar plan-limits pace budget groups details alert prices menubar-settings harnesses dropdown`.

## Clarifications

### Session 2026-10-20

- Q: Where do the margin pixels around a new crop come from? → A: From the dropdown image itself: the crop rectangle grows by the margin on each side; no color is synthesized (the dropdown's material and section bands are not one flat color).
- Q: Does each new crop include the section header with the account's name? → A: Yes, both crops start at the top of the (first) Claude Max section, so the account name and plan are visible.
- Q: Does the second Claude Max account show a pace note? → A: No; it stays calm (on pace, below thresholds), so the two sections contrast.
- Q: How wide is the margin, given the dropdown leaves only a small inset beside each section? → A: The dropdown's own side inset (about 8 px at 2x), used on all four sides, at least 4 px and at most 4% of the shorter side; a fixed 2% minimum is not reachable horizontally without synthesized pixels.

## User Scenarios & Testing *(mandatory)*

The "users" of this feature are the maintainer, who runs the capture before a site update, and the landing page visitor, who sees the resulting images.

### User Story 1 - One image shows usage at a glance (Priority: P1)

A visitor looks at the "Usage at a glance" card and sees, in one image, a Claude Max subscription's plan limits, its pace and its usage details expanded, readable at card size. Today the same story needs three separate images (plan limits, pace, details).

**Why this priority**: It is card 1 of the new grid and replaces three images; the site's phase-1 placeholder (the full dropdown) is too tall to read at card size.

**Independent Test**: Run the capture against an empty target folder and open `glance-light.webp` and `glance-dark.webp`: each shows one Claude Max section with its plan windows, the pace note and the expanded details breakdown, and nothing else of the dropdown.

**Acceptance Scenarios**:

1. **Given** the demo build with the default scenario, **When** the maintainer runs the capture, **Then** the target folder contains `glance-light.webp` and `glance-dark.webp`.
2. **Given** a `glance` image, **When** it is viewed, **Then** it shows the first Claude Max account's plan windows (5-hour, 7-day and the model limit), the pace note on its 7-day row, and its details breakdown expanded (models view), in one contiguous region of the dropdown.
3. **Given** a `glance` image, **When** its borders are inspected, **Then** the content fills the image up to the margin rule of FR-012.

---

### User Story 2 - One image shows two accounts on the same provider (Priority: P1)

A visitor looks at the "Same provider, more than once" card and sees two Claude Max subscriptions as two separate sections of the dropdown, each with its own name, plan windows and levels, which makes clear that AgentTacho tracks several subscriptions of one provider side by side.

**Why this priority**: Card 3 has no existing image at all; its phase-1 placeholder shows something else.

**Independent Test**: Run the capture and open `same-provider-light.webp` and `same-provider-dark.webp`: each shows two Claude Max sections stacked, with different names and different usage levels.

**Acceptance Scenarios**:

1. **Given** the default demo scenario, **When** the demo build starts, **Then** it shows two Claude Max subscription accounts that read their credentials from two different directories.
2. **Given** the capture ran, **When** `same-provider` is viewed, **Then** it shows both Claude Max sections stacked in dropdown order, each with its display name and plan windows, and no other account's section.
3. **Given** the two sections, **When** they are compared, **Then** their names differ and their window levels differ visibly (at least 15 percentage points on each shown window).

---

### User Story 3 - The capture produces exactly the set the site uses (Priority: P2)

The maintainer runs the capture and gets exactly the images the reframed site references: seven stems in light and dark, 14 files. Stems the site dropped are no longer captured, and the capture no longer depends on setup only those stems needed.

**Why this priority**: Fewer shots make each capture faster and each review smaller; obsolete files would otherwise keep being regenerated and reviewed for nothing.

**Independent Test**: Run the release test suite: it asserts the seven stems and the 14-file count, and no test refers to a dropped stem.

**Acceptance Scenarios**:

1. **Given** the capture completes, **When** it prints its summary, **Then** it lists exactly the 14 files `menubar budget harnesses prices menubar-settings glance same-provider` in light and dark with their pixel sizes.
2. **Given** a target folder that still holds images of dropped stems from an earlier run, **When** the capture runs, **Then** those files are left untouched (the site repository removes them in its own pull request).
3. **Given** a Mac where AgentTacho Demo has no notification permission or its notifications are not set to banners, **When** the capture runs, **Then** it does not stop because of notifications.

---

### User Story 4 - Docs and tests describe the new set (Priority: P3)

A contributor reading `AGENTS.md` or `docs/website.md` finds the current stem list, file count and card count, so the instructions match what the capture does.

**Why this priority**: Stale counts mislead the next feature's screenshot step but do not break anything.

**Independent Test**: Check the stem lists and counts named in SC-004; none names a dropped stem or an old count.

**Acceptance Scenarios**:

1. **Given** the change is merged, **When** a contributor reads `AGENTS.md`, **Then** it states seven screenshots, six feature cards, a one-line feature strip, and 14 files per capture run.
2. **Given** the change is merged, **When** a contributor reads `docs/website.md`, **Then** its stem list and file count match the capture script.

### Edge Cases

- **Second account changes other shots.** The second Claude Max account appears in the bar and the dropdown, so `menubar` (and any dropdown crop such as `budget`) may change size or position. The capture must still find each crop region by its marker, never by a fixed offset.
- **Bar width.** A fifth bar entry makes the rendered bar wider. The `menubar` image must still render completely (no clipped entries).
- **Content taller than the aspect allows.** If a region's content cannot meet the aspect range of FR-012 within the margin limit, the capture fails for that stem with a message naming the stem and the measured aspect, instead of writing a letterboxed or cropped-through image.
- **Expanded details left open.** The `glance` capture expands the first Claude Max section's details and collapses them again (FR-010b); if collapsing fails, the capture fails for `glance` rather than letting `harnesses` press an ambiguous picker. Later steps must not depend on the dropdown's scroll position.
- **Notification prompt.** On a Mac where the demo never got notification permission, macOS may show its permission prompt during the run; the capture grabs single windows, so the prompt never appears in a shot.
- **Dropdown height cap.** With one more section the dropdown may hit its height cap and scroll. Each new crop must scroll its region fully into view before capturing, as the existing details crop does.
- **Second account without its own usage.** The second account must have its own plan data in the scenario; it must never show the first account's numbers or an error state.
- **Dark and light.** Both appearances use the same crop rules; a crop that meets FR-012 in one appearance but not the other fails the capture.

## Requirements *(mandatory)*

### Functional Requirements

**Demo scenario**

- **FR-001**: The default demo scenario MUST contain a second Claude Max subscription account, on the Claude Code harness, whose credential directory differs from the first account's (for example `~/.claude` and `~/.claude-personal`).
- **FR-002**: The two Claude Max accounts MUST have distinct display names that identify both as Claude Max and tell them apart by purpose (for example "Claude Max · Work" and "Claude Max · Personal").
- **FR-003**: At the scenario's last frame (when the capture runs), the second account MUST have its own plan data (5-hour and 7-day windows, plan "max") with levels that differ from the first account's by at least 15 percentage points on each window, and that stay below its lowest threshold and on pace (no pace note) so the section reads calm.
- **FR-004**: The second account MUST have a few usage records of its own, so its section shows real activity and its details breakdown is not empty.
- **FR-005**: The second account MUST be shown in the bar, placed directly after the first Claude Max account, and directly after it in the dropdown order.
- **FR-006**: The first Claude Max account MUST keep the states the existing shots rely on: its pace note on the 7-day row and its model limit row.
- **FR-007**: The demo coverage tests MUST check, at the scenario's last frame, the states the new shots rely on: two subscription accounts on the Claude Code harness with different credential directories and distinct names, both shown in the bar and adjacent in the dropdown order, each with its own plan data, and a non-empty details breakdown for the first one.

**Capture**

- **FR-008**: The capture MUST produce a new stem `glance`: the first Claude Max section of the dropdown with its plan windows, its pace note and its details breakdown expanded in the models view, as one image per appearance.
- **FR-009**: The capture MUST produce a new stem `same-provider`: the region of the dropdown that contains both Claude Max sections, stacked as the dropdown shows them, with the details collapsed, and no other account's section.
- **FR-010**: Each new crop MUST be located through markers the app exposes for screenshots (like the existing crops), and its region MUST be scrolled fully into view before capture.
- **FR-010a**: The app MUST expose these screenshot markers, each identifying exactly one element even with two Claude Max accounts: (a) the first Claude Max account's whole section including its header, (b) that section's details disclosure, and (c) one region spanning both Claude Max sections from the first header to the end of the second section. Markers that only the dropped stems used (the Claude plan container and the pace row) MUST be removed or restricted to the first Claude Max account. Markers have no visible effect: the real app looks and behaves the same.
- **FR-010b**: The capture MUST run the dropdown crops in this order: `same-provider` (all details collapsed), then `glance` (expand the first Claude Max section's details, select the models view, capture, collapse again), then `budget` and `harnesses` as today. Whenever the capture presses a view picker (Models, Harnesses), exactly one details section is expanded, so a picker title is never ambiguous.
- **FR-011**: The capture MUST stop producing the stems `plan-limits`, `pace`, `details`, `groups`, `alert` and `dropdown`. The stem set MUST be exactly `menubar budget harnesses prices menubar-settings glance same-provider`, 14 files per run.
- **FR-012**: For `glance` and `same-provider`, the image MUST consist of the cropped region plus a uniform margin taken from the surrounding dropdown pixels (the crop rectangle grows by the margin on each side; no color is synthesized), so that:
  - the margin is the same on all four sides: the smaller of the region's left and right distance to the dropdown window's edge, measured from the marker and window frames at capture time (about 8 px at 2x today), never less than 4 px and never more than 4% of the image's shorter side,
  - the aspect ratio (width : height) lies between 3:4 and 4:3,
  - the region's content is never cut.
  When the content alone violates the aspect range, or the dropdown image does not extend far enough to supply the margin, the stem fails as a capture failure (FR-015).
- **FR-012a**: Both new crops MUST include the section header of each Claude Max section they show, so the account name and plan are visible.
- **FR-013**: The capture MUST print the pixel size of every written file, as today, so the site can size its card image areas from the actual images.
- **FR-014**: The capture MUST NOT require any notification setup now that no shot shows a notification: the notification permission check, the notification style check (Notification Center, Banners) and the wait for a delivered banner are removed, and so is the `--first-run` mode, whose only purpose was the notification permission. The usage line and the release tests change with it.
- **FR-015**: A failure in a new stem MUST follow the existing failure contract: the capture names the stems it could not capture and leaves the target folder untouched.
- **FR-016**: The capture MUST NOT delete or overwrite files in the target folder other than the 14 files of the current stem set.

**Tests and docs**

- **FR-017**: The release test suite MUST cover the two new stems (their capture steps, scroll-into-view before capture, and the margin and aspect rule of FR-012 on a simulated region), assert the 14-file count, and contain no assertions about dropped stems.
- **FR-018**: `AGENTS.md` MUST describe the new set: seven screenshots, six feature cards, a one-line feature strip instead of the "small things", and 14 files per capture run; its examples MUST use the new counts.
- **FR-019**: `docs/website.md` MUST list the seven stems (citing this spec), state seven screenshots and 14 files per run, describe six feature cards and the one-line strip instead of nine cards and five small things (including the page test description), and drop the `--first-run` and Banners setup from its capture steps.
- **FR-020**: Only the demo build may be used for the new images; no image may come from a real AgentTacho with real accounts (constitution III, V).

### Key Entities

- **Stem**: a named screenshot the capture produces in light and dark (`<stem>-light.webp`, `<stem>-dark.webp`). The set of stems is the contract with the site.
- **Crop region**: the part of a captured window that one stem shows, found through a marker the app sets for screenshots.
- **Demo scenario**: the fixed set of accounts, plan data, usage records and timed frames the demo build plays; the only source of what the images show.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One capture run produces exactly 14 files, and each of `glance` and `same-provider` exists in light and dark.
- **SC-002**: In both new images, the four margins are equal, at least 4 px and at most 4% of the shorter side, and the aspect ratio lies between 3:4 and 4:3.
- **SC-003**: At the site's card width, a reviewer can read the account names and window percentages in both new images without zooming (checked in the AGENTS.md step 5 review, both appearances).
- **SC-004**: The release tests and the app tests pass (`make test-release`, `make test`), and outside `specs/` and `brainstorm/` no stem list (the `STEMS=` lines, `<stem>-light`/`<stem>-dark` file names, the stem list in `docs/website.md`, the plan template example in `AGENTS.md`) names a dropped stem, and no instruction states 22 files, eleven screenshots or nine cards.
- **SC-005**: The capture runs to completion on a Mac where AgentTacho Demo was never granted notification permission.

## Screenshots and website

| | |
|---|---|
| Shots that change | `menubar` (second Claude entry), possibly `budget` position only; the real app shows no visible change (only screenshot markers, FR-010a) |
| New shots | `glance`, `same-provider` |
| Dropped shots | `plan-limits`, `pace`, `details`, `groups`, `alert`, `dropdown` |
| Demo scenario | second Claude Max account with its own directory, names, plan data and usage (FR-001 to FR-007) |
| Website copy | none in this repository; the site's phase-2 pull request swaps its placeholders for the new pairs, removes the dropped pairs and updates `tests/page.test.ts` |

## Assumptions

- The site's phase-1 restructure (six cards, one-line strip, placeholders) is built in the site repository and is not part of this feature. Because the capture never deletes files from its target, the dropped pairs stay in the site checkout until the site's phase-2 pull request removes them, so neither repository has to merge first.
- The fill rule (FR-012) replaces the brainstorm's proposal of one fixed 16:10 aspect. Measured from today's images, the regions are portrait or square (plan section with expanded details about 5:6, two stacked plan sections about 1:1, both at the dropdown's fixed width), so a 16:10 frame would need far more than 4% padding. The app therefore fixes the margin and an aspect range, and the site sizes each card's image area from the printed pixel sizes.
- Running the capture is not part of the automated implementation: it quits AgentTacho, switches the appearance and moves the mouse, so it runs only with the maintainer's go-ahead (AGENTS.md step 4). The automated part ends with passing tests.
- The demo's timed notification frame stays in the scenario; it no longer feeds a shot, and the capture still waits for the last frame as today.
- Existing display names elsewhere in the scenario (ChatGPT Plus, Claude via Vertex, OpenAI API, Side project) are unchanged.
