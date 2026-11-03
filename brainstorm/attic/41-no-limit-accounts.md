# Brainstorm: Accounts without a limit

**Date:** 2026-11-02
**Status:** active

## Problem Framing

The maintainer uses EnMaaS, Red Hat's intranet model gateway, through the cc-deck profile `enmaas`. It offers two kinds of models:

- **Open-weight models** such as `rits/zai-org/glm-5-3` and `rits/deepseek-ai/DeepSeek-V4.1-Flash-1017`. All share the `rits/` prefix, have no budget and no price: use as many tokens as you like.
- **Anthropic and OpenAI models**, which count against a monthly allowance of 300 US$.

Both come on top of the Claude subscription. The maintainer wants two accounts for EnMaaS: one for the free `rits/` models and one for the paid models with its 300 US$ budget.

The paid side needs nothing new: a token-based account with its own monthly budget (spec 004) and a session kind with a condition (spec 038) already cover it. The open question is the free side. Today every token-based account must have an own budget or belong to a group (spec 004 FR-008), its section shows US dollars, and unpriced models mark it "incomplete, unpriced: …" (idea inbox `unpriced-model-accounts`). A made-up limit such as 1,000 US$ would give a percentage, threshold colors and a pace meter that all claim a limit that does not exist.

What the maintainer wants to learn from a glance at the free account:

- **How much I use it**: token volume in the period.
- **What it saves me**: what the same tokens would have cost with a real model, for example "would have cost that much with Claude Opus 5.5".

Not wanted: a menu bar entry, a comparison against the own usual week.

Seen in the logs (2026-11-02): sessions that used `rits/` models hold 9,846 `rits/zai-org/glm-5-3` records and 870 `claude-opus-5-5` records with `msg_` ids. Whether those Claude records went through the EnMaaS gateway (paid budget) or Vertex is not yet known.

## Approaches Considered

### A: "No limit" account with a "Value as" reference model (chosen)

A third budget choice for token-based accounts next to "Own budget" and "Group": **No limit**. An optional **Value as** picks one model from the price table; all of the account's tokens are valued at that model's prices.

- Pros: honest (no percentage, no colors, no pace); answers both questions; one setting per account; notional prices stay out of the price table, so no other account can show them as real spend.
- Cons: one reference model per account is coarse when the account mixes a small and a large model.

### B: Price aliases in the price table

Each `rits/` model is mapped to a real model ("GLM priced as Sonnet", "DeepSeek Flash priced as Haiku"), plus a No limit account.

- Pros: finer value per model.
- Cons: notional prices live next to real ones; any account that ever sees these models shows the made-up cost as real spend; one mapping per model version to maintain (`DeepSeek-V4.1-Flash-1017` changes with each release).

### C: Artificial limit

An own budget of 1,000 US$ plus price overrides for the `rits/` models. Works today.

- Pros: no new feature.
- Cons: the percentage, threshold colors, notifications and pace meter all describe a limit that does not exist.

## Decision

Approach A. The free EnMaaS account becomes a No limit account valued as Claude Opus 5.5; the paid EnMaaS account stays a normal account with an own monthly budget of 300 US$.

## Key Requirements

- **Budget choice.** A token-based account has exactly one of: own budget, group membership, or **No limit** (changes spec 004 FR-008). A No limit account keeps a period (weekly or monthly, as for budgets) that sets the window its usage is counted in, but has no amount.
- **No menu bar entry.** A No limit account never appears in the menu bar and has no thresholds, no threshold notifications and no pace meter (extends spec 011 FR-011).
- **Dropdown section.** Its section shows the tokens of the period as the headline, like a subscription or Unassigned shows tokens. With a Value as model it adds a value line such as "≈ 412 US$ at Claude Opus 5.5 prices", worded as a value, never as spend. Day rows and Σ show tokens.
- **Value as.** Optional, one model from the effective price table (built-in, imported or override). All four token kinds (input, output, cache write, cache read) are valued at that model's rates, whatever model the records name. Without a Value as model the section shows tokens only and never shows "incomplete, unpriced".
- **Value as model gone.** When the chosen model leaves the price table (an import removed it), the value line is replaced by a neutral note naming the missing model; the tokens still show.
- **No groups.** A No limit account cannot be a group member, since a group is a shared budget.
- **Attribution unchanged.** The two EnMaaS accounts both name the `enmaas` directory; a directory claimed by several accounts falls through to the session kinds and conditions (spec 037, spec 038). Free account: "Other provider", only when Model starts with `rits/`. Paid account: "Other provider" with a condition that selects the Anthropic and OpenAI models (see open questions).
- **Screenshots and website.** Visible change in Settings (budget choice, Value as) and in the dropdown (a section without a bar). The demo scenario gains a No limit account valued as a built-in model; the plan's "Screenshots and website" section decides whether this earns a card candidate (constitution V).
- **Out of scope:** price aliases per model (approach B); a menu bar entry for No limit accounts; comparing against the own usual week; quarterly, yearly or one-time budgets.

## Calls Made in This Brainstorm (not discussed, check while reading)

- One Value as model per account, not per model in the account.
- The period of a No limit account reuses the budget period settings (weekly or monthly, with their start day).
- Tokens are the headline, the value is the second line; not the other way round.
- A No limit account cannot join a group.

## Open Questions

- Which model ids and request ids do paid EnMaaS records (Anthropic and OpenAI through the gateway) carry? Do they lack an Anthropic request id, so "Other provider" catches them, and which condition separates them from Vertex records in the same profile (for example Model matches `^(claude|gpt)`)? Check real records before the spec fixes it.
- Should a "worth" sum also appear across accounts (for example the total value of all No limit accounts), or stay per account?
- Wording of the value line and its tooltip ("≈", "worth", "would have cost"), and how the Settings section names the choice ("No limit", "Unlimited", "Free").
- Does the Unassigned hint or the Accounts list need to mark No limit accounts so their missing bar entry is not mistaken for an error?
