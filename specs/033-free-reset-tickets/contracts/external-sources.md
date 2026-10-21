# Contract: External Sources

Both sources are undocumented. AgentTacho decodes only the fields below and ignores every other field.

## Claude: free-reset block on the usage request

Request (changed): `GET https://api.anthropic.com/api/oauth/usage?cedar_ember=1`, headers unchanged (`Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `Accept: application/json`), session unchanged (ephemeral, no cache, no cookies, redirects refused, 30 s request, 45 s resource).

Response (added part):

```json
{
  "five_hour": { "...": "unchanged" },
  "cedar_ember": {
    "eligible": true,
    "grants": [
      { "resets_left": 1, "resets_total": 1, "starts_at": "2026-10-20T08:00:00Z", "ends_at": "2026-10-24T08:00:00Z", "paused": false },
      { "resets_left": 1, "resets_total": 1, "starts_at": null, "ends_at": null, "paused": false }
    ]
  }
}
```

| Case | Ticket read |
|---|---|
| no `cedar_ember` key, `eligible: false`, or empty `grants` | `.tickets([])` |
| valid block | `.tickets` per research R1 |
| block with wrong types, negative `resets_left`, bad time, > 200 grants, > 50 usable tickets | `.clearingFailure` |
| usage request throws | `.temporaryFailure` (usage handled as today) |
| HTTP 4xx except 401 and 429 with the flag | plain repeat, `TicketFlag` per data model |

Test fixtures: valid block with one expiring and one non-expiring grant; paused, future and ended grants; `eligible: false`; missing key; malformed block next to valid windows (windows still decode); 51 usable tickets; HTTP 400 then 200 plain; HTTP 400 then 500 plain; 401 and 429 (no repeat).

## Codex: reset credits

Request (new): `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`, headers as `wham/usage` (`Authorization: Bearer <token>`, `ChatGPT-Account-ID` when known, `Accept: application/json`, `User-Agent: AgentTacho/<version>`), ephemeral session, redirects refused, answer host and path checked, `timeoutInterval = 10`. Sent only after a successful `wham/usage` fetch for the same Codex home and refresh.

Response:

```json
{
  "available_count": 2,
  "credits": [
    { "id": "ignored", "reset_type": "weekly", "status": "available", "granted_at": "2026-10-18T10:00:00Z", "expires_at": "2026-10-25T10:00:00Z" },
    { "id": "ignored", "status": "redeemed", "expires_at": "2026-10-30T10:00:00Z" }
  ]
}
```

| Case | Ticket read |
|---|---|
| no `credits` key or empty list | `.tickets([])` |
| valid list | `.tickets`, one per `status == "available"` with future or absent `expires_at` |
| wrong types, bad time, > 200 credit records, > 50 usable | `.clearingFailure` |
| request throws (transport, timeout, any HTTP status, unexpected location) | `.temporaryFailure` |
| `wham/usage` failed or was not sent | no request, `.temporaryFailure(skipped)` |

`available_count` is not used; the list decides.

## Usage pages (opened in the browser, no request by AgentTacho)

- Claude: `https://claude.ai/settings/usage`
- Codex: `https://chatgpt.com/settings/usage?tab=overview`
