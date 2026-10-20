# Brainstorm: Threshold Levels and Budget Direction

**Date:** 2026-10-20
**Status:** active

## Problem Framing

Each Claude account, Codex account and budget has two notification thresholds (80% and 100% by default). They only partly drive what the user sees:

- In the menu bar the lower threshold sets the warning level (orange value), but the critical level (red) is hardcoded to 100% (`BarLayout.level`, spec 001 FR-003, spec 012).
- In the dropdown the thresholds have no effect at all. The percent turns red only at 100% or more, and the bar fill is orange for pace attention (spec 025 FR-003), not for a threshold.

A user who sets the upper threshold to 90% gets notified at 90% but sees nothing red until 100%. The levels and the notifications should mean the same thing everywhere.

Second, the app shows every budget as filling up (0% to 100% used). Some users think in what is left: how quickly the budget empties as they burn it down. That is a matter of preference and should be one global switch.

## Approaches Considered

Behavior was settled through questions (see Decision). The approaches cover how to deliver it.

### A: Two specs, levels first
- Pros: the levels change is small and ships on its own; the direction spec builds on settled level semantics; smaller diffs to review.
- Cons: two screenshot rounds and two pull request cycles.

### B: One combined spec (chosen)
- Pros: one review, one screenshot round, one release note; thresholds and direction are designed together, which matters because remaining mode changes how thresholds read.
- Cons: a large diff touching almost every visible surface; a level bug and a direction bug are harder to tell apart in review.

### C: Levels now, park direction
- Pros: smallest scope.
- Cons: the direction switch is wanted, not a maybe.

## Decision

Approach B: one spec covering both parts.

### Part 1: Levels from thresholds

- The lower threshold is the **warning** level, the upper threshold the **critical** level, for menu bar and dropdown alike. Notifications keep firing at the same thresholds.
- Menu bar: unchanged mechanics (spec 012 level color and symbols), only the critical level now comes from the upper threshold.
- Dropdown: only the **percent number** takes the level color (orange at warning, red at critical). The bar fill keeps its pace meaning (orange for pace attention) and turns red at the critical threshold instead of at a fixed 100%.
- Defaults: only the lower field set means critical stays 100%; neither set means 80% / 100% as today.
- A real limit (100% used, a Codex limit reached, the Claude seven-day window at 100%) is always critical, even when the upper threshold is set above 100%.

### Part 2: Global direction switch

- A setting in the General tab: show budgets as **used** (0% to 100%, today's behavior and the default) or **remaining** (100% to 0%).
- Remaining mode flips every budget and window value: menu bar values, dropdown percents and bars, budget amounts, tooltips and accessibility text, the Settings bar preview.
- Bars empty toward the left like a battery; the pace tick sits at the expected remaining share.
- Run-out arrows flip: `↗` becomes `↘`, `↑` becomes `↓`.
- Pace note wording stays ("15% ahead · runs out in 2d 13h"): it describes the burn rate, which is the same in both modes.
- Thresholds follow the direction in the UI: Settings reads "notify at 20% left / 0% left" and notifications say "20% left". Stored values stay in used percent (80 / 100), so switching modes changes wording only, never behavior. Older configuration files load unchanged.
- Over budget (Vertex and API budgets above 100% used): remaining mode shows a **negative value**, for example `−15%` in red, with an empty red bar; a dollar amount reads "$15 over".
- Spend figures that are not a budget level (cost breakdown per model and per day, Σ totals) do not flip.

## Key Requirements

- One level computation, driven by the entity's thresholds, feeds the menu bar, the dropdown percent color and the dropdown bar's red state.
- The warning threshold never colors the dropdown bar fill; orange on the bar stays pace attention only.
- Real limits are critical regardless of the configured upper threshold.
- The direction setting is global, stored in the configuration file, absent key means "used".
- Thresholds are stored in used percent in both modes; Settings, notifications and accessibility text present them in the chosen direction.
- Remaining mode shows negative percent values for budgets over 100%, in red.
- Arrows `↗`/`↑` flip to `↘`/`↓` in remaining mode; the Menu Bar tab's checkbox label follows.
- Level and direction decisions live in `UsageCore` with tests; the SwiftUI and AppKit layers stay thin (constitution II).
- Visible change in both parts: new screenshots from the demo build and website copy updates (constitution V). The demo scenario needs an entry with an upper threshold below 100% and, for the remaining-mode shots if any, an over-budget entry.
- Spec 001 FR-003, spec 012 and spec 025 FR-003 (red at a fixed 100%) are amended by the new level rule.

## Open Questions

- Threshold editor wording in remaining mode, and whether its help text ("The lower value also marks the entry as a warning...") explains both levels
- Configuration files with more than two thresholds: which one is critical (the second lowest, or the highest)
- An upper threshold equal to or below the lower one (both levels at the same value: critical wins?)
- Exact dollar wording for budgets in remaining mode ("$60 left of $100", "$15 over")
- Whether remaining mode rounds so that 99.6% used shows "0%" left or "1%" left, and how that lines up with the red-at-100 rule
- Whether notifications for budgets above 100% in remaining mode read "15% over" or "−15% left"
- Whether the website gets a shot of remaining mode or only a mention in the feature copy
- Whether the menu bar's Settings preview shows both directions or only the active one
