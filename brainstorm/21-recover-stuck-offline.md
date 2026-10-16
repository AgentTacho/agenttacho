# Brainstorm: Recover From a Stuck Offline State

**Date:** 2026-10-16
**Status:** active

## Problem Framing

On 2026-10-16 the running 0.4.1 app failed every Claude and Codex usage request for more than six hours with "The Internet connection appears to be offline" (URL error -1009), from 12:26 UTC on, through sleep and wake. The network worked the whole time: `curl` reached both endpoints in about 0.16 s and `git push` succeeded. Restarting AgentMeter fixed it at once. The likely trigger was a network change (two WireGuard VPN profiles are configured), after which the process kept a broken network state: both usage clients use one `URLSession` for the whole process lifetime (`UsageEndpointClient.defaultSession`, `CodexUsageClient.defaultSession`). The system log kept no detail, so the exact cause is not proven.

"Refresh now" did not help: a manual refresh within 60 s of the last attempt reuses the last result (spec 010 FR-007, FR-008, `EndpointPolicy.minimumSpacing`), even when that result was a transport failure. Planned as 0.4.2 together with the pace line fix (spec 019).

## Approaches Considered

### A: Fresh session per request, manual retry after transport errors, detailed error log (chosen)
- Pros: removes the likely cause (a stuck session cannot outlive one request); gives the user a working retry; the next occurrence leaves evidence.
- Cons: a new session per request costs a TLS handshake each time (negligible at one request every few minutes).

### B: Only recreate the session after repeated transport failures
- Pros: keeps connection reuse in the normal case.
- Cons: more state and thresholds; the first failures after a network change still fail.

### C: Recreate the session on network path changes (path monitor)
- Pros: reacts exactly when the network changes.
- Cons: depends on the monitor seeing the change that broke the session, which is the unproven part.

## Decision

Approach A:

1. Each Claude and Codex usage request uses its own short-lived session with the same privacy settings as today (ephemeral, no cache, no cookies, redirects refused, request and total time limits), released after the request.
2. "Refresh now" calls an endpoint again, ignoring the 60 s spacing, when the last attempt for that endpoint ended in a transport error (offline, timeout, DNS failure, connection lost or refused, TLS failure): no request reached the server, so the rate limit is not touched. After a server answer (5xx, 429 or any HTTP status), the spacing and the existing backoff stay as today. Other triggers (wake, dropdown open, Settings) keep today's spacing.
3. The diagnostic log line of a transport failure names the error domain and code and the underlying network error (for example `NSURLErrorDomain -1009, underlying kCFErrorDomainCFNetwork ... _kCFStreamErrorCodeKey 50`), never a token or header.

## Key Requirements

- No change to privacy guarantees: the README "Security and privacy" statements (refused redirects, no cache or cookies, 45 s total limit) stay true.
- A transport failure followed by a working network recovers on the next request, without restarting the app.
- A manual refresh after a transport failure performs a real request even within 60 s, at most once per click.
- Logic (which errors count as transport errors, when manual refresh bypasses the spacing, the log text) lives in `UsageCore` with tests first.

## Open Questions

- Exact list of URL error codes that count as transport errors (spec 010 already distinguishes transport from service errors; reuse that classification).
- Whether the quick retry of spec 010 (30 s after a transport error) should also use the fresh session (it would, by construction) and whether a manual click while that retry is pending merges with it.
- Whether the dropdown should say "Retrying…" while a manual retry is in flight.
