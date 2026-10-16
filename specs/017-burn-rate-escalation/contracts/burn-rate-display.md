# Contract: Burn Rate Display

The user-visible surface of spec 017, extending `specs/011-pace-forecast/contracts/pace-display.md`.

## Bar entry

| Condition (in order) | Marker after the value | Accessibility suffix |
|---|---|---|
| toggle off, level warning or critical, stale, or member share | none | none |
| burns fast (FR-005 to FR-007) | `↑` | `, burning fast, projected to run out well before reset` |
| spec 011 run-out counts and is not withheld | `↗` | `, projected to run out before reset` |
| otherwise | none | none |

At most one marker per entry. The marker is drawn in the neutral tone (spec 012).

## Dropdown pace meter text (tooltip and accessibility label)

| State | Text |
|---|---|
| burns fast | `<delta text> · burning fast · runs out <fast run-out>` |
| spec 011 run-out | `<delta text> · runs out <run-out>` |
| otherwise | `<delta text>` |

`<delta text>` is "on pace", "N% ahead" or "N% behind" (spec 011 FR-008). The run-out time uses `UsageFormat.runOutText` (spec 011 FR-009). The meter is orange when the entry burns fast or has a spec 011 run-out, secondary otherwise. The toggle does not affect the dropdown.

## Menu Bar tab

Toggle label: `Show ↗ or ↑ when an entry will run out before it resets`. Stored key unchanged: `showsRunOutMarker` (default true).
