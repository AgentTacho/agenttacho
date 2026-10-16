# Data Model: Keep Last Good Values

All types live in `UsageCore` unless noted. Swift names are proposals for the implementation.

## FailureCategory (new, `Snapshot/FailureCategory.swift`)

```swift
public enum FailureCategory: String, Equatable, Sendable {
    case transport, signInRejected, rateLimited, serviceChanged
    public static func classify(_ error: Error) -> FailureCategory
}
```

| Error | Category |
|---|---|
| `UsageEndpointError.network` | transport |
| `UsageEndpointError.httpStatus(500...599)` | transport |
| `UsageEndpointError.httpStatus(401)`, `.httpStatus(403)` | signInRejected |
| `UsageEndpointError.rateLimited` | rateLimited |
| `UsageEndpointError.decoding`, `.httpStatus(any other)` | serviceChanged |
| `CodexUsageError.noLimits` | serviceChanged |
| any other error type | transport |

Spec: FR-001. Failures before a request (credential read, expired, missing, remembered rejected token) are not classified (FR-002).

## RetryEpisodes (new, `Snapshot/RetryEpisodes.swift`)

Per-account failure-episode state, a plain value type owned by each network source.

```swift
public struct RetryEpisodes: Equatable, Sendable {
    public static let delay: TimeInterval = 30
    public enum Phase: Equatable, Sendable {
        /// A quick retry is due at `retryAt`; `unmarked` keeps the shown values unmarked.
        case grace(retryAt: Date, unmarked: Bool)
        /// The episode's quick retry was used or is not available.
        case exhausted
    }
    public private(set) var phases: [String: Phase]
    public mutating func succeeded(_ id: String)
    /// Returns the phase after a failed request.
    public mutating func failed(_ id: String, category: FailureCategory, now: Date, hasLiveValuesThisRun: Bool) -> Phase
    /// Grace ended without a request (blocked at retry time): the episode is exhausted.
    public mutating func expire(_ id: String)
    public func retryAt(_ id: String) -> Date?
    public mutating func forget(except ids: Set<String>)
}
```

Transitions (per account):

| From | Event | To |
|---|---|---|
| none | success | none |
| none | failure, transport | grace(now + 30 s, unmarked = has live values this run) |
| none | failure, other category | exhausted |
| grace | success | none |
| grace | failure (any) | exhausted (shown stale) |
| grace | retry time passed, no request (blocked) | exhausted (shown stale) |
| exhausted | success | none |
| exhausted | failure | exhausted |

Spec: FR-004 to FR-009, Key Entities "Failure episode", "Grace period".

## SubscriptionState (changed, `Snapshot/UsageSnapshot.swift`)

New cases:

```swift
/// Transport failure inside a grace period: values shown unmarked (FR-005).
case retrying(lastGoodAt: Date?, error: String, retryAt: Date)
/// The usage service rejected the sign-in (FR-010).
case signInRejected(lastGoodAt: Date?)
```

| State | Bar `~` (with a percent) | Dropdown note | Style | Threshold evaluation |
|---|---|---|---|---|
| `.ok` | no | none | | yes |
| `.retrying` | no | "Couldn't reach the usage service, retrying at HH:MM" (or the failure text for 5xx) | secondary | no (values unchanged) |
| `.stale` | yes | "Stale, last good value ..." + reason (unchanged) | orange | no |
| `.signInRejected` | yes | "Sign-in rejected, run claude to sign in again" (+ last good time; non-default directory named) | red | no |
| `.credentialsExpired` | yes when a status exists (changed: today the bar shows `--`; spec 010 FR-015 needs saved values marked stale) | unchanged | orange | no |
| `.notSignedIn` | no values | unchanged | secondary | no |

`isOk` stays true only for `.ok`. A new `isStale` covers `.stale`, `.signInRejected` and `.credentialsExpired`. In the coordinator, `.signInRejected` is a source error like `.stale` (footer "stale", error line, holds back `lastSuccessfulRefreshAt`); `.retrying` is not a source error but also holds back `lastSuccessfulRefreshAt`.

## SubscriptionEntry (changed)

Adds `quickRetryAt: Date?` (set while the account's episode has a pending quick retry, also when the shown values are stale or absent; the coordinator schedules its timer from it), `endingGrace(now:) -> SubscriptionEntry`: a `.retrying` entry whose `retryAt <= now` becomes `.stale(lastGoodAt:error:)`; other entries are returned unchanged (research R3), and `reused(now:) -> SubscriptionEntry` for a result reused without a request: the entry stays as it is (`.retrying` included) while its retry's due window (`retryAt + 30 s`) is open, and ends stale without a retry time once it passed. The failure category is not stored in the entry: the state already carries what it decides (grace, stale, rejected sign-in), and the diagnostic log records it (FR-003).

## SubscriptionStatus and ModelLimit (changed)

- `ModelLimit.resetsAt` becomes `Date?`.
- `SubscriptionStatus.effective(now:) -> SubscriptionStatus`: every window whose reset time is `<= now` shows 0% and `resetsAt = nil` (FR-016, research R7).

## CodexLimitsState and CodexLimitsEntry (changed, `Subscription/CodexLimits.swift`)

- New state `.retrying(reason: String, retryAt: Date)`: `isStale` false; `impliedLiveLimits` true.
- `CodexLimitsEntry.quickRetryAt: Date?`, as for `SubscriptionEntry`.
- `CodexLimitsEntry.signInRejected: Bool` (default false): true when the shown reason is a rejected sign-in, from a 401/403 answer or the remembered-token case (FR-012).
- `CodexLimitsSource.Failure` gains `category: FailureCategory?` and `signInRejected: Bool`.

## UsageSnapshot (changed)

Adds `isPreliminary: Bool` (default false): true only for the early result built from saved values at launch (FR-015, research R6).

## RefreshTrigger and EndpointPolicy (changed, `Snapshot/EndpointPolicy.swift`)

- `RefreshTrigger.quickRetry`, rank 2.
- `EndpointPolicy.decide(.quickRetry, now:)`: `.reuse(reason: "rate limited until HH:MM", retryAt: nil)` while blocked; otherwise `.fetch`. It does not set or reset `retryUsed` and ignores spacing and "already fresh".

## LastGoodValues and LastGoodStore (new, `Snapshot/LastGoodStore.swift`)

```swift
public struct SavedClaudeValues: Codable, Equatable, Sendable {
    public var credentialDirectory: String   // canonical path
    public var fetchedAt: Date
    public var fiveHour: SavedWindow?
    public var sevenDay: SavedWindow?
    public var modelLimits: [SavedModelLimit]
}
public struct SavedCodexValues: Codable, Equatable, Sendable {
    public var codexHome: String              // canonical path
    public var observedAt: Date
    public var planType: String?
    public var windows: [SavedCodexWindow]   // lengthMinutes, usedPercent, resetsAt?, limitReached
}
public struct LastGoodValues: Codable, Equatable, Sendable {
    public var version: Int                   // 1
    public var claude: [String: SavedClaudeValues]
    public var codex: [String: SavedCodexValues]
}
public actor LastGoodStore {
    public init(fileURL: URL, initial: LastGoodValues?, log: DiagnosticLog?)
    public static func load(from url: URL) -> (LastGoodValues?, problem: String?)
    /// The values loaded at launch plus every replace since; sources seed from it.
    public func values() -> LastGoodValues
    public func replace(claude: [String: SavedClaudeValues])
    public func replace(codex: [String: SavedCodexValues])
}
```

Writes: atomic replace, then `chmod 0600` on the new file after every write; the directory is created with 0700 and an existing directory is tightened to 0700. A failed write is logged once per launch and never shown to the user. `SavedModelLimit.resetsAt` is optional from the start (matching the changed `ModelLimit`).

Seeding: a source seeds its in-memory last good values once, on its first `collect` or `savedOutput`, from `values()`; saved times later than `now` are clamped to `now` (spec edge case "Clock moved backwards").

Validation: unknown `version`, undecodable JSON or a missing file load as nil (FR-018); the problem string is logged once by the caller. Values never include tokens, account ids of credentials, or plan type for Claude (FR-013, FR-014). File format: `contracts/last-good-file.md`.

## SavedValuesSource (new protocol, `Snapshot/RefreshCoordinator.swift`)

```swift
public protocol SavedValuesSource: UsageSource {
    /// Entries built from saved values for accounts still configured with the
    /// same canonical directory; nil when there are none.
    func savedOutput(configuration: Configuration, now: Date) async -> SourceOutput?
}
```

Adopted by `SubscriptionSource` (returns `.subscriptions` with `.ok` entries) and `CodexLimitsSource` (returns `.codexLimits` with the newer of saved live and newest snapshot).
