# Research: Unified Token Accounts

Decisions for spec 043. Each names the requirement it serves.

## R1: Keep the `.noLimit` case internally as "own budget without an amount"

- **Decision**: `TokenMembership` keeps its three cases. `.noLimit(NoLimitSettings)` now means an own budget without an amount (FR-002). `NoLimitSettings` gains `thresholds` and `shownInBar`, kept and inert while there is no amount (FR-003). Entering an amount turns the membership into `.ownBudget(BudgetSettings)` with the same period, thresholds and shown-in-bar; clearing it turns it back. The user sees one "Own budget" choice; the split is internal.
- **Rationale**: every budget consumer (`budgetOwners`, `BarLayout`, `ThresholdTracker`, pace, burn rate, `GroupEntry`) relies on a non-optional `budgetUSD`. Keeping amount-less accounts in their own case keeps the compiler checking that none of them ever sees a missing amount, and reuses spec 041's exclusions without new code (FR-008). Threshold state is dropped and re-baselined by the existing owner-set logic (FR-009, spec 041 FR-019).
- **Alternatives**: `BudgetSettings.budgetUSD: Decimal?` (rejected: optional amount ripples through every budget path and group budgets, which must keep an amount, FR-002); a 0 sentinel (rejected in brainstorm 43).

## R2: Configuration form

- **Decision**: an own budget without an amount is written as `"budget": {"period": ..., "shownInBar": ..., "thresholds": [...]}` without `budgetUSD`. On read, a `budget` object whose `budgetUSD` is absent or `null` decodes to `.noLimit` (FR-002, FR-004). A stored `budgetUSD` of 0 or less stays invalid through the existing validation (spec 003 FR-019). The spec 041 form `"noLimit": {"period": ...}` still decodes, with thresholds `[80, 100]` and shown in bar `true` (FR-004); its forbidden keys stay forbidden. `budget` and `noLimit` together stay invalid (one budget choice). `noLimit` is never written again. Group budgets keep requiring `budgetUSD` (validated where groups decode).
- **Rationale**: the file then says what the UI says: one own budget, amount optional. Old files load unchanged; invalid old files stay invalid (edge cases).
- **Alternatives**: keep writing `noLimit` (rejected: the file would keep a concept the UI dropped); `"budgetUSD": null` on write (rejected: absent is shorter, and null is accepted on read anyway).

## R3: The Show setting

- **Decision**: new enum `DropdownShow { automatic, percent, tokens, money }` stored on `TokenBasedSettings.show` for every token-based account (kept in a group, FR-018a), account-level key `"show"`, written only when not Automatic, absent means Automatic, an unknown value gives a load note and Automatic (like `timeFormat`). `DropdownShow.resolve(hasAmount:hasPricedUsage:) -> HeadlineMeasure` (`percent`, `tokens`, `money`) implements FR-011 and FR-012. `dataRelevant()` masks it (FR-010: no refresh).
- **Rationale**: one pure function decides the headline everywhere (dropdown, demo coverage, tests).
- **Alternatives**: store it inside the budget objects (rejected: it must survive group membership, FR-018a).

## R4: Snapshot data for an account without an amount

- **Decision**: the aggregator builds the No limit entry from a priced breakdown (per-model `costUSD` and `priced`, as own budgets get), and `NoLimitEntry` gains `spentUSD` (sum of priced records), `hasPricedUsage` and `unpricedModels`. `tokenAccounts` keeps its unpriced token entry.
- **Rationale**: Money headline (FR-013), Automatic (FR-011), the unpriced note (FR-007) and cost Details (FR-014) all need costs; the existing breakdown already carries them per model.
- **Alternatives**: price at presentation time (rejected: records are priced once at refresh; repricing in the view would duplicate spec 006 logic).

## R5: Value as values only unpriced models

- **Decision**: `ReferenceValue.make` gets the breakdown's unpriced per-model rows only (`!priced`). With a Value as model it always returns `.value` (also 0, so "≈ $0" shows, FR-014) or `.missing` (FR-007 last sentence). The value tooltip gains a variant for accounts that also have priced usage (FR-015).
- **Rationale**: the aggregator keeps a per-model breakdown of only the records without a price (`NoLimitEntry.unpricedUsage`), so Value as values exactly the unpriced records, also when one model has both kinds (FR-006, review-plan advisory).

## R6: Headline texts in core

- **Decision**: new `HeadlineText` (UsageCore/Dropdown) produces headline, tooltip and accessibility text for each `HeadlineMeasure`, for both section kinds:
  - Percent: `DirectedPercent` as today.
  - Tokens: `CompactFormat.tokens`, tooltip "48,213,507 tokens this month", spoken "48.2 million tokens this month".
  - Money: whole dollars rounded half up via `BudgetAmountFormatter.wholeAmount` ("$37", "$0", "<$1"); in remaining mode on an account with an amount, the amount left ("$63") or over with a typographic minus ("−$12"), tooltip and spoken text like the amount line ("$62.58 left of $100/month", "$12.40 over $100/month"); otherwise "$37.42 spent this month".
  `NoLimitPresentation` takes the resolved measure and uses `HeadlineText`; `BudgetSection` gets its header text from `HeadlineText` instead of `DirectedPercent` directly (FR-013, FR-016).
- **Rationale**: one tested source for every headline string (constitution II).

## R7: Settings editor as one form

- **Decision**: new core type `OwnBudgetForm` (period, `amount: Decimal?`, thresholds, shownInBar) built from `.ownBudget` or `.noLimit` and turned back into the matching membership (`membership`), so the editor binds one form and the case flips when the amount field is filled or emptied (FR-018, FR-019). The budget picker shows "Own budget" for both cases and no "No limit" (FR-017). `NewAccountSheet` defaults to an own budget without an amount. `movingAccountToNoLimit` is removed (no UI path); `movingAccountToOwnBudget` keeps today's group prefill (FR-019). Disabled controls carry `.help` texts from [contracts/ui-strings.md](contracts/ui-strings.md).
- **Rationale**: the view stays thin and the case flip is tested in core.

## R8: Menu Bar tab

- **Decision**: the Menu Bar tab lists an account without an amount with a disabled "Show in bar" checkbox and a help text, caption "No limit" (FR-020, `Arrangement.budgetCaption` already returns it).

## R9: Demo and tests

- **Decision**: `Resources/demo/default.json` writes `acc-free` in the new form (`budget` without `budgetUSD`) and adds `acc-api` ("API key", icon `solid:key`, Claude Code, session kind Other provider, its own Claude Code directory `~/.claude-api`) as a monthly own budget without an amount, arranged after `acc-free`. The demo's `usage` list names records by account id, so `acc-api` gets a few records of a built-in priced Claude model this month without touching any other section. Coverage: Money headline for `acc-api`, Tokens headline and value line for `acc-free`, no bar entry for either; `shotNoLimitAccountId` still returns `acc-free` (first account without an amount in arrangement order). A legacy fixture with `noLimit` stays in `NoLimitConfigurationTests`.
