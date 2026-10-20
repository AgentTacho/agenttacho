# Feature Specification: Colored Bar Levels

**Feature Branch**: `012-colored-bar-levels`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Colored bar levels (from brainstorm/12-colored-bar-levels.md). Show the warning and over-limit levels of bar entries with color instead of the ⚠ and ‼ glyphs: a 'Level color' setting (Text, the default; Pill; Off) and a separate 'Also show ⚠ / ‼ symbols' checkbox, off by default. The bar keeps MenuBarExtra and is drawn as a full-color image that follows the menu bar's appearance."

This feature changes how the menu bar shows the levels defined in `specs/001-agenttacho/spec.md` FR-003. The level computation stays. In this spec, an entry is at the **warning level** when its percent is at or above its warning threshold (the lowest configured threshold, or 80%) and below the over-limit level; it is at the **over-limit level** when its percent is 100% or above, or when it is a Codex plan entry with a reached plan window limit (spec 007 FR-012), even if the shown percent is lower. Until now the levels were always shown as a `⚠` or `‼` prefix; after this feature they are shown by color, by symbols, by both, or, if the user chooses so, not at all in the bar (FR-012). Spec 001 FR-003's "MUST visually distinguish" therefore holds for every setting except the explicit opt-out of FR-012.

## Clarifications

### Session 2026-10-16

- Q: In the pill style, may the bar get wider when an entry reaches a level, or must width be reserved for the pill at all times? → A: The bar may grow by the pill's horizontal padding while an entry has a pill; no width is reserved when no entry has a level, so a bar without levels keeps today's width.
- Q: Does the bar's accessibility text (also used in log lines) still contain the `⚠` and `‼` glyphs when symbols are on? → A: No. It always names the level in words ("warning", "over limit") and never contains the glyphs, whatever the settings; the stale marker is kept as today.
- Q: What happens to an unknown level color value in the configuration file when the user next saves from Settings? → A: It is replaced by the value in effect (Text), like any other setting written back on save.
- Q (walkthrough): Is "Also show ⚠ / ‼ symbols" the right label, given that the symbols also work alone with Level color Off? → A: No; the checkbox is labeled "Mark levels with ⚠ / ‼".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Levels stand out at a glance (Priority: P1)

A user watches their Claude subscription and a Vertex budget in the menu bar. When the Vertex budget passes its warning threshold, its value turns orange; when it passes 100%, red. The user notices the change from the corner of their eye without reading the numbers, and the bar is no wider than before the level was reached.

**Why this priority**: This is the reason for the feature: today's small monochrome glyphs are easy to miss and widen the bar.

**Independent Test**: With default settings, push an entry over its warning threshold and over 100% (for example by lowering its budget), and check that only its value changes color, the entry's width stays the same, and the bar looks unchanged in light and dark menu bars when no entry has a level.

**Acceptance Scenarios**:

1. **Given** default settings and an entry at 85% with a warning threshold of 80%, **When** the bar is displayed, **Then** the entry's value is shown in orange, its icon in the menu bar's normal color, and no `⚠` is shown.
2. **Given** default settings and an entry at 104%, **When** the bar is displayed, **Then** the entry's value is shown in red and no `‼` is shown.
3. **Given** default settings and an entry at 42%, **When** the bar is displayed, **Then** the entry looks as it does in the previous version (without the glyph, which it did not have either).
4. **Given** default settings and an entry at a level, **When** the system switches between light and dark appearance, **Then** the bar's neutral parts follow the new appearance and the level color stays legible, without restarting AgentTacho.
5. **Given** a configuration file written by an earlier version (no level display settings), **When** AgentTacho starts, **Then** it uses colored text without symbols and the file loads without a problem notice.

---

### User Story 2 - Choose a pill instead of colored text (Priority: P2)

A user finds colored digits too subtle on their tinted menu bar. In Settings they switch "Level color" to Pill: an entry at a level now sits on a small rounded orange or red background, with its icon and value readable on top.

**Why this priority**: Colored text is the default and covers most users; the pill is the louder alternative for users who need more visibility.

**Independent Test**: Switch "Level color" to Pill, push an entry to the warning and over-limit levels, and check that a rounded background of the level color appears behind the whole entry, that the text on it is readable, and that the Settings preview shows the same.

**Acceptance Scenarios**:

1. **Given** "Level color" set to Pill and an entry at its warning level, **When** the bar is displayed, **Then** the entry (icon and value) is drawn on a rounded orange background with text that is readable on it.
2. **Given** "Level color" set to Pill and an entry at 100% or above, **When** the bar is displayed, **Then** the entry is drawn on a rounded red background.
3. **Given** "Level color" set to Pill and two adjacent entries at a level, **When** the bar is displayed, **Then** the two pills are visually separate.
4. **Given** "Level color" set to Pill, **When** no entry has a level, **Then** no pill is drawn and the bar looks as with colored text.

---

### User Story 3 - Keep the symbols (Priority: P2)

A color-blind user, or a user with a grayscale display filter, cannot tell orange from the normal text color. They check "Mark levels with ⚠ / ‼" and get today's glyphs back, alone (with "Level color" Off) or together with color.

**Why this priority**: Without this option the feature would remove information for users who cannot rely on color.

**Independent Test**: Check "Mark levels with ⚠ / ‼" with each "Level color" choice and confirm the glyph prefixes appear as in the previous version, combined with the chosen color style.

**Acceptance Scenarios**:

1. **Given** "Level color" Off and the symbol checkbox checked, **When** an entry is at its warning level, **Then** the bar shows `⚠` before its value, in the menu bar's normal color, as in the previous version.
2. **Given** "Level color" Text and the symbol checkbox checked, **When** an entry is over 100%, **Then** the bar shows `‼` before its value, and the glyph and the value are red.
3. **Given** "Level color" Pill and the symbol checkbox checked, **When** an entry is at its warning level, **Then** the glyph appears inside the pill before the value.
4. **Given** any display setting, **When** VoiceOver reads the bar, **Then** each entry at a level is announced with its level ("warning" or "over limit").

---

### User Story 4 - Hide levels from the bar (Priority: P3)

A user who relies on notifications wants a plain bar. They set "Level color" to Off and leave the symbol checkbox unchecked. Settings tells them that levels no longer appear in the bar; notifications and the dropdown still show them.

**Why this priority**: A deliberate opt-out for a minority of users; the defaults keep levels visible.

**Independent Test**: Set "Level color" Off with symbols unchecked, check that the note appears in Settings, that an entry over 100% shows no level in the bar, and that its notification still arrives.

**Acceptance Scenarios**:

1. **Given** "Level color" Off and the symbol checkbox unchecked, **When** the Menu Bar tab is shown, **Then** a short note says that levels will not appear in the bar and that notifications and the dropdown still show them.
2. **Given** that setting and an entry over 100%, **When** the bar is displayed, **Then** the entry shows its value without color or glyph.
3. **Given** that setting, **When** an entry crosses a configured threshold, **Then** the threshold notification is sent as before.
4. **Given** that setting, **When** the user turns on color or symbols again, **Then** the note disappears.

### Edge Cases

- A stale entry (value marked `~`) at a level: the level is shown with the same color as a fresh entry; the `~` marker stays directly before the value, after a glyph if symbols are on, and inside the pill in the pill style.
- An entry without a percent (`--` unavailable, `…` no data yet) never has a level and is never colored.
- A group member entry (spec 004) colors by its group's warning threshold, as its level does today.
- The dropdown is open: the bar entry is shown highlighted by the system; neutral parts and level colors follow FR-015.
- A secondary display whose menu bar is inactive, a tinted menu bar (wallpaper tinting), "Reduce transparency" and "Increase contrast": neutral parts look like the menu bar's other text, and level colors stay distinguishable from the neutral color.
- The configuration file contains an unknown value for the level color: the default (Text) is used, the problem is noted in the diagnostic log without a problem notice, and the rest of the file loads (FR-003).
- The bar shows the placeholder "AgentTacho" (no entry configured or no data yet): it is drawn in the neutral color.
- An older AgentTacho version reads a configuration file written by this version: it ignores the two new settings and keeps working with glyphs. If the older version saves the file, the two settings are dropped; after upgrading again the defaults apply. This is accepted.
- A Codex plan entry at 60% whose 5-hour limit is reached is at the over-limit level: red value (or red pill), `‼` when symbols are on, "over limit" in the accessibility text.
- The run-out marker `↗` of spec 011 (pace forecast, merged while this feature was built) follows the value in the neutral tone in every style. Spec 011 shows it only on entries without a level, so it never sits on a pill or carries a level color; its accessibility suffix ("projected to run out before reset") follows the level words.

## Requirements *(mandatory)*

### Functional Requirements

**Settings**

- **FR-001**: The configuration MUST hold a "level color" setting with the values Text, Pill and Off. When the setting is absent, Text MUST be used.
- **FR-002**: The configuration MUST hold a "show level symbols" setting (on or off). When the setting is absent, off MUST be used.
- **FR-003**: A configuration file without these settings (written by an earlier version) MUST load unchanged and behave as Text with symbols off. The settings MUST be written to the file only when the configuration is next saved. An unknown level color value MUST fall back to Text and be noted in AgentTacho's diagnostic log; it MUST NOT make the configuration invalid and MUST NOT show a problem notice, like an unreadable arrangement (spec 008). The next save from Settings MUST write the value in effect (Text) in its place.
- **FR-004**: The Menu Bar tab in Settings (spec 008) MUST offer both settings: "Level color" with the choices Text, Pill and Off, and the checkbox "Mark levels with ⚠ / ‼". Changes MUST apply to the bar immediately, like the tab's other settings, and MUST NOT trigger a refresh.
- **FR-005**: The Menu Bar tab's bar preview (spec 008) MUST show the chosen level style and update as the settings change. Because the preview sits on a fixed dark capsule whatever the system appearance, it MUST render as the bar does in a dark menu bar: white for neutral parts, the dark-appearance orange and red, and the same pill, pill text color and glyph rules.
- **FR-006**: The threshold help text in Settings (which today says the lower threshold marks the entry with `⚠` and 100% marks it with `‼`) MUST describe the levels without naming a specific marker, for example "The lower value marks the entry as a warning in the menu bar (80% when both are empty); 100% marks it as over the limit."

**Bar rendering**

- **FR-007**: With "Level color" Text, the value of an entry at its warning level MUST be shown in orange and the value of an entry at the over-limit level in red. The icon MUST stay in the neutral color. With symbols on, the glyph MUST take the value's color.
- **FR-008**: With "Level color" Pill, an entry at a level MUST be drawn on a rounded background in the level color (orange or red) that covers its icon, glyph (if shown), stale marker and value. Text and icon on the pill MUST be drawn in black or white, whichever has the higher contrast ratio against the pill fill as resolved for the current appearance; the result MUST reach at least 4.5:1 in light and dark menu bars, each with and without "Increase contrast". This choice is a presentation decision under FR-020. Adjacent pills MUST NOT touch. While an entry has a pill, the bar MAY be wider by at most the pill's horizontal padding on both sides of that entry; no width is reserved for pills when no entry has a level.
- **FR-009**: With "Level color" Off, the bar MUST NOT color any part.
- **FR-010**: With symbols on, the bar MUST show `⚠` before the value of an entry at its warning level and `‼` before the value of an entry at the over-limit level, in the positions used by the previous version. With symbols off, the bar MUST NOT show a glyph.
- **FR-011**: The level colors MUST be the system's orange and red, the same hues the dropdown uses for its warning and error text, including their adaptations for dark appearance and increased contrast.
- **FR-012**: "Level color" Off with symbols off MUST be a valid configuration in which the bar shows no level. The Menu Bar tab MUST then show a short note that levels will not appear in the bar and that notifications and the dropdown still show them; the note MUST disappear when either setting is turned on.
- **FR-013**: Every part of the bar that does not carry a level color (icons, values of entries without a level, the stale marker of an entry without a level, the placeholder) MUST be drawn in the menu bar's own text color for its current appearance, so that a bar without levels looks the same as in the previous version in light, dark and tinted menu bars, on an inactive secondary display, with "Reduce transparency" and with "Increase contrast". When no part of the bar carries a level color (no entry at a level, or "Level color" Off), the bar MAY be drawn as a monochrome image tinted by the system, as in the previous version.
- **FR-014**: The bar MUST follow appearance changes (light and dark, accent and tinting, accessibility display options) while running, without a restart and within one second of the change.
- **FR-015**: While the dropdown is open and the system shows the bar entry highlighted, neutral parts MUST follow the same rule as FR-013 for the highlighted state, and level colors and pills MUST stay distinguishable from the neutral color.
- **FR-016**: The stale marker `~` MUST keep its meaning and stay directly before the value in every style (after the glyph when symbols are on).
- **FR-017**: The level computation MUST NOT change: an entry's level is determined exactly as in spec 001 FR-003, spec 004 and spec 007 FR-012. (Amended by spec 030 (2026-10-20): the level now comes from the one level rule of spec 030 FR-001 to FR-003, critical at the owner's second threshold or a real limit.)

**Accessibility**

- **FR-018**: The bar's accessibility text MUST name the level of every entry at a level, independent of the display settings, for example "Vertex warning 85%", "Vertex over limit 104%" and, for a stale entry, "Vertex warning ~85%". Entries without a level MUST be read as today (name and value). The accessibility text, which also serves as the bar's plain-text form in log lines, MUST NOT contain the `⚠` or `‼` glyphs in any setting; the stale marker stays as today. (Amended by spec 030 (2026-10-20): the critical level comes from the owner's second threshold (spec 030 FR-002); a critical entry below a real limit reads "critical", one at a real limit "over limit", for example "Claude Max critical 91%", spec 030 FR-004.)

**Unchanged behavior**

- **FR-019**: Threshold notifications, the threshold settings and the dropdown MUST NOT change.
- **FR-020**: The decisions which part of an entry gets which color, whether a glyph is shown, what the accessibility text says and whether the hidden-levels note is shown MUST be computable without drawing, so they can be tested apart from the menu bar rendering.

**Documentation**

- **FR-021**: The README's description of the bar markers MUST describe the new behavior (colored values by default, pill and symbols as options), and spec 001 FR-003 MUST get a note pointing to this spec for how levels are shown.

### Key Entities

- **Level display settings**: two global settings in the configuration: the level color style (Text, Pill or Off) and whether level symbols are shown. They affect only how the bar presents levels, never the levels themselves.
- **Bar entry presentation**: for one bar entry, what is drawn and how: the icon, the glyph (if any), the stale marker, the value, which of them carry the level color, whether a pill is drawn, and the accessibility text. Derived from the entry's level, its stale state and the level display settings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With default settings, an entry at a level takes no more width in the bar than the same entry without a level (previously the glyph added one character).
- **SC-002**: In a side-by-side comparison of the previous version and this version (manual walkthrough check), a bar with no entry at a level looks the same in each of these conditions: light menu bar, dark menu bar, tinted menu bar, inactive secondary display, "Reduce transparency", "Increase contrast".
- **SC-003**: Every combination of the three level color choices and the symbol checkbox (six combinations), each at the normal, warning and over-limit levels, fresh and stale, produces the presentation described in FR-007 to FR-016, verified by automated tests of the presentation decisions.
- **SC-004**: Text on a pill meets a contrast ratio of at least 4.5:1 against the pill fill in light and dark menu bars, each with and without "Increase contrast", verified by automated tests of the text color choice for the resolved fill colors.
- **SC-005**: A configuration file from the previous version loads without changes or problem notice and shows colored text without symbols.
- **SC-006**: VoiceOver names the level of every entry at a level in all six setting combinations.
- **SC-007**: After a switch between light and dark appearance, the bar shows the new appearance within one second (manual walkthrough check).

## Assumptions

- The settings belong in the Menu Bar tab (spec 008), next to the bar preview, because they only affect the bar's look.
- Existing users get the new defaults (colored text, symbols off); the release notes announce the change. No migration writes to their configuration file.
- A stale entry at a level keeps the full level color: hiding or dimming a possibly outdated warning would be the riskier choice, and the `~` marker already says the value is old.
- Pill geometry (corner radius, padding, gap) and the exact text color on the pill are design details for the plan, bounded by FR-008.
- How the bar obtains the menu bar's text color for a full-color image (including inactive displays and the highlighted state) is an implementation question; the plan starts with a short spike to confirm it, since it is the main technical risk. If the spike shows that neutral parts of a full-color image cannot match the system's tinting, the bar uses the FR-013 fallback (monochrome system-tinted image) whenever no level color is shown, so SC-002 holds in the common case, and the remaining difference while a level is shown is documented in the plan.
- The bar stays a `MenuBarExtra` label; replacing it with a status item is out of scope.
- The pace-forecast bar marker (spec 011) landed on `main` first; this feature adapts to it (see Edge Cases).
