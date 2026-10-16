# Tasks: Recover From a Stuck Offline State

**Input**: Design documents from `specs/021-recover-stuck-offline/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Required (AGENTS.md, test first). `make test` only.

## Conventions for every task

- Doc comments cite the spec requirements (for example `spec 021 FR-003`).
- No em dash or en dash characters anywhere.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.
- Research R1 to R7 hold the design; names below are binding.

## Interfaces (binding)

```swift
// UsageEndpointClient.swift
public enum UsageSession {
    public static func configuration() -> URLSessionConfiguration  // ephemeral, urlCache nil, reloadIgnoringLocalAndRemoteCacheData, no cookie storage, httpShouldSetCookies false, timeoutIntervalForResource 45
    public static func make() -> URLSession
}
public struct NetworkFailureDetail: Equatable, Sendable, CustomStringConvertible {
    public let domain: String; public let code: Int
    public let underlyingDomain: String?; public let underlyingCode: Int?
    public let streamErrorCode: Int?
    public init(_ error: URLError)   // reads only NSUnderlyingErrorKey (domain, code) and "_kCFStreamErrorCodeKey"
    // description: "NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50" (parts omitted when absent)
}
// UsageEndpointError: case network(String, detail: NetworkFailureDetail? = nil); description unchanged
//   public var logDescription: String  // description + " [\(detail)]" when detail != nil
// UsageEndpointClient / CodexUsageClient:
//   init(makeSession: @escaping @Sendable () -> URLSession = { UsageSession.make() }, url:, clock:[, userAgent:])  // per request, finishTasksAndInvalidate after
//   init(session: URLSession, url:, clock:[, userAgent:])  // shared, never invalidated (tests); no default value
//   defaultSession removed

// FailureCategory.swift
public static func isNoAnswer(_ error: Error) -> Bool  // classify == .transport && not UsageEndpointError.httpStatus

// EndpointPolicy.swift
// Decision: case fetchNoAnswer(retryAt: Date?)
// mutating func decide(_ trigger: RefreshTrigger, now: Date, noAnswerRetry: Bool = false) -> Decision

// RefreshCoordinator.swift
// RefreshContext: public var manualRequested = false; public var claudeNoAnswerOnly = false
// NetworkBoundSource: func noAnswerAccounts() async -> Set<String>  (extension default [])
// private var pendingManual = false; performRefresh(trigger:paceExempt:retryMerged:manualMerged:)

// CodexLimitsSource.swift: FetchGate.lastNoAnswer: Bool
```

---

## Phase 1: User Story 1 - Recovers by itself after a network change (P1)

- [X] T001 Run `make test` once for the baseline. Then write failing tests: in `Tests/UsageCoreTests/UsageEndpointClientTests.swift` and `Tests/UsageCoreTests/CodexUsageClientTests.swift`, `eachRequestUsesItsOwnSession` (a `makeSession` closure builds a new stub session per call, counts calls and records `ObjectIdentifier`s; the first fetch fails with a no-answer error and the second succeeds on a distinct session, SC-001), `sessionIsInvalidatedAfterTheRequest` (a probe delegate sees `didBecomeInvalidWithError`; the test waits with a confirmation or a polling timeout), `freshSessionKeepsPrivacySettings` (no cache, no cookies, 45 s resource limit from `UsageSession.configuration()`), `redirectStillRefusedWithFreshSession`; rewrite `defaultSessionNeverPersistsRequestsOrCookies` and `requestHasATotalTimeLimit` against `UsageSession`.
- [X] T002 Implement `UsageSession` and the two-init `SessionSource` in both clients per the Interfaces block; remove `defaultSession`; doc comments cite spec 021 FR-001, FR-002. App.swift keeps `UsageEndpointClient()` and `CodexUsageClient()`. Run `make test`.

**Checkpoint**: commit `fix(network): use a fresh session for each usage request`.

## Phase 2: User Story 3 - The log shows why a request failed (P3, needed by US2)

- [X] T003 Write failing tests: new `Tests/UsageCoreTests/NetworkFailureDetailTests.swift` (format with and without underlying error and stream code; no URL even when userInfo has `NSURLErrorFailingURLStringErrorKey`); `transportFailureCarriesDetail` in both client tests (stub throws `URLError(.notConnectedToInternet, userInfo: [NSUnderlyingErrorKey: NSError(domain: "kCFErrorDomainCFNetwork", code: -1009), "_kCFStreamErrorCodeKey": 50])`; if `StubURLProtocol` drops the userInfo, cover the end-to-end case through `NetworkFailureDetail(urlError)` unit tests and note it); `noAnswerFailureLogsTheErrorDetail` in `SubscriptionSourceTests` and in `CodexLimitsSourceTests` (log contains `NSURLErrorDomain -1009`, entry error text equals today's, no token or ChatGPT account ID); extend the existing credential-leak tests; update `mapsTransportFailureToNetworkError` to `case .network(let message, _)`; in `FailureCategoryTests` add `noAnswerCoversNetworkAndForeignErrors` and `httpAnswersAreNeverNoAnswer` (500, 503, 429, 401, 403, 302, decoding, `CodexUsageError.noLimits`).
- [X] T004 Implement `NetworkFailureDetail`, `.network(_, detail:)`, `logDescription`, `FailureCategory.isNoAnswer`; both clients throw with detail; `SubscriptionSource` log note and `CodexLimitsSource.detail(of:)` use `logDescription` while UI strings stay on `description` (spec 021 FR-007, FR-008). Run `make test`.

**Checkpoint**: commit `fix(network): log the underlying error of failed usage requests`.

## Phase 3: User Story 2 - "Refresh now" really retries (P2)

Research R4, R5 and R7 hold the design.

- [X] T005 Write failing tests in `Tests/UsageCoreTests/EndpointPolicyTests.swift` (`manualWithinSpacingAfterNoAnswerFetchesNoAnswerAccounts`, `noAnswerBypassRespectsRateLimitBlock`, `noAnswerBypassKeepsTheSettingsFollowUp`, `withoutNoAnswerManualStaysSpaced`) and `Tests/UsageCoreTests/SubscriptionSourceTests.swift` (`noAnswerOnlyRequestsOnlyNoAnswerAccounts`: accounts ok, offline, 503; only offline is requested, the others keep `fetchOutcome == nil` and `reachedService == false`; `noAnswerClearedBySuccessAndByAnHTTPAnswer`; `manualMergedIntoQuickRetryAlsoRequestsNoAnswerAccounts`).
- [X] T006 Implement `EndpointPolicy.decide(noAnswerRetry:)` and `.fetchNoAnswer`, the `RefreshContext` fields, and in `SubscriptionSource` the `noAnswer` set, `noAnswerAccounts()` and the restricted collect rule of R7. Run `make test`.
- [X] T007 Write failing tests in `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` (harness gains `manualRequested:`): `manualAfterNoAnswerBypassesHomeSpacing`, `manualAfterHTTP5xxStaysSpaced`, `manualAfterNoAnswerThen5xxStaysSpaced`, `noAnswerBypassRespectsTheRateLimitWait`, `otherTriggersStaySpacedAfterNoAnswer` (wake, dropdownOpen, idleReturn), `bypassCountsForHomeSpacingAndItsRateLimitSetsTheWait` (after a successful bypass the next manual within 60 s is not due; a 429 on the bypass sets the wait).
- [X] T008 Implement `FetchGate.lastNoAnswer` and the Codex bypass placement of R7. Run `make test`.
- [X] T009 Write failing tests in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` (`ScriptedNetworkSource` gains `noAnswer` and `noAnswerAccounts()`), each with explicit request counts:
  - `manualAfterNoAnswerSendsOneRequestPerService` (one Claude and one Codex request within 60 s);
  - `manualAfter5xxReusesWithinSpacing` (no request);
  - `nonManualTriggersStaySpacedAfterNoAnswer` (wake, dropdownOpen, settings, idleReturn: no request);
  - `bypassCountsForSpacingPaceAndDropdownOpen` (after the bypass, a wake within 60 s is reused and `shouldRefreshOnOpen()` is false; the pace does not record it as a scheduled call);
  - `bypassRateLimitSetsTheBlock`; `answeredAccountKeepsItsLastResult`;
  - `noAnswerRunKeepsThePendingSettingsFollowUp` (a pending settings follow-up survives a successful no-answer run and is scheduled from `.fetchNoAnswer(retryAt:)`);
  - `manualBeforeQuickRetryTakesItsPlace` (no-answer at t, manual at t+10 s, timer at t+31 s: two requests in total, "quick retry dropped" logged);
  - merged cases: `manualMergedIntoPendingScheduledKeepsTheBypass`, `manualMergedIntoPendingQuickRetrySendsOneRequest`, `manualMergedIntoPendingWakeKeepsTheBypass`, `clicksDuringARunningRefreshCollapseIntoOneFollowUp` (three clicks, one extra request), `followUpAfterAnAnsweredRunStaysSpaced`.
  Existing regression tests stay green unchanged: `refreshesWithoutARequestJustAfterTheRetryTimeKeepTheRetry`, `quickRetryCountsForSpacingAndItsRateLimitBlocks`, `manualTwiceWithinSpacingCallsTheEndpointOnce`, Codex `manualRefreshesAreSpaced`.
- [X] T010 Implement in `RefreshCoordinator`: `pendingManual` and `manualMerged`, the `manual` gate, the no-answer-only mode at the decision sites named in R7 (mode selection, pace branch, `scheduleRetry` for `.fetchNoAnswer(retryAt:)`, the `cancelRetry()` exemption, `endpointCalled`, removing `.claude` from `pacedEndpoints`), and the log line `endpoint fetched for no-answer accounts (Refresh now)`. Doc comments cite spec 021 FR-003, FR-003a to FR-003c, FR-004 to FR-006, FR-009. Run `make test`.
- [X] T011 Docs: update the comment at `Sources/AgentMeter/App.swift` `refreshNow()`; extend the "The tokens are powerful" bullet in `README.md` per research R6 (FR-010); add "(amended by spec 021 for no-answer failures)" to the manual spacing line in `docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md`. Scan the changed files for em and en dash characters (U+2014, U+2013). Run `make test` and `make app`.

**Checkpoint**: commit `fix(refresh): retry no-answer failures on Refresh now`. SC-004 (VPN or Wi-Fi toggle smoke test) is run in the walkthrough.

## Dependencies

T001, T002 (Phase 1) before T003, T004 (Phase 2, uses the clients) before Phase 3 (uses `isNoAnswer`): T005, T006, then T007, T008, then T009, T010 (needs both sources), then T011.
