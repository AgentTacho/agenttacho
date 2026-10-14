# Brainstorm: Icon Labels and Standalone Budgets

**Date:** 2026-10-14
**Status:** active

## Problem Framing

Today every account and budget group carries a 1 to 3 character text label plus an optional Font Awesome icon. Whatever is shown (the icon, else the text) must be unique across all accounts and groups. Every token-based account must belong to exactly one budget group, and only subscription accounts and groups can appear in the menu bar.

In practice this is too rigid:
- Text labels are redundant once icons exist.
- The uniqueness rule blocks natural choices, such as the Claude icon for several Claude Code accounts.
- A single token-based account with its own budget needs an artificial one-member group.
- A group member cannot be watched on its own in the bar.

The goal is to simplify labelling and loosen the account/budget structure without losing any existing configuration.

## Approaches Considered

### A: Shared budget block on the account
The group's budget fields (period, amount, thresholds, show-in-bar) become one reusable budget definition. A token-based account has either a group membership or its own budget, never both.
- Pros: honest data model and a readable config file; a standalone account is first-class in the dropdown, the bar, and notifications.
- Cons: aggregation, thresholds, and the bar need a second budget-carrying entity type besides groups.

### B: Hidden one-member group
"Own budget" in settings silently creates a group containing only this account and hides it in the UI.
- Pros: almost no aggregation changes.
- Cons: invisible groups in the config file; removing or moving accounts and label rules get fiddly; surprising for hand edits.

### C: Keep groups mandatory, smooth the UI
Only make one-member groups painless to create and display.
- Pros: smallest change.
- Cons: does not deliver accounts without a group; the group still appears as an extra level in the dropdown.

## Decision

Approach A.

**Labels:** text labels are removed and every account and group has exactly one required icon, with a default by type or provider. Icons may repeat.

**Standalone accounts:** a token-based account may stand alone with its own budget that behaves exactly like a group's. It can be moved into a group later and back out.

**Members in the bar:** a group member can also be shown individually in the bar as its share of the group's budget.

## Key Requirements

Labels:
- Every account and group has exactly one icon from the bundled catalog; "no icon" is not allowed and the text label is removed.
- Default icon for new entries: subscription account `brands:claude`, Vertex token-based account `brands:google`, group `solid:wallet`. The user can change it in settings.
- The same icon may be used by several accounts and groups; the uniqueness rule on labels is dropped. The dropdown and settings show icon plus name.
- Existing configurations load unchanged in meaning. An entry without an icon gets the default icon for its type, and a stored text label is ignored. The next save writes the new form without the `label` key.

Standalone token-based accounts:
- A token-based account belongs to a group or has its own budget, exactly one of the two.
- The own budget has the same settings and behaviour as a group budget: period (weekly or monthly), amount, thresholds and notifications, show-in-bar, dropdown summary with spend, percent, reset, and breakdown.
- Settings let the user move an account between "own budget" and a group in both directions. Removing the last member of a group still deletes the group.

Group members in the bar:
- A token-based account in a group gets its own show-in-bar toggle (default off).
- Its bar entry shows the account's spend in the group's window as a percent of the group's budget (existing rounding and over-100% rules). It colors by the group's warning threshold and sends no notifications of its own.
- In the bar, a member's entry follows its group's entry, or stands alone if the group itself is not shown.

Out of scope:
- Per-member sub-budgets inside a group.
- Text labels as a fallback.
- Changes to subscription accounts beyond the icon rule.

## Open Questions

- Should the bar visually separate duplicate icons (for example a subtle index), or is the ordering plus the dropdown enough?
- Config format for an account's own budget: nested budget object or flat fields like groups have today?
- Should a standalone account's thresholds and threshold state carry over when it is moved into a group (and the group's when moved out), or reset?
- Does the Unassigned entry need an icon now that labels are icon-only?
