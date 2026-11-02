# Contract: headlineWindow values and last-good.json

Deltas to spec 027 `contracts/config-file.md` and spec 010 `contracts/last-good-file.md`.

## headlineWindow (Claude subscription accounts)

| Value | Window | Since |
|---|---|---|
| absent | default window (spec FR-009) | 027 |
| `fiveHour` | first plan window of a 5-hour group | 027 |
| `sevenDay` | `weekly_all`, else first plan window of the `weekly` group | 027 |
| `model:<name>` | the model's first weekly limit (else first limit) | 027 |
| `model:<name>:<kind>` | a further limit of that model | 040 |
| `limit:<kind>` | another plan window, by kind (by group when it has no kind) | 040 |

A value naming a window that is not in the latest values resolves to the default window and stays stored. Codex values (`window:<name>`) are unchanged. The previous version ignores the two new forms and drops them on its next save.

## last-good.json, Claude entry (version 1)

```json
"<account id>": {
  "credentialDirectory": "/Users/me/.claude",
  "fetchedAt": "2026-11-02T06:34:18.354Z",
  "windows": [
    { "identity": "sevenDay", "kind": "weekly_all", "group": "weekly", "lengthSeconds": 604800, "name": "7-day",
      "utilizationPercent": 11, "resetsAt": "2026-11-06T07:00:00.000Z" },
    { "identity": "model:Fable", "kind": "weekly_scoped", "group": "weekly", "lengthSeconds": 604800, "name": "Fable",
      "modelName": "Fable", "utilizationPercent": 15, "resetsAt": "2026-11-06T07:00:00.000Z", "allowancePercentOfWeekly": 50 }
  ],
  "sevenDay": { "utilizationPercent": 11, "resetsAt": "2026-11-06T07:00:00.000Z" },
  "modelLimits": [ { "modelName": "Fable", "utilizationPercent": 15, "resetsAt": "2026-11-06T07:00:00.000Z", "allowancePercentOfWeekly": 50 } ]
}
```

- `windows` wins when present; without it the legacy keys are read (old files).
- Legacy keys are written for the identities `fiveHour`, `sevenDay` and the `model:<name>` limits, so the previous version reads them after a downgrade.
- `version` stays 1.
- "Never in the file" gains: kind and group strings from the answer are allowed, as model names are.
