# Brainstorm: Budget groups without an amount

**Date:** 2026-11-10
**Status:** active

## Problem Framing

Spec 043 made the amount of an own budget optional: a token-based account without an amount has no limit and shows its real spend, its tokens, or an estimate at a reference model's prices. Budget groups still always need an amount (spec 003 FR-001, restated in spec 043 FR-002), and spec 043 named "groups without an amount and a Show choice for groups" as out of scope.

That leaves a gap for free models used from more than one harness. The maintainer's own setup (aprofile profiles for GLM and DeepSeek through EnMaaS, private and work, each for Claude Code and Codex) needs one token-based account per harness, because one account reads one harness. Without a no-amount group, the free models show as two dropdown sections, "Free models (Claude Code)" and "Free models (Codex)", where one section with both as members is wanted. The only workaround today is a group with a fake amount (for example 100,000 USD), which shows a meaningless "$93 of $100,000/month", a 0% bar and a pace tick.

Success: a budget group with an empty amount shows one section with the combined spend (or tokens) of its members, each member listed with its own spend, and nothing that suggests a limit.

Non-goals and anti-goals:
- No new kind of grouping next to budget groups (two concepts that look alike would confuse).
- No merge of own budgets and groups into one concept.
- No rule about which accounts may share a group.
- A no-amount group must never notify, never show a percent, and never take a menu bar entry, as with a no-amount account.

## Approaches Considered

### A: Groups mirror spec 043
The group's `budgetUSD` becomes optional; groups gain `valueAs` and `show` with the same meaning as on an account with its own budget. The spec 043 rules (headline choice, Details, the "≈ $X at … prices" line, "incomplete, unpriced" note) apply to a group as a whole.
- Pros: small, additive change to the configuration file (optional keys only, old files load unchanged, no migration); reuses settled 043 behavior; users meet the same "No limit" placeholder in both editors.
- Cons: the no-amount rules now live in two places (accounts and groups); the implementation should share them rather than duplicate them.

### B: One budget concept (own budget = group of one)
Merge own budgets and groups so every budget setting lives in one place.
- Pros: cleanest long-term model.
- Cons: file format change and migration, reworked account and group editors, undoes the "Own budget" choice spec 043 just settled; far bigger than the problem.

### C: Display-only section
A new arrangement element that sums its members without any budget semantics.
- Pros: budget groups stay untouched.
- Cons: a second grouping concept next to budget groups, a new editor, against the HIG preference for one standard pattern.

## Decision

Approach A, chosen by the maintainer on 2026-11-10.

## Key Requirements

Stated by the maintainer:
- A budget group's amount is optional. A group without an amount has no limit: no percent, bar, pace tick, thresholds, notifications or menu bar entry.
- Groups get the account settings of spec 043: "Price tokens as" (`valueAs`) and "Dropdown shows" (`show`), with the same meaning, applied to the group's combined records.

Proposed during the session and accepted by the maintainer:
- Member rows under a group without an amount show each member's spend (or tokens under a token headline), without the share percent, which needs an amount.
- Member shares in the menu bar (a member shown on its own as a percent of the group budget) are off without an amount: kept, disabled, and active again once an amount is entered, like an account's thresholds and "Show in menu bar" in spec 043.
- An account that leaves a no-amount group for its own budget is prefilled from the group as today (spec 004 FR-014), which here means an own budget without an amount.
- No rule about which accounts share a group. "Free" and "paid" are properties of records (priced or not), not of accounts; spec 043 already handles priced and unpriced records side by side, and a group does the same across its members. Putting a paid account into a no-limit group is a legitimate choice for watching its spend.
- Settings: Groups > Add and the group editor accept an empty amount with the placeholder "No limit", and the Menu Bar tab captions such a group "No limit" with a disabled "Show in bar", as for accounts.
- Configuration: an absent `budgetUSD` or `null` means no amount, a present amount must be greater than 0, and `show: "automatic"` is not written, all as in spec 043.

My calls (proposals with reasons, open for the spec):
- Adding a group in Settings keeps today's defaults (weekly, 60 USD). Reason: a new group is more often a shared cap; the amount can be cleared in the editor.
- Removing a no-amount group that still has members and moving them "each to its own budget with the group's settings" gives each an own budget without an amount. Reason: follows the existing prefill rule.
- The group's `valueAs` values the unpriced records of all members; a member's own `valueAs` is kept but has no effect while it is in a group (as spec 043 already says for group members).
- Visible UI change: the demo scenario (`Resources/demo/default.json`) gets a no-limit group with a Claude Code and a Codex member, so the screenshots can show it (AGENTS.md, constitution V). Whether it earns a landing page card candidate is for the plan.

## Open Questions
- Group headline under Automatic when some members have priced records and others only tokens: real spend plus the "≈" line, as for one account, or a per-member mix?
- Details of a no-amount group: does "Show account details" follow the group's headline (cost per model under Money, tokens under Tokens) for every member?
- Notifications and threshold state when an amount is removed from a group with a baseline, and the first refresh after an amount is entered again (spec 043 sets a baseline without notifying; confirm the same for groups).
- Whether the per-refresh aggregation cost (inbox `single-pass-no-amount-aggregation`) should be addressed together, since a no-amount group adds another breakdown per refresh.
- Website copy: the "Shared budgets" wording in the README and the site may need "with or without a limit".
