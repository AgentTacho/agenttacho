# Brainstorm Overview

Last updated: 2026-11-03

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 18 | 2026-10-16 | landing-page | approved | - | - |
| 28 | 2026-10-19 | default-window-setting | rejected | - | - |
| 35 | 2026-10-23 | translucent-dropdown | parked | 036 (branch) | - |
| 36 | 2026-10-23 | nsmenu-dropdown | active | - | - |

## Open Threads
- Native form of each footer part in the NSMenu (status row, update line, source error lines) (from #36)
- Headline switch rows and Details inside the menu's tracking loop (from #36)
- Content row height changes while the menu is open, and the height cap against the menu's maximum (from #36)
- Orange and red text on the system's glass over light desktops (from #36)
- Which spec 036 parts carry over, and the opaque option's configuration key (from #36)
- Theme mismatch in the spec 036 walkthrough (light configured, dark shown) (from #36)
- Capturing and cropping the menu in the demo build and capture script (from #36)
- MenuBarOpener and MenuBarExtra mentions in docs and comments (from #36)

## Parked Ideas
- Translucent dropdown (#35)
  Reason: a custom MenuBarExtra window cannot get the system's menu glass; waits for the dropdown in a real NSMenu (#36), where an opt-in "Opaque background" is planned to replace its toggle. Spec 036 and its walkthrough results are on branch `036-translucent-dropdown`.

Brainstorm 28 (default window setting) is rejected: spec 027's saved dropdown choice already serves as a per-account default, and hiding the marker and tag removed information; see its Rejection section.

Spec 022 (`022-move-repo-org`, an earlier draft for the repository location) is abandoned; the repository location was part of #22 (name the app AgentTacho, now in `attic/`).

Archived sessions 01 to 17, 19 to 27, 29 to 34 and 37 to 43 are in `attic/`; each has its spec in `specs/`, except 42 (abandoned, superseded by 43). New ideas wait in `idea-inbox.md`.
