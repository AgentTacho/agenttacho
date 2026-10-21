# Code Review: Free Reset Tickets

**Spec:** specs/033-free-reset-tickets/spec.md
**Date:** 2026-10-21
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 95% (42 of 44 checks; FR-022 and FR-023 are release steps outside the code)**

- Functional requirements: 22 of 24 compliant (FR-001 to FR-021 with FR-010a). FR-022 (recapture, card candidates entry) and FR-023 (merge order of constitution 2.1.0 and the site list) happen in the site repository and at merge time. FR-020's README part is done on this branch; its website mirror belongs with FR-022.
- Edge cases: 20 of 20.
- Acceptance scenarios: US1 1 to 8, US2 1 to 7 and US3 1 to 3 are traced to code. The glyph rendering, the browser opening and the Settings toggle are SwiftUI only and are checked in the walkthrough. Their texts and ordering are tested in UsageCore.
- Success criteria:
  - By tests: SC-002, SC-003, SC-004, SC-005.
  - By code and tests: SC-001.
  - In the capture run: SC-006.

The spec has no `## Constants` section, so the constants check was skipped.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `UsageEndpointClient.fetch(token:includeTickets:)` adds `cedar_ember=1`. `CodexLimitsSource.live` sends `fetchResetCredits` only after a successful `wham/usage`. A skipped request is `.temporaryFailure("skipped")`. | Compliant |
| FR-002 | `ResetTicketDecoding.claude/codex`: eligible, paused, start and end times; `resets_left` tickets per grant; `available` credits. | Compliant |
| FR-003 | `ResetTicketRead.applied(to:now:)`: keep minus expired, or clear. `requestFailure` maps errors to temporary failures. Usage, errors and timing come only from the plain or plan result. | Compliant |
| FR-004 | `SubscriptionSource.attempt`: 4xx other than 401 and 429 is repeated once. The `TicketFlag` state is on, suspended or offForRun. | Compliant |
| FR-005 | Same headers, `SessionSource` refuses redirects, host and path check, ephemeral session with 10 s for the request and the resource. | Compliant |
| FR-006 | `ResetTicket` holds only `expiresAt`. It is not in `LastGoodStore`, not in the config and not in the log. No service id is decoded. | Compliant |
| FR-007 | GET only. The glyphs open fixed `AppLinks` URLs. | Compliant |
| FR-008 | `glyphs(at:)`: soonest first, no expiry last, three glyphs plus "+N". | Compliant |
| FR-009 | `labelText("solid:gift")` in `colors.secondary`, "+N" in the same color. | Compliant |
| FR-010, FR-010a | `ResetTicketText` tooltips with the click line; `AppLinks.claudeUsagePage` and `codexUsagePage`; `panel?.close()`. | Compliant |
| FR-011 | One accessibility element, label from `ResetTicketText.accessibilityLabel`, actions "Open usage page". | Compliant |
| FR-012 | Glyphs are filtered at `times.now` on every dropdown tick. | Compliant |
| FR-013 | No menu bar change; groups and budgets get no glyphs. | Compliant |
| FR-014 | `ResetTicketExpiryTracker` groups by expiry and uses strict "less than" ranges. A first sighting at 24 h settles both steps. Since the review, a changed login no longer counts the tickets of refreshes started before the change. | Compliant |
| FR-015 | `ResetTicketExpiryAlert.title/body`, absolute time; no token or id. | Compliant |
| FR-016 | `UserDefaultsResetTicketNoticeStore` (`freeResetNotices`), pruned by expiry and by removed account. | Compliant |
| FR-017 | `notifyFreeResetExpiry`, default true; the Settings toggle; a suppressed step counts as delivered. Since the review, queued reminders are dropped when the switch is off at drain time. | Compliant |
| FR-018 | `PendingNotificationQueue`, "no app bundle" log; no tracker in the demo build. | Compliant |
| FR-019 | Once-per-kind failure lines, flag-drop line, delivered, suppressed and queued lines. | Compliant |
| FR-020 | README "Security and privacy" names the flag, the credit request, the 10 s limit, memory-only tickets and no redemption. The website mirror is with FR-022. | Compliant (README) |
| FR-021 | `Resources/demo/default.json` gives the first Claude account two tickets; the coverage report has `resetTicketsWithExpiry` and `resetTicketsWithoutExpiry`. | Compliant |
| FR-022 | Recapture and card candidates entry, in the site repository. | Pending |
| FR-023 | Merge order of the dependencies. | Pending (merge time) |

## Edge cases

All 20 are handled. The ones a reviewer may want to check:

- **Claude without a request:** no sign-in clears the tickets; an expired or unreadable credential keeps them (`applyTickets`).
- **Codex without a request** (not due, blocked, no sign-in): the tickets are kept minus expired. With live limits off there is no request and no glyphs.
- **Flag refused:** the plain repeat decides the usage; the tickets are cleared after a plain success and kept after a plain failure.
- **Implausible data:** more than 200 grants or more than 50 usable tickets, a negative or non-integer count, or a bad time clears the tickets.
- **Two accounts on one login:** Codex tickets are kept per home and notified per account.
- **Account renamed:** the record is keyed by account id, and the title uses the current display name.

## Extra behavior (not in the spec)

- A changed Claude Code directory or Codex home clears that account's tickets, resets the flag and logs failures afresh, as the sources already do for usage values. This is helpful and follows the existing per-directory rule.
- From the review: reminders queued while permission is pending are dropped when they expire before permission arrives, and a group that reached the 24-hour step while queued posts once. Both follow FR-012 and FR-014.

## Spec evolution candidates

- FR-005 says the credit request "never holds up the refresh". In the code it can hold up the refresh for up to 10 s (NOTABLE-1). The maintainer can either reword the spec or move the request off the critical path.
- FR-001 says "after each successful plan-limit request", which leaves no room for backing off from a credit endpoint that keeps failing (NOTABLE-2).
- contracts/external-sources.md could limit the raw Codex `credits` list (FINDING-17), and contracts/texts.md could log the refusal code (FINDING-18).

## Conclusion

The code matches the spec. The deep review found no Critical issues and 5 Important ones, and all 5 were fixed in round 1:

- 3 test gaps around FR-004.
- 2 Codex findings: queued reminders that ignored the switch, and an in-flight snapshot after a login change.

8 Minor findings were also fixed. 5 Minor findings remain, and none of them blocks. Two of them change a contract and need the maintainer's decision.

## Code Review Guide

These are the places where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Subscription/SubscriptionSource.swift`, `attempt` and `applyTickets`. This is the FR-004 flag state machine, and the rule that the plain result alone decides usage and credential health. Read it with `SubscriptionSourceTicketTests`.
2. `Sources/UsageCore/Subscription/ResetTickets.swift`. These are the lenient decoders of the two undocumented sources and the keep or clear rule (FR-002, FR-003). They decide what an unexpected answer does.
3. `Sources/UsageCore/Notifications/ResetTicketExpiryTracker.swift` with `ResetTicketNoticeStore.swift`. They cover the two steps, the persisted record and the identity fence from the review (FR-014, FR-016, FR-017).
4. `Sources/UsageCore/Subscription/CodexLimitsSource.swift` and `CodexUsageClient.fetchResetCredits`. The credit request follows the plan-limit request, uses 10 s, and keeps its tickets per home (FR-001, FR-005).
5. Walkthrough:
   - Hover and click the glyphs in both dropdown themes.
   - Shrink the dropdown with a long account name.
   - Turn the switch off while the permission prompt is open.

## Deep Review Report

**Gate:** PASS (after fix round 1; the re-review of the fix commits 5b9919c..2626be3 by CodeRabbit and Codex found nothing)
**Details:** specs/033-free-reset-tickets/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 3 | 2 | 1 | completed (1 Notable; FINDING-7 also reported by Architecture) |
| Architecture & Idioms | 8 | 4 | 4 | completed (3 Minor, 1 Notable left) |
| Security | 3 | 1 | 2 | completed (1 Minor, 1 Notable left) |
| Production Readiness | 3 | 0 | 3 | completed (1 Minor, 2 Notable) |
| Test Quality | 5 | 5 | 0 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch and fix commits) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 2 | 2 | 0 | completed (branch and fix commits; tests blocked by its sandbox) |
| Test Suite (regression) | 0 | 0 | 0 | passed |
| **Total** | **24** | **14** | **10** | |

After merging duplicates, the review found 0 Critical, 5 Important (all fixed), 13 Minor (8 fixed, 5 remaining) and 5 Notable findings. The Notables were captured to brainstorm/idea-inbox.md.

MVP: Architecture & Idioms (8 findings).

Key fixes applied:

1. The FR-004 tests now pin these rules (b9a1ee5, test quality):
   - The plain result alone decides the entry: a refusal followed by a different plain failure.
   - A 5xx answer is not repeated.
   - The suspended flag survives failed plain requests.
   - The exact sequences after 401 and 429.
2. Expiry reminders are fenced after a login change in the settings, and Codex accounts with live limits off never notify (2626be3, Codex).
3. Queued reminders are rechecked at drain time (2626be3, Codex and correctness):
   - Dropped when the switch is off or the expiry has passed.
   - The 24-hour step replaces a queued 3-day alert.
   - Logged when queued.
4. A login change logs ticket read failures afresh (2626be3, correctness and architecture). A stored epoch out of range no longer traps (2626be3, security). The temporary failure label is now "undecodable" (2626be3, architecture).

Remaining Minor findings (none of them blocks):

- FINDING-14: duplicated ticket bookkeeping in the two sources (refactor).
- FINDING-15: the `includeTickets` Bool shapes the result (API cleanup).
- FINDING-16: the authorization gate is written three times in the presenter.
- FINDING-17: no limit on the raw Codex `credits` list (contract change, needs a decision).
- FINDING-18: the refusal code and suspend transitions are not logged (log text contract, needs a decision).

Post-fix spec coverage: 22 of 22 code requirements verified. FR-022 and FR-023 are pending (recapture, site entry, merge order).

Notable observations: 5 captured to brainstorm/idea-inbox.md (`codex-credit-off-critical-path`, `codex-credit-backoff`, `flag-refusal-on-403`, `expiry-record-emitted-vs-posted`, `same-directory-login-switch`).

Test results after fixes: `make build` is clean, and `make test` passed (1877 + 70).
