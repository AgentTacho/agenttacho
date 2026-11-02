# Quickstart: Accounts without a Limit

## Prerequisites

- Checkout of branch `041-no-limit-accounts`.
- `make test` passes on the branch.

## Automated validation

```bash
make test           # core suites of research R10 and DefaultScenarioTests
make test-release   # scripts unchanged, must stay green
```

Expected: all suites pass; `ReferenceValueTests` pins the hand-computed value (SC-003), `NoLimitTransitionTests` covers all six switch paths (SC-004).

## Demo walkthrough

```bash
make app-demo && open .build/AgentTacho-demo.app   # path as printed by make
```

1. Open the dropdown. After the existing sections, "Free models" shows a token headline (no percent), "tokens this month" with the reset text, and "≈ $<n> at <model> prices". No bar, no pace note, no "incomplete" note.
2. The menu bar shows the same four entries as before; none for "Free models".
3. Settings > Accounts: "Free models" reads "Other provider · no limit / month". Its editor shows Period, Value as and Times, and no amount, thresholds or "Show in menu bar".
4. Set Value as to "None": the value line disappears, tokens remain.
5. Switch the budget to "Own budget": Apply is refused until an amount above 0 is entered. Enter 50: the account appears in the menu bar with a percent.
6. Switch back to "No limit": the bar entry goes away; Value as is restored.
7. Settings > Menu Bar: the "Free models" row says "No limit" and has no checkbox.

## Hand-edited configuration checks

| Edit to `config.json` | Expected |
|---|---|
| add `"budget": {...}` to the No limit account | configuration error naming the account, last valid configuration stays |
| add `"thresholds": [80]` inside `noLimit` | configuration error "No limit has no amount, thresholds or menu bar setting" |
| set `"valueAs": "gateway-x/unknown"` | valid; section note "Value as model gateway-x/unknown has no price" |
| remove `period` from `noLimit` | valid; section shows "tokens this week" |
