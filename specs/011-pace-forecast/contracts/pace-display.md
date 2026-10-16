# Contract: Pace Display

## Dropdown pace meter (FR-008 to FR-011)

A `PaceMeter` at the end of these rows (no extra line): a 44 pt track, a tick in the middle for even use, and a bar from the tick to the left (behind) or right (ahead) with length `|Pace.meterOffset|` of the half track (delta over 50 points, clamped to 1; 0 within the band, tick only):

| Row | Pace source |
|---|---|
| Claude "5-hour" | `status.fiveHour.pace(length: Pace.fiveHourSeconds, observedAt: status.fetchedAt, now: snapshot.generatedAt)` |
| Claude "7-day" | `status.sevenDay.pace(length: WindowResolver.weekSeconds, ...)` |
| Model limit (e.g. "Fable") | `limit.pace(observedAt: status.fetchedAt, now:)` |
| Codex plan window | `window.pace(observedAt: observation.observedAt, now:)` for each effective window |
| Budget amount line (group or own budget) | `entry.pace(now: snapshot.generatedAt)` |

Not shown: group member lines, token-based accounts without a budget, Unassigned, rows whose pace is nil.

Tooltip and accessibility text (`Pace.summary`) and color:

| Pace | Text | Color |
|---|---|---|
| delta -5...+5 | `on pace` | secondary |
| delta > 5, no run-out (held back or none) | `12% ahead` | secondary |
| delta > 5, run-out | `12% ahead · runs out Wed 14 Oct 16:20` (time only when today) | orange |
| delta < -5 | `8% behind` | secondary |

## Menu bar marker (FR-012 to FR-015)

- Rendered value: `<icon> <level glyph><stale ~><value>↗`, for example `62%↗`. Since the marker requires level `.normal` and not stale, the glyph and `~` never appear together with `↗`.
- Accessibility and plain text: `<name> 62%, projected to run out before reset`.
- Bar window per entry: Claude subscription 7-day window; Codex plan longest effective window; group or own budget the budget itself. Member share entries never carry the marker.
- Menu Bar tab: `Toggle("Show ↗ when an entry will run out before it resets")` (label renamed in spec 012's walkthrough), default on, below the preview. The preview uses the same `BarLayout.segments` and follows the toggle.

## Configuration key

```json
{ "showsRunOutMarker": false }
```

Absent means `true`. Written by the normal configuration save after a settings change.
