# Code Review: Recover From a Stuck Offline State

**Spec:** specs/021-recover-stuck-offline/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 13/13 (100%)
- Error Handling: 3/3 (100%)
- Edge Cases: 4/4 (100%)
- Non-Functional: 2/2 (100%)

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 one connection setup per request, invalidated after it | `SessionSource.perRequest` with `defer { finishTasksAndInvalidate() }`, `UsageSession.make()` default in both clients (UsageEndpointClient.swift, CodexUsageClient.swift) | Compliant |
| FR-002 privacy rules kept | `UsageSession.configuration()`: ephemeral, no URL cache, no cookies, 45 s resource limit; 30 s request timeout; `RedirectRefuser` task delegate on every session | Compliant |
| FR-003 manual bypass after no-answer, rate-limit wait respected | `EndpointPolicy.decide(noAnswerRetry:)` returns `.fetchNoAnswer` only after the block check; Codex `decide` checks `blockedUntil` before `manualRequested && gate.lastNoAnswer` | Compliant |
| FR-003a merged click keeps the bypass | `pendingManual` / `manualMerged` in `RefreshCoordinator`; retry and pace paths; `updateQuickRetry` keeps a click merged into a dropped quick retry (fixed in review) | Compliant |
| FR-003b bypass counts as last attempt, rate limit sets the wait | `policy.record` on the no-answer run, `lastNetworkRefreshAt`, `claudePaceBypassed` / `codexPaceBypassed`, Codex `gate.lastFetchAt` and `blockedUntil` | Compliant |
| FR-003c per Claude account | `SubscriptionSource.noAnswer` set, restricted run via `claudeNoAnswerOnly` | Compliant |
| FR-004 HTTP answers keep spacing | `FailureCategory.isNoAnswer` excludes `.httpStatus` (5xx included), rate limits, decoding; flag cleared on any answer | Compliant |
| FR-005 other triggers unchanged | `manual` true only for `.manual` or a merged click; Codex bypass only with `manualRequested` | Compliant |
| FR-006 at most one request per service per refresh | one request per account/home per run; clicks during a run collapse into one follow-up | Compliant |
| FR-007 log detail | `NetworkFailureDetail` (domain, code, underlying domain and code, stream code), `logDescription` used only in the log notes of both sources | Compliant |
| FR-008 no secrets in logs, errors, notifications | detail reads only domains and integer codes; user-facing texts use `description` | Compliant |
| FR-009 logic outside the UI | all decisions in `UsageCore`; App.swift only changes a doc comment | Compliant |
| FR-010 README names the extra request | "The tokens are powerful" bullet (reworded in review to "each time you click") | Compliant |

### Error Handling

| Case | Location | Status |
|------|----------|--------|
| URL error with detail | `UsageEndpointError.network(_, detail:)` in both clients | Compliant |
| Non-URL error (for example cancellation) counts as no-answer | `classify` returns `.transport`, `isNoAnswer` true | Compliant |
| Failure before a request leaves the flag unchanged | Claude `.credential*` attempts and Codex `.noRequest` do not touch it | Compliant |

### Edge Cases

| Edge case | Implementation | Status |
|-----------|----------------|--------|
| No-answer inside the grace period: click takes the quick retry's place | restricted run plus `updateQuickRetry` drop; test `manualBeforeQuickRetryTakesItsPlace` | Compliant |
| Rate-limit wait active, then no-answer: wait respected | block checked first in both policies | Compliant |
| Both services fail: one click retries both; an answered service stays spaced | tests `manualAfterNoAnswerSendsOneRequestPerService`, `manualAsksOnlyCodex...`, `manualAsksOnlyClaude...` (added in review) | Compliant |
| No new dropdown note text | only log texts change | Compliant |

### Extra Features (Not in Spec)

None. The log summary text "endpoint fetched for no-answer accounts (Refresh now)" supports FR-007 diagnostics.

### Spec-Declared Constants

The spec has no `## Constants` section; check skipped.

## Code Quality Notes

Doc comments cite spec 021 requirements, as AGENTS.md requires. The diff contains no em or en dash characters. The README "Security and privacy" section stays true: requests still go only to the two usage endpoints, redirects are refused, there is no cache or cookie storage, there is a 45 s total limit, and the new extra request is listed.

## Deep Review Report

**Gate: PASS** (after fix round 1). Details: [review-findings.md](review-findings.md).

| Agent                   | Found | Fixed | Remaining | Status |
|-------------------------|-------|-------|-----------|--------|
| Correctness             | 2 | 1 | 1 (Minor) | completed |
| Architecture & Idioms   | 9 | 2 | 7 (5 Minor, 2 Notable) | completed |
| Security                | 3 | 1 | 2 (Notable) | completed |
| Production Readiness    | 4 | 0 | 4 (2 Minor, 2 Notable) | completed |
| Test Quality            | 6 | 2 | 4 (Minor) | completed |
| Goal Alignment          | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external)   | 0 | 0 | 0 | completed (2 rounds) |
| Copilot (external)      | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external)        | 2 | 1 | 1 (Minor, ambiguous) | completed (2 rounds) |
| Test Suite (regression) | 0 | 0 | 0 | passed (1431 tests) |
| **Total**               | **26** | **7** | **19** | |

The architecture log-wording finding and Codex's round 2 P3 concern the same line and are merged into one finding in review-findings.md.

MVP: Architecture & Idioms (9 findings)

Key fixes applied:
1. A "Refresh now" click merged into a queued quick retry is no longer lost when the running refresh drops that quick retry (FR-003a, FR-006). Regression test `clickMergedIntoADroppedQuickRetryStillRuns` was red before the fix. (correctness)
2. Tests for the mixed case, where only Claude or only Codex got no answer, assert request counts per service (SC-002, edge case 3). (test quality)
3. A Codex source test covers a click merged into a pace-held scheduled run and into a wake (FR-003a). (test quality)
4. The README bullet now says the bypass request comes with each click, not once (FR-010). (security)
5. The diagnostic log text for a no-answer run without a Claude request is clearer. The policy design doc's rule 4 notes the spec 021 amendment. (architecture, codex)

Remaining findings (none Critical or Important). Items that need a product decision were left unchanged:
- FINDING-8 (Codex P2): after a Codex-only bypass, the footer's "Last refreshed" time and the summary log still follow the Claude endpoint.
- NOTABLE-1: a pre-request failure keeps the no-answer flag, so clicks re-read credentials without sending a request.
- NOTABLE-3: there is no minimum gap between bypass clicks after a finished run.

Post-fix spec coverage: 13/13 requirements verified ✓ all covered

Notable observations: 6 captured to brainstorm/idea-inbox.md

## Conclusion

The implementation matches spec 021 in every functional requirement and edge case. The one correctness gap found in review (a lost merged click) is fixed and covered by a test. `make test` (1431 tests) and `make app` pass. Ready for the walkthrough and the final gate.
