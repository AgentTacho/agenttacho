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

## Budget section

```
[icon] Vertex                                  532%
1,596 of 300 US$/month           resets in 13d 7h
██████████████████████████████████████████████████  (red)
```

- Member lines only with two or more members; empty group keeps "No accounts in this group yet".
- Notes after the bar: incomplete prices, "stale since <time>".
- Identifiers: `agenttacho.budgetRow` on header, amount line and bar of the shot budget; `agenttacho.details` unchanged.

## Subscription headers

- Claude and Codex: icon, name, bold headline percent (unchanged); no tooltip on the name.
- No Codex plan type line, no "Tokens this week" line.
- Expanded Details of a subscription section: first line "This week: 45.1M tokens", then the view picker and table.

## Dividers

- One `Divider` between consecutive sections, none above the first, one before the footer.

## Footer

```
<source error lines, red>
<update line, only while an update waits / installs / failed>
Last refreshed 16:54                         stale
[↻]                                     [⚙]  [⏻]
```

| Element | Text / symbol | Tooltip | Accessibility label | Shortcut | Identifier |
|---|---|---|---|---|---|
| refresh | `arrow.clockwise` | Refresh now | Refresh now | none | `agenttacho.refreshButton` |
| Settings | `gearshape` | Settings… | Settings… | ⌘, | `agenttacho.settingsButton` |
| Quit | `power` | Quit AgentTacho | Quit AgentTacho | ⌘Q | `agenttacho.quitButton` |

- "Last refreshed" tooltip: the pace line text while a pace is slowed, none otherwise; the same text is its accessibility value.
- No gear menu, no "About AgentTacho", no "Check for Updates…" in the dropdown.

## Settings

- Account detail (Claude subscription, Codex subscription, token-based with own budget) and group detail: a segmented `Picker("Times")` with "Relative" and "Absolute", bound to the Settings draft.
