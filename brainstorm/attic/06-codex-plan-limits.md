# Brainstorm: Codex Plan Limits (Multi-Harness Part B)

**Date:** 2026-10-14
**Status:** active

## Problem Framing

Spec 006 (part A of brainstorm #05) added a Codex subscription account for ChatGPT-plan logins. It shows tokens only: no percent, no reset times, no thresholds and no bar entry. The user wants the same treatment Claude subscription accounts get.

The user spends the plan's Codex quota in several places (Codex on other machines, cloud tasks, IDE extensions), not only through Codex CLI on this Mac. Local data alone therefore lags behind the real utilization.

Two data sources exist:

- **Rollout snapshots.** Every Codex `token_count` event carries a `rate_limits` object: `limit_id`, `primary` and `secondary` windows (`used_percent`, `window_minutes`, `resets_at`), `credits`, `plan_type`, `rate_limit_reached_type`. It reflects the state after this machine's last turn.
- **Usage endpoint.** Codex CLI 0.162.1 contains `/wham/usage` and `/api/codex/usage` paths under `chatgpt.com/backend-api`, returning a `RateLimitStatusPayload` (plan type, primary and secondary window, limit reached, credits, spend control). It is an internal, undocumented API and needs `tokens.access_token` from `~/.codex/auth.json`.

A read-only survey of the local rollouts (158 files) showed:

- Plus: primary window 300 minutes (5 hours), secondary window 10080 minutes (weekly).
- Free: primary window 43200 minutes (30 days), no secondary window.
- A second bucket `limit_id: "premium"` appears, so far always with empty windows.
- Some events carry `rate_limits` with every field null.

Window lengths therefore come from the data, not from fixed 5h and weekly assumptions.

## Approaches Considered

### A: Hybrid, endpoint first with snapshot fallback
Query the usage endpoint with the current access token (read-only). When the token is expired, the call fails, or the machine is offline, show the newest local snapshot, marked stale.
- Pros: accurate across all devices; still useful offline or without a valid token; the snapshot fallback costs little because part A already parses the rollouts.
- Cons: depends on an undocumented API; two sources to reconcile.

### B: Snapshots only
- Pros: no credentials, no network, simplest.
- Cons: wrong for this user, because usage elsewhere stays invisible until the next local turn and thresholds fire late.

### C: Endpoint only, mirroring the Claude subscription path
- Pros: one source, reuses the existing subscription source pattern.
- Cons: nothing to show when the token has expired (Codex only refreshes it while running) or when the API changes.

## Decision

**Approach A (hybrid).** The endpoint is the primary source because the user's quota is spent on several devices. Rollout snapshots are the fallback, so the account keeps showing plausible values when the endpoint is unavailable.

## Key Requirements

- The Codex subscription account gains plan limits: percent and reset time per window, threshold notifications, and a bar entry with a shown-in-bar setting, like Claude subscription accounts.
- Windows come from the data (`window_minutes`). Plans with one window (Free, 30 days) and two windows (Plus, 5h and weekly) both work.
- The bar shows the longest window (weekly on Plus, 30-day on Free), matching Claude, whose bar shows the 7-day window. All windows appear in the dropdown.
- Threshold notifications apply to every window, as for Claude's 5h and 7-day windows.
- The endpoint call is on by default, with a per-account toggle to use snapshots only.
- AgentTacho reads the access token from the account's Codex home and never refreshes it. Refreshing would rotate the refresh token and could log Codex out. An expired token means fallback, not an error loop.
- The token never appears in logs, errors, or the UI (same guarantee as the Claude credential path).
- Fallback: when the endpoint is unavailable, use the newest snapshot from the account's Codex home and mark the entry stale with its age.
- A window whose `resets_at` has passed shows as reset (0%) rather than repeating the old percent.
- Null or empty `rate_limits` objects and buckets without windows are ignored and never overwrite a good value.
- Part A's token counting and attribution stay unchanged.

## Out of Scope

- Showing credits, credit balance, or spend control.
- Refreshing or writing Codex credentials.
- API-key (OpenAI provider) accounts, which have no plan limits.

## Open Questions

- Which endpoint path to use (`/wham/usage` vs `/api/codex/usage`), and what headers it needs (for example `ChatGPT-Account-Id` from `tokens.account_id`).
- Is the endpoint stable enough, and how should a changed or failing response be detected and logged without blocking the snapshot fallback?
- When both sources have values, does the newest observation win, or does the endpoint always win while it is reachable?
- How should the `premium` bucket (`limit_id` other than `codex`) be handled if it ever carries windows: a separate window, or ignored?
- Refresh cadence for the endpoint, given that the Claude endpoint is rate-limited and network-bound sources reuse results on reprice.
- Should `rate_limit_reached_type` (limit hit) get its own visual state beyond 100%?
- The part A review finding M-11 (`planAccounts` name is vague next to part B) should be settled in this spec.
