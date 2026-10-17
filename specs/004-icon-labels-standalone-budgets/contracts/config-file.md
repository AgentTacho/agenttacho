# Contract Delta: Configuration File (icons, token-based budgets)

This extends `specs/001-agenttacho/contracts/config-file.md` and `specs/003-monthly-budget-period/contracts/config-file.md`.

## Written by the app

```json
"accounts": [
  { "id": "acc-max", "type": "subscription", "icon": "brands:claude", "displayName": "Claude Max",
    "harness": "claudeCode", "credentialDirectory": "~/.claude", "shownInBar": true, "thresholds": [80, 100] },
  { "id": "acc-team", "type": "tokenBased", "icon": "brands:google", "displayName": "Team Vertex",
    "harness": "claudeCode", "provider": "vertex", "groupId": "grp-team", "shownInBar": true, "customMarker": null },
  { "id": "acc-own", "type": "tokenBased", "icon": "brands:google", "displayName": "Personal Vertex",
    "harness": "claudeCode", "provider": "vertex", "customMarker": null,
    "budget": { "period": "monthly", "budgetUSD": 100, "shownInBar": true, "thresholds": [80, 100] } }
],
"groups": [
  { "id": "grp-team", "name": "Team", "icon": "solid:wallet", "period": "monthly", "budgetUSD": 300,
    "shownInBar": true, "thresholds": [80, 100] }
]
```

No entry contains `label`.

## Decoding rules

| Situation | Result |
|-----------|--------|
| `label` present | ignored |
| `icon` absent, `null`, or `""` | type default (`brands:claude` for subscriptions, `brands:google` for Vertex, `solid:wallet` for groups) |
| `icon` not in the catalog | validation error (config rejected, last valid config kept) |
| token-based: `groupId` present, `budget` absent | group member; `shownInBar` defaults to `false` |
| token-based: `budget` present, `groupId` absent | own budget |
| token-based: both present | **decode error** |
| token-based: neither present | **decode error** |
| `budget.period` absent | weekly |
| `budget.period` `null`, unknown, or not a string | **decode error** |
| `budget.budgetUSD` absent | **decode error** |
| `budget.budgetUSD` ≤ 0 | validation error naming the period |
| a `budget.thresholds` value ≤ 0 | validation error (existing threshold message, naming the account) |
| `budget.shownInBar` absent | `true` |
| `budget.thresholds` absent | `[]` |

Group rules from spec 003 are unchanged.

## Encoding rules

- Every account and group is written with `icon`. `label` is never written.
- A member writes `groupId` and `shownInBar`. A standalone account writes `budget` and no `groupId`.
- Loading a legacy file does not rewrite it. The new form appears on the next save from settings.
