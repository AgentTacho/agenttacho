# Contract: Configuration File (token-based accounts)

`~/.config/agenttacho/config.json`, `accounts[]` entries with `"type": "tokenBased"`. Other account types are unchanged, except that `harness` is now written from the account's kind (`claudeCode` for a Claude subscription, `codex` for a Codex subscription).

## New form (written from this feature on)

```json
{
  "id": "acc-lab",
  "type": "tokenBased",
  "displayName": "Lab gateway",
  "icon": "brands:claude",
  "harness": "claudeCode",
  "matchRule": { "type": "custom", "field": "model", "text": "intranet/" },
  "claudeCodeDirectory": "~/agent-profiles/lab/claude",
  "groupId": "grp-lab",
  "shownInBar": false,
  "timeFormat": "relative"
}
```

| Key | Values | Notes |
|---|---|---|
| `harness` | `claudeCode`, `codex`, `openCode` | missing means `claudeCode` |
| `matchRule` | `{"type":"preset","preset":P}`, `{"type":"custom","field":F,"text":T}`, `{"type":"none"}` | its presence marks the new form |
| `matchRule.preset` | Claude Code: `vertex`; Codex: `apiKey`; OpenCode: `vertex`, `openai` | read together with `harness` |
| `matchRule.field` | `model`, `requestId`, `messageId` (Claude Code only), `anywhere` | |
| `matchRule.text` | non-blank string, case-sensitive | |
| `claudeCodeDirectory` | string | written only for harness `claudeCode`, only when not blank |
| `codexHome` | string | written only for harness `codex`, only when not blank |
| `additionalSessionDirectories` | as spec 035 | never for `openCode` |
| `provider`, `customMarker` | | never written for token-based accounts |

### Lenient reading (FR-015)

| Input | Result | Load note |
|---|---|---|
| `matchRule` not an object, unknown `type`, unknown preset for the harness, unknown field, field not offered for the harness, blank or missing `text` | rule `none` | `matchRule of account "X" is not readable, ignored` |
| directory key of another harness (for example `codexHome` on a `claudeCode` account) | ignored | `codexHome of account "X" does not belong to a Claude Code account, ignored` |
| `claudeCodeDirectory` or `codexHome` on an `openCode` account | ignored | same pattern, "an OpenCode account" |
| unknown `harness` value | decode error, as an unknown account type today | |

## Legacy form (read once, migrated)

A token-based account without `matchRule`:

| Legacy | Migrated |
|---|---|
| `"provider": "vertex"` or no `provider` | `harness: claudeCode`, `matchRule: preset vertex`, directory from `claudeCodeDirectory` |
| `"provider": "openai"` | `harness: codex`, `matchRule: preset apiKey`, directory from `codexHome` |
| `"customMarker": "T"` (non-blank) | `matchRule: custom anywhere T` (replaces the preset) |
| stored `harness` | ignored |
| other provider's directory key | ignored with today's load note |

Diagnostic log, once per load and account: `account "X" migrated from provider vertex to harness Claude Code` (the clipped name, as other load notes). The next save writes the new form.

## Validation (Settings "Not applied", FR-011)

`Configuration.validate()` throws for a token-based account whose rule is `custom` with blank text: `Account "X": the match rule needs a text`.
