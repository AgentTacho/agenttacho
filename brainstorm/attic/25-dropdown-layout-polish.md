# Brainstorm: Dropdown Layout Polish

**Date:** 2026-10-19
**Status:** active

## Problem Framing

The spec 025 walkthrough (minimal dropdown, merged as 4dc3425) showed four places where the dropdown still spends lines or attention it does not need to:

- A budget group shows three "Details" disclosures: one per member account and one for the group. Opening them one by one is busy, and the group's own Details already holds the totals.
- Subscription Details start with a "This week: 188.7M tokens" line, a whole line for one number that belongs to the per-day calendar it sums.
- The footer scrolls out of view once the content is taller than the panel, so the refresh, Settings and Quit icons can disappear.
- "Last refreshed" takes a line of its own above the icon row.

The idea inbox item `member-line-rule-in-core` adds a testability gap in the same place: the rule that member lines show only with two or more members lives in the view and is repeated in the demo coverage report.

A fifth walkthrough idea, switching which limit the headline percent and the menu bar show, changes what the bar, alerts and markers mean. It gets its own brainstorm (idea inbox `headline-percent-switch`). The screenshots are recaptured after this round (idea inbox `minimal-dropdown-screenshots`).

## Approaches Considered

### Budget Details

#### A: Expand-all button inside the budget Details (chosen)
- Member summary lines ("Claude via Vertex  $181 (36%)") stay as glanceable rows; their own Details disclosures go.
- The budget Details shows the group's tables and calendar, then a "Show accounts" button that adds each member's tables below, under the member's name.
- Pros: one disclosure per section; shares still readable without a click; per-account detail stays one click deeper.
- Cons: a long Details when accounts are shown.

#### B: An "Accounts" view in the picker
- The Models / Projects / Harnesses picker gets a fourth view with one row per account (tokens, cost, share); member lines and their Details go.
- Pros: compact, no button.
- Cons: per-account model and project tables are gone.

#### C: Members only inside Details
- Member lines move into the Details too, with the button of A.
- Pros: smallest closed section.
- Cons: shares need a click.

### Footer

#### A: Whole footer pinned (chosen)
- Source errors, the update line and the status row stay fixed below the scrolling sections.
- Pros: problems and actions are always visible.
- Cons: a long error list takes height from the sections.

#### B: Only the status row pinned
- Errors and the update line scroll with the sections.
- Pros: more room for sections.
- Cons: an error can scroll out of view.

## Decision

Budget Details approach A, footer approach A, the Σ sum in the calendar row, the status beside the refresh icon, and `member-line-rule-in-core` folded in. One spec, dropdown only.

```
▣ Company budget                     86%
430 of $500/month          resets in 12d
█████████████████│████████░░░░░░░░░
27% ahead · runs out in 2d 23h
G  Claude via Vertex          $181 (36%)
֍  OpenAI API                 $249 (50%)
⌄ Details
  [Models|Projects|Harnesses]
  ...tables...
  T  F  S  S  M  T  W  T     Σ
  12 40 31 55 42 0  0  0   180
  [ Show accounts ▾ ]
  ── Claude via Vertex ──
  ...tables...
  … sections scroll …
───────────────────────────────────────
<source errors, only when present>
<update line, only while an update waits>
↻  Last refreshed 7:23 AM            ⚙   ⏻
```

## Key Requirements

- A budget group has exactly one Details disclosure, the group's. Member summary lines (icon, name, amount, share) stay and have no Details of their own.
- Inside the group's Details, below the group's tables and calendar, a "Show accounts" button reveals each member's tables (with the same view picker choice) under the member's name; pressing it again hides them.
- Own-budget accounts, subscriptions and Unassigned keep a single Details as today.
- The rule for member lines (shown with two or more members) and for the members' tables lives in tested core logic; the demo coverage test checks it (idea inbox `member-line-rule-in-core`).
- The "This week: …" line goes. Every per-day calendar row ends with a Σ column with the sum for the shown period: tokens for subscriptions, dollars for budgets, in the same units and format as the day values.
- The footer stays pinned below the scrolling sections: source errors, the update line (only while it has something to say) and the status row.
- The status row is: refresh icon, "Last refreshed …" right next to it, then Settings and Quit icons on the right. The pace text stays the tooltip and accessibility value of the status; the "stale" marker stays in the status.
- No horizontal scrolling anywhere and no visible scrollbar (spec 025 walkthrough).
- Constitution V: the changed dropdown shots are recaptured in the screenshot round that follows this spec.

## Open Questions

- Does "Show accounts" remember its state across openings, like the view picker does?
- What does Σ show when the period has no usage, and is it bold or secondary?
- How does the pinned footer behave at the height cap (sections scroll, footer fixed) and with many error lines?
- VoiceOver order with a pinned footer: sections first, then footer?
- Does a long "Last refreshed" text (another day's date) still fit between the refresh icon and the Settings icon at 360 pt?
