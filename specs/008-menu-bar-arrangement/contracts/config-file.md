# Contract: `arrangement` in config.json

Location: `~/.config/llm-usage-menubar/config.json`, top-level key, optional. File `version` stays `1`.

```json
{
  "version": 1,
  "accounts": [ ... ],
  "groups": [ ... ],
  "arrangement": {
    "entries": [
      { "kind": "group", "id": "grp-vertex" },
      { "kind": "account", "id": "DD73C467-E970-44DE-9342-263613EFA73A" },
      { "kind": "account", "id": "F42D727A-79A4-42B1-938D-78D53512FE3A" }
    ],
    "members": {
      "grp-vertex": ["acc-opencode-vertex", "acc-vertex"]
    }
  }
}
```

Rules:

- `kind` is `"account"` or `"group"`. Unknown kinds, unknown ids, references whose account is not an entry, duplicates after the first, and member ids not belonging to the keyed group are ignored when reading (FR-011). None of them makes the file invalid.
- `entries` and `members` may each be missing or empty; missing items are appended in default order (FR-011).
- The key is absent until a change affects the order (FR-004, FR-004a). Loading a file never adds it.
- When written, `entries` lists every entry and `members` every group with all its members, in the current order.
- Older AgentMeter versions ignore the key on read and drop it on their next save; the order then falls back to the default.
