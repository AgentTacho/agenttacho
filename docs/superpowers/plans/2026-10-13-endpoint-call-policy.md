# Endpoint Call Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Call Anthropic's usage endpoint only from the timer, launch, wake, "Refresh now" and subscription-relevant settings edits, with 60 s spacing for user triggers and a `Retry-After` backoff plus one retry after HTTP 429, so every scheduled refresh delivers fresh data.

**Architecture:** A pure value type `EndpointPolicy` decides per refresh trigger whether to fetch or reuse the last network result and computes blocks and retry times. `RefreshCoordinator` passes a `RefreshTrigger` into each run, consults the policy when the run starts, runs either the existing full refresh or the existing reprice path, records the fetch outcome, and owns a single retry task. `UsageEndpointClient` reports 429 with its `Retry-After` as a typed error, and `SubscriptionSource` attaches a `FetchOutcome` to each account entry.

**Tech Stack:** Swift 6 compiler (Swift 5.10 tools), Foundation, SwiftUI, Swift Testing, SwiftPM via `make`.

**Spec:** `docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md`

## Global Constraints

- Build and test only through the Makefile: `make test` and `make app`. Never call `swift test` directly. If tests fail with "catalog not found", run `rm -rf .build/out/Products/Debug/UsageCoreTests.xctest` and rerun.
- Spacing for `manual`, `wake` and `settings` triggers: 60 seconds (`EndpointPolicy.minimumSpacing = 60`), compared with `<` (exactly 60 s fetches).
- Backoff without `Retry-After`: 60 s, doubling per consecutive 429, capped at the configured refresh interval (`EndpointPolicy.defaultBackoff = 60`).
- The retry task sleeps until the block end plus 1 second.
- One block for all subscription accounts; nothing about fetches or blocks is persisted across launches.
- Never use em-dash or en-dash characters in code, comments, strings, docs or commit messages.
- Tests never touch the network, the keychain, `~/.config/llm-usage-menubar` or `~/Library/Logs`; use `StubURLProtocol` and `makeTempDirectory`.
- Follow the existing style: doc comments on public API, Swift Testing (`@Suite struct`, `@Test func`, `#expect`, `#require`).
- Every commit message ends with the line `Assisted-By: 🤖 Claude Code`.
- Work on a branch `endpoint-call-policy` created from `main`. Do not include the uncommitted `specs/002-price-import/RUNBOOK.md` in any commit.

## Review Focus

- `Retry-After: 0` must not leave the app stuck: the block ends immediately and the retry fetches (test in Task 1).
- "Refresh now" exactly 60 s after the last fetch must fetch, not reuse (boundary test in Task 1).
- Waking from sleep while a block is active must not call the endpoint (tests in Task 1 and Task 5).
- Changing the refresh interval while backing off must change the backoff cap on the next 429 (test in Task 1, coordinator sets the interval each run in Task 5).
- A scheduled tick arriving while a price reprice runs must win the pending slot and still fetch (test in Task 5).

---

### Task 1: EndpointPolicy, RefreshTrigger and FetchOutcome

**Files:**
- Create: `Sources/UsageCore/Snapshot/EndpointPolicy.swift`
- Test: `Tests/UsageCoreTests/EndpointPolicyTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public enum RefreshTrigger: String, Sendable, CaseIterable { case scheduled, launch, wake, manual, settings, retry, local }` with `public var rank: Int` (scheduled/retry 2; launch/wake/manual/settings 1; local 0).
  - `public enum FetchOutcome: Equatable, Sendable { case success, rateLimited(retryAfter: TimeInterval?), otherError }` with `public var isRateLimited: Bool` and `public static func combined(_ outcomes: [FetchOutcome]) -> FetchOutcome?`.
  - `public struct EndpointPolicy: Equatable, Sendable` with `public enum Decision: Equatable, Sendable { case fetch, reuse(reason: String, retryAt: Date?) }`, `public var refreshInterval: TimeInterval`, read-only `lastAttemptAt`, `lastOutcome`, `blockedUntil`, `consecutiveRateLimits`, `retryUsed`, `public init(refreshInterval: TimeInterval)`, `public mutating func decide(_ trigger: RefreshTrigger, now: Date) -> Decision`, `public mutating func record(_ outcome: FetchOutcome, now: Date) -> Date?`.

- [ ] **Step 1: Create the branch**

```bash
git checkout -b endpoint-call-policy
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/UsageCoreTests/EndpointPolicyTests.swift`:

```swift
import Foundation
import Testing
@testable import UsageCore

@Suite struct EndpointPolicyTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func fetched(_ policy: inout EndpointPolicy, at date: Date) {
        _ = policy.decide(.launch, now: date)
        _ = policy.record(.success, now: date)
    }

    private func isReuse(_ decision: EndpointPolicy.Decision, prefix: String) -> Bool {
        if case .reuse(let reason, _) = decision { return reason.hasPrefix(prefix) }
        return false
    }

    @Test func localAlwaysReusesEvenBeforeTheFirstFetch() {
        var policy = EndpointPolicy(refreshInterval: 300)
        #expect(isReuse(policy.decide(.local, now: t0), prefix: "local change"))
    }

    @Test func firstDecisionFetchesForEveryNetworkTrigger() {
        for trigger in RefreshTrigger.allCases where trigger != .local {
            var policy = EndpointPolicy(refreshInterval: 300)
            #expect(policy.decide(trigger, now: t0) == .fetch, "trigger \(trigger)")
        }
    }

    @Test func userTriggersAreSpacedBySixtySecondsWithAnInclusiveBoundary() {
        for trigger in [RefreshTrigger.manual, .wake, .settings] {
            var policy = EndpointPolicy(refreshInterval: 300)
            fetched(&policy, at: t0)
            #expect(isReuse(policy.decide(trigger, now: t0.addingTimeInterval(59)), prefix: "last fetch 59 s ago"), "trigger \(trigger)")
            #expect(policy.decide(trigger, now: t0.addingTimeInterval(60)) == .fetch, "trigger \(trigger)")
        }
    }

    @Test func scheduledAndLaunchIgnoreSpacing() {
        var policy = EndpointPolicy(refreshInterval: 300)
        fetched(&policy, at: t0)
        #expect(policy.decide(.scheduled, now: t0.addingTimeInterval(10)) == .fetch)
        #expect(policy.decide(.launch, now: t0.addingTimeInterval(10)) == .fetch)
    }

    @Test func retryAfterSuccessIsReusedAsAlreadyFresh() {
        var policy = EndpointPolicy(refreshInterval: 300)
        fetched(&policy, at: t0)
        #expect(isReuse(policy.decide(.retry, now: t0.addingTimeInterval(120)), prefix: "already fresh"))
    }

    @Test func rateLimitBlocksEveryTriggerUntilRetryAfter() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.decide(.launch, now: t0)
        let retryAt = policy.record(.rateLimited(retryAfter: 120), now: t0)
        #expect(retryAt == t0.addingTimeInterval(120))
        #expect(policy.blockedUntil == t0.addingTimeInterval(120))
        for trigger in [RefreshTrigger.scheduled, .launch, .wake, .manual, .settings, .retry] {
            #expect(isReuse(policy.decide(trigger, now: t0.addingTimeInterval(119)), prefix: "rate limited until"), "trigger \(trigger)")
        }
        #expect(policy.decide(.retry, now: t0.addingTimeInterval(120)) == .fetch)
    }

    @Test func wakeDuringABlockDoesNotFetch() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.decide(.launch, now: t0)
        _ = policy.record(.rateLimited(retryAfter: 600), now: t0)
        #expect(isReuse(policy.decide(.wake, now: t0.addingTimeInterval(300)), prefix: "rate limited until"))
    }

    @Test func retryAfterZeroDoesNotLeaveABlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.decide(.launch, now: t0)
        let retryAt = policy.record(.rateLimited(retryAfter: 0), now: t0)
        #expect(retryAt == t0)
        #expect(policy.decide(.retry, now: t0.addingTimeInterval(1)) == .fetch)
    }

    @Test func backoffDoublesAndCapsAtTheRefreshInterval() {
        var policy = EndpointPolicy(refreshInterval: 300)
        var waits: [TimeInterval] = []
        var now = t0
        for _ in 0..<5 {
            _ = policy.record(.rateLimited(retryAfter: nil), now: now)
            waits.append(policy.blockedUntil!.timeIntervalSince(now))
            now = policy.blockedUntil!
        }
        #expect(waits == [60, 120, 240, 300, 300])
    }

    @Test func backoffCapFollowsAChangedRefreshInterval() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        policy.refreshInterval = 90
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        #expect(policy.blockedUntil == t0.addingTimeInterval(90))
    }

    @Test func retryAfterHeaderWinsOverBackoff() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: 1000), now: t0)
        #expect(policy.blockedUntil == t0.addingTimeInterval(1000))
    }

    @Test func successResetsBackoffAndBlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0)
        _ = policy.record(.success, now: t0.addingTimeInterval(200))
        #expect(policy.blockedUntil == nil)
        #expect(policy.consecutiveRateLimits == 0)
        _ = policy.record(.rateLimited(retryAfter: nil), now: t0.addingTimeInterval(300))
        #expect(policy.blockedUntil == t0.addingTimeInterval(360))
    }

    @Test func onlyOneRetryPerScheduledPeriod() {
        var policy = EndpointPolicy(refreshInterval: 300)
        #expect(policy.record(.rateLimited(retryAfter: 60), now: t0) != nil)
        #expect(policy.record(.rateLimited(retryAfter: 60), now: t0.addingTimeInterval(61)) == nil)
        // A scheduled tick inside the block resets the allowance and asks for one retry.
        let decision = policy.decide(.scheduled, now: t0.addingTimeInterval(100))
        #expect(decision == .reuse(reason: decision.reason, retryAt: t0.addingTimeInterval(121)))
        #expect(policy.retryUsed)
        #expect(policy.record(.rateLimited(retryAfter: 60), now: t0.addingTimeInterval(121)) == nil)
    }

    @Test func otherErrorCountsForSpacingButDoesNotBlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        #expect(policy.record(.otherError, now: t0) == nil)
        #expect(policy.blockedUntil == nil)
        #expect(isReuse(policy.decide(.manual, now: t0.addingTimeInterval(10)), prefix: "last fetch"))
        #expect(policy.decide(.scheduled, now: t0.addingTimeInterval(10)) == .fetch)
    }

    @Test func clockMovingBackwardsExpiresTheBlock() {
        var policy = EndpointPolicy(refreshInterval: 300)
        _ = policy.record(.rateLimited(retryAfter: 3600), now: t0)
        #expect(policy.decide(.scheduled, now: t0.addingTimeInterval(-600)) == .fetch)
        #expect(policy.blockedUntil == nil)
    }

    @Test func combinedOutcomes() {
        #expect(FetchOutcome.combined([]) == nil)
        #expect(FetchOutcome.combined([.success, .success]) == .success)
        #expect(FetchOutcome.combined([.success, .otherError]) == .otherError)
        #expect(FetchOutcome.combined([.success, .rateLimited(retryAfter: 30), .rateLimited(retryAfter: 90)]) == .rateLimited(retryAfter: 90))
        #expect(FetchOutcome.combined([.rateLimited(retryAfter: nil), .otherError]) == .rateLimited(retryAfter: nil))
        #expect(FetchOutcome.combined([.rateLimited(retryAfter: nil), .rateLimited(retryAfter: 30)]) == .rateLimited(retryAfter: 30))
    }

    @Test func triggerRanks() {
        #expect(RefreshTrigger.scheduled.rank == RefreshTrigger.retry.rank)
        #expect(RefreshTrigger.retry.rank > RefreshTrigger.manual.rank)
        #expect(RefreshTrigger.manual.rank == RefreshTrigger.settings.rank)
        #expect(RefreshTrigger.launch.rank > RefreshTrigger.local.rank)
    }
}

extension EndpointPolicy.Decision {
    /// The reason of a reuse decision, empty for `.fetch` (test helper).
    var reason: String {
        if case .reuse(let reason, _) = self { return reason }
        return ""
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test 2>&1 | tail -20`
Expected: build failure, "cannot find 'EndpointPolicy' in scope".

- [ ] **Step 4: Implement `EndpointPolicy.swift`**

Create `Sources/UsageCore/Snapshot/EndpointPolicy.swift`:

```swift
import Foundation

/// Why a refresh runs. Decides, through `EndpointPolicy`, whether the
/// refresh may call the usage endpoint.
public enum RefreshTrigger: String, Sendable, CaseIterable {
    case scheduled, launch, wake, manual, settings, retry, local

    /// While a refresh runs, one pending trigger is kept: the one with the
    /// highest rank.
    public var rank: Int {
        switch self {
        case .scheduled, .retry: return 2
        case .launch, .wake, .manual, .settings: return 1
        case .local: return 0
        }
    }
}

/// Result of one usage endpoint request for an account.
public enum FetchOutcome: Equatable, Sendable {
    case success
    case rateLimited(retryAfter: TimeInterval?)
    case otherError

    public var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    /// One outcome for all accounts of a refresh: any rate limit wins (with
    /// the longest known wait), all successes are a success, anything else
    /// is an other error. Nil when no request was made.
    public static func combined(_ outcomes: [FetchOutcome]) -> FetchOutcome? {
        guard !outcomes.isEmpty else { return nil }
        var limited = false
        var longest: TimeInterval?
        for case .rateLimited(let wait) in outcomes {
            limited = true
            if let wait { longest = max(longest ?? wait, wait) }
        }
        if limited { return .rateLimited(retryAfter: longest) }
        return outcomes.allSatisfy { $0 == .success } ? .success : .otherError
    }
}

/// Decides whether a refresh calls the usage endpoint or reuses the last
/// network result, and tracks rate-limit blocks and the single retry
/// (docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md).
/// A plain value with no clock of its own: callers pass `now`.
public struct EndpointPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case fetch
        /// `retryAt` asks the caller to schedule one retry at that time.
        case reuse(reason: String, retryAt: Date?)
    }

    /// Minimum time between endpoint calls for `manual`, `wake` and `settings`.
    public static let minimumSpacing: TimeInterval = 60
    /// First backoff after a 429 without `Retry-After`; doubles per consecutive 429.
    public static let defaultBackoff: TimeInterval = 60

    /// Caps the backoff; the coordinator updates it from the configuration.
    public var refreshInterval: TimeInterval
    public private(set) var lastAttemptAt: Date?
    public private(set) var lastOutcome: FetchOutcome?
    public private(set) var blockedUntil: Date?
    public private(set) var consecutiveRateLimits = 0
    public private(set) var retryUsed = false

    public init(refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
    }

    public mutating func decide(_ trigger: RefreshTrigger, now: Date) -> Decision {
        if trigger == .scheduled { retryUsed = false }
        if trigger == .local { return .reuse(reason: "local change", retryAt: nil) }
        guard let last = lastAttemptAt else { return .fetch }
        if let until = blockedUntil {
            if now < last {
                // The clock moved backwards; never stay blocked because of it.
                blockedUntil = nil
            } else if now < until {
                var retryAt: Date?
                if trigger == .scheduled && !retryUsed {
                    retryUsed = true
                    retryAt = until
                }
                return .reuse(reason: "rate limited until \(until.formatted(date: .omitted, time: .shortened))", retryAt: retryAt)
            }
        }
        if trigger == .retry, let outcome = lastOutcome, !outcome.isRateLimited {
            return .reuse(reason: "already fresh", retryAt: nil)
        }
        let elapsed = now.timeIntervalSince(last)
        if [.manual, .wake, .settings].contains(trigger), elapsed < Self.minimumSpacing {
            return .reuse(reason: "last fetch \(Int(elapsed)) s ago", retryAt: nil)
        }
        return .fetch
    }

    /// Records the outcome of a fetch. Returns the time of the single retry
    /// to schedule, or nil.
    public mutating func record(_ outcome: FetchOutcome, now: Date) -> Date? {
        lastAttemptAt = now
        lastOutcome = outcome
        switch outcome {
        case .success:
            blockedUntil = nil
            consecutiveRateLimits = 0
            return nil
        case .otherError:
            return nil
        case .rateLimited(let retryAfter):
            let cap = max(refreshInterval, Self.defaultBackoff)
            let backoff = min(Self.defaultBackoff * pow(2, Double(consecutiveRateLimits)), cap)
            consecutiveRateLimits += 1
            let until = now.addingTimeInterval(retryAfter ?? backoff)
            blockedUntil = until
            guard !retryUsed else { return nil }
            retryUsed = true
            return until
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E 'EndpointPolicyTests|Test run with'`
Expected: `Suite EndpointPolicyTests passed`, and the final line reports all tests passed.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageCore/Snapshot/EndpointPolicy.swift Tests/UsageCoreTests/EndpointPolicyTests.swift
git commit -m "feat(refresh): add EndpointPolicy for usage endpoint calls

Assisted-By: 🤖 Claude Code"
```

---

### Task 2: Typed 429 with Retry-After in UsageEndpointClient

**Files:**
- Modify: `Sources/UsageCore/Subscription/UsageEndpointClient.swift` (error enum at the top, `fetch(token:)`)
- Modify: `Tests/UsageCoreTests/StubURLProtocol.swift` (response headers)
- Test: `Tests/UsageCoreTests/UsageEndpointClientTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `UsageEndpointError.rateLimited(retryAfter: TimeInterval?)`; `static func parseRetryAfter(_ value: String?, now: Date) -> TimeInterval?` on `UsageEndpointClient`; `StubURLProtocol.register(key:headers:handler:)`.

- [ ] **Step 1: Let the stub return response headers**

In `Tests/UsageCoreTests/StubURLProtocol.swift`, next to `handlers`, add:

```swift
    nonisolated(unsafe) private static var responseHeaders: [String: [String: String]] = [:]

    /// Like `register(key:handler:)`, with extra response headers.
    static func register(key: String, headers: [String: String], handler: @escaping Handler) {
        register(key: key, handler: handler)
        lock.lock(); defer { lock.unlock() }
        responseHeaders[key] = headers
    }
```

In `unregister(key:)` add `responseHeaders[key] = nil` inside the lock. In `startLoading()`, read the headers inside the existing lock section and merge them into the response:

```swift
        Self.lock.lock()
        let handler = Self.handlers[key]
        let extraHeaders = Self.responseHeaders[key] ?? [:]
        Self.requests[key, default: []].append(request)
        Self.lock.unlock()
```

```swift
            let fields = ["Content-Type": "application/json"].merging(extraHeaders) { _, new in new }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!
```

- [ ] **Step 2: Write the failing tests**

Append to the `UsageEndpointClientTests` suite:

```swift
    private func rateLimitError(headers: [String: String], key: String, now: Date = Date()) async -> UsageEndpointError? {
        let token = "tok-429-\(key)"
        StubURLProtocol.register(key: "Bearer \(token)", headers: headers) { _ in (429, Data("{}".utf8)) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = UsageEndpointClient(session: StubURLProtocol.makeSession(), clock: { now })
        do {
            _ = try await client.fetch(token: token)
            Issue.record("expected a 429 failure")
            return nil
        } catch let error as UsageEndpointError {
            return error
        } catch {
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    @Test func rateLimitWithDeltaSeconds() async {
        let error = await rateLimitError(headers: ["Retry-After": "120"], key: "delta")
        #expect(error == .rateLimited(retryAfter: 120))
        #expect(error?.description == "usage endpoint returned HTTP 429, retry after 120 s")
    }

    @Test func rateLimitWithHTTPDate() async {
        let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        let error = await rateLimitError(headers: ["Retry-After": "Tue, 13 Oct 2026 12:02:00 GMT"], key: "date", now: now)
        #expect(error == .rateLimited(retryAfter: 120))
    }

    @Test func rateLimitWithoutOrWithUnreadableHeader() async {
        #expect(await rateLimitError(headers: [:], key: "none") == .rateLimited(retryAfter: nil))
        #expect(await rateLimitError(headers: ["Retry-After": "soon"], key: "bad") == .rateLimited(retryAfter: nil))
        #expect(await rateLimitError(headers: ["Retry-After": "-5"], key: "neg") == .rateLimited(retryAfter: nil))
        let none = UsageEndpointError.rateLimited(retryAfter: nil)
        #expect(none.description == "usage endpoint returned HTTP 429")
    }

    @Test func httpDateInThePastMeansNoWait() {
        let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        #expect(UsageEndpointClient.parseRetryAfter("Tue, 13 Oct 2026 11:00:00 GMT", now: now) == 0)
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test 2>&1 | tail -20`
Expected: build failure, "type 'UsageEndpointError' has no member 'rateLimited'".

- [ ] **Step 4: Implement**

In `UsageEndpointClient.swift`, extend the error enum:

```swift
public enum UsageEndpointError: Error, Equatable, CustomStringConvertible {
    case httpStatus(Int)
    /// HTTP 429; `retryAfter` from the `Retry-After` header, nil when absent or unreadable.
    case rateLimited(retryAfter: TimeInterval?)
    case decoding(String)
    case network(String)

    public var description: String {
        switch self {
        case .httpStatus(let code): return "usage endpoint returned HTTP \(code)"
        case .rateLimited(let wait):
            return "usage endpoint returned HTTP 429" + (wait.map { ", retry after \(Int($0.rounded(.up))) s" } ?? "")
        case .decoding(let detail): return "usage endpoint response could not be decoded: \(detail)"
        case .network(let detail): return "usage endpoint unreachable: \(detail)"
        }
    }
}
```

In `fetch(token:)`, directly before `guard http.statusCode == 200 else {`:

```swift
        if http.statusCode == 429 {
            throw UsageEndpointError.rateLimited(
                retryAfter: Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: clock()))
        }
```

Add to `UsageEndpointClient`:

```swift
    /// `Retry-After` as delta-seconds or HTTP-date (RFC 9110); nil when
    /// absent, negative or unreadable. A date in the past means no wait.
    static func parseRetryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) {
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E 'UsageEndpointClientTests|Test run with'`
Expected: suite passes; `mapsNon200ToHTTPStatus` (401, 403, 500) still passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageCore/Subscription/UsageEndpointClient.swift Tests/UsageCoreTests/StubURLProtocol.swift Tests/UsageCoreTests/UsageEndpointClientTests.swift
git commit -m "feat(subscription): report HTTP 429 with Retry-After

Assisted-By: 🤖 Claude Code"
```

---

### Task 3: FetchOutcome on subscription entries

**Files:**
- Modify: `Sources/UsageCore/Snapshot/UsageSnapshot.swift` (`SubscriptionEntry`)
- Modify: `Sources/UsageCore/Subscription/SubscriptionSource.swift` (`fetch(account:...)`)
- Test: `Tests/UsageCoreTests/SubscriptionSourceTests.swift`

**Interfaces:**
- Consumes: `FetchOutcome` (Task 1), `UsageEndpointError.rateLimited` (Task 2), `StubURLProtocol.register(key:headers:handler:)` (Task 2).
- Produces: `SubscriptionEntry.fetchOutcome: FetchOutcome?` and init parameter `fetchOutcome: FetchOutcome? = nil`.

- [ ] **Step 1: Write the failing tests**

Append to the `SubscriptionSourceTests` suite:

```swift
    @Test func fetchOutcomePerAccount() async throws {
        let dir = try makeTempDirectory("sub-outcome")
        defer { try? FileManager.default.removeItem(at: dir) }
        let okToken = "outcome-ok-\(Self.secret)"
        let limitedToken = "outcome-429-\(Self.secret)"
        let brokenToken = "outcome-net-\(Self.secret)"
        StubURLProtocol.register(key: "Bearer \(okToken)") { _ in (200, Data(usageResponseJSON.utf8)) }
        StubURLProtocol.register(key: "Bearer \(limitedToken)", headers: ["Retry-After": "30"]) { _ in (429, Data("{}".utf8)) }
        StubURLProtocol.register(key: "Bearer \(brokenToken)") { _ in throw URLError(.notConnectedToInternet) }
        defer {
            for t in [okToken, limitedToken, brokenToken] { StubURLProtocol.unregister(key: "Bearer \(t)") }
        }
        let reader = FakeCredentialReader()
        reader.credentials["~/a"] = OAuthCredential(accessToken: okToken, expiresAt: far)
        reader.credentials["~/b"] = OAuthCredential(accessToken: limitedToken, expiresAt: far)
        reader.credentials["~/c"] = OAuthCredential(accessToken: brokenToken, expiresAt: far)
        let (source, _) = makeSource(reader: reader, token: okToken, logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig(directories: ["~/a", "~/b", "~/c", "~/none"]))))
        #expect(out["acc-0"]?.fetchOutcome == .success)
        #expect(out["acc-1"]?.fetchOutcome == .rateLimited(retryAfter: 30))
        #expect(out["acc-2"]?.fetchOutcome == .otherError)
        #expect(out["acc-3"]?.state == .notSignedIn)
        #expect(out["acc-3"]?.fetchOutcome == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test 2>&1 | tail -20`
Expected: build failure, "value of type 'SubscriptionEntry' has no member 'fetchOutcome'".

- [ ] **Step 3: Implement**

In `UsageSnapshot.swift`, replace `SubscriptionEntry`:

```swift
public struct SubscriptionEntry: Equatable, Sendable {
    public var status: SubscriptionStatus?
    public var state: SubscriptionState
    public var breakdown: UsageBreakdown
    /// Outcome of this refresh's endpoint request; nil when no request was
    /// made (not signed in, credentials expired or unreadable).
    public var fetchOutcome: FetchOutcome?

    public init(status: SubscriptionStatus?, state: SubscriptionState, breakdown: UsageBreakdown = .empty,
                fetchOutcome: FetchOutcome? = nil) {
        self.status = status
        self.state = state
        self.breakdown = breakdown
        self.fetchOutcome = fetchOutcome
    }
}
```

In `SubscriptionSource.fetch(account:settings:previous:reader:client:now:)`, change the success return to:

```swift
            return (SubscriptionEntry(status: status, state: .ok, fetchOutcome: .success), "ok (5h \(five), 7d \(seven))")
```

and the final `catch` block to:

```swift
        } catch {
            let message = describe(error)
            let outcome: FetchOutcome
            if case .rateLimited(let wait)? = error as? UsageEndpointError {
                outcome = .rateLimited(retryAfter: wait)
            } else {
                outcome = .otherError
            }
            return (SubscriptionEntry(status: previous, state: .stale(lastGoodAt: previous?.fetchedAt, error: message), fetchOutcome: outcome),
                    "fetch failed: \(message)" + (previous == nil ? "" : ", keeping values from \(previous!.fetchedAt)"))
        }
```

The credential read failure, not signed in and expired paths keep `fetchOutcome` nil.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E 'SubscriptionSourceTests|Test run with'`
Expected: suite passes, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Snapshot/UsageSnapshot.swift Sources/UsageCore/Subscription/SubscriptionSource.swift Tests/UsageCoreTests/SubscriptionSourceTests.swift
git commit -m "feat(subscription): attach fetch outcome to subscription entries

Assisted-By: 🤖 Claude Code"
```

---

### Task 4: Configuration.needsNetworkRefresh

**Files:**
- Modify: `Sources/UsageCore/Config/Configuration.swift` (next to `needsRefresh(comparedTo:)`)
- Test: `Tests/UsageCoreTests/ConfigurationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public func needsNetworkRefresh(comparedTo old: Configuration) -> Bool`.

- [ ] **Step 1: Write the failing test**

Append to the `ConfigurationTests` suite (it already has `example()` returning the decoded contract example):

```swift
    @Test func needsNetworkRefreshOnlyForSubscriptionChanges() throws {
        let base = try example()

        var local = base
        local.priceOverrides[0].inputPerMTok += 1
        local.groups[0].weeklyBudgetUSD += 1
        local.logDirectories.append("~/elsewhere")
        local.accounts[1].customMarker = "project-x"
        local.accounts[0].label = "X"
        if case .subscription(var settings) = local.accounts[0].kind {
            settings.thresholds = [10]
            local.accounts[0].kind = .subscription(settings)
        }
        #expect(local.needsRefresh(comparedTo: base))
        #expect(!local.needsNetworkRefresh(comparedTo: base))

        var removed = base
        removed.accounts.remove(at: 0)
        removed.alignmentAccountId = nil
        #expect(removed.needsNetworkRefresh(comparedTo: base))

        var added = base
        added.accounts.append(Account(id: "acc-2", label: "W", displayName: "Work",
                                      kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude-work"))))
        #expect(added.needsNetworkRefresh(comparedTo: base))

        var directory = base
        if case .subscription(var settings) = directory.accounts[0].kind {
            settings.credentialDirectory = "~/.claude-other"
            directory.accounts[0].kind = .subscription(settings)
        }
        #expect(directory.needsNetworkRefresh(comparedTo: base))

        var realigned = added
        realigned.alignmentAccountId = "acc-2"
        #expect(realigned.needsNetworkRefresh(comparedTo: added))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure, "value of type 'Configuration' has no member 'needsNetworkRefresh'".

- [ ] **Step 3: Implement**

In `Configuration.swift`, directly after `needsRefresh(comparedTo:)`:

```swift
    /// True when going from `old` to this configuration changes what the
    /// usage endpoint is asked: subscription accounts added or removed, a
    /// credential directory, or the alignment account. Every other
    /// data-relevant edit only needs a local re-price.
    public func needsNetworkRefresh(comparedTo old: Configuration) -> Bool {
        subscriptionFingerprint() != old.subscriptionFingerprint()
    }

    private func subscriptionFingerprint() -> [String] {
        subscriptionAccounts
            .map { "\($0.id)|\($0.kind.subscription?.credentialDirectory ?? "")" }
            .sorted() + ["alignment|\(effectiveAlignmentAccountId ?? "")"]
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E 'ConfigurationTests|Test run with'`
Expected: suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Config/Configuration.swift Tests/UsageCoreTests/ConfigurationTests.swift
git commit -m "feat(config): tell subscription-relevant edits from local ones

Assisted-By: 🤖 Claude Code"
```

---

### Task 5: Triggers, policy and retry in RefreshCoordinator

**Files:**
- Modify: `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`
- Modify: `Sources/UsageCore/Snapshot/UsageSnapshot.swift` (`UsageSnapshot` fields)
- Test: `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`

**Interfaces:**
- Consumes: `RefreshTrigger`, `EndpointPolicy`, `FetchOutcome` (Task 1); `SubscriptionEntry.fetchOutcome` (Task 3).
- Produces:
  - `public func requestRefresh(trigger: RefreshTrigger = .scheduled)` (existing `requestRefresh()` calls keep compiling).
  - `public func refreshAndWait(trigger: RefreshTrigger = .scheduled) async -> UsageSnapshot`.
  - `requestReprice()` and `repriceAndWait()` unchanged in signature; they use `.local`.
  - init parameter `retrySleep: @escaping @Sendable (TimeInterval) async -> Void` with a default that sleeps for real.
  - `UsageSnapshot.endpointBlockedUntil: Date?`, `UsageSnapshot.nextRetryAt: Date?`.

- [ ] **Step 1: Add the snapshot fields**

In `UsageSnapshot`, add after `lastSuccessfulRefreshAt`:

```swift
    /// End of an active rate-limit block on the usage endpoint, if any.
    public var endpointBlockedUntil: Date?
    /// Time of the scheduled retry after a rate limit, if any.
    public var nextRetryAt: Date?
```

and in its `init` add parameters `endpointBlockedUntil: Date? = nil, nextRetryAt: Date? = nil` after `lastSuccessfulRefreshAt` with matching assignments.

- [ ] **Step 2: Extend the test helpers**

In `RefreshCoordinatorTests.swift`:

Change `subscriptionOutput` to carry an outcome:

```swift
func subscriptionOutput(percent: Double = 12, outcome: FetchOutcome? = .success) -> SourceOutput {
    let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: percent, resetsAt: isoDate("2026-10-13T12:00:00Z")),
                                    sevenDay: nil, fetchedAt: isoDate("2026-10-13T08:00:00Z"))
    let state: SubscriptionState = outcome?.isRateLimited == true
        ? .stale(lastGoodAt: nil, error: "usage endpoint returned HTTP 429") : .ok
    return .subscriptions(["acc-max": SubscriptionEntry(status: status, state: state, fetchOutcome: outcome)])
}
```

In `GatedNetworkSource`, change `private let output: SourceOutput` to `private var output: SourceOutput` and add:

```swift
    func setOutput(_ output: SourceOutput) { self.output = output }
```

Add next to `AdvancingClock`:

```swift
/// A clock tests move by hand.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

/// Stands in for the retry sleep: records each requested delay and waits
/// until `open()`.
actor SleepGate {
    private(set) var delays: [TimeInterval] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func sleep(_ delay: TimeInterval) async {
        delays.append(delay)
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
    }
}
```

Give `makeCoordinator` a `retrySleep` parameter whose default never fires during a test, and pass it on:

```swift
func makeCoordinator(configJSON: String = contractExampleJSON, name: String = "coord",
                     clock: @escaping @Sendable () -> Date = { Date() },
                     retrySleep: @escaping @Sendable (TimeInterval) async -> Void = { _ in try? await Task.sleep(for: .seconds(3600)) }) throws -> (RefreshCoordinator, URL) {
```

```swift
    let coordinator = RefreshCoordinator(configStore: store, log: log, resolver: WindowResolver(), aggregator: Aggregator(),
                                         calendar: utc, clock: clock, retrySleep: retrySleep)
```

- [ ] **Step 3: Write the failing tests**

Append to the `RefreshCoordinatorTests` suite:

```swift
    @Test func manualTwiceWithinSpacingCallsTheEndpointOnce() async throws {
        let clock = MutableClock(isoDate("2026-10-13T08:00:00Z"))
        let (coordinator, dir) = try makeCoordinator(name: "spacing", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput())
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        _ = await coordinator.refreshAndWait(trigger: .launch)
        clock.advance(30)
        _ = await coordinator.refreshAndWait(trigger: .manual)
        #expect(await network.calls == 1)
        clock.advance(30)
        _ = await coordinator.refreshAndWait(trigger: .manual)
        #expect(await network.calls == 2)

        let logText = try String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)
        #expect(logText.contains("trigger manual, endpoint reused (last fetch 30 s ago)"))
    }

    @Test func localTriggerNeverCallsTheEndpoint() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "local")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput())
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())
        _ = await coordinator.refreshAndWait(trigger: .launch)
        _ = await coordinator.refreshAndWait(trigger: .local)
        _ = await coordinator.repriceAndWait()
        #expect(await network.calls == 1)
    }

    @Test func rateLimitBlocksAndRetriesOnceAtTheBlockEnd() async throws {
        let start = isoDate("2026-10-13T08:00:00Z")
        let clock = MutableClock(start)
        let gate = SleepGate()
        let (coordinator, dir) = try makeCoordinator(name: "retry", clock: { clock.now() },
                                                     retrySleep: { await gate.sleep($0) })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(outcome: .rateLimited(retryAfter: 120)))
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.endpointBlockedUntil == start.addingTimeInterval(120))
        #expect(first.nextRetryAt == start.addingTimeInterval(120))
        #expect(await waitUntil { await gate.delays.count == 1 })
        #expect(await gate.delays.first == 121)

        // A scheduled tick and a wake inside the block reuse the last result.
        clock.advance(60)
        let blocked = await coordinator.refreshAndWait(trigger: .scheduled)
        _ = await coordinator.refreshAndWait(trigger: .wake)
        #expect(await network.calls == 1)
        #expect(blocked.subscriptions["acc-max"]?.state.isOk == false)
        #expect(blocked.nextRetryAt == start.addingTimeInterval(120))

        // The block ends; the retry fetches fresh data.
        await network.setOutput(subscriptionOutput(percent: 20))
        clock.advance(61)
        let before = await coordinator.refreshCount
        await gate.open()
        #expect(await waitUntil {
            let count = await coordinator.refreshCount
            let running = await coordinator.isRunning
            return count == before + 1 && !running
        })
        #expect(await network.calls == 2)
        let fresh = try #require(await coordinator.latestSnapshot)
        #expect(fresh.subscriptions["acc-max"]?.state.isOk == true)
        #expect(fresh.endpointBlockedUntil == nil)
        #expect(fresh.nextRetryAt == nil)
    }

    @Test func aRetryThatHitsAnotherLimitIsNotRetriedAgain() async throws {
        let start = isoDate("2026-10-13T08:00:00Z")
        let clock = MutableClock(start)
        let gate = SleepGate()
        let (coordinator, dir) = try makeCoordinator(name: "retry-twice", clock: { clock.now() },
                                                     retrySleep: { await gate.sleep($0) })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(outcome: .rateLimited(retryAfter: 120)))
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        _ = await coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await gate.delays.count == 1 })
        clock.advance(121)
        await gate.open()
        #expect(await waitUntil {
            let calls = await network.calls
            let running = await coordinator.isRunning
            return calls == 2 && !running
        })
        let snapshot = try #require(await coordinator.latestSnapshot)
        #expect(snapshot.nextRetryAt == nil)
        #expect(snapshot.endpointBlockedUntil == start.addingTimeInterval(241))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await gate.delays.count == 1)
    }

    @Test func pendingScheduledWinsOverPendingLocalReprice() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "pending-rank")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(), open: false)
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        await coordinator.requestRefresh(trigger: .launch)
        #expect(await waitUntil { await network.calls == 1 })
        await coordinator.requestRefresh(trigger: .local)
        await coordinator.requestRefresh(trigger: .scheduled)
        await coordinator.requestRefresh(trigger: .local)
        await network.release()
        #expect(await waitUntil {
            let running = await coordinator.isRunning
            let count = await coordinator.refreshCount
            return !running && count == 2
        })
        #expect(await network.calls == 2)
    }

    @Test func reusedResultsDropRemovedSubscriptionAccounts() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "reuse-filter")
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(GatedNetworkSource(output: subscriptionOutput()))
        await coordinator.register(FakeLogSource())
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.subscriptions["acc-max"] != nil)

        var config = try decodeConfig(contractExampleJSON)
        config.accounts.removeAll { $0.id == "acc-max" }
        config.alignmentAccountId = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: dir.appendingPathComponent("config.json"), options: .atomic)

        let second = await coordinator.repriceAndWait()
        #expect(second.subscriptions["acc-max"] == nil)
    }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `make test 2>&1 | tail -20`
Expected: build failure, "extra argument 'retrySleep' in call" and "extra argument 'trigger' in call".

- [ ] **Step 5: Implement the coordinator changes**

In `RefreshCoordinator.swift`:

Replace the properties `pending` and `pendingReprice` with:

```swift
    /// One trigger remembered while a refresh runs; the highest rank wins.
    private var pendingTrigger: RefreshTrigger?
    /// Decides per run whether the usage endpoint is called.
    private var policy = EndpointPolicy(refreshInterval: TimeInterval(Configuration.defaultRefreshIntervalSeconds))
    /// The single retry after a rate limit, and its time.
    private var retryTask: Task<Void, Never>?
    private var nextRetryAt: Date?
    private let retrySleep: @Sendable (TimeInterval) async -> Void
```

Extend `init` with a last parameter and assignment:

```swift
                calendar: Calendar = .current, clock: @escaping @Sendable () -> Date = { Date() },
                retrySleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
```

```swift
        self.retrySleep = retrySleep
```

Replace `requestRefresh()`, `requestReprice()`, `refreshAndWait()` and `runLoop(mode:)` with:

```swift
    /// Starts a refresh for `trigger`, or remembers it while one runs (one
    /// pending trigger, the highest `rank` wins). Whether the usage endpoint
    /// is called is decided by `EndpointPolicy` when the run starts.
    public func requestRefresh(trigger: RefreshTrigger = .scheduled) {
        if running {
            if pendingTrigger.map({ trigger.rank > $0.rank }) ?? true {
                pendingTrigger = trigger
            }
            return
        }
        running = true
        loopTask = Task { await self.runLoop(trigger: trigger) }
    }

    /// A refresh that never calls the usage endpoint and reuses the last
    /// network result (FR-023a). Used after price imports and local edits.
    public func requestReprice() {
        requestRefresh(trigger: .local)
    }

    /// Requests a refresh and waits until the coordinator is idle again.
    public func refreshAndWait(trigger: RefreshTrigger = .scheduled) async -> UsageSnapshot {
        requestRefresh(trigger: trigger)
        return await waitUntilIdle()
    }
```

Keep `repriceAndWait()` and `waitUntilIdle()` as they are. Replace `runLoop`:

```swift
    private func runLoop(trigger initial: RefreshTrigger) async {
        var trigger = initial
        while true {
            pendingTrigger = nil
            let snapshot = await performRefresh(trigger: trigger)
            refreshCount += 1
            latestSnapshot = snapshot
            previousSnapshot = snapshot
            continuation.yield(snapshot)
            guard let next = pendingTrigger else { break }
            trigger = next
        }
        running = false
    }
```

In `SourceResult`, change `let result` to `var result`.

Change the signature to `private func performRefresh(trigger: RefreshTrigger) async -> UsageSnapshot` and replace its mode selection (from `// A reprice needs a stored result` through the end of the `switch mode` block) with:

```swift
        policy.refreshInterval = TimeInterval(configuration.refreshIntervalSeconds)
        let networkSources = sources.filter { $0 is NetworkBoundSource }
        let decision = policy.decide(trigger, now: started)
        var mode: Mode = decision == .fetch ? .full : .reprice
        var reuseReason: String?
        if case .reuse(let reason, let retryAt) = decision {
            reuseReason = reason
            if let retryAt { scheduleRetry(at: retryAt) }
        }
        // A reprice needs a stored result for every network-bound source;
        // otherwise it runs as a full refresh.
        if mode == .reprice && !networkSources.allSatisfy({ lastNetworkResults[$0.name] != nil }) {
            log.append(source: "refresh", message: "no stored network result, running a full refresh")
            mode = .full
            reuseReason = nil
        }
        var results: [SourceResult]
        switch mode {
        case .full:
            results = await collect(from: sources, context: context)
            lastNetworkResults = [:]
            lastNetworkRefreshAt = started
            var outcomes: [FetchOutcome] = []
            for r in results where r.isNetworkBound {
                lastNetworkResults[r.name] = r
                switch r.result {
                case .success(.subscriptions(let entries)): outcomes += entries.values.compactMap(\.fetchOutcome)
                case .success(.records): break
                case .failure: outcomes.append(.otherError)
                }
            }
            if let outcome = FetchOutcome.combined(outcomes) {
                if let retryAt = policy.record(outcome, now: started) {
                    scheduleRetry(at: retryAt)
                } else if outcome == .success {
                    cancelRetry()
                }
            }
        case .reprice:
            results = await collect(from: sources.filter { !($0 is NetworkBoundSource) }, context: context)
            let configured = Set(configuration.subscriptionAccounts.map(\.id))
            for source in networkSources {
                var reused = lastNetworkResults[source.name]!
                reused.reused = true
                if case .success(.subscriptions(let entries)) = reused.result {
                    reused.result = .success(.subscriptions(entries.filter { configured.contains($0.key) }))
                }
                results.append(reused)
            }
        }
```

After `snapshot.lastSuccessfulRefreshAt = ...`, add:

```swift
        snapshot.endpointBlockedUntil = policy.blockedUntil.flatMap { $0 > started ? $0 : nil }
        snapshot.nextRetryAt = nextRetryAt
```

Replace the final "done" log call with:

```swift
        let endpointText: String
        if networkSources.isEmpty {
            endpointText = "no endpoint"
        } else if mode == .full {
            endpointText = "endpoint fetched"
        } else {
            endpointText = "endpoint reused (\(reuseReason ?? "reprice"))"
        }
        log.append(source: "refresh", message: String(format: "done in %.3f s, %d source error(s), window %@%@%@, trigger %@, %@",
                                                      elapsed, sourceErrors.count, windowText,
                                                      configError.map { ", config error: \($0.message)" } ?? "",
                                                      mode == .reprice ? ", reprice (network sources reused)" : "",
                                                      trigger.rawValue, endpointText))
```

Add the retry helpers to the actor:

```swift
    /// Replaces any pending retry with one at `date` (plus 1 s, so the
    /// block has ended when it runs).
    private func scheduleRetry(at date: Date) {
        retryTask?.cancel()
        nextRetryAt = date
        let delay = max(0, date.timeIntervalSince(clock())) + 1
        let sleep = retrySleep
        retryTask = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await self?.fireRetry()
        }
        log.append(source: "refresh", message: "endpoint retry scheduled at \(iso(date))")
    }

    private func fireRetry() {
        retryTask = nil
        nextRetryAt = nil
        requestRefresh(trigger: .retry)
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        nextRetryAt = nil
    }
```

Remove the now unused `Mode`-based `requested` variable and update the doc comment of `requestReprice` as above. The existing tests `repriceBeforeAnyRefreshIsAFullRefresh`, `repriceDuringRunningRefreshRunsOneFollowUpReprice` and `pendingFullRefreshWinsOverPendingReprice` must keep passing unchanged: `.local` before any fetch falls back to a full refresh, and `.scheduled` (rank 2) beats `.local` (rank 0).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E 'RefreshCoordinatorTests|Test run with|failed'`
Expected: `RefreshCoordinatorTests` passes, no failures anywhere.

- [ ] **Step 7: Commit**

```bash
git add Sources/UsageCore/Snapshot/RefreshCoordinator.swift Sources/UsageCore/Snapshot/UsageSnapshot.swift Tests/UsageCoreTests/RefreshCoordinatorTests.swift
git commit -m "feat(refresh): gate usage endpoint calls by trigger, back off and retry once after 429

Assisted-By: 🤖 Claude Code"
```

---

### Task 6: App triggers and the dropdown note

**Files:**
- Modify: `Sources/LLMUsageMenuBar/App.swift` (launch task, `refreshNow()`, `saveConfiguration(_:)`, `restartTimer(interval:)`, `observeWake()`)
- Modify: `Sources/LLMUsageMenuBar/DropdownView.swift` (`SubscriptionSection.stateLine`, `.stale` case)

**Interfaces:**
- Consumes: `requestRefresh(trigger:)` (Task 5), `Configuration.needsNetworkRefresh(comparedTo:)` (Task 4), `UsageSnapshot.nextRetryAt` and `endpointBlockedUntil` (Task 5).
- Produces: nothing for later tasks.

- [ ] **Step 1: Pass triggers in `App.swift`**

Launch task: `await coordinator.requestRefresh()` becomes `await coordinator.requestRefresh(trigger: .launch)`.

`refreshNow()`:

```swift
    /// "Refresh now": calls the usage endpoint unless the last fetch is
    /// under 60 s old or a rate-limit block is active.
    func refreshNow() {
        let coordinator = self.coordinator
        Task { await coordinator.requestRefresh(trigger: .manual) }
    }
```

In `restartTimer(interval:)`: `await coordinator.requestRefresh()` becomes `await coordinator.requestRefresh(trigger: .scheduled)`.

In `observeWake()`: `Task { await coordinator.requestRefresh() }` becomes `Task { await coordinator.requestRefresh(trigger: .wake) }`.

In `saveConfiguration(_:)`, replace the refresh decision and log line:

```swift
        let refresh = config.needsRefresh(comparedTo: previous)
        let trigger: RefreshTrigger = config.needsNetworkRefresh(comparedTo: previous) ? .settings : .local
        log.append(source: "config", message: "saved from settings: \(config.accounts.count) account(s), \(config.groups.count) group(s), interval \(config.refreshIntervalSeconds) s"
                   + (refresh ? ", refresh \(trigger.rawValue)" : ", display only"))
```

```swift
        if refresh {
            let coordinator = self.coordinator
            Task { await coordinator.requestRefresh(trigger: trigger) }
        }
```

Update the doc comment above `saveConfiguration` to say that only subscription changes may call the usage endpoint; all other data-relevant edits re-price locally. Delete the stale duplicate first doc comment paragraph ("Validates and writes the configuration, restarts the timer ...").

- [ ] **Step 2: Show the retry time in the dropdown**

In `DropdownView.swift`, `SubscriptionSection.stateLine`, `.stale` case, after `Text(error).fixedSize(horizontal: false, vertical: true)`:

```swift
                if let retry = snapshot?.nextRetryAt {
                    Text("Retrying at \(retry.formatted(date: .omitted, time: .shortened))")
                } else if let until = snapshot?.endpointBlockedUntil {
                    Text("Rate limited until \(until.formatted(date: .omitted, time: .shortened))")
                }
```

- [ ] **Step 3: Build and run all tests**

Run: `make test 2>&1 | tail -3 && make app 2>&1 | tail -1`
Expected: all tests pass, then "Built build/AgentMeter.app". No new warnings in `App.swift` or `DropdownView.swift`.

- [ ] **Step 4: Check for forbidden dashes**

Run: `rg -n '[—–]' Sources Tests docs/superpowers/plans/2026-10-13-endpoint-call-policy.md || echo clean`
Expected: `clean`

- [ ] **Step 5: Commit**

```bash
git add Sources/LLMUsageMenuBar/App.swift Sources/LLMUsageMenuBar/DropdownView.swift
git commit -m "feat(app): pass refresh triggers, re-price locally on non-subscription edits

Assisted-By: 🤖 Claude Code"
```

- [ ] **Step 6: Manual verification (user)**

```bash
pkill -x LLMUsageMenuBar; open build/AgentMeter.app
```

1. Settings, Prices: override a price and type several digits. Then run `tail -n 20 ~/Library/Logs/llm-usage-menubar/usage.log | grep -E 'config|refresh\] done'`. Expected: `refresh local` on the config lines, `trigger local, endpoint reused (local change)` on the done lines, and no `[subscription] <id>: ok` line in between.
2. Click "Refresh now" twice within a minute. Expected: one done line with `trigger manual, endpoint fetched`, then one with `endpoint reused (last fetch N s ago)`.
3. After an hour of normal use: `grep -c "$(date -u +%Y-%m-%dT%H).*endpoint fetched" ~/Library/Logs/llm-usage-menubar/usage.log` shows about 12.
