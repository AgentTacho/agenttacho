# Contract: Claude usage endpoint, window fields

Delta to spec 001 `contracts/external-sources.md`. The request is unchanged: `GET https://api.anthropic.com/api/oauth/usage` with the OAuth bearer token and `anthropic-beta: oauth-2025-04-20`.

## Fields read

```json
{
  "five_hour": null,
  "seven_day": { "utilization": 11.0, "resets_at": "2026-11-06T07:00:00.000Z" },
  "limits": [
    { "kind": "weekly_all", "group": "weekly", "percent": 11, "severity": "normal",
      "resets_at": "2026-11-06T07:00:00.000Z", "scope": null, "is_active": false },
    { "kind": "weekly_scoped", "group": "weekly", "percent": 15, "severity": "normal",
      "resets_at": "2026-11-06T07:00:00.000Z",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": true }
  ],
  "weekly_scoped_shares": [ { "limit_index": 1, "allowance_percent_of_weekly": 50 } ]
}
```

(Values illustrative; shape observed 2026-11-02.)

| Field | Use |
|---|---|
| `limits[].kind` | identity part, log, name fallback |
| `limits[].group` | length and name (spec FR-003), log |
| `limits[].percent` | utilization; entry skipped without it |
| `limits[].resets_at` | reset; null means not started; unreadable means entry skipped |
| `limits[].scope.model.display_name` | model limit name; empty or missing with a model object means skipped |
| `limits[].scope.surface` | non-null with no model: entry skipped, logged |
| `limits[].severity`, `limits[].is_active` | decoded leniently, not used (FR-013) |
| `weekly_scoped_shares[].limit_index` | index into the raw `limits` array, allowance of that model limit |
| `five_hour`, `seven_day` | fallback only (FR-002), decoded leniently |

Every other key (`spend`, `extra_usage`, `seven_day_breakdown`, codenamed keys) is ignored. An unreadable `limits` entry never fails the answer; an unreadable top-level object never fails the answer.

## Log lines

- On the first successful fetch and on every change of the window set: `[subscription] <account id>: windows weekly_all/weekly/none, weekly_scoped/weekly/model:Fable (limits)`; `(fallback)` when FR-002 applied; skipped entries as `<kind>/<group>/<scope> skipped`.
- Summary per fetch: `<account id>=ok(7-day 11%, Fable 15%)`.
