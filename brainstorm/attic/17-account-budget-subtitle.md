# Brainstorm: Account Budget Subtitle

**Date:** 2026-10-16
**Status:** active

## Problem Framing

In Settings > Accounts, the list subtitle of a token-based account says only "token-based (Vertex)", the provider (idea inbox item `accounts-list-budget-subtitle`, found in the spec 009 walkthrough). Since explicit group management, groups can stay empty and accounts move between groups, but the list does not show where an account's spend counts. The user has to select each account to see its budget.

It is planned as the 0.4.1 release, which also serves as the first end-to-end test of the one-click update from 0.4.0 (spec 013).

## Approaches Considered

### A: Provider and budget only ("Vertex · group Vertex")
- Pros: shortest line.
- Cons: the amount and period still need a click.

### B: Provider, budget, period and amount (chosen)
- Pros: one glance answers where the spend counts and how large that budget is.
- Cons: longer line; a long group name can truncate in the narrow list.

### C: Formatting from the dropdown ("400 US$/month") or the current Groups list ("$400.00 per month")
- Pros: reuses existing strings.
- Cons: the two Settings lists would keep two different amount styles; the user wants one compact style.

## Decision

Approach B, with one shared amount style for both Settings lists:

- Accounts list subtitle of a token-based account: provider, a middle dot, then the budget, then the amount and period. In a group: the group's icon and name as the Budget picker shows them, for example "Vertex · [wallet] Vertex, $400 / month". With its own budget: "OpenAI · own budget, $50 / week".
- Groups list subtitle changes to the same amount style: "$400 / month, 2 member(s)" instead of "$400.00 per month, 2 member(s)".
- Amount style: currency, whole dollars when the amount is whole, cents only when it has cents ("$99.50 / month"); " / month" or " / week" after it. Currency symbol and grouping follow the locale, as elsewhere in the app.

## Key Requirements

- The subtitle follows the Settings draft, so it changes while the user edits a budget, a group name or icon, or moves the account, before saving.
- A token-based account whose group id points at no existing group (only possible by hand-editing) says so instead of showing an empty name, for example "Vertex · no group".
- Subscription accounts keep their subtitles ("Claude subscription", "ChatGPT subscription").
- The text is built by a tested `UsageCore` formatter, not inline in the view (AGENTS.md); the Groups list uses the same amount formatter.
- No configuration, network or credential change; README only if it describes these subtitles.

## Open Questions

- Exact text for an account in a missing group ("no group" or the dangling id).
- Whether the group's icon renders as the same glyph in a subtitle's caption font as in the picker, and what to show for a group without an icon.
- Whether VoiceOver should read the icon name or skip it in the subtitle.
