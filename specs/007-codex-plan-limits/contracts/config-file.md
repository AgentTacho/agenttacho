# Contract Delta: Configuration File (Codex plan limits)

This extends the configuration contract of spec 006.

```json
{
  "accounts": [
    { "id": "acc-codex", "type": "codexSubscription", "icon": "brands:openai", "displayName": "ChatGPT Plus",
      "harness": "codex", "codexHome": "~/.codex", "customMarker": null,
      "shownInBar": true, "thresholds": [80, 95], "liveLimits": true }
  ]
}
```

## Rules

- `type: "codexSubscription"` now also takes `shownInBar` (default `true`), `thresholds` (default `[]`, each a whole number greater than 0) and `liveLimits` (default `true`). All three are optional on read and always written.
- A spec 006 file (only `codexHome`) decodes with the defaults, so the account appears in the bar (spec FR-017).
- Two `codexSubscription` accounts with the same expanded `codexHome` still fail validation.
- `alignmentAccountId` must still name a Claude `subscription` account; a Codex subscription account is rejected, as today.
- Credentials are never written to this file.
