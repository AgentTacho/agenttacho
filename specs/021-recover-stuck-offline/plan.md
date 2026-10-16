# Implementation Plan: Recover From a Stuck Offline State

**Branch**: `021-recover-stuck-offline` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/021-recover-stuck-offline/spec.md`

## Summary

Both usage clients get a fresh, invalidated `URLSession` per request from a shared `UsageSession.make()` (R1). A `NetworkFailureDetail` carried in `UsageEndpointError.network` puts the URL error's domain, code, underlying error and stream code into the diagnostic log only (R2). `FailureCategory.isNoAnswer` separates no-answer failures from HTTP answers; the Claude source keeps a per-account no-answer set and the Codex fetch gate a per-home flag (R3). A manual click (also when merged into another pending trigger) lets `EndpointPolicy` return `.fetchNoAnswer`, the coordinator then runs the sources in a "no-answer accounts only" mode, and the Codex gate bypasses its per-home spacing; rate-limit waits still win (R4, R5). README gains one clause (R6).

## Global Constraints

- Build and test only with `make test`, `make app`.
- Logic in `UsageCore`, tests first; doc comments cite `spec 021 FR-...`; no em or en dash characters.
- No token, header value, ChatGPT account ID or email address in any log line or error text.
- Numbers from the spec, unchanged: 30 s request timeout, 45 s total limit, 60 s manual spacing.
- Research R7 lists implementation details from the plan review; they are binding.

## Technical Context

**Language/Version**: Swift 5.10

**Primary Dependencies**: Foundation (`URLSession`, `URLError`); no new dependencies

**Storage**: none

**Testing**: Swift Testing via `make test` (`StubURLProtocol` for HTTP)

**Target Platform**: macOS 14 or newer, Apple Silicon

**Project Type**: desktop menu bar app (`UsageCore` plus thin `AgentMeter`)

**Constraints**: README "Security and privacy" stays true and is updated in the same change (AGENTS.md)

**Scale/Scope**: about 7 `UsageCore` files, 1 app comment, README, one design doc line

## Constitution Check

`.specify/memory/constitution.md` is the unfilled template; `AGENTS.md` is the gate:

| Rule | Status |
|---|---|
| Makefile only | Pass |
| Logic in `UsageCore`, tests first | Pass: all decisions in `UsageCore`; App.swift only a comment |
| Doc comments cite specs | Pass |
| No em or en dashes | Pass |
| Credentials and network: README stays true | Pass: privacy settings unchanged; README names the extra request (FR-010) |

Post-design re-check: unchanged, pass.

## Project Structure

```text
Sources/UsageCore/Subscription/UsageEndpointClient.swift  # UsageSession, per-request session, NetworkFailureDetail, .network(_, detail:)
Sources/UsageCore/Subscription/CodexUsageClient.swift     # per-request session, detail
Sources/UsageCore/Snapshot/FailureCategory.swift          # isNoAnswer
Sources/UsageCore/Snapshot/EndpointPolicy.swift           # decide(noAnswerRetry:), Decision.fetchNoAnswer
Sources/UsageCore/Snapshot/RefreshCoordinator.swift       # RefreshContext fields, pendingManual, no-answer-only mode, log line
Sources/UsageCore/Subscription/SubscriptionSource.swift   # noAnswer set, noAnswerAccounts(), restricted collect, log detail
Sources/UsageCore/Subscription/CodexLimitsSource.swift    # FetchGate.lastNoAnswer, manual bypass, log detail
Sources/AgentMeter/App.swift                              # comment at refreshNow()
README.md                                                 # tokens bullet (FR-010)
docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md  # manual spacing amended by spec 021
Tests/UsageCoreTests/...                                  # see tasks.md
```

**Structure Decision**: existing files; no new targets.

## Complexity Tracking

No violations. The two-init client design (R1) keeps about 45 test call sites unchanged.
