# Brainstorm: Keep Last Good Values

**Date:** 2026-10-15
**Status:** active

## Problem Framing

AgentTacho already keeps the last good values within one run: when a fetch fails, Claude subscription accounts and Codex subscription accounts keep their previous numbers, the bar marks them with `~`, and the dropdown says "Stale, last good value <time>". Three gaps remain, all of them noticed in daily use:

1. **A blip is visible at once.** The refresh on wake from sleep often runs before Wi-Fi is back. One failed request turns the bar to `~` until the next scheduled refresh, although nothing is really wrong.
2. **Claude errors are not classified.** A rejected token (HTTP 401 or 403, for example after a new login elsewhere) looks exactly like a Wi-Fi blip: "stale". Nothing tells the user that they have to act. Codex accounts already separate a rejected sign-in from being offline.
3. **Values live only in memory.** After a quit, an update or a relaunch while offline, Claude rows show `…` or `--` until a fetch succeeds. Codex accounts mostly avoid this because they fall back to the limits Codex writes into its own session files.

Seeded from the idea inbox entry `keep-last-good-values` (source: CodexBar comparison, which classifies errors as transport vs auth and never blanks a row on a Wi-Fi blip).

## Approaches Considered

### A: Shared last-good layer in UsageCore (chosen)

One error classifier (transport, auth, rate limit, service changed), modeled on the classification Codex already has, one small store on disk for last good values, and the quick transport retry in the refresh policy. Both network-bound sources, the Claude usage endpoint and Codex live limits, use them.

- Pros: same behavior for every provider; the wake blip is fixed for Codex too; no duplicated classification logic; ready for the next provider.
- Cons: touches both sources and the endpoint policy, so the diff is larger than B.

### B: Claude only

Classification and persistence only in `SubscriptionSource`; Codex unchanged.

- Pros: smallest diff.
- Cons: Codex rows still flip to `~` after wake; Claude gets its own copy of logic Codex already has; a third provider would need a third copy.

### C: Persist the whole snapshot

Save the complete `UsageSnapshot` and restore it at launch.

- Cons: log-based values are rescanned at launch anyway, the file gets large, and the rule for windows that reset in between gets messy. Rejected.

## Decision

Approach A. Decided after a comparison of what each provider already covers: Codex has the auth classification and a relaunch fallback, neither provider hides a wake blip, so a shared layer closes all gaps once instead of copying Codex logic into the Claude source.

## Key Requirements

- **Quick retry on transport errors.** When a fetch fails with a transport error (offline, timeout, server error), the values stay unmarked and one retry runs after about 30 seconds. Only if the retry fails too are the values marked stale. Applies to the Claude usage endpoint and to Codex live limits. Rate limits keep their existing backoff and single retry.
- **Auth errors are their own state for Claude.** On HTTP 401 or 403 the last values stay visible with `~` in the bar, and the dropdown shows an action note in a distinct color, for example "Sign-in rejected, run claude to sign in again". This matches the rejected state Codex accounts already have.
- **Last good values survive a relaunch.** On every successful fetch the values are saved; at launch they are loaded and shown marked stale with their original time until a fetch succeeds.
- **Reset rule.** If a persisted window has reset since it was saved (its reset time is in the past), it shows 0% marked `~` instead of the old value.
- **No secrets on disk.** The saved file holds only account id, percentages, reset times and the fetch time, never a token. It lives in AgentTacho's own application support directory, never in the agents' files. The README's "Security and privacy" section is updated in the same pull request (it currently says AgentTacho writes only the configuration and the log).
- **One shared classifier.** Claude and Codex errors map to the same categories, so the dropdown wording and the stale marking follow the same rules for both.

Out of scope: notifications about rejected credentials or resets (inbox item `reset-and-credential-notifications`), adaptive refresh intervals, and stopping requests after an auth error until the credential changes.

## Open Questions

- Exact retry delay (about 30 s) and whether a retry that is already pending for a rate limit absorbs the transport retry.
- Where exactly the file lives (`~/Library/Application Support/agenttacho/` or the caches directory) and what happens when it is unreadable or from an older format (ignore it and log once is the likely answer).
- Whether persisted values are dropped after some maximum age even without a known reset (for example a window without a reset time).
- Which errors count as transport: timeouts and connection errors clearly; are HTTP 5xx and refused redirects (3xx) transport or service errors?
- Whether Codex live values should be persisted at all, or whether its session-file fallback already covers the relaunch case well enough.
- Whether the "credentials expired" state for Claude (token past its expiry before the request) also deserves the action note, since Claude Code refreshes the token only when it runs.
