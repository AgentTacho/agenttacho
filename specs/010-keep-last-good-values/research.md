# Research: Keep Last Good Values

All decisions below were made against the code on `main` at b98cab6 (RefreshCoordinator, EndpointPolicy, SubscriptionSource, CodexLimitsSource, ThresholdTracker, BarLayout, DropdownView, App).

## R1: Where the failure episode lives

- **Decision**: Each network source keeps its own per-account episode state, using one shared pure value type `RetryEpisodes` (UsageCore/Snapshot). The source decides from it whether a failed request becomes a grace entry (`.retrying`) or a stale entry. The coordinator only schedules the quick-retry timer from the entries it receives.
- **Rationale**: The sources already own the per-account knowledge (Claude `lastGood`, Codex `lastLive`, `lastFailure`, the per-home fetch gate). Codex is not a `NetworkBoundSource`, so it runs on every refresh and gates its own requests; putting episode logic in the coordinator would need the coordinator to understand both sources' internals. A shared value type keeps the rules identical (spec FR-001, "same rules for both providers") and testable without actors.
- **Alternatives**: (a) Episode state in the coordinator, sources only report categories: the coordinator cannot tell Codex's "not due" from "fetched", and it would have to rewrite entries after the fact. (b) Episode state inside `EndpointPolicy`: the policy is global for all Claude accounts, while episodes are per account (FR-009).

## R2: How the quick retry runs

- **Decision**: A new `RefreshTrigger.quickRetry` (rank 2, like `.retry`). The coordinator keeps a second timer task (`quickRetryTask`) next to the rate-limit `retryTask`. After every refresh it sets the timer to the earliest future `retryAt` among `.retrying` entries (Claude and Codex), or cancels it when there is none. `EndpointPolicy.decide(.quickRetry)` returns `.fetch` unless a rate-limit block is active (then `.reuse`), so neither the 60 s spacing nor the "already fresh" rule applies (FR-008). `SubscriptionSource` on `.quickRetry` requests only accounts in a grace phase and returns its last entries, with `fetchOutcome` nil, for the others (FR-009). `CodexLimitsSource.decide` on `.quickRetry` returns `.fetch` for accounts in a grace phase (bypassing spacing) and `.notDue` for the rest.
- **Rationale**: Reusing `.retry` collides with policy rule 4 ("already fresh" after a non-rate-limit outcome) and with the rate-limit retry bookkeeping (`retryUsed`). A separate trigger keeps the existing design document's rules intact. Because the quick retry is an ordinary full refresh for the policy, `policy.record` sets `lastAttemptAt` and a 429 on it sets the shared block, as FR-009 requires.
- **Alternatives**: A per-account fetch API on the coordinator (bypassing `performRefresh`): duplicates aggregation and snapshot assembly.

## R3: Ending a grace period without the retry

- **Decision**: Grace ends on the next request for the account, whoever sends it (scheduled tick, wake after the spacing, the quick retry): the source sees the account in a grace phase and applies the outcome (success clears the episode, any failure marks stale and uses the retry). When the quick retry fires but is not sent (Claude: policy reuse because of a rate-limit block; Codex: fetch gate blocked), the account becomes stale: for Codex in the source (blocked plus grace phase), for Claude in the coordinator, which turns reused `.retrying` entries whose `retryAt` has passed into `.stale` during snapshot assembly (`SubscriptionEntry.endingGrace(now:)`). The same rule covers reprices after the retry time.
- **Rationale**: The Claude source is not called on a reprice, so only the coordinator can update reused entries. Keying the expiry on `retryAt <= now` also prevents a "retrying at 09:42" note from surviving past 09:42 in any path.

## R4: Failure classification

- **Decision**: `FailureCategory` enum (`transport`, `signInRejected`, `rateLimited`, `serviceChanged`) and `FailureCategory.classify(_ error: Error)`, shared by both sources:
  - `UsageEndpointError.network` → transport; `.httpStatus(500...599)` → transport;
  - `.httpStatus(401)`, `.httpStatus(403)` → signInRejected;
  - `.rateLimited` → rateLimited;
  - `.decoding`, `.httpStatus(3xx)` (refused redirect), other statuses, `CodexUsageError.noLimits` → serviceChanged;
  - an unknown error type → transport (URLSession errors that escape the client's mapping are connection problems).
  Codex keeps its wording table (`CodexLimitsSource.failure(for:)`), now keyed by category plus status code; a 5xx gets the reason "usage service unavailable (HTTP N)".
- **Rationale**: Both clients already map URLSession errors to `.network` and statuses to `.httpStatus`. Classification by our own error types keeps credential text out of messages (spec 007 FR-018).

## R5: Saved file format and writer

- **Decision**: `LastGoodStore` (UsageCore/Snapshot), an actor owning `~/Library/Application Support/agentmeter/last-good.json` (new `Paths.lastGoodFileURL`). JSON with `"version": 1`, a `claude` map and a `codex` map keyed by account id (contract in `contracts/last-good-file.md`). Loaded once synchronously at app start (`LastGoodStore.load(from:)` returns the decoded value or nil plus a log line). Each source calls `store.replace(claude:)` or `store.replace(codex:)` with its full current map after every `collect` that changed it; the store writes the whole file with `Data.write(options: .atomic)` and sets POSIX permissions 0600 (directory 0700). Dates as ISO 8601 with fractional seconds; directories stored canonical (`Attributor.canonical(paths.expand(...))`).
- **Rationale**: One writer for one file avoids interleaved writes from two sources. Atomic replace satisfies FR-014. A full replace per collect drops removed accounts (FR-015). The file is small (a few hundred bytes per account), so writing every 5 minutes is negligible; unchanged maps are not written.
- **Alternatives**: `UserDefaults` (no file to describe in the README, harder to test, mixes with app preferences); one file per source (two files to document, no benefit).

## R6: Early result at launch

- **Decision**: `RefreshCoordinator.publishSavedValues()`: called by the app after registering sources and before `requestRefresh(.launch)`. It asks every source conforming to the new `SavedValuesSource` protocol for `savedOutput(configuration:now:)` and, when at least one entry exists, yields a snapshot with `isPreliminary = true` that contains only `subscriptions` and `codexLimits` (all other maps empty, so the bar shows `…` and budget rows show "Refreshing…"). It is skipped when a refresh result already exists. Saved Claude entries carry state `.ok` with their saved status; Codex entries carry the newer of the saved live result and the newest snapshot as `.live`/`.newerSnapshot`. The app feeds a preliminary snapshot to the threshold tracker only with `subscriptions` emptied, so saved Codex values set the Codex baseline (spec 007 FR-015) and saved Claude values never do (FR-019); it does not treat it as the first snapshot (launch-time reconciliation waits for the first non-preliminary result). The coordinator stores it as `previousSnapshot` (not `latestSnapshot`), re-checking after its awaits that no refresh result exists yet.
- **Rationale**: Without an early result, an offline launch shows `…` until the request times out (up to the client timeout), which fails SC-002. Empty maps reuse the existing placeholder paths in BarLayout (`entry == nil` → `…`).

## R7: Reset handling at display time

- **Decision**: `SubscriptionStatus.effective(now:)` returns a copy in which every window (5-hour, 7-day, model limits) whose reset time has passed shows 0% and no reset time; `ModelLimit.resetsAt` becomes optional for that. BarLayout, DropdownView and the coordinator's alignment use `effective(now: snapshot.generatedAt)`. Codex already does this (`CodexLimitObservation.effectiveWindows(now:)`, spec 007 FR-010).
- **Rationale**: Applying the rule where values are shown covers saved and in-run stale values alike (FR-016, review M5) without rewriting stored data; a live value just fetched never has a passed reset, so applying it everywhere is safe.

## R8: Styling

- **Decision**: Dropdown note colors: grace note `.secondary`, stale `.orange` (unchanged), sign-in rejected `.red`. The bar keeps one stale marker (`~`) per entry: `.retrying` is not stale, `.signInRejected` with values is stale. Codex: `CodexLimitsEntry.signInRejected` (set by the source when the failure is a rejection, including the remembered-token case) selects the red style.
- **Rationale**: Matches the clarifications; the bar has no color channel for stale today, so no new bar styling is needed.

## R9: Budget alignment from saved values

- **Decision**: `publishSavedValues()` also seeds `lastAlignmentReset` from the saved 7-day reset of the alignment account when it is in the future (FR-020), so the first refresh's initial window is aligned even if the request fails.
- **Rationale**: `performRefresh` already prefers `lastAlignmentReset` for the initial window and replaces it with a fetched reset.
