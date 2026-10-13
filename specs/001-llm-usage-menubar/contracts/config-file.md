# Contract: Configuration File

Path: `~/.config/llm-usage-menubar/config.json`. Written by the settings window, readable and editable by hand. The app reloads it at the start of a refresh when its modification time changed.

```json
{
  "version": 1,
  "refreshIntervalSeconds": 300,
  "logDirectories": ["~/.local/share/cc-deck/profiles/work/claude"],
  "weekFallback": { "weekday": 2, "hour": 0 },
  "alignmentAccountId": "acc-max",
  "startAtLogin": false,
  "accounts": [
    {
      "id": "acc-max",
      "type": "subscription",
      "label": "M",
      "displayName": "Claude Max",
      "harness": "claudeCode",
      "credentialDirectory": "~/.claude",
      "shownInBar": true,
      "thresholds": [80, 100]
    },
    {
      "id": "acc-vertex",
      "type": "tokenBased",
      "label": "VC",
      "displayName": "Claude Code via Vertex",
      "harness": "claudeCode",
      "provider": "vertex",
      "groupId": "grp-vertex",
      "customMarker": null
    }
  ],
  "groups": [
    {
      "id": "grp-vertex",
      "name": "Vertex weekly",
      "label": "V",
      "weeklyBudgetUSD": 60,
      "shownInBar": true,
      "thresholds": [80, 100]
    }
  ],
  "priceOverrides": [
    {
      "model": "claude-opus-5-5",
      "inputPerMTok": 4.0,
      "outputPerMTok": 20.0,
      "cacheWrite5mPerMTok": 5.0,
      "cacheWrite1hPerMTok": 8.0,
      "cacheReadPerMTok": 0.2
    }
  ]
}
```

Rules:
- Unknown keys are ignored on read (forward compatibility, FR-017). A save from the settings window rewrites the file with the known keys only; unknown keys from a hand edit are not preserved.
- A field of the wrong JSON type (for example `"refreshIntervalSeconds": "300"`) is a decode error and rejects the whole file like invalid JSON (FR-033).
- `type` values other than `subscription` and `tokenBased` make the account entry invalid; the whole file is then rejected and the last valid configuration stays active (FR-033).
- `~` is expanded in every path field.
- A missing file on first launch is replaced by a default: refresh 300 s, fallback Monday 00:00, and one subscription account labeled `M` pointing at `~/.claude` if its keychain item exists (FR-034).
- Labels are unique across all accounts and groups together (FR-032); the example uses `M`, `VC`, and `V`.
