# Feature Specification: Dropdown Theme

**Feature Branch**: `032-dropdown-theme`

**Created**: 2026-10-21

**Status**: Draft

**Input**: Brainstorm `brainstorm/31-dropdown-theme.md`: "When switching to light mode, the dropdown is still dark. Change this, and add an option in the General settings to switch the theme (Auto / Dark / Light)."

## Background

The dropdown is always dark today. Spec 025 made it dark and opaque because the translucent panel it replaced made the orange and red status lines unreadable over a light desktop. Opacity was the fix that mattered; dark was a side choice. With the system in light appearance, the menu bar, Settings and every other app are light, and the dark dropdown looks out of place.

This feature lets the dropdown follow the system appearance by default and adds a setting for people who want a fixed dark or light dropdown.

## Clarifications

### Session 2026-10-21

- Q: Should a theme change in Settings reach a dropdown that is already open at once, or only at its next opening? → A: At once, like an Auto switch of the system appearance; the next opening is the latest moment.
- Q: Should the light panel use a fixed background color or the system's dynamic window background? → A: A fixed light color, like the dark panel's fixed color, so the contrast tests resolve against a known background.
- Q: What wins if a dark panel text color turns out to miss 4.5:1? → A: The contrast target (FR-007); that one color is adjusted, and FR-008's "unchanged" yields for it only.
- Q: Must the light panel's bar fills reach 3:1, given that system orange cannot on a light background? → A: No; level fills keep the system orange and red, because the percentage text and the note carry the same information (FR-010).
- Q: Against which background is text contrast measured? → A: The least favorable one a text can sit on: plain panel, band, or hover over a band (FR-007).
- Q: How is "band visible but not heavier" tested? → A: Same opacity factors on the light foreground; a test asserts the band differs from the panel and is no stronger than on the dark panel (FR-011).
- Q: Do link-styled buttons (update line, "Show account details") fall under the text contrast target? → A: Yes; they get a link color of their own in each panel, fixed where the system link color misses 4.5:1 (FR-007, code review 2026-10-21).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Dropdown follows the system appearance (Priority: P1)

A user works in light appearance. They open the dropdown and see a light panel that matches the menu bar and their other apps. When they switch the system to dark appearance, the next look at the dropdown shows the dark panel they know from earlier versions.

**Why this priority**: This is the reported problem. With only this story, every user in light appearance gets a matching dropdown without touching a setting.

**Independent Test**: With the setting at its default, open the dropdown in light appearance, then in dark appearance, and compare it with the system look.

**Acceptance Scenarios**:

1. **Given** the default setting and the system in light appearance, **When** the user opens the dropdown, **Then** the panel is light and opaque, and all text is readable.
2. **Given** the default setting and the system in dark appearance, **When** the user opens the dropdown, **Then** the panel looks as it did before this feature.
3. **Given** the default setting and the dropdown open, **When** the system switches between light and dark appearance, **Then** the panel follows within one second, without closing it.
4. **Given** the default setting, light appearance and an account with a warning (orange) and an error (red) line, **When** the user opens the dropdown, **Then** both lines are as readable on the light panel as they are on the dark one.
5. **Given** the default setting and an upgrade from a version with the always-dark dropdown, **When** the user opens the dropdown in light appearance, **Then** the panel is light (no migration keeps the old look).

---

### User Story 2 - Choose a fixed theme in Settings (Priority: P2)

A user likes the dark dropdown even though their system runs in light appearance. In Settings > General they set the dropdown theme to Dark, and the dropdown stays dark from then on, whatever the system does. Another user can pick Light the same way.

**Why this priority**: It keeps the old look available for those who want it, but the main problem is solved by story 1 alone.

**Independent Test**: Set the theme to Dark in light appearance and to Light in dark appearance, open the dropdown each time, and check it ignores the system appearance.

**Acceptance Scenarios**:

1. **Given** the system in light appearance, **When** the user picks Dark, **Then** the dropdown shows the dark panel at its next opening at the latest, and keeps it after the system switches appearance.
2. **Given** the system in dark appearance, **When** the user picks Light, **Then** the dropdown shows the light panel at its next opening at the latest, and keeps it after the system switches appearance.
3. **Given** Dark or Light is chosen, **When** the user picks Auto, **Then** the dropdown follows the system appearance again.
4. **Given** any theme, **When** the user quits and relaunches AgentTacho, **Then** the chosen theme is still in effect.
5. **Given** the dropdown open, **When** the user changes the theme in Settings, **Then** the dropdown switches to the chosen panel as soon as Settings applies the change, without closing (FR-004).
6. **Given** any theme, **When** the user looks at Settings, the menu bar item or the Settings bar preview, **Then** they look as before: Settings follows the system, the menu bar item follows the menu bar, and the preview keeps its dark capsule.

---

### User Story 3 - Hand-edited configuration (Priority: P3)

A user who edits the configuration file by hand can set the theme there. A value AgentTacho does not know falls back to Auto, and the user can see why.

**Why this priority**: The configuration file is a supported way to change settings, but few users take it.

**Independent Test**: Write each known value and one unknown value into the configuration file, reload, and check the dropdown and the diagnostic log.

**Acceptance Scenarios**:

1. **Given** a configuration without a theme entry, **When** AgentTacho loads it, **Then** the theme is Auto.
2. **Given** a configuration with an unknown theme value, **When** AgentTacho loads it, **Then** the theme is Auto and the load notes name the unknown value, as they do for other unknown values.
3. **Given** the theme left at or set back to Auto, **When** AgentTacho saves the configuration, **Then** the file carries no theme entry.

---

### Edge Cases

- **Increase Contrast** on: in both themes the panel keeps the system's higher-contrast variants of its text colors, and every text color still reaches the contrast target of FR-007.
- **Appearance switch while the dropdown is open** with Auto: the panel, the section bands, the bars and all text colors switch together; no line keeps the colors of the other theme.
- **Theme changed in Settings while the dropdown is open**: the dropdown switches as soon as Settings applies the change (FR-004).
- **Section bands (spec 028)** on the light panel: the band tint stays visible against the light background, and band edges stay invisible (no line).
- **Hover and selection fills** (spec 027 headline switch) stay visible on the light panel.
- **Footer, update line, error lines and "Last refreshed"** follow the theme like the sections do.
- **Long dropdown at the height cap**: the scroll area and the pinned footer show the same background; no dark strip remains in Light, and no light strip in Dark.
- **Demo app (screenshots)**: the demo build follows the same setting and default, so a capture in light appearance shows the light panel and a capture in dark appearance shows the dark one.

## Requirements *(mandatory)*

### Functional Requirements

**Theme setting**

- **FR-001**: The dropdown MUST have a theme setting with three values: Auto, Dark and Light. The default is Auto.
- **FR-002**: Settings > General MUST offer the theme as a segmented picker in the Display section, below "Show usage as" and in the same style, labeled "Dropdown theme" with the choices "Auto", "Dark" and "Light".
- **FR-003**: The theme MUST be stored in the configuration under the key `dropdownTheme`, with the values `auto`, `dark` and `light`. With Auto, the configuration MUST carry no theme entry. A missing entry or the value `auto` MUST read as Auto without a note. An unknown, wrong-case or non-string (including null) value MUST read as Auto and add a load note naming the key and, when it is a string, the value, as the configuration does for `displayDirection` (spec 030 FR-008); it never makes the configuration invalid.
- **FR-004**: A theme change MUST take effect in the dropdown as soon as Settings applies it, also while the dropdown is open, and at its next opening at the latest, without a restart.
- **FR-005**: The theme MUST apply to the dropdown only. Settings, the menu bar item and the Settings bar preview MUST look as they do without this feature.

**Panel appearance**

- **FR-006**: With Auto, the dropdown MUST use the light panel while the system is in light appearance and the dark panel while it is in dark appearance, and MUST follow a system switch within one second, also while it is open. With Dark or Light, it MUST use that panel regardless of the system appearance.
- **FR-007**: The panel MUST be opaque in every theme. Every text color in the dropdown (primary, secondary, warning, error, and link-styled buttons such as "Install", "Release notes" and "Show account details") MUST reach a contrast ratio of at least 4.5:1 against the least favorable background it can sit on (the plain panel, a section band, or a hover fill over a band), in both panels, with and without Increase Contrast where it can be resolved.
- **FR-008**: The dark panel MUST stay as it is today: same background, same colors, same layout. Only a text color that misses FR-007 MAY change, and only as far as FR-007 needs.
- **FR-009**: The light panel MUST use a fixed light background color (not one that varies with system settings), MUST keep the dark panel's layout, sizes and section bands, and MUST differ from it only in colors. The warning and error text MUST keep their orange and red hues, in a darker shade where the system color misses FR-007. Any other text color of the light panel (for example the secondary color) that misses FR-007 MUST be darkened as far as FR-007 needs.
- **FR-010**: Level fills of the bars in the light panel MUST keep the system's orange and red, the same colors as the menu bar's levels. They are exempt from a non-text contrast target, because the percentage text and the orange or red note next to them carry the same information. Bar tracks, band tints and hover fills are governed by FR-011, not by this requirement.
- **FR-011**: The section bands, hover fills and selection fills on the light panel MUST use the same opacity factors as on the dark panel, applied to the light panel's own foreground color. A test MUST assert that a band differs from the plain panel (contrast ratio above 1.0) and is no stronger than the band on the dark panel.
- **FR-012**: Everything in the dropdown (sections, scroll area, pinned footer, error and update lines) MUST follow the same theme at the same time.

**Tests and screenshots**

- **FR-013**: Tests MUST resolve the real text colors under both panels and assert FR-007's ratio against each background FR-007 names, as spec 012 does for the menu bar pills.
- **FR-014**: The demo build MUST follow the same setting and default, so the capture script needs no change in how it switches appearances. The demo scenario's coverage test MUST check that the default scenario shows a warning line and an error line in the dropdown, since the light shots rely on them.
- **FR-015**: Every screenshot that shows the dropdown MUST be recaptured, so its light variant shows the light panel. The site copy MUST be checked for text that calls the dropdown dark, and changed where it does.

### Key Entities

- **Dropdown theme**: the user's choice for the dropdown's look. One of Auto, Dark, Light; Auto is the default and is not written to the configuration.
- **Panel style**: what a theme resolves to at a given moment (light or dark panel), derived from the theme and the current system appearance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the default setting, in light appearance, the dropdown opens with a light panel on 100% of openings; in dark appearance it is identical to the previous version's dropdown, apart from a text color FR-008 allows to change.
- **SC-002**: With the dropdown open and Auto chosen, a system appearance switch shows in the dropdown within one second (manual walkthrough check).
- **SC-003**: Every text color in both panels reaches at least 4.5:1 against its background, checked by tests that resolve the real colors.
- **SC-004**: A user can switch the theme in Settings in one step (one picker), and the dropdown shows the choice as soon as Settings applies it.
- **SC-005**: After a relaunch, the chosen theme is still in effect in 100% of cases.
- **SC-006**: The recaptured light screenshots show the light panel, the dark screenshots are unchanged apart from intended differences, and no shot shows a real account name or a non-US format.

## Assumptions

- The menu bar item's look is decided by the system and the menu bar; this feature does not change it.
- The Settings window keeps following the system appearance; a whole-app theme was considered and rejected in the brainstorm.
- The Settings bar preview keeps its fixed dark capsule (spec 008 FR-013), so it needs no theme.
- Increase Contrast colors that cannot be resolved in tests without changing the system setting are covered by the manual walkthrough, as in spec 012.
- Which stems show the dropdown is decided by the existing capture script (seven stems, spec 031); no new stem and no new landing page card are needed, since this is a change to existing UI.
- Settings applies its draft automatically after a short pause (existing behavior), so a theme change reaches the running dropdown without a save button.
