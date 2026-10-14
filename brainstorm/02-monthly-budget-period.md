# Brainstorm: Monthly Budget Period

**Date:** 2026-10-14
**Status:** active

## Problem Framing

Budget groups today carry a single weekly budget (`weeklyBudgetUSD`), and their window follows a subscription account's 7-day reset, falling back to a configured weekday and hour (Monday 00:00 by default). Some token-based spend is governed by a company spending limit that is granted per calendar month, not per week. Tracking that limit against a weekly window forces the user to divide the monthly amount by an uneven number of weeks, and the reset dates never line up with the company's month. The app should let a budget group track a monthly budget whose window runs from the 1st of the month to the end of the month.

## Approaches Considered

### A: Period field plus a neutral budget amount
Each budget group gets `period: weekly | monthly` and a single `budgetUSD`. The legacy `weeklyBudgetUSD` key still decodes (as a weekly group), so existing configuration files load unchanged.
- Pros: one budget, one window, one percent per group; no invalid combinations; labels ("per week", "per month") derive from the period; a single code path for aggregation and thresholds.
- Cons: renames a configuration key (mitigated by legacy decoding).

### B: Two optional amounts
Keep `weeklyBudgetUSD`, add `monthlyBudgetUSD`; validation requires exactly one to be set.
- Pros: no key rename.
- Cons: representable invalid states (both or neither set); every consumer branches on which field is present.

### C: Global period switch
One global setting turns every budget group monthly.
- Pros: smallest change.
- Cons: rejected; different groups can be governed by different limits, so the period must be per group.

## Decision

Approach A. Each budget group chooses either a weekly or a monthly period (either/or, not both at once). Monthly windows start on the 1st at 00:00 local time and end at 00:00 local time on the 1st of the next month. Monthly groups behave exactly like weekly ones; no pacing indicator is added.

## Key Requirements

- A budget group has a period of weekly or monthly, and exactly one budget amount that applies to that period.
- A monthly window starts at local midnight on the 1st of the current month and ends at local midnight on the 1st of the next month (handles 28 to 31 day months and DST transitions through calendar arithmetic).
- A monthly window is never aligned to a subscription reset and ignores the weekly fallback setting.
- A monthly group shows spend to date, budget, percent, and reset date in the dropdown, can be shown in the bar, and supports thresholds, the same as a weekly group. Percent rounding and over-100% display follow the existing rules.
- Thresholds of a monthly group re-arm when the month rolls over.
- Token-based accounts inside a monthly group report their spend over the group's monthly window, including the per-model breakdown.
- The Unassigned entry keeps the weekly window. Subscription accounts are unaffected.
- Existing configuration files with `weeklyBudgetUSD` keep loading as weekly groups; the default period for new and legacy groups is weekly.
- Settings let the user pick the period next to the budget amount, both when creating a group and when editing one; labels such as "Weekly budget" and "per week" follow the chosen period.
- Switching a group's period takes effect at the next refresh with the newly resolved window.
- Out of scope: pacing markers or pace-based notifications, configurable month-boundary time zone, custom start day of month, having both a weekly and a monthly budget on one group.

## Open Questions

- When a group's period is switched mid-window, should threshold notification state be reset immediately, or treated like a window rollover with a baseline (relates to the inbox item on threshold baseline after reset)?
- Is a monthly window's session-log coverage guaranteed for up to 31 days back (log index retention, first launch mid-month)?
- How should the dropdown phrase the reset date for a monthly group ("resets Nov 1" vs. weekday form used for weekly)?
- Should the configuration writer emit the new `budgetUSD` key immediately on load, or only when the group is next edited?
