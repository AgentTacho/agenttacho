# Data Model: Recover From a Stuck Offline State

No persisted data changes.

| Type | Change |
|---|---|
| `UsageSession` (new) | `configuration()`, `make()`: ephemeral, no cache, no cookies, 45 s resource limit |
| `NetworkFailureDetail` (new) | `domain`, `code`, `underlyingDomain?`, `underlyingCode?`, `streamErrorCode?`; log-only description |
| `UsageEndpointError.network` | gains `detail: NetworkFailureDetail? = nil`; `description` unchanged; new `logDescription` |
| `FailureCategory` | `isNoAnswer(_:)` |
| `EndpointPolicy.Decision` | new `.fetchNoAnswer(retryAt: Date?)`; `decide(_:now:noAnswerRetry:)` |
| `RefreshContext` | `manualRequested`, `claudeNoAnswerOnly` (default false) |
| `SubscriptionSource` | `noAnswer: Set<String>` per account; `noAnswerAccounts()` via `NetworkBoundSource` |
| `CodexLimitsSource.FetchGate` | `lastNoAnswer: Bool` per Codex home |
| `RefreshCoordinator` | `pendingManual`; `performRefresh(... manualMerged:)` |
