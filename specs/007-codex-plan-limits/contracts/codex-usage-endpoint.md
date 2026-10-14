# Contract: Codex Plan Usage (consumed, read-only)

AgentMeter consumes two undocumented Codex interfaces. Both are read-only for AgentMeter.

## 1. Live usage service

Request (research R1):

```http
GET https://chatgpt.com/backend-api/wham/usage
Authorization: Bearer <auth.json tokens.access_token>
ChatGPT-Account-ID: <auth.json tokens.account_id>      (omitted when absent)
Accept: application/json
User-Agent: AgentMeter/<version>
```

Response fields used (all optional, unknown fields ignored):

```json
{
  "plan_type": "plus",
  "rate_limit": {
    "limit_reached": false,
    "primary_window":   { "used_percent": 20, "limit_window_seconds": 18000,  "reset_at": 1791999819 },
    "secondary_window": { "used_percent": 11, "limit_window_seconds": 604800, "reset_at": 1792477782 }
  },
  "rate_limit_reached_type": null
}
```

| HTTP result | AgentMeter outcome |
|-------------|--------------------|
| 200, at least one window | `.live` |
| 200, no window | stale, reason "usage service reported no limits" |
| 200, undecodable | stale, source error "usage service changed" |
| 401, 403 | stale, source error "Codex sign-in rejected"; after a 401 the same token is not sent again until Codex replaces it |
| 3xx | redirect refused (the token never reaches another host), stale, reason "usage service returned HTTP n" |
| 429 | stale, wait `Retry-After` (at most one hour) or one refresh interval |
| other status, transport error | stale, reason "offline" or "usage service returned HTTP n" |

## 2. Credential file `<codexHome>/auth.json`

Fields read: `auth_mode` (must be `"chatgpt"`), `tokens.access_token`, `tokens.account_id`. Nothing else is decoded. The file is never written. The access token's JWT `exp` claim decides expiry.

`<codexHome>/config.toml` key read only when `auth.json` is missing: `cli_auth_credentials_store` (`keyring` or `auto` means the sign-in lives in the keychain).

## 3. Rollout snapshot `<codexHome>/sessions/YYYY/MM/DD/rollout-*.jsonl`

`event_msg` lines with `payload.type == "token_count"`:

```json
{"timestamp":"2026-10-14T14:20:01.123Z","type":"event_msg","payload":{"type":"token_count","info":null,
 "rate_limits":{"limit_id":"codex","primary":{"used_percent":20.0,"window_minutes":300,"resets_at":1791999819},
  "secondary":{"used_percent":11.0,"window_minutes":10080,"resets_at":1792477782},
  "plan_type":"plus","rate_limit_reached_type":null}}}
```

Counted only when `limit_id` is `"codex"` or absent, `plan_type` is a non-empty string, and at least one of `primary`/`secondary` has `used_percent` and `window_minutes > 0`. Copied parent history in forked files is skipped (spec 006 rule).
