# Contract: Configuration Keys

## Token-based account with No limit

```json
{
  "id": "acc-free",
  "type": "tokenBased",
  "icon": "solid:gift",
  "displayName": "Free models",
  "harness": "claudeCode",
  "sessionKind": "otherProvider",
  "condition": {"field": "model", "operator": "startsWith", "text": "gateway-a/"},
  "noLimit": {"period": "monthly"},
  "valueAs": "claude-opus-5-5",
  "timeFormat": "relative"
}
```

| Key | Where | Type | Required | Rule |
|---|---|---|---|---|
| `noLimit` | account | object | one of `groupId`, `budget`, `noLimit` | marks the account as No limit (FR-001) |
| `noLimit.period` | `noLimit` | `"weekly"` or `"monthly"` | no | absent means weekly (FR-002) |
| `valueAs` | account | string | no | model id; allowed on every token-based account; effective only with `noLimit` (FR-003) |

## Validation (load and save)

| Configuration | Result |
|---|---|
| exactly one of `groupId`, `budget`, `noLimit` | valid |
| none of them | invalid: the existing message, worded "Account \"<displayName>\" has neither groupId, budget nor noLimit; set exactly one" |
| two or three of them | invalid: "Account \"<displayName>\" has more than one of groupId, budget and noLimit; set exactly one" |
| `noLimit` with `budgetUSD`, `thresholds` or `shownInBar` inside | invalid: "Account \"<displayName>\": No limit has no amount, thresholds or menu bar setting" |
| `noLimit` with an account-level `shownInBar` or `thresholds` | invalid: same message |
| `noLimit.period` not weekly or monthly | invalid: the existing period message |
| `valueAs` naming a model without a price | valid (the dropdown shows the missing-model note) |
| `valueAs` on an account with `budget` or `groupId` | valid, kept, no effect |

Invalid configurations keep the last valid configuration in effect and show the configuration error, as today (spec 001 FR-033).

## Encoding

- `noLimit` is written with its `period` always present.
- `valueAs` is written when set (`encodeIfPresent`); a blank `valueAs` is read as absent. `timeFormat` is written as today.
- A configuration without No limit accounts is written byte for byte as before.
