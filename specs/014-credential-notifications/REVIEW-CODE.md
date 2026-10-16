# Code Review: Credential Notifications

**Spec:** specs/014-credential-notifications/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 97%**

- Functional Requirements: 14.5/15 (97%)
- Success Criteria: 6/6 (100%)
- Edge Cases: 15/15 (100%)
- Spec-declared constants: none (no `## Constants` section)

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 health derivation | `CredentialHealth.claude/codex`; `SubscriptionEntry.credentialExpiresAt`; `CodexCredentialProblem` set in `CodexLimitsSource.live` | Compliant |
| FR-002 eligibility, bar visibility | `CredentialAlertTracker.eligibleAccounts` (Claude subscriptions, Codex with live limits; `shownInBar` unused) | Compliant |
| FR-003 notify working to rejected / not signed in | tracker transitions 4 and 5, `isDue` | Compliant |
| FR-004 baseline after launch, add, directory change, live limits on | state per identity, `health == nil` until first non-unchanged result, `notBefore` for in-flight refreshes, preliminary snapshots skipped | Compliant |
| FR-005 24 h expiry delay from the credential's time | `expiryDelay`, `isDue` (`now >= at + 24 h`), re-checked on unchanged results | Compliant |
| FR-006 one notification per episode, kind change | `Episode.notified`, kind updated before `notifyIfDue` | Compliant |
| FR-007 withdraw on recovery | transition 3, presenter `withdraw`, late completions removed again (`CredentialPostLedger`) | Compliant |
| FR-008 removal, directory change, live limits off | `configurationPass` | Compliant |
| FR-009 texts and directory in the command | `CredentialAlert.title/body/command` | Compliant |
| FR-010 no credential data; log delivered, withdrawn, dropped with account id and health | texts from configuration only; log lines per contract | Minor deviation: withdraw and dropped lines carry the account id but not the health (contract `credential withdrawn: <accountId>`) |
| FR-011 one per account | identifier `credential-<accountId>` | Compliant |
| FR-012 switch | `Configuration.notifySignInProblems` (default true, excluded from `dataRelevant`), Settings toggle, `configurationChanged`, suppressed events | Compliant |
| FR-013 click opens dropdown | `NotificationClickHandler`, `MenuBarOpener` (status button click, fallback activate) | Compliant |
| FR-014 permission and queue | `PendingNotificationQueue`, `removeCredential` on withdraw | Compliant |
| FR-015 no requests, no writes, README | no new network or file access; README "Security and privacy" bullet added | Compliant |

### Success Criteria

SC-001 to SC-006 are covered by the tracker tests and `CredentialNoTokenTests` (real sources, sentinel tokens, exact event sequence).

### Edge Cases

All 15 edge cases in the spec map to code paths and tests (see review-findings.md and the test-quality mapping: baseline at launch, offline at launch, new account or directory, removal, transport errors, kind changes, Codex token already rejected, live limits off, unreadable credentials, permission pending, no app bundle, unknown expiry, clock moved backwards).

### Extra Features (Not in Spec)

- Notifications are shown as banners also while AgentMeter is active (`willPresent`). Covered by the spec's "Changes to earlier specs" note.
- Leftover credential notifications from an earlier run are removed at launch. Covered by the edge case "Already failing at launch".

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- FR-010: either add the health to the withdraw and dropped log lines, or relax FR-010 to "the account id, and the health for delivered notifications" (the contract already uses the shorter form).
- FR-001: say whether a result replayed without a request (reprice, not-due refresh) counts as that request's result (review-findings NOTABLE-1).

### Optional Improvements
- Share the "default directory or `CLAUDE_CONFIG_DIR=<dir>`" rule with the spec 010 dropdown note (FINDING-11).
- Drop the redundant `Episode.health` (FINDING-12), unify log subjects (FINDING-13), drop or use `CredentialHealth.isFailing` (FINDING-14).

## Conclusion

The implementation covers every requirement; the only deviation is the missing health on withdraw and dropped log lines, a spec evolution candidate. Deep review passed. The first pass found no Critical or Important issues; the Minor fixes applied afterwards produced two Important findings in re-review, both fixed.

## Deep Review Report

**Gate: PASS** (after fix round 3). Full details: `specs/014-credential-notifications/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 2 | 0 | 2 (Notable) | completed |
| Architecture & Idioms | 8 | 3 | 5 (4 Minor, 1 Notable) | completed |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 3 | 2 | 1 (Notable) | completed |
| Test Quality | 5 | 4 | 1 (Notable) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 2 | 2 | 0 | completed (branch: 0; re-reviews: 2 Important) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 3 | 2 | 1 (Minor) | completed (branch: 0; re-reviews: 3 P2) |
| Test Suite (regression) | 0 | 0 | 0 | passed (927 tests) |
| **Total (after dedup)** | **21** | **11** | **10** | |

Rows add up to 23 found and 13 fixed before deduplication: the presenter "posted" finding was reported by both architecture and production readiness, and the withdraw-before-completion race by both CodeRabbit and Codex.

By severity: 0 Critical, 2 Important (2 fixed), 14 Minor (9 fixed, 5 remaining), 5 Notable.

MVP: Architecture & Idioms (8 findings)

Key fixes applied (commit a72bf5d):
1. `CredentialPostLedger` (UsageCore, 6 tests): a credential notification counts as posted only after a successful, current `add`; a post completing after its withdrawal is removed again and logged (coderabbit, codex, architecture, production readiness).
2. Notification click logs "dropdown already open (<window class>)" instead of claiming it opened the dropdown (production readiness).
3. No-token tests pin the exact event sequence from the real Claude and Codex sources (test quality, SC-006).
4. New tracker tests: expiry turning into not signed in or keychain, changed expiry time, clock moved backwards; explicit times for `configurationChanged` (test quality, FR-005, FR-006).
5. Doc comments corrected (`Episode.delivered`, `CodexCredentialProblem`); contract lists `credential failed` and the new click line.

Remaining findings: none Critical or Important. Minor: FINDING-11 to FINDING-15 (optional refactors; Codex's superseded-post ordering case triaged as Minor because two posts for one account are at least a refresh apart).

Post-fix spec coverage: 15/15 requirements verified.

Notable observations: 5, captured to brainstorm/idea-inbox.md.
