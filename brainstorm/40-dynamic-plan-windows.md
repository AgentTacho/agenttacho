# Brainstorm: Dynamic Claude Plan Windows

**Date:** 2026-11-02
**Status:** spec-created (specs/040-dynamic-plan-windows)

## Problem Framing

Anthropic removed the 5-hour window from Claude plans. The usage endpoint (`GET /api/oauth/usage`) now answers `five_hour: null`, and the last-good store has held only `sevenDay` plus the Fable model limit since then. AgentTacho hardcodes the Claude windows as two fixed fields, `fiveHour` and `sevenDay`, so the dropdown keeps drawing a "5-hour" row that permanently reads "unavailable".

The assumption is spread across the code base: `SubscriptionStatus` and `LastGoodStore` (two fixed fields), `DropdownView` (two fixed `WindowRow`s), `ThresholdTracker.WindowKind` (`fiveHour`, `sevenDay`), `Pace` (`fiveHourSeconds`, `fiveHourPace`), `BurnRate`, `PaceReading`, `HeadlineChoice` (`claudeFiveHour`, config value `"fiveHour"`), `HeadlineWindow` (tag "5h"), the Settings wording ("the 5-hour or the 7-day limit"), the diagnostic log line (`5h ..., 7d ...`), and the demo scenario (`claude.<id>.fiveHour`), which means the website screenshots still show a 5-hour row.

Codex is not affected. Spec 007 already builds its window list from the data (`window_minutes`, named "5-hour", "weekly", "30-day" from the length), so the Codex side needs no change.

### What the endpoint returns today

A single read-only fetch on 2026-11-02 (structure only, values redacted) showed:

- Top-level `five_hour: null`, `seven_day: {utilization, resets_at, limit_dollars, used_dollars, remaining_dollars, locked_reason}`, and about 20 more top-level keys, all null, most of them codenames (`seven_day_opus`, `seven_day_sonnet`, `tangelo`, `cinder_cove`, ...).
- A generic `limits` array. Each entry: `kind`, `group`, `percent`, `severity`, `resets_at`, `scope {model {id, display_name}, surface}`, `is_active`. Today two entries:
  - `kind: weekly_all`, `group: weekly`, `scope: null`, `is_active: false` (the 7-day window)
  - `kind: weekly_scoped`, `group: weekly`, `scope.model.display_name: "Fable"`, `is_active: true` (the model limit spec 033 era code already reads)
- `weekly_scoped_shares` (already read), plus new `seven_day_breakdown` (percent per surface: Claude Code, Chats, Cowork, Other), `spend` and `extra_usage`.

`limits` has no window length; `group` names the window family instead.

## Approaches Considered

Scope first:

### A: Show what is sent
Keep the known Claude window kinds as fixed fields, but show a row, threshold, pace and headline option only when the endpoint returns that window.
- Pros: smallest change, fixes the visible problem.
- Cons: a new window kind from Anthropic stays invisible until code changes again.

### B: Generic Claude window list (chosen)
Claude windows become a list, like Codex. The UI, thresholds, pace and headline choice iterate over it.
- Pros: windows that come, go or change appear without a code change; aligns Claude with the Codex model.
- Cons: medium refactor (threshold keys, pace, last-good schema, headline configuration migration).

### C: One window model for Claude and Codex
A single plan-window type, one row view, one threshold and pace path for both harnesses.
- Pros: cleanest long term, prepares the provider-descriptor idea in the inbox.
- Cons: largest refactor and highest regression risk, for no visible gain over B today.

Source of the list, once B was chosen:

### B1: `limits[]` with top-level fallback (chosen)
Every `limits` entry becomes a window; `group` gives length and name. Top-level `five_hour`/`seven_day` are used only when `limits` is missing or empty.

### B2: Top-level keys
Every non-null top-level window object becomes a window, named from a key table. Codenamed keys stay unknown, and model limits still need `limits`.

### B3: Both, merged
Top-level classic windows plus `limits` for the rest, deduplicated (`seven_day` equals `weekly_all`). Most complete, but two sources must agree.

## Decision

**B with source B1.** Claude plan windows become a list read from the endpoint's `limits` array. `group` maps to the window length and name (`weekly` is 7 days; a 5-hour or session group is 5 hours, should one return). The top-level `five_hour` and `seven_day` objects serve only as a fallback when `limits` is absent or empty. Codex stays as it is.

## Key Requirements

- Claude subscription status holds a list of windows read from `limits[]`; each window has an identity (kind plus scope), a display name, percent, reset time, and a length when its group is known.
- Known groups map to a length and a name: `weekly` to 7 days ("7-day"); a 5-hour or session group to 5 hours ("5-hour"). An unknown group still shows as a row named from its kind, without pace.
- Entries with `scope.model` remain model limits (with `weekly_scoped_shares` allowance), now as members of the same list.
- When `limits` is missing or empty, the top-level `five_hour` and `seven_day` objects are read instead, so an older response shape keeps working.
- A window the endpoint does not send has no dropdown row, no threshold notification, no pace line and no headline option. The "5-hour: unavailable" row disappears. A failed fetch keeps showing last-good values as today (spec 010).
- Dropdown rows, threshold notifications, pace, burn rate escalation, headline choice and the menu bar tag all work over the list.
- Default headline stays the longest window (7-day today), matching Codex.
- Existing configuration keeps working: a saved headline `"fiveHour"` falls back to the default when no 5-hour window is sent; `"sevenDay"` maps to the weekly-all window; model-name headlines keep working. The last-good store reads its old format.
- Threshold state for a window that disappears is dropped without a notification.
- The diagnostic log lists the window kinds and groups seen on each successful fetch (without values), so the next API change shows in the log.
- Settings wording stops naming specific windows ("each plan window is checked on its own" or similar).
- Demo scenario: Claude accounts drop the 5-hour window and use the list form; the coverage test checks a Claude account without a 5-hour window. Screenshots that show the Claude dropdown or bar are recaptured, and website copy that names the 5-hour window is updated (constitution V).
- Codex behavior and data are unchanged.

## Out of Scope

- Codex window handling (already data-driven, spec 007).
- A shared Claude and Codex window model (approach C).
- `seven_day_breakdown` per-surface split (added to the idea inbox), `spend`, `extra_usage`, and the dollar fields of `seven_day`.
- Reading the codenamed top-level keys.

## Open Questions

- What `is_active` means (the binding limit? `weekly_all` is false while the Fable limit is true) and whether it should affect the headline or the row style.
- Whether `severity` ("normal", ...) should feed the threshold level or stay ignored in favor of AgentTacho's own thresholds.
- The stable key for a window in the configuration (headline choice, threshold state): `kind`, `kind` plus model name, or a derived name.
- Whether Claude's weekly window should be named "weekly" to match Codex, or keep "7-day" (and the "7d"/"wk" bar tags).
- Which `group` values to map besides `weekly` when a shorter window returns, and how an unknown group is named in the bar tag.
- Whether a window with `scope.surface` (not seen yet) is shown like a model limit or ignored.
- Which screenshots change (glance, menubar, dropdown shots with Claude rows) and which website data files mention the 5-hour window.
