# Brainstorm: Open-ended spend for No limit accounts

**Date:** 2026-11-02
**Status:** abandoned (superseded by #43)

## Problem Framing

Spec 041 added No limit accounts for free models (for example the `rits/` models of a company gateway): tokens are the headline, and an optional Value as model adds a notional line such as "≈ $412 at claude-opus-5-5 prices. Nothing was spent".

One case is still missing: **pay-as-you-go API usage without a budget**. The prices are real and the money is really spent, but there is no allowance to measure against. Its user cares about the dollars more than the token count. Today such a user has two poor choices: an own budget with a made-up amount (percentage, colors and pace describe a limit that does not exist), or a No limit account valued as one model, whose wording says "nothing was spent" and which prices every record at that one model.

No concrete setup of the maintainer needs this yet; it is for other users (a direct Anthropic or OpenAI API key, or a router with its own prices).

A second wish came with it: choose per account whether the dropdown headline shows **tokens or money**.

After spec 041 all three cases are one kind of account that differs only in which prices value its tokens:

| Case | Priced at | Meaning |
|---|---|---|
| Free models | a reference model | notional "would cost" |
| Open-ended API | each record's own price | real spend |
| Tracking only | nothing | tokens only |

## Approaches Considered

### A: "Priced at" choice and a Headline choice on No limit accounts (chosen)

The Value as pop-up of a No limit account becomes **Priced at**: None, **Own model prices**, or a reference model. A per-account **Headline** choice (Tokens or Amount) decides the big number; the other measure moves to the second line.

- Pros: one account kind; covers all three cases; reuses spec 041's section, period, attribution, Settings switching and demo coverage.
- Cons: "No limit" does not name an API account on its own; the Settings wording needs care.

### B: Separate "Pay as you go" budget choice

A fourth budget choice next to own budget, group and No limit, for real-spend accounts.

- Pros: a self-explaining label in Settings.
- Cons: two account kinds that differ only in pricing; duplicate validation, switching paths and presentation.

### C: Price aliases for the free models

Give GLM and DeepSeek a price in the price table (aliases to real models, or their public list prices as overrides).

- Pros: per-model "would cost".
- Cons: brainstorm 41 approach B again, rejected for the same reason: notional prices in the price table show as real spend in any account that sees these models, and every model version needs its own entry.

## Decision

Approach A. A No limit account gets a Priced at choice (None, Own model prices, reference model) and a per-account Headline choice (Tokens or Amount). It stays dropdown-only, as in spec 041.

## Key Requirements

- **Priced at.** A No limit account has exactly one of: None (tokens only), Own model prices (each record priced by the effective price table, as for an own budget), or a reference model (spec 041 FR-007, unchanged). This replaces spec 041's Value as setting; a stored Value as model reads as Priced at that model, so existing configurations load unchanged.
- **Real spend wording.** With Own model prices the amount is real spend and is worded as such ("$37 spent this month"), without "≈" and without the "Nothing was spent" tooltip. The reference model wording of spec 041 FR-012 stays for notional values. The two must never look alike.
- **Unpriced models.** With Own model prices, records of unpriced models produce the usual "incomplete, unpriced" note, as for an own budget. With None or a reference model, spec 041 FR-008 holds (no such note).
- **Headline choice.** Per account: Tokens or Amount. The headline shows the chosen measure, the second line the other one, left of the reset text. With Priced at None only Tokens is possible.
- **Defaults.** Own model prices starts with Headline Amount; None and a reference model start with Tokens (as spec 041 shows today).
- **Dropdown only.** No menu bar entry, no thresholds, no threshold notifications, no pace (spec 041 FR-009 unchanged). A user who wants alerts sets an own budget.
- **Details.** Open question below: whether the per-model table and day rows follow the headline measure.
- **Settings.** The No limit editor shows Priced at and Headline; the Headline control is disabled or hidden with Priced at None. Switching between No limit, own budget and group keeps working as in spec 041 FR-018.
- **Screenshots and website.** Visible change in Settings (Priced at, Headline) and in the dropdown (an amount headline on a No limit section). The demo scenario gains a No limit account with Own model prices and Headline Amount; the plan's "Screenshots and website" section decides whether this earns a card candidate together with spec 041 (constitution V).
- **Out of scope:** price aliases for free models (approach C); a menu bar entry or dollar alerts for No limit accounts; a global tokens-or-money switch; a total across accounts.

## Calls Made in This Brainstorm (not discussed, check while reading)

- Real-spend accounts show "incomplete, unpriced" for unpriced models; notional and token-only accounts do not.
- The headline defaults follow the pricing (Own prices: Amount; others: Tokens).
- Spec 041's Value as setting is migrated, not kept beside Priced at.
- Precision of real spend: open question below, since spec 041 rounds notional values to whole dollars on purpose.

## Open Questions

- Settings naming: does "No limit" still fit when the account is an API spend tracker, or should the choice read "No budget" / "Open-ended"? Label for "Own model prices" ("Actual prices", "Each model's price").
- Precision of the real-spend amount: cents (as budgets show) or whole dollars (as spec 041's value line)?
- Do Details (per-model table, day rows, Σ) follow the headline measure, or always show tokens with a dollar column for priced accounts?
- Configuration key shape for Priced at (one key with a sentinel for own prices, or a mode plus a model) and the migration of spec 041's Value as key.
- Does the Accounts list subtitle change for a real-spend account (for example "no limit / month, own prices")?
- VoiceOver and tooltip wording for an amount headline, and how the second line reads with Headline Amount and a reference model ("48.2M tokens" vs. "≈ $412 at … prices" as headline).

---

## Revisit: 2026-11-03

### Updated Problem Framing

Reassessed whether the feature is worth its cost. Approach A turns "No limit" into three things (tokens only, notional value, real spend) plus a Headline switch, and puts notional and real dollars in the same section, the confusion spec 041 worked to avoid. No current user needs it.

### New Approaches Considered

#### D: Own budget with amount 0 as "no cap", plus a percent, tokens or money display choice

- Pros: a priced pay-as-you-go account is conceptually an own budget without a cap; the price table, the unpriced note and the period already work there.
- Cons: 0 already means "no amount entered" and saving refuses it (spec 041 FR-018); "$0 budget" reads as "nothing allowed" (100% at the first token). Percent, pace, thresholds, notifications and the menu bar entry would all need switching off at 0, which rebuilds No limit inside own budget with a magic number. Free models still need No limit for their reference value, so no concept goes away. The display choice is really tokens or money, since percent exists only with an amount.

#### E: "Actual prices" as one more Value as option (minimal fallback)

- Pros: no new account kind, no Headline switch; the second line reads "$37 spent this month" without "≈" and without the "Nothing was spent" tooltip; tokens stay the headline.
- Cons: a dollar-minded user still sees tokens as the big number.

### Updated Decision

Parked: no concrete need, and approach A adds more confusion than value. Approach D is rejected (sentinel amount, duplicated suppression rules). When a real pay-as-you-go user appears, start from approach E, not A.

### Open Threads

- Revisit with approach E when a concrete pay-as-you-go setup appears.

---

## Superseded: 2026-11-03

Brainstorm 43 (unified token accounts) replaces this idea: an own budget with an optional amount, pricing derived from the price table, and a per-account Show choice. Pay-as-you-go spend is covered there.
