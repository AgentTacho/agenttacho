# Brainstorm: Unified token accounts

**Date:** 2026-11-03
**Status:** active

## Problem Framing

Spec 041 made "No limit" a third budget choice for token-based accounts, next to own budget and group, as a separate kind of account by type. Brainstorm 42 then tried to cover pay-as-you-go API spend by adding a Priced at choice and a Headline choice to No limit, which overloaded it and was parked.

The maintainer's goal is a streamlined, intuitive Settings UI with few moving parts. Seen from there, an account without a limit is simply an own budget without an amount. With the amount optional, "No limit" disappears as a concept: the picker offers only Own budget and Group, and real-spend tracking for pay-as-you-go accounts falls out of it without a new kind of account.

Stated by the maintainer: streamlined UI, few moving parts; menu bar entries only for accounts with an amount above 0 and priced models; a per-account choice of what the dropdown shows (percent, tokens or money).

## Approaches Considered

### A: One token account, everything derived

Own budget with an optional amount; the dropdown headline is derived (percent with an amount, dollars spent if the models are priced, otherwise tokens).

- Pros: the fewest controls; no display setting to explain.
- Cons: no way to see tokens or money as the headline when the derived rule picks something else.

### B: A plus a per-account Show choice (chosen)

As A, plus a dropdown display choice per account: Automatic, Percent, Tokens or Money. Automatic is the derived rule of A.

- Pros: one kind of token account; the user can override the headline; Automatic keeps the default right when the amount or prices change later.
- Cons: one more control in the account editor; reworks the type split spec 041 just shipped.

### C: Keep spec 041 as it is

No limit stays a separate picker choice; brainstorm 42 stays parked.

- Pros: no rework.
- Cons: nothing gets simpler; pay-as-you-go spend stays uncovered.

### Rejected along the way

- **Amount 0 as "no cap"** (first form of this idea, see brainstorm 42's revisit): "$0" reads as "nothing allowed". The amount field is empty instead, with the placeholder "No limit".
- **An explicit per-account pricing setting** ("own model prices / free"): replaced by deriving it from the price table, one control fewer.

## Decision

Approach B. One kind of token account with an optional amount, pricing derived from the price table, and a per-account Show choice (Automatic, Percent, Tokens, Money) for the dropdown. Supersedes brainstorm 42 and reshapes spec 041's No limit into an own budget without an amount.

## Key Requirements

- **One account kind.** The budget picker of a token-based account offers Own budget and Group. No limit is no longer a choice; an own budget with an empty amount has no limit. The amount field shows the placeholder "No limit" when empty, and saving accepts it.
- **Derived pricing.** Records are priced from the effective price table as today. Value as (spec 041 FR-007) values only the unpriced records. There is no per-account pricing setting.
- **Show choice.** Per account: Automatic (default), Percent, Tokens or Money. Automatic shows percent with an amount, otherwise money if the account's models are priced, otherwise tokens. Percent is unavailable without an amount. The choice affects the dropdown only.
- **Gating.** Thresholds, pace, threshold notifications and the menu bar entry exist only with an amount above 0 and priced models. Their controls are disabled otherwise, not hidden, following the HIG.
- **Real vs. notional.** Real spend ("$37 spent this month") and a Value as amount ("≈ $412 at claude-opus-5-5 prices") never look alike (spec 041 FR-012 wording stays for notional values).
- **Unpriced note.** Records of unpriced models without a Value as model produce the usual "incomplete, unpriced" note when the headline is money, as for an own budget today.
- **Migration.** A configuration with spec 041's `noLimit` loads unchanged as an own budget without an amount, keeping its period and `valueAs`. Spec 041's dropdown section, attribution and demo coverage are reused.
- **Screenshots and website.** Visible change in Settings (picker, optional amount, Show) and in the dropdown (a money headline without a limit). The `no-limit` shot and the "Free models, valued at a real price" card stay valid in content; the plan decides whether their copy changes (constitution V).
- **Out of scope:** groups without an amount; the Show choice in the menu bar; a total across accounts; price aliases for free models.

## Open Questions

- Accounts mixing priced and free models without an amount: does Automatic pick money (with the unpriced note) or tokens, and do real spend and a Value as amount ever appear together?
- What the second line shows for each Show choice (for example tokens under a money headline, the amount under a percent headline).
- Label of the Show choice and its options, and VoiceOver and tooltip wording.
- Whether an accidental empty amount needs a guard, now that empty means no limit (spec 041 FR-018 refused it).
- Settings layout: where the Show choice sits in the account editor, and how the disabled threshold and menu bar controls explain why.
- Configuration shape: an absent `budgetUSD` versus a `noLimit` key on write, and whether the old key is still written.
