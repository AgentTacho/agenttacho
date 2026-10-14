# Contract Delta: Configuration File (harnesses)

This extends the configuration contracts of specs 001, 003 and 004.

```json
{
  "logDirectories": [],
  "codexHomes": ["~/.codex-work"],
  "openCodeDirectories": [],
  "accounts": [
    { "id": "acc-oai", "type": "tokenBased", "icon": "brands:openai", "displayName": "OpenAI API",
      "harness": "claudeCode", "provider": "openai", "customMarker": null,
      "budget": { "period": "monthly", "budgetUSD": 50, "shownInBar": true, "thresholds": [80, 100] } },
    { "id": "acc-codex", "type": "codexSubscription", "icon": "brands:openai", "displayName": "ChatGPT Plus",
      "harness": "codex", "codexHome": "~/.codex", "customMarker": null }
  ]
}
```

## Rules

- `codexHomes` and `openCodeDirectories` are optional. When either is absent it means `[]`. The default locations `~/.codex` and `~/.local/share/opencode` are always read.
- `provider` accepts `"vertex"` and `"openai"`. Any other value is a decode error, as it is today.
- `type: "codexSubscription"` takes `codexHome`, which is optional and defaults to `"~/.codex"`, plus `icon`, `displayName`, and `customMarker`. It has no `shownInBar`, no `thresholds`, and no `budget`. Unknown keys are ignored.
- Two `codexSubscription` accounts with the same expanded `codexHome` fail validation.
- `harness` is still accepted on every account and still written, but attribution no longer reads it. It accepts `"claudeCode"`, `"codex"` and `"openCode"`.
- Files written by the previous version decode unchanged.
