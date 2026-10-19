# Contract: `timeFormat` in the configuration file

Applies to every object in `accounts` and `groups` of `~/.config/agenttacho/config.json`.

| Stored value | Read as | Load note | Written back on save |
|---|---|---|---|
| key absent | `relative` | none | `"timeFormat": "relative"` |
| `"relative"` | `relative` | none | `"relative"` |
| `"absolute"` | `absolute` | none | `"absolute"` |
| any other string | `relative` | `timeFormat "<value>" is not known, using relative` | `"relative"` |
| `null`, number, object | `relative` | `timeFormat is not readable, using relative` | `"relative"` |

- A load note goes to the diagnostic log; no problem notice is shown and the rest of the file loads (as `levelColor`, spec 012).
- The key is accepted on token-based accounts in a group and kept, though it has no effect there (FR-021).
- Example:

```json
{ "id": "acc-claude", "type": "subscription", "displayName": "Claude Max",
  "credentialDirectory": "~/.claude", "timeFormat": "absolute" }
```
