# Code Review: Keep Last Good Values

**Spec:** specs/010-keep-last-good-values/spec.md
**Date:** 2026-10-15
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%** (after two compliance fixes in commit 2cadf81; 35/37 = 94.6% before them)

- Functional Requirements: 21/21 (100%)
- Edge Cases: 11/11 (100%)
- Success Criteria: 5/5 (100%)
- Contract (contracts/last-good-file.md): compliant

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 classification | `FailureCategory.classify` (FailureCategory.swift); 5xx and network are transport, 401/403 sign-in rejected, 429 rate limited, decoding, other status and `CodexUsageError.noLimits` service changed; refused redirects surface as 3xx (UsageEndpointClient) and the Codex wrong-location answer now throws `.decoding` | Compliant |
| FR-002 pre-request failures unchanged | SubscriptionSource `apply` keeps `.notSignedIn`, `.credentialsExpired`, credential read failures; Codex `.noRequest`; both expire the episode, no retry | Compliant |
| FR-003 diagnostic log | category in "fetch failed (category)" and "request failed ... (category)"; coordinator logs timer set, sent, dropped, suppressed, moved; texts come from own error types only | Compliant |
| FR-004 one quick retry 30 s after first transport failure | `RetryEpisodes.failed` (grace only when no phase and transport), `RetryEpisodes.delay = 30`, coordinator `updateQuickRetry` | Compliant |
| FR-005 grace keeps values unmarked, neutral note, saved values excluded | `.retrying` states for Claude and Codex, `unmarked` only with `liveThisRun`; BarLayout treats `.retrying` like `.ok`; DropdownView secondary-color `GraceNote`; `inGrace` keeps `lastSuccessfulRefreshAt` | Compliant |
| FR-006 retry outcome | success clears the phase; any failure in the grace phase returns `.exhausted`, stale or `.signInRejected` | Compliant |
| FR-007 no retry for other categories; rate-limit wait at retry time | `RetryEpisodes.failed`; `EndpointPolicy.decide(.quickRetry)` respects the block; `quickRetrySuppressed`, `endingGrace`, Codex `.blocked` branch expire the episode | Compliant |
| FR-008 bypasses spacing and "already fresh"; scheduled or wake fetch takes its place | `EndpointPolicy.decide` returns `.fetch` for `.quickRetry` after the block check; Codex `decide` skips spacing for `.quickRetry`; a fetching scheduled or wake refresh exhausts the episode and `updateQuickRetry` cancels the timer | Compliant |
| FR-009 only failed accounts; counts for shared policy | Claude keeps `lastEntries` for accounts not due; Codex `.notDue` for accounts not due; outcomes recorded via `policy.record` | Compliant |
| FR-010 Claude sign-in rejected | `.signInRejected` state; bar `~` with values, `--` without; red `SignInRejectedNote`, `CLAUDE_CONFIG_DIR=` for non-default directory; credentials expired unchanged | Compliant |
| FR-011 note disappears on success | success sets `.ok` | Compliant |
| FR-012 Codex rejected in attention style | `CodexLimitsEntry.signInRejected`, red in `.stale` and `.unavailable` | Compliant |
| FR-013 save after every success | SubscriptionSource `save`, CodexLimitsSource `save`, `LastGoodStore.replace` | Compliant |
| FR-014 no token, own directory, owner-only, atomic | `SavedClaudeValues` and `SavedCodexValues` carry no credential fields; temp file 0600 plus `rename`, directory 0700 | Compliant |
| FR-015 early result, canonical directories, stale after a failed first refresh | `publishSavedValues`, `savedOutput` in both sources, `isPreliminary` placeholders in DropdownView, `firstSnapshot` handling in App.swift | Compliant |
| FR-016 passed windows show 0% | `SubscriptionStatus.effective(now:)` in BarLayout and DropdownView; Codex `effectiveWindows` | Compliant |
| FR-017 saved Codex live result in the comparison; discarded with live off | Codex `seedIfNeeded`, `newer(live:snapshot:)`, `.off` branch clears `lastLive`, `save` only live plans | Compliant |
| FR-018 bad file ignored, logged once | `LastGoodStore.load` returns a problem logged once in App.swift; next write replaces the file | Compliant |
| FR-019 notifications | App.swift clears `subscriptions` of the preliminary snapshot before `ThresholdTracker.observe`; the tracker only reads `.ok` Claude entries | Compliant |
| FR-020 saved reset drives alignment while in the future | `publishSavedValues` seeds a future reset. **Deviation found:** the real SubscriptionSource never throws, so a failed first request returns the saved values as a `.stale` entry and `performRefresh` took its passed 7-day reset as the alignment reset (rolled forward), instead of behaving as without a reset time. The existing test used a throwing fake and missed it. **Fixed** in 2cadf81 (`accountsFetchedThisRun`, `dropPassedSavedAlignmentReset`) with two new tests | Compliant after fix |
| FR-021 README | "What it writes" section, notes in "What you should know". **Deviation found:** "It never holds ... an account ID" was inaccurate, since the file is keyed by configuration account ids; the contract excludes ChatGPT account ids. **Fixed** in 2cadf81 | Compliant after fix |

### Edge Cases

All 11 edge cases are handled: retry and timer collide (scheduled fetch exhausts the phase, timer dropped), manual refresh in grace (spacing reuse, timer kept), retry while asleep (overdue expiry plus wake fetch), retry blocked by a rate limit (FR-007 paths), mixed outcomes (per-account episodes), no values yet (grace with `unmarked: false`, still retried), already stale (one retry per episode), unreadable file (FR-018), clock moved backwards (`min(fetchedAt, now)`), live limits off (discarded), threshold notifications (FR-019).

### Success Criteria

SC-001 (no `~` within 30 s of recovery), SC-002 (early result before the first refresh), SC-003 (red sign-in note), SC-004 (token search tests in LastGoodStoreTests and the source tests), SC-005 (at most one quick retry per episode) are covered by implementation and tests.

### Extra Features (Not in Spec)

- `RefreshTrigger.quickRetry` and the coordinator's `pendingQuickRetry` so a rate-limit retry and a quick retry that arrive during a running refresh both run. Supports FR-007 and FR-008. Helpful.
- `CodexLimitsSource.block(home:until:)` test hook. Internal, test only.

### Spec-Declared Constants

The spec has no `## Constants` section. Skipped.

## Recommendations

### Critical (Must Fix)
- None open.

### Spec Evolution Candidates
- None.

### Optional Improvements
- When a Codex quick retry runs while the Claude endpoint is rate limited, the coordinator logs "quick retry suppressed (rate limited)" although the Codex request is sent (the Codex source gates itself). Log wording only.

## Conclusion

After the two fixes, the implementation matches the spec.

## Deep Review Report

**Gate: PASS** (after fix round 3). Full details in `review-findings.md`.

| Agent                   | Found | Fixed | Remaining | Status |
|-------------------------|-------|-------|-----------|--------|
| Correctness             |     3 |     2 |         1 | completed |
| Architecture & Idioms   |    10 |     4 |         6 | completed |
| Security                |     2 |     2 |         0 | completed |
| Production Readiness    |     7 |     2 |         5 | completed (1 Notable) |
| Test Quality            |    13 |     5 |         8 | completed (1 Notable) |
| Goal Alignment          |     0 |     0 |         0 | skipped (no pull request) |
| Re-review (rounds 1, 2) |     4 |     4 |         0 | completed |
| CodeRabbit (external)   |     1 |     1 |         0 | completed |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled in config) |
| Codex (external)        |     3 |     1 |         2 | completed (1 duplicate fixed, 1 Minor kept, 1 rejected) |
| Test Suite (regression) |     0 |     0 |         0 | passed every round |

Totals after deduplication: 0 Critical, 7 Important (all fixed), 30 Minor (12 fixed), 2 Notable (captured to `brainstorm/idea-inbox.md`). Several findings were reported by more than one agent, so the per-agent rows add up to more than the totals.

MVP: Test Quality (13 findings).

Key fixes applied:
1. Quick retry counted from the failure, and a due retry is never dropped. A request that times out no longer loses its retry (FR-004; correctness, production, Codex).
2. The refresh timer restarts on wake, so a tick that came due during sleep does not take the quick retry's place (FR-008, SC-001; production).
3. The FR-019 notification rule moved into ThresholdTracker, with a test (architecture, test quality).
4. No retry loop from reused results after a suppressed retry (FR-007; re-review round 1).
5. After the early result, a failed record source keeps fresh budget entries (FR-015; correctness).
6. The saved file is read through one descriptor: no symlink, no FIFO block, at most 1 MiB, and the temp file is cleaned up (FR-018; security, CodeRabbit, re-review).
7. Tests run the real SubscriptionSource end to end (US3-1), cover Codex SC-004, and cover a failed scheduled or wake request in grace (test quality).
8. The README lists every file AgentMeter writes and everything `last-good.json` holds (FR-021; security).

Post-fix spec coverage: 21/21 requirements verified (FR-019 moved, still covered).

Final `make test`: 790 tests in 82 suites passed.
