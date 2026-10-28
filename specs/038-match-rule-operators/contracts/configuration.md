# Contract: Configuration File (which sessions a token-based account counts)

**Feature**: 038-match-rule-operators (reworked 2026-10-28)

## Written form

```json
{ "id": "acc-gw", "type": "tokenBased", "displayName": "Claude Code via gateway",
  "harness": "claudeCode", "claudeCodeDirectory": "~/.claude-gateway",
  "sessionKind": "otherProvider",
  "condition": { "field": "model", "operator": "contains", "text": "glm" },
  "budget": { "period": "monthly", "budgetUSD": 200 } }
```

| Key | Values | Written |
|---|---|---|
| `sessionKind` | Claude Code: `directoryOnly`, `vertex`, `otherProvider`; Codex: `apiKey`; OpenCode: `vertex`, `openai`, `anthropic`, `otherProvider` | always |
| `condition.field` | `model`, `requestId` and `messageId` (both Claude Code only), `anywhere` | when the condition is on and the kind offers one (never for `directoryOnly`) |
| `condition.operator` | `startsWith`, `contains`, `regex` (`anywhere`: `contains`, `regex`) | with `field` |
| `condition.text` | the text or ICU pattern, not blank | with `field` |

Never written for a token-based account: `matchRule`, `provider`, `customMarker`. Subscription accounts keep `customMarker` unchanged.

## What a kind counts (exact, case-sensitive)

| Harness | `sessionKind` | A record without decisive Claude Code directory counts when |
|---|---|---|
| Claude Code | `directoryOnly` | never |
| Claude Code | `vertex` | the request id starts with `req_vrtx_` |
| Claude Code | `otherProvider` | the request id does not start with `req_` |
| Codex | `apiKey` | the session signed in with an API key |
| OpenCode | `vertex` | the provider is `google-vertex` or `google-vertex-anthropic` |
| OpenCode | `openai` | the provider is `openai` |
| OpenCode | `anthropic` | the provider is `anthropic` (API key and Claude plan sign-in alike) |
| OpenCode | `otherProvider` | the provider is set and is none of these four; only with a condition |

Sessions that ran from the account's Claude Code directories count for it whatever kind and condition say (spec 037, unchanged).

## Condition matching (first version, unchanged)

| Operator | Matches when (ignoring case, never diacritics) |
|---|---|
| `startsWith` | the field begins with the text, compared literally |
| `contains` | the field contains the text, compared literally |
| `regex` | the ICU pattern is found anywhere in the field; `^`/`$` anchor it; `(?-i)` restores case sensitivity |

An empty field never matches. A regex stops after 50 ms on one record and counts as no match; the condition then sits out the rest of the refresh, and the next refresh tries again (spec FR-007).

## Reading earlier forms

Loading takes the first form present: `sessionKind`, then `matchRule`, then `provider`.

| Stored | Loaded as |
|---|---|
| `"provider": "vertex"` or no `provider` (v0.8.0) | Claude Code, `vertex` |
| the same plus a token-based `"customMarker": M` | Claude Code, `vertex`, condition `anywhere` `contains` M |
| `"provider": "openai"` (v0.8.0) | Codex, `apiKey` (a marker M becomes `anywhere` `contains` M) |
| `"matchRule": {"type": "preset", "preset": P}` | the kind P of the harness |
| `"matchRule": {"type": "none"}` | Claude Code `directoryOnly`; Codex `apiKey`; OpenCode: as unreadable |
| `"matchRule": {"type": "custom", "field": F, "operator": O, "text": T}` | Claude Code `otherProvider`, Codex `apiKey`, OpenCode `otherProvider`; condition F, O (missing: `startsWith`, or `contains` on `anywhere`; `startsWith` on `anywhere`: `contains`), T |
| unknown or other-harness kind or preset, unreadable condition or custom rule | `directoryOnly` (Claude Code), `apiKey` (Codex), `otherProvider` without a condition (OpenCode) |
| `condition` together with `directoryOnly` | `directoryOnly`, condition ignored (not kept for a later kind) |
| `condition` with an invalid pattern | kept as written; matches no record; Settings refuses to save until corrected |
| OpenCode `otherProvider` without `condition` | kept; matches no record; Settings asks for a condition |

## Log notes (diagnostic log, once per account and load)

| Case | Line |
|---|---|
| v0.8.0 account | `account "<name>" migrated from provider <p> to <Harness>, sessions <Kind>` |
| v0.8.0 account with a token-based marker | the line above plus `; its marker became the condition "Anywhere contains <M>" of Vertex sessions, a company gateway needs Other provider` (Vertex only) |
| `matchRule` form | `account "<name>": match rule migrated to sessions <Kind>` (plus ` with a condition` for a custom rule) |
| unreadable | `account "<name>": which sessions count could not be read; it counts <Kind> until you choose in Settings` |
| condition on Directory only | `condition of account "<name>" does not apply to Directory only, ignored` |
| invalid pattern | `account "<name>": the regular expression of the condition is not valid; it matches no usage until you correct it in Settings` |
| sit-out (per refresh) | `account "<name>": condition took longer than 50 ms on one record and was skipped for the rest of this refresh` |

`<name>` is clipped as every load note; `<M>` is clipped the same way.

## Settings refusal ("Not applied" line)

| Draft | Message |
|---|---|
| condition on with a blank text, or OpenCode `otherProvider` without a condition | `Account "<name>": the condition needs a text` |
| `regex` that does not compile | `Account "<name>": the regular expression is not valid` |
