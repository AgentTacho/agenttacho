# Contract: Dropdown layout, texts and accessibility

## Window row (Claude 5-hour, 7-day, model limits; Codex windows)

```
5-hour  38%                    resets in 2h 26m      <- name, percent, reset text
██████████████░░░░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    <- RowBar: fill, tick
15% ahead · runs out in 2d 13h                       <- PaceNote, orange, only on attention
```

| Case | Line 1 | Bar | Note |
|---|---|---|---|
| normal with pace | name, percent, "resets …" | fill + tick, tone from RowBar | only on attention |
| no pace (FR-007 cases) | as above | fill, no tick | none |
| not started | name, percent, "not started" | fill, no tick | none |
| reset since observation | name, percent, no reset text | fill, no tick | none |
| unavailable | name, "unavailable" | none | none |
| 100% or more / limit reached | red percent | full red | none; Codex adds "Limit reached" (red) |

- Tooltips: the reset text shows the other time form (FR-019); the note shows its run-out in the other form; a model-limit name shows "<model> weekly limit, N% of the 7-day limit" (FR-019a). No tooltip on the bar.
- Accessibility: one element per row, label "<name>, <percent>, <reset text>, <pace summary>" (pace summary omitted without a pace).
- Identifier: the row with the screenshot's note carries `agenttacho.paceRow`; the Claude plan block keeps `agenttacho.claudePlan`.
- Headline switch (amended by spec 027 FR-001 to FR-003, `specs/027-headline-window-switch/contracts/bar-and-dropdown.md`): in a Claude or Codex subscription section every window row has a 12 pt marker slot at its leading edge with `●` on the headline row, is clickable as a whole (a click makes it the headline window, the default row clears the choice), shows a subtle rounded highlight and `○` on hover unless it is the headline row, and offers the accessibility action "Show in menu bar"; the headline row is selected and its label ends with ", shown in menu bar". Budget, member and Unassigned rows have no slot.

## Budget section

```
[icon] Vertex                                  532%
1,596 of 300 US$/month           resets in 13d 7h
██████████████████████████████████████████████████  (red)
```

- Member lines only with two or more members, without Details of their own; the group's one Details end with "Show accounts" / "Hide accounts" when two or more members have usage (amended by spec 026, see `specs/026-dropdown-layout-polish/contracts/dropdown-ui.md`); empty group keeps "No accounts in this group yet".
- Notes after the bar: incomplete prices, "stale since <time>".
- Identifiers: `agenttacho.budgetRow` on header, amount line and bar of the shot budget; `agenttacho.details` unchanged.

## Subscription headers

- Claude and Codex: icon, name, bold headline percent; no tooltip on the name. With a headline window other than the default, its tag ("5h", "wk", "Fable") stands before the percent in the secondary color and regular weight (amended by spec 027 FR-008).
- No Codex plan type line, no "Tokens this week" line.
- Expanded Details of a subscription section: the view picker first, then the table; the day row ends with the Σ column holding the week's total (amended by spec 026 FR-008, FR-009).

## Bands

Replaced by spec 028: no `Divider` anywhere in the dropdown. The sections alternate plain and tinted full-width bands, starting plain, and the pinned footer has its own band. See `specs/028-section-bands/contracts/dropdown-bands.md`.

## Footer

Amended by spec 026 (FR-010 to FR-013): the footer is pinned below the scrolling sections, shows at most 3 error lines ("+N more"), and "Last refreshed" moved into the icon row, now the status row.

```
<up to 3 source error lines, red, one line each>
<update line, only while an update waits / installs / failed>
[↻] Last refreshed 16:54   stale            [⚙]  [⏻]
```

| Element | Text / symbol | Tooltip | Accessibility label | Shortcut | Identifier |
|---|---|---|---|---|---|
| refresh | `arrow.clockwise` | Refresh now | Refresh now | none | `agenttacho.refreshButton` |
| Settings | `gearshape` | Settings… | Settings… | ⌘, | `agenttacho.settingsButton` |
| Quit | `power` | Quit AgentTacho | Quit AgentTacho | ⌘Q | `agenttacho.quitButton` |

- "Last refreshed" tooltip: the full status text when truncated and the pace line text while a pace is slowed, joined by a line break when both apply, none otherwise; the pace text is its accessibility value (spec 026 FR-013).
- No gear menu, no "About AgentTacho", no "Check for Updates…" in the dropdown.

## Settings

- Account detail (Claude subscription, Codex subscription, token-based with own budget) and group detail: a segmented `Picker("Times")` with "Relative" and "Absolute", bound to the Settings draft.
