# Quickstart: Codex Plan Limits

## Prerequisites

- Codex CLI signed in with a ChatGPT plan (`~/.codex/auth.json` with `auth_mode: "chatgpt"`).
- At least one Codex session run on this machine (for the snapshot fallback).
- A Codex subscription account in AgentTacho (Settings, Accounts, add, platform ChatGPT).

## Automated checks

```bash
make test
```

Covers: snapshot extraction from fixtures (Plus, Free, premium bucket, all-null, forked), endpoint decoding and HTTP outcomes via `StubURLProtocol`, credential reading (chatgpt, apikey, missing, keychain config, JWT expiry), source selection (live, stale, local-only, unavailable, clamped future time), fetch gating (reprice, 429 with and without Retry-After, manual spacing), thresholds per window and on toggle, bar styling, configuration round-trip and defaults, and the token-redaction sentinel.

## Manual scenarios

1. **Live values** (US1): run `make run`, open the dropdown. The Codex account lists "5-hour" and "weekly" with percent and reset time; the bar shows the weekly percent. Compare with `/status` in Codex: within 1 point (SC-001).
2. **Fallback** (US2): turn off Wi-Fi, click Refresh. The account shows the same values marked stale with "offline" and the observation time.
3. **Snapshot only** (US4): turn off "Live limits" for the account. The dropdown labels values as local data with the observation time; the bar entry is not dimmed. `log stream` or the diagnostic log shows no usage service request for this account.
4. **Thresholds** (US3): set a threshold just above the current weekly percent, use Codex until it is crossed, refresh: one notification naming the account, "weekly" and the threshold.
5. **Credentials untouched** (SC-004, SC-005): `stat ~/.codex/auth.json` before and after a day of refreshes shows the same modification time; `rg -F "$(jq -r .tokens.access_token ~/.codex/auth.json | cut -c1-20)" ~/Library/Application\ Support/AgentTacho` finds nothing.
