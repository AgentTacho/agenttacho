# Feature Specification: Section Bands

**Feature Branch**: `028-section-bands`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "Section bands (from brainstorm/27-section-bands.md). The dropdown draws a divider between every pair of sections and one above the pinned footer; with several accounts and groups it reads as a stack of horizontal lines. Replace them with full-width zebra bands: sections alternate plain and very faintly tinted, starting plain, Unassigned continues the alternation, a group with its members is one section. The pinned footer always gets its own band, a touch stronger than the zebra tint. The row hover highlight of spec 027 stays visible on a tinted band. The error lines at the top get no band. The stripe of each section is decided by tested logic. Every dropdown screenshot changes."

Spec 025 FR-011 puts a **divider** between each pair of consecutive sections and one before the footer; spec 026 FR-010 keeps that last one above the **pinned footer**. With three accounts and a budget group the dropdown shows four lines, and every expanded Details adds more structure between them. The lines compete with the bars, which are the content.

In this spec a **section** is what the dropdown shows for one arranged entry (an account or a group with its members, spec 008 FR-003) or for Unassigned. A **band** is the background area behind one section or behind the footer. A **stripe** is a section's band style: **plain** (the panel background, no tint) or **tinted**. The **panel** is the dropdown's always-dark, opaque background (spec 025, `DropdownView`).

## Clarifications

### Session 2026-10-19

- Q: How do band edges look: hard edges, rounded corners or a soft fade? → A: Hard, straight edges with no rounded corners, gradient, shadow or line; a band is a flat fill.
- Q: Do the bands change what VoiceOver reads? → A: No. The bands are purely visual; the accessibility elements, their labels and the reading order stay as they are.
- Q: Do the bars' empty tracks and other translucent fills keep their colors on a tinted band? → A: Yes. The bar track, the pace marker and the hover highlight keep their colors and stay visible on a tinted band; only the band behind them changes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sections apart without lines (Priority: P1)

A user with a Claude subscription, a Codex plan and a budget group opens the dropdown. There are no horizontal lines. The Claude section sits on the plain panel, the Codex section on a band that is just a shade lighter and runs from the panel's left edge to its right edge, and the budget group on the plain panel again. Where one section ends and the next begins is clear at a glance, without a line.

**Why this priority**: This is the whole feature: the same separation with less visual noise.

**Independent Test**: Open the demo dropdown with at least three sections; check there is no divider anywhere, the second section has a full-width tinted band, the first and third have none, and each section's text has room above and below inside its band.

**Acceptance Scenarios**:

1. **Given** two or more sections, **When** the dropdown opens, **Then** no divider is shown between sections.
2. **Given** sections in arrangement order, **When** the dropdown opens, **Then** the first section is plain, the second tinted, the third plain, and so on.
3. **Given** a tinted section, **When** the dropdown opens, **Then** its band spans the full panel width (no inset from the left or right edge) and reaches from the end of the previous band to the start of the next, with no gap and no overlap.
4. **Given** any section, **When** the user reads it, **Then** its first and last lines keep a vertical distance from the band's edges, so no text or bar touches a band edge.
5. **Given** a group with members, **When** the dropdown opens, **Then** the group's header, bar, member lines and Details share one band.
6. **Given** Unassigned usage, **When** the dropdown opens, **Then** Unassigned is the last section and takes the next stripe after the last arranged entry.
7. **Given** a single section, **When** the dropdown opens, **Then** it is plain and the footer band follows it.

---

### User Story 2 - A footer that stands apart (Priority: P1)

The footer (source errors, the update line, the status row with the refresh, Settings and Quit icons) sits on its own band, a little lighter than the tinted sections, from the panel's left edge to its right edge and down to the panel's bottom edge. It stays apart from the last section whether that section is plain or tinted, and when the sections scroll under the height cap (spec 026 FR-010) the scrolling content ends where the footer band begins.

**Why this priority**: The divider above the footer goes too; without its own band the footer would merge into a last section with the same stripe.

**Independent Test**: Open the dropdown once with an odd and once with an even number of sections; check the footer band is distinct from the last section in both cases and there is no line above it. Expand Details until the sections scroll and check the footer band stays put.

**Acceptance Scenarios**:

1. **Given** the dropdown is open, **When** the user looks at the footer, **Then** it has its own band, stronger than a tinted section's, spanning the full width down to the panel's bottom edge, with no divider above it.
2. **Given** the last section is tinted, **When** the dropdown opens, **Then** the footer band is still visibly different from it.
3. **Given** content taller than the height cap, **When** the user scrolls the sections, **Then** the footer band stays pinned and the sections' bands scroll above it.
4. **Given** source errors or an update line, **When** the footer shows them, **Then** they sit inside the footer band above the status row (spec 026 FR-011, FR-014).

---

### User Story 3 - Hover and markers still read on a band (Priority: P2)

On a tinted Claude section the user hovers the 5-hour row. The row's hover highlight and the ○ marker of spec 027 show as clearly as on a plain section.

**Why this priority**: The row switch of spec 027 relies on the hover highlight as its only affordance; a band must not swallow it.

**Independent Test**: Put a subscription on the second (tinted) position, hover a non-headline row, and compare the highlight with the same row on a plain section.

**Acceptance Scenarios**:

1. **Given** a subscription section on a tinted band, **When** the user hovers a non-headline window row, **Then** the row's hover highlight is visible against the band.
2. **Given** a window row on a tinted band, **When** the user reads its bar, **Then** the bar's empty track and pace marker are visible as on a plain section.
3. **Given** an expanded Details with its view picker and tables on a tinted band, **When** the user reads it, **Then** the picker, tables and day row read as on a plain section.

---

### Edge Cases

- No accounts configured: the "No accounts configured" text is not a section and gets no band; the footer band shows as usual.
- A configuration error or demo scenario error line at the top: it is not a section, sits on the plain panel above the first section, and does not shift the alternation (the first section stays plain).
- An entry hidden from the menu bar (spec 008) is still a section in the dropdown and takes its stripe like any other.
- A group with no members or one member (spec 009, spec 025 FR-010) is one section.
- Unassigned with an empty breakdown is not shown and takes no stripe; the footer band follows the last arranged entry.
- Adding, removing or reordering accounts or groups while the dropdown is closed: the stripes follow the new arrangement order the next time it opens, always starting plain.
- An expanded Details makes its section taller; its band grows with it and the following stripes do not change.
- The height cap with a short screen (spec 026 FR-010a): only the sections area scrolls; a section partly scrolled under the footer is cut at the footer band's top edge.
- "Increase contrast" turned on in the system's accessibility settings: the tinted and footer bands are drawn stronger so the boundaries stay visible (FR-006).
- The screenshot crops of single sections (`plan-limits`, `pace`, `budget`, `groups`, `details`, `harnesses`) show the band of the cropped section, plain or tinted depending on its position in the demo scenario.

## Requirements *(mandatory)*

### Functional Requirements

**Bands**

- **FR-001**: The dropdown MUST NOT show a divider between sections or above the pinned footer; this replaces spec 025 FR-011 and the footer divider kept by spec 026 (Assumptions, FR-010).
- **FR-002**: Sections MUST alternate stripes in arrangement order (spec 008 FR-003), the first section plain, the second tinted, and so on; Unassigned, when shown, MUST be the last section and take the next stripe. A group with its members, its member lines and its Details MUST be one section with one stripe.
- **FR-003**: Which stripe each section gets MUST be decided by tested UsageCore logic (constitution II) from the number of arranged entries and whether Unassigned is shown (the dropdown passes that flag; the rule for showing Unassigned is unchanged). The configuration error, demo scenario error and "No accounts configured" lines MUST NOT count as sections.
- **FR-004**: Every band MUST span the full panel width, edge to edge. Consecutive bands MUST meet without gap or overlap. Each section's content MUST keep the same horizontal inset as today and a vertical padding inside its band, top and bottom, so text and bars never touch a band edge. The footer's content MUST have a top padding inside the footer band like a section's, and keep its bottom inset (12 pt) to the panel's edge.
- **FR-004a**: A band MUST be a flat fill with hard, straight edges: no rounded corners, gradient, shadow or line at its edge.
- **FR-005**: The tints MUST be derived from the panel's foreground color at low opacity, not from fixed RGB values, so they stay correct if the panel's appearance changes. The strengths MUST be ordered plain (none) < tinted < footer in both contrast modes, and each of tinted and footer MUST be stronger with "Increase contrast" than without, both checked by a unit test; whether the tinted band reads as visibly different yet subtle is judged in the walkthrough on the recaptured shots (SC-002), starting from the strengths in Assumptions.
- **FR-006**: When the system's "Increase contrast" setting is on, the tinted and footer bands MUST be drawn at a higher strength, keeping the footer stronger than the tinted band.

**Footer**

- **FR-007**: The pinned footer (spec 026 FR-010) MUST have its own band in every state, whatever the last section's stripe, from the bottom of the sections area to the panel's bottom edge, across the full width. Its content (spec 026 FR-011 to FR-014) keeps its order and inset.
- **FR-008**: When the sections scroll (spec 026 FR-010, FR-010a), the section bands MUST scroll with their sections, and the footer band MUST stay pinned below them.

**Hover**

- **FR-009**: The row hover highlight and the ○ marker of spec 027 (FR-002) MUST stay visible on a tinted band: the hover highlight MUST be drawn on top of the band, so a hovered row always differs from its band by the highlight's own strength, in both contrast modes. The bar track, the pace marker and the hover highlight MUST keep their colors (spec 025 FR-002 to FR-005).
- **FR-009a**: The bands MUST NOT change the dropdown's accessibility elements, their labels or the reading order.

**Specs, docs and screenshots**

- **FR-010**: Earlier specs MUST be amended where they describe the dividers: spec 025's User Story 6 text and Independent Test, its acceptance scenario 1 ("N-1 dividers ... one divider before the footer"), FR-011, FR-023 ("Below the last section and its divider"), the Unassigned edge case ("gets dividers") and the "Dividers" section of `specs/025-minimal-dropdown/contracts/dropdown-ui.md`; spec 026's Assumptions ("The pinned footer's divider above it stays").
- **FR-011**: `docs/accounts-and-budgets.md` ("separated by dividers") MUST describe the sections as set apart by alternating background bands and the footer by its own band.
- **FR-012**: The demo `default` scenario MUST keep at least three sections (today four arranged entries: Max, Codex, the Company budget group with two of the five accounts as members, and Side), so a shot of the full dropdown shows plain, tinted and plain bands and the footer band. The demo coverage test MUST check its stripe sequence: plain, tinted, plain, tinted for the four entries, then Unassigned plain if the scenario shows it. When the last section is tinted, the `dropdown` shot also covers User Story 2, scenario 2.
- **FR-012a**: No website copy changes: the site's data files do not mention dividers. Only the shots of FR-013 change.
- **FR-013**: Every screenshot cropped from the dropdown (`plan-limits`, `pace`, `budget`, `groups`, `details`, `harnesses`, `dropdown`) MUST be recaptured from the demo build with `scripts/screenshots/capture.sh` and reviewed in both appearances, and the README dropdown image MUST be replaced, before the release that ships this feature (constitution V). The capture run needs the maintainer's go (AGENTS.md, step 4).

### Key Entities

- **Section stripe**: for one shown section, plain or tinted, decided by its position in the dropdown's list of sections.
- **Band style**: the three background strengths the dropdown uses: plain (no tint), tinted (section), and footer; each has a normal and an increased-contrast strength.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A dropdown with N sections shows 0 horizontal divider lines instead of N (N minus 1 between sections plus 1 above the footer).
- **SC-002**: In the demo `default` scenario a viewer can tell where each section ends and the footer begins without hovering (walkthrough, in the recaptured `dropdown` shot).
- **SC-003**: The dropdown is not taller than before for the same content: the vertical space between two sections' content, and between the last section's content and the footer's, is at most what a divider with its spacing took (21 pt).
- **SC-004**: The stripe rule is covered by automated tests, including Unassigned shown and hidden, one section, and the demo `default` scenario.
- **SC-005**: All existing automated tests pass.

## Assumptions

- The panel stays always dark and opaque (spec 025); the bands sit on top of its background color.
- Starting strengths: tinted band about 4% of the foreground color over the panel, footer band about 7%; with "Increase contrast" about 8% and 12%. The hover highlight stays `Color.primary` at 6%, as implemented for spec 027 FR-002, drawn on top of the band. The plan may adjust the values after looking at the demo build, as long as FR-005, FR-006 and FR-009 hold.
- The vertical padding inside a band is about 10 pt top and bottom, so two sections' content keeps about the distance it has today (10 pt spacing, a 1 pt divider, 10 pt spacing).
- The first section's band starts below the panel's top inset as today; the first section is plain, so the top inset shows the same background.
- The Settings window's dividers are out of scope.
- No configuration change, no new setting.
