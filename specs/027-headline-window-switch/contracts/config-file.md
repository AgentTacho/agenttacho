# Contract: `headlineWindow` in the configuration file

Delta to `specs/004-icon-labels-standalone-budgets/contracts/config-file.md` and spec 007's Codex account fields.

| Account type | Field | Values | Absent |
|---|---|---|---|
| `subscription` | `headlineWindow` | `"fiveHour"`, `"sevenDay"`, `"model:<model name>"` | default window (7-day) |
| `codexSubscription` | `headlineWindow` | `"window:<N>-hour"`, `"window:<N>-day"`, `"window:weekly"` | default window (longest) |
| `tokenBased` | none | | |

```json
{ "id": "acc-max", "type": "subscription", "icon": "brands:claude", "displayName": "Claude Max",
  "credentialDirectory": "~/.claude", "shownInBar": true, "thresholds": [80, 100],
  "headlineWindow": "fiveHour" }
```

- Written only when set; a click on the default row removes it.
- Model names match the dropdown's name exactly, including case.
- Invalid value, a value of the other account type, an empty model name, a non-string or `null`: ignored (default window), one diagnostic log line, the file stays valid; the next save drops it.
- A `headlineWindow` on a `tokenBased` account is ignored like any unknown key.
- Changing it never triggers a refresh (presentation only).
