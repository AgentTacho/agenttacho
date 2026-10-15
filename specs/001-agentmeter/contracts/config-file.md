# Contract: Configuration File

Path: `~/.config/agentmeter/config.json`. Written by the settings window, readable and editable by hand. The app reloads it at the start of a refresh when its modification time changed.

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
      "icon": "brands:claude",
      "displayName": "Claude Max",
      "harness": "claudeCode",
      "credentialDirectory": "~/.claude",
      "shownInBar": true,
      "thresholds": [80, 100]
    },
    {
      "id": "acc-vertex",
      "type": "tokenBased",
      "icon": "brands:google",
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
      "name": "Vertex",
      "icon": "solid:wallet",
      "period": "weekly",
      "budgetUSD": 60,
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
- A missing file on first launch is replaced by a default: refresh 300 s, fallback Monday 00:00, and one subscription account with the Claude icon pointing at `~/.claude` if its keychain item exists (FR-034).
- Each group has a `period` (`"weekly"` or `"monthly"`, absent means weekly) and a `budgetUSD` greater than 0 for that period. Weekly groups follow the weekly window; monthly groups run from 00:00 local time on the 1st to the 1st of the next month. Files written before spec 003 use `weeklyBudgetUSD` instead; they still load as weekly groups, and the decoding rules for both forms are in `specs/003-monthly-budget-period/contracts/config-file.md`.
- Every account and group has an `icon`, a Font Awesome Free icon as `"style:name"` with style `solid`, `regular` or `brands` (for example `"icon": "brands:claude"`). Icons may repeat. An icon missing from the bundled catalog rejects the file. Text labels (`label`) were removed by spec 004: a stored `label` is ignored, and an absent icon gets the type's default. A token-based account belongs to a group (`groupId`) or carries its own `budget`. The full rules are in `specs/004-icon-labels-standalone-budgets/contracts/config-file.md`.
- Spec 006 adds Codex and OpenCode: the optional lists `codexHomes` and `openCodeDirectories`, the token-based provider `"openai"`, and the account type `"codexSubscription"` with an optional `codexHome`. `harness` accepts `"claudeCode"`, `"codex"` and `"openCode"` and no longer affects attribution. The full rules are in `specs/006-multi-harness-usage/contracts/config-file.md`.
