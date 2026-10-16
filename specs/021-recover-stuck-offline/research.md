# Research: Recover From a Stuck Offline State

Facts were mapped against the code on 2026-10-16 (file:line references are approximate after edits).

## R1: Session per request (FR-001, FR-002)

- **Facts**: both clients hold `public static let defaultSession` (ephemeral, no cache, no cookies, `timeoutIntervalForResource = 45`) and take `session: URLSession = defaultSession` in their init; App.swift constructs `UsageEndpointClient()` and `CodexUsageClient()`; about 45 tests inject `StubURLProtocol.makeSession()` and sometimes reuse one session for several fetches.
- **Decision**: `enum UsageSession { static func configuration() -> URLSessionConfiguration; static func make() -> URLSession }` with today's settings, shared by both clients. Each client stores a `SessionSource`: `.perRequest(@Sendable () -> URLSession)` (production; the client calls `finishTasksAndInvalidate()` in a `defer` after each request) or `.shared(URLSession)` (tests; never invalidated). Inits: `init(makeSession: @escaping @Sendable () -> URLSession = UsageSession.make, ...)` and `init(session: URLSession, ...)` without a default, so they are not ambiguous and existing tests keep compiling. `defaultSession` is removed.
- **Alternatives**: recreating only after repeated failures, or on path changes (out of scope); migrating all tests to `makeSession:` (larger diff, same effect).

## R2: Error detail in the log only (FR-007, FR-008)

- **Facts**: clients map `URLError` to `UsageEndpointError.network(localizedDescription)`; that string becomes the log note and the UI state (`.retrying` / `.stale(error:)`), `sourceErrors`, the dropdown, and `GraceNote.reason` matching. Codex shows reason "offline" and logs `detail(of:)`.
- **Decision**: `public struct NetworkFailureDetail: Equatable, Sendable, CustomStringConvertible { domain, code, underlyingDomain?, underlyingCode?, streamErrorCode? }`, `init(_ error: URLError)` reading only those values (`NSUnderlyingErrorKey` as `NSError` domain and code, `_kCFStreamErrorCodeKey` as `Int`); description `NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50`. `case network(String, detail: NetworkFailureDetail? = nil)`; `description` unchanged; new `logDescription` = description plus ` [detail]`. Claude log note and Codex `detail(of:)` use `logDescription`; UI strings keep `description`.

## R3: No-answer classification and state (spec definition, FR-003c)

- **Decision**: `FailureCategory.isNoAnswer(_ error: Error) -> Bool` = `classify == .transport` and not `UsageEndpointError.httpStatus`. `FetchOutcome` stays as is (its `combined()` and tests unchanged). `SubscriptionSource` keeps `private var noAnswer: Set<String>` (insert on a no-answer failure, remove on success or any HTTP answer, prune with removed accounts, clear on credential directory change) and exposes `noAnswerAccounts()` through `NetworkBoundSource` (default `[]` in the protocol extension). `CodexLimitsSource.FetchGate` gains `lastNoAnswer` (set on failure from `isNoAnswer`, cleared on success).

## R4: Manual bypass (FR-003, FR-003b, FR-003c)

- **Facts**: `EndpointPolicy.decide` reuses manual-type triggers within 60 s ("last fetch N s ago"); a rate-limit block wins before that; the coordinator then runs a reprice from `lastNetworkResults`. The quick retry asks only due accounts inside `SubscriptionSource.collect` (kept entries get `fetchOutcome = nil`, `reachedService = false`). Codex `decide` spaces manual-type triggers per home via `FetchGate.lastFetchAt`.
- **Decision**: `RefreshContext` gains `manualRequested` and `claudeNoAnswerOnly` (default false). `EndpointPolicy.decide(_:now:noAnswerRetry: Bool = false)` returns new `Decision.fetchNoAnswer(retryAt:)` instead of the spacing reuse (and the merged `.retry` "already fresh" reuse) when `noAnswerRetry`; blocks and `.local` unchanged. The coordinator computes `manual = trigger == .manual || manualMerged` (never for `.local`), asks the Claude source for `noAnswerAccounts()`, treats `.fetchNoAnswer` (and a pace reuse with no-answer accounts) as a full run with `claudeNoAnswerOnly = true`, and sets `endpointCalled` accordingly. `SubscriptionSource.collect` requests, in a restricted run, only accounts that are due for the quick retry or (manual and in `noAnswer`); new or changed accounts are requested as today. `CodexLimitsSource.decide` fetches when `manualRequested && gate.lastNoAnswer`, after the block and same-run checks. FR-003b follows from existing bookkeeping (`policy.record`, `recordPacedCalls`, Codex gate and `entry.attempted`).

## R5: Merged triggers (FR-003a, FR-006)

- **Facts**: `requestRefresh` keeps one pending trigger by rank (scheduled, retry, quickRetry 2; manual and other user triggers 1); the click itself is lost when outranked.
- **Decision**: `private var pendingManual` set by a manual request while running, reset per iteration, passed as `manualMerged` into `performRefresh`. Ranking and `merged()` unchanged. Clicks during a run collapse into one follow-up, which bypasses only if the running refresh left a no-answer state.

## R6: README (FR-010)

- **Decision**: extend the last sentence of the "The tokens are powerful" bullet: "..., one retry when a rate limit ends, and, when you click "Refresh now" within a minute of a request that could not reach the service, one more request for each account that got no answer."

## R7: Implementation notes from the plan review

- **Restricted run and the settings follow-up**: the coordinator's success path calls `cancelRetry()` unless the trigger is a quick retry; a no-answer-only run is exempt the same way: `(trigger != .quickRetry && !claudeNoAnswerOnly) || retryTrigger == .retry`.
- **Decision checks**: the sites that compare `decision == .fetch` (mode selection, pace branch, retry scheduling) must treat `.fetchNoAnswer` as a fetch for the restricted mode, and `scheduleRetry` also runs for `.fetchNoAnswer(retryAt:)` (the settings follow-up).
- **Restricted Claude collect rule**: `restricted = trigger == .quickRetry || claudeNoAnswerOnly`; in a restricted run an account is requested when `isRetryDue(id) || (manualRequested && noAnswer.contains(id))`, plus new or changed accounts as today.
- **Codex bypass placement and state**: in `CodexLimitsSource.decide`, insert `if manualRequested && gate.lastNoAnswer { return .fetch }` after the `blockedUntil` and `attemptedHome` checks and before `switch trigger`. On every `.failed`, `gate.lastNoAnswer = FailureCategory.isNoAnswer(error)`; on success `false`; on no request unchanged.
- **Pace bookkeeping**: when a pace reuse becomes a no-answer-only run, remove `.claude` from `pacedEndpoints` for that run so `recordCall(scheduled: true)` does not book it as a scheduled call.
- **Test seams**: a test `makeSession` closure must build a new stub session per call (a reused session would be invalidated after the first request); the invalidation test waits for `didBecomeInvalidWithError` with a confirmation or a polling timeout.
- **Concurrency**: the `RefreshContext` fields are `public var`; the default `makeSession` is written `{ UsageSession.make() }` so it stays warning-free under Swift 6 checking.
