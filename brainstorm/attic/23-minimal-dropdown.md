# Brainstorm: Minimal Dropdown

**Date:** 2026-10-18
**Status:** spec-created (specs/025-minimal-dropdown)

## Problem Framing

AgentTacho should feel calm: show what matters at a glance and nothing the user has to read only to dismiss it. The spirit is littlebigdetails.com; the visual reference is CodexBar's window row (title with percent, reset time, a full-width bar with a pace marker, the pace in words). The dropdown is the densest place in the app today:

- Each window row packs a label, the percent, a long absolute reset ("resets Fri 23. Oct at 09:00") and a 44 pt pace meter whose meaning (ahead, behind, run-out) lives only in its tooltip.
- The Codex section adds "ChatGPT Plus plan" (the header already says Plus) and "Tokens this week", which the Claude section does not have.
- A group with one member repeats its own numbers in the member line ("Claude Code via Vertex 1.596 US$ (532%)").
- Sections run into each other without separators.
- The gear opens a menu (About, Check for Updates, Settings, Quit) for actions that are one click each elsewhere; About and the update check already live in Settings > About (spec 020).
- The pace line ("Claude and Codex limits next checked at 17:07 (no agent activity)") is background information on a line of its own, and the update line, the pace line and source errors shift "Last refreshed" around.

This session covers the dropdown only. The menu bar label and the Settings layout can get their own minimalism pass later.

## Approaches Considered

### A: CodexBar cards
- Three lines per window: label, percent and reset; a full-width bar with the pace tick; the pace sentence always ("13% behind", "on pace").
- Pros: everything explicit, closest to CodexBar.
- Cons: tallest (the Claude section grows from 4 to over 10 lines); "on pace" and "behind" add text that asks nothing of the user.

### B: Bar, note on demand (chosen)
- Two lines per window: label, percent and reset; a full-width bar with the pace tick. A third line, orange, only when the pace calls for attention (a run-out or a fast burn).
- Pros: the bar shows percent and pace without a tooltip; text appears only when it matters, so an orange line means "look here".
- Cons: "behind" and "on pace" show only as the tick position, not in words.

### C: One line, inline bar
- Today's single-line rows with the pace meter replaced by a short bar showing fill and tick; the orange note as in B.
- Pros: most compact, smallest change.
- Cons: a short bar is hard to read and the row stays crowded.

## Decision

Approach B for every limit window and every budget, with these choices:

- Reset and run-out times are relative by default ("resets in 4d 16h", "runs out in 2d 13h") and configurable per account and per group to a short absolute form. The tooltip on a time shows the other form.
- Section headers keep their bold headline percent.
- The footer is "Last refreshed" above a row of three icons: refresh, Settings, Quit.
- The quiet app-update line stays, shown only while an update is waiting.
- Codex's weekly token total moves into Details; Claude's Details gets the same total.
- Three idea inbox items fold in because the redesign rewrites the rows they touch: dropdown-note-view-model, single-pace-and-burn-value, run-out-text-in-core.

Mockup of a subscription section (tick = where even use would be now):

```
✳ Claude Code (Max)                          48%
5-hour  38%                    resets in 2h 26m
██████████████░░░░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░
7-day   48%                    resets in 4d 16h
█████████████│████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
15% ahead · runs out in 2d 13h            (orange)
Fable   31%                    resets in 4d 16h
████████████░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
› Details
────────────────────────────────────────────────
...
────────────────────────────────────────────────
Last refreshed 16:54       (tooltip: next check)
↻                                         ⚙   ⏻
```

## Key Requirements

Rows
- A limit window row (Claude 5-hour, 7-day and model limits; Codex windows) shows label, percent and reset time on one line, then a full-width bar: fill to the used percent, a tick where even use would be at the snapshot time.
- An orange note under the bar appears only when the pace has a run-out or burns fast, for example "15% ahead · runs out in 2d 13h" or "burning fast · runs out in 3h 10m". On pace and behind show no note.
- No pace information depends on a tooltip; the pace meter and its tooltip go. The bar has an accessibility label with the full text (window, percent, reset, pace).
- "Limit reached" and percents at or over 100 keep their red marking.
- A budget (group or own budget) keeps its header with icon, name and percent, then "1.596 of 300 US$/month" with the reset time, then the bar with the budget's pace tick and the same on-demand note.
- A group with exactly one member drops the member line; groups with several members keep theirs.

Sections
- A divider separates sections (each account, group, and Unassigned).
- Codex drops the "ChatGPT <plan> plan" line (the header names the plan) and the "Tokens this week" line; the week's total appears in Details.
- Details shows the token total for subscription sections, Claude and Codex alike.
- Stale, retrying, sign-in and configuration notes stay visible in their section.

Times
- Reset and run-out times come from one tested UsageCore formatter that takes a calendar and the snapshot time (inbox: run-out-text-in-core).
- Every account and group has a time format setting, relative (default) or absolute; existing configurations read as relative.
- Relative: "in 2h 26m", "in 4d 16h". Absolute: the time only today, weekday and time within a week, the date beyond ("Sun 1. Nov").
- The tooltip on a time shows the other form.
- Relative times stay current while the dropdown is open.

Footer
- Order from the top: source errors, the app-update line (only while an update is available, downloading, verifying, or after a failed install from the previous run), "Last refreshed", the icon row. "Last refreshed" is always the last text line.
- "Last refreshed 16:54" names the date only when it is not today; the stale marker stays on that line.
- The refresh pace line ("… next checked at 17:07 (no agent activity)") moves into the tooltip of "Last refreshed".
- Icon row: refresh on the left, Settings and Quit on the right, each with a tooltip and an accessibility label. ⌘, and ⌘Q keep working while the dropdown is open.
- The gear menu goes. About and "Check for Updates…" are only in Settings > About; the dropdown's transient check result line goes with the dropdown check.

Code quality folded in
- Grace, stale and rejected sign-in notes come from a UsageCore view-model with text and style (neutral, stale, attention) (inbox: dropdown-note-view-model).
- Each row gets one pace and burn value; BurnRate carries its Pace, so the app layer stops resolving them separately (inbox: single-pace-and-burn-value).
- Row and note text is built and tested in UsageCore; the views only render it (constitution II).

Specs and website
- Specs to amend: 004 FR-018a (member line of a single member), 007 FR-011 and FR-013 (Codex section lines), 011 FR-008 and FR-010 (pace meter and tooltip), 013 FR-003, FR-009 and FR-010 (dropdown check, update line), 016 FR-016 and 019 (pace line placement), 017 FR-012 (burn text in the meter tooltip).
- Constitution V: the dropdown shots (`plan-limits`, `budget`, `details`, the full dropdown) are recaptured from the demo build and reviewed; the demo scenario shows an orange note, a relative and an absolute time, and an available update.

## Open Questions

- Bar fill color: neutral, or the colored levels of spec 012 (with red at 100%)?
- What the "Last refreshed" tooltip shows when no plan is slowed: the next regular check, or nothing?
- Exact relative formats at the edges ("in 45m", "in 13d", under a minute) and the absolute format's date rule for budgets.
- Where the time format setting sits in Settings (account detail, group detail) and its wording.
- Whether a fast burn without a run-out inside the window gets a note.
- Whether multi-member group lines get a bar or stay text.
- VoiceOver: whether the note is part of the row's label or its own element.
