# Contract: External Data Sources

The app consumes two external formats it does not own. Both are read-only.

## 1. Anthropic OAuth usage endpoint

Request:
```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <claudeAiOauth.accessToken>
anthropic-beta: oauth-2025-04-20
```

Credential source: macOS Keychain generic password, service `Claude Code-credentials` for `~/.claude`, otherwise `Claude Code-credentials-<first 8 hex chars of SHA-256(configDirectoryPath)>`. Value is JSON; only `claudeAiOauth.accessToken` and `claudeAiOauth.expiresAt` (epoch milliseconds) are read. The token is kept in memory for the duration of one request and never logged or written.

Response fields consumed (everything else ignored):
```json
{
  "five_hour": { "utilization": 8.0, "resets_at": "2026-10-13T10:49:59.706966+00:00" },
  "seven_day": { "utilization": 50.0, "resets_at": "2026-10-16T06:59:59.706992+00:00" }
}
```
Either window object may be `null`; the app then shows that window as unavailable.

Error handling: non-200, network error, or undecodable body marks the source as failed for this refresh; the last good status is kept and marked stale. HTTP 401 with a token whose `expiresAt` has passed is reported as "credentials expired".

## 2. Claude Code session log records

Files: `<configDir>/projects/**/*.jsonl`, one JSON object per line, append-only.

Consumed records: those with `"type": "assistant"` and a `message.usage` object. Fields read:

| JSON path | Use |
|---|---|
| `timestamp` | ISO 8601 UTC; window membership and daily trend |
| `requestId` | Provider detection (`req_vrtx_` prefix means Vertex); dedupe fallback |
| `message.id` | Dedupe key (several records share one id; the last wins) |
| `message.model` | Pricing lookup after normalization |
| `message.usage.input_tokens` | input |
| `message.usage.output_tokens` | output |
| `message.usage.cache_creation.ephemeral_5m_input_tokens` | cache write 5m (falls back to `cache_creation_input_tokens` when the split is absent) |
| `message.usage.cache_creation.ephemeral_1h_input_tokens` | cache write 1h |
| `message.usage.cache_read_input_tokens` | cache read |

Any line that fails to decode, lacks these fields, or is truncated is skipped without failing the file. Records of other types (`user`, `system`, `attachment`, ...) are ignored.

## 3. Built-in price table resource

`Sources/UsageCore/Resources/prices.json`: array of price entries with the fields in `data-model.md` → PriceEntry, USD per million tokens. User overrides in the config file replace entries with the same canonical `model`.
