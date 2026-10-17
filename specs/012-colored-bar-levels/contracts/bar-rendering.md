# Contract: Bar rendering by level display setting

Input: the bar items from `BarLayout.segments` and `LevelDisplaySettings`. Output: what the menu bar shows. The decision table is implemented by `BarPresentation` and fully covered by unit tests (SC-003); the app only maps tones to colors.

## Decision table (one entry)

| Level color | Symbols | Level | Icon | Glyph | Value (and stale marker) | Pill |
|---|---|---|---|---|---|---|
| Text | off | normal | neutral | none | neutral | no |
| Text | off | warning | neutral | none | orange | no |
| Text | off | over limit | neutral | none | red | no |
| Text | on | warning | neutral | `⚠` orange | orange | no |
| Text | on | over limit | neutral | `‼` red | red | no |
| Pill | off | warning | on-pill | none | on-pill | orange |
| Pill | off | over limit | on-pill | none | on-pill | red |
| Pill | on | warning | on-pill | `⚠` on-pill | on-pill | orange |
| Pill | on | over limit | on-pill | `‼` on-pill | on-pill | red |
| Off | off | any | neutral | none | neutral | no |
| Off | on | warning | neutral | `⚠` neutral | neutral | no |
| Off | on | over limit | neutral | `‼` neutral | neutral | no |

Normal level with any setting: neutral icon and value, no glyph, no pill. Stale entries follow the same row; the `~` takes the value's tone and sits after the glyph.

## Colors

| Tone | Color |
|---|---|
| neutral | template image tinted by macOS when the whole bar is neutral; otherwise `labelColor` for the drawing appearance |
| warning | `systemOrange` for the drawing appearance |
| over limit | `systemRed` for the drawing appearance |
| on-pill | black or white by `PillContrast.textColor(onFill:)` for the resolved pill fill |

## Layout

- Order per entry: icon, space, glyph (if any), stale marker (if any), value. Entries separated by two spaces, as today.
- Pill: rounded rectangle behind icon through value; corner radius of half the pill height capped at 4 pt, horizontal padding 3 pt, vertical inset so the pill fits the menu bar height; the two-space separator keeps adjacent pills apart. The bar grows by the padding only while an entry has a pill.

## Accessibility text

`"<name> <stale marker><value>"` for normal entries; `"<name> warning <stale marker><value>"` and `"<name> over limit <stale marker><value>"` at a level. Entries joined by two spaces. Never contains `⚠` or `‼`. Empty bar: `"AgentTacho"`.
