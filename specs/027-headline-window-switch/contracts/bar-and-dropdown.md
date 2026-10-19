# Contract: Bar entry and dropdown rows

Delta to `specs/012-colored-bar-levels/contracts/bar-rendering.md` and `specs/025-minimal-dropdown/contracts/dropdown-ui.md`.

## Bar entry

Order of drawn parts: icon, tag, glyph, stale marker, value, run-out marker.

| Headline | Drawn | Accessibility |
|---|---|---|
| default | `✳ 70%` (as today) | as today |
| Claude 5-hour | `✳ 5h 58%` | `Claude Max 5-hour window 58%` |
| Claude 5-hour, stale, warning, symbols on | `✳ 5h ⚠ ~85%` | `Claude Max 5-hour window warning ~85%` |
| Claude 5-hour, unavailable | `✳ 5h --` | `Claude Max 5-hour window --` |
| Claude model limit `Fable` | `✳ Fable 31%` | `Claude Max Fable weekly limit 31%` |
| Codex `5-hour` | `◎ 5h 40%` | `ChatGPT Plus 5-hour window 40%` |
| Codex `weekly` (not longest) | `◎ wk 60%` | `ChatGPT Plus weekly window 60%` |
| before first values | `✳ …` (no tag) | as today |

- Accessibility keeps today's format `<name> [warning|over limit] <value>` plus the run-out suffix, with the window name after the entry name.
- The tag takes the icon's tone; on a pill it is inside the pill.
- The Menu Bar tab's preview renders the same entries (it uses `BarLayout.segments` with the draft).

## Dropdown section header

`✳ Claude Max ............ 5h 58%`: tag in the secondary color and regular weight, percent bold. No tag with the default window.

## Window rows (Claude and Codex sections only)

| State | Marker slot (12 pt) | Hover | Click | Accessibility |
|---|---|---|---|---|
| headline | `●` | none | nothing | selected, label ends ", shown in menu bar" |
| other row | empty | rounded subtle fill behind name line and bar, `○` in slot | makes it the headline (default row: clears the choice) | action "Show in menu bar" |

- The dropdown stays open after a click; header, `●` and bar update at once.
- Name tooltip, reset tooltip and the orange note stay as in spec 025.
- Budget, member and Unassigned rows have no slot.
