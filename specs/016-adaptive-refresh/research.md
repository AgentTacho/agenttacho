# Research: Adaptive Refresh

All Technical Context items are resolved; no NEEDS CLARIFICATION remains.

## R1: Where the pace decisions live

- **Decision**: A new value type `AdaptivePace` in `Sources/UsageCore/Snapshot/AdaptivePace.swift`, owned by `RefreshCoordinator` next to `EndpointPolicy`. It has no clock: every method takes `now`. It holds the base interval, the enabled flag, the current `SystemConditions`, and per paced endpoint (`.claude`, `.codex`) the last call time and the current interval.
- **Rationale**: FR-019 asks for plain, tested values. `EndpointPolicy` already shows the pattern (a struct mutated by the coordinator, tested in `EndpointPolicyTests`). Keeping rate limits in `EndpointPolicy` and pacing in `AdaptivePace` keeps both small and leaves the rate-limit rules untouched (FR-014).
- **Alternatives considered**: Extending `EndpointPolicy` with pace state (rejected: it is Claude-only and its rules are spec 001/010 territory; mixing makes FR-014 hard to verify). Putting the pace in the app's timer (rejected: untestable, violates AGENTS.md).

## R2: The activity signal

- **Decision**: Activity for an endpoint is computed from the records of the current refresh: the newest `timestamp` among records whose `harness` counts for that endpoint (Claude: `.claudeCode`, `.openCode`; Codex: `.codex`, `.openCode`). The endpoint has new activity when that newest timestamp is later than the endpoint's last call that reached the service (FR-004, FR-013).
- **Rationale**: Stateless and exact. Record sources return every record with `timestamp >= window.start`, and any activity after the last call is inside the collection window, so nothing is missed. Re-reading after launch, a price change or a window move yields old timestamps and never counts (clarification 1). Activity before a failed call carries over by construction, because the last call time only moves on calls that reached the service (FR-013).
- **Alternatives considered**: Counting record ids new to the index (rejected: re-derivation after a price change and window moves would report everything as new; three sources handle re-derivation differently, see idea inbox `unified-rederive-policy`). File modification times (rejected: OpenCode's SQLite WAL changes without new usage).

## R3: Scan before the endpoint decision

- **Decision**: `performRefresh` collects the record sources first, then decides per endpoint, then collects the rest. Record sources are those that are neither `NetworkBoundSource` (the Claude `SubscriptionSource`) nor the new marker protocol `EndpointGatedSource`, which `CodexLimitsSource` adopts (it is a plain source that gates its own requests and runs on every refresh, reprices included). The second batch is the Claude source when it is called, plus every `EndpointGatedSource`, always with `codexPaceDue`. This order applies to every refresh, with the toggle on or off.
- **Rationale**: FR-006 needs the current scan before the decision. Running the scan first in all modes keeps one code path; the endpoint calls and their sequence are unchanged with the toggle off (SC-004), only the network requests start after the local scan (incremental, typically well under a second).
- **Alternatives considered**: Sequential only when adaptive is on (rejected: two code paths for little gain). Deciding from the previous refresh's scan (rejected by spec review: a new record would be seen one base interval late, breaking SC-002).

## R4: Calling one endpoint while reusing the other

- **Decision**:
  - **Claude**: `EndpointPolicy.decide` runs as today. When it says `.fetch` for a `.scheduled` trigger and `AdaptivePace` says the Claude endpoint is not due, the coordinator switches to the existing reprice mode: the stored Claude result is reused with the usual directory filter, and the reuse reason is `adaptive pace, next call <time>`. This happens only when a stored result exists and the credential directories are unchanged since it (`lastNetworkDirectories == directories`), so an account added or moved by hand is fetched at once. Otherwise the refresh runs in full.
  - **Codex**: `RefreshContext` gets `codexPaceDue: Bool` (default `true`). For every `.scheduled` refresh, in every mode (full, reprice for pace, reprice for a Claude rate-limit block or spacing), the coordinator sets it from `AdaptivePace.shouldCall(.codex, ...)`. `CodexLimitsSource.decide` returns `.notDue` for `.scheduled` when it is `false`. Every other trigger ignores it.
  - **Reprice** for other reasons (`.local`, spacing, rate-limit block) keeps reusing the Claude result as today; the Codex source is collected as today, with `codexPaceDue` on scheduled ticks.
- **Rationale**: Each endpoint already has its own gate: `EndpointPolicy` for Claude, `FetchGate` per Codex home. The pace only adds a "not due" input to each. `CodexLimitsSource` already handles `.notDue` (no stale marking, newest snapshot shown), which matches FR-007.
- **Alternatives considered**: Skipping the Codex source entirely when not due (rejected: it would also skip the local rollout snapshot scan that can show newer values). One pace for both endpoints (rejected by clarification 1: Claude activity says nothing about Codex limits).

## R5: "Reached the service"

- **Decision**: `SubscriptionEntry` and `CodexLimitsEntry` get a transient `reachedService: Bool` (default `false`, not saved to `last-good.json`). It is `true` when this refresh sent a request for the entry and got a success, or a failure whose `FailureCategory` is not `.transport`. Spec 010 FR-001 counts HTTP 5xx as transport, so 5xx does not advance the pace (spec FR-005 updated to say so).
- **Rationale**: Both sources already classify failures with `FailureCategory.classify`. A boolean on the entry is the smallest way to carry the fact to the coordinator, which records one call per endpoint when any entry of that endpoint reached the service.
- **Alternatives considered**: A new `FetchOutcome` case (rejected: `FetchOutcome` drives `EndpointPolicy.record`, which must stay unchanged). Asking the sources after `collect` (rejected: an extra protocol and actor hop for one bit).

## R6: New triggers

- **Decision**: `RefreshTrigger` gets `.dropdownOpen` and `.idleReturn`, both rank 1 like `.wake`. `EndpointPolicy.decide` spaces them like `.manual`, `.wake` and `.settings` (60 s). `CodexLimitsSource.decide` handles them like `.wake`. Neither touches `retryUsed`, which only `.scheduled` resets and uses.
- **Rationale**: FR-011 and FR-012 describe them as spaced, unpaced refreshes that never call during a block, which is exactly the existing wake behavior.

## R7: The timer

- **Decision**: With the toggle off, `AppModel.restartTimer` keeps today's fixed loop unchanged (SC-004). With the toggle on, an adaptive loop sleeps until `await coordinator.nextScheduledRefresh()`, then requests `.scheduled`. `AdaptivePace.nextScheduledRefresh(now:)` returns `max(now, min(lastRefreshAt + timerInterval, earliest due time))` (FR-010a), where only due times later than `lastScheduledAt + tickTolerance` count. A due time a scheduled refresh already handled (an endpoint whose calls fail by transport, are blocked or make no request, so its last call does not move, or one without any call) does not pull the timer forward; otherwise the loop would spin once per second while offline. Without a completed refresh it returns `now + timerInterval`, so the first adaptive tick comes one interval after launch as today and never adds a request or replaces a pending quick retry. The loop is re-armed after every published snapshot, on a change of system conditions, on wake, and on configuration changes to the interval or the toggle (through `coordinator.configurationChanged(_:)`). When `nextScheduledRefresh()` returns nil (toggle off in the coordinator) the loop ends and the app falls back to the fixed loop.
- **Rationale**: The coordinator knows the last refresh and the endpoint calls; the app only sleeps. Re-arming after each snapshot implements "counted from the last refresh" (FR-010) for refreshes of any trigger.
- **Alternatives considered**: A fixed base tick that skips work (rejected: wakes the Mac every base interval while idle or in Low Power Mode, against US3).

## R8: Reading the system conditions

- **Decision**: An app-side `SystemConditionsMonitor` (AppKit, no permissions):
  - Low Power Mode: `ProcessInfo.processInfo.isLowPowerModeEnabled` plus `NSProcessInfoPowerStateDidChange`.
  - Thermal state: `ProcessInfo.processInfo.thermalState` (`.serious`, `.critical`) plus `ProcessInfo.thermalStateDidChangeNotification`.
  - Idle: `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: kCGAnyInputEventType)` of at least 600 s, polled every 60 s. A locked screen (`com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` distributed notifications) and sleeping displays (`NSWorkspace.screensDidSleepNotification`, `screensDidWakeNotification`) count as idle at once.
  - Returning from idle (the idle flag going from `true` to `false`) asks for an `.idleReturn` refresh, only with the toggle on (FR-002). When a wake refresh started within the last 60 s, the app skips it (FR-011). With the toggle off the coordinator ignores conditions (`setConditions` returns false and logs nothing).
- **Rationale**: These APIs need no Accessibility or Input Monitoring permission (FR-020). A 60 s poll satisfies "within 60 seconds" in FR-011 at negligible cost.
- **Alternatives considered**: `NSEvent` global monitors (rejected: keyboard monitoring needs Input Monitoring permission). IOKit `HIDIdleTime` (same data as `CGEventSource`, more code).

## R9: Detecting the dropdown opening

- **Decision**: `DropdownView` calls `model.dropdownOpened()` from `.onAppear`. With `.menuBarExtraStyle(.window)`, the content appears each time the window opens. The model asks `await coordinator.shouldRefreshOnOpen()` and, if it says yes, requests `.dropdownOpen`. With the toggle off, nothing happens (FR-002).
- **Rationale**: This is the smallest hook. The walkthrough verifies that it fires on every opening. If it does not, the fallback is `NSWindow.didBecomeKeyNotification` filtered to the extra's window, behind the same model method. `shouldRefreshOnOpen()` returns false while a refresh runs, so opening during a refresh neither starts nor queues another one (spec edge case).
- **Note**: The `MenuBarExtra` window takes its size when it opens (`DropdownView.swift:19`). Values that arrive while it is open update the rows; the pace line has a fixed one-line height, so no resize issue is expected.

## R10: The configuration key

- **Decision**: `adaptiveRefresh` (top-level boolean, default `true`). It is decoded leniently: a non-boolean value becomes `true` and adds a load note (`adaptiveRefresh is not a boolean, using true`) through `ConfigurationLoadNotes`, which the coordinator logs (FR-001, as spec 012 FR-003 does for `levelColor`). The key is excluded from the data-relevant comparison like `levelColor`, so toggling it causes no network refresh. The app re-arms the timer instead.
- **Rationale**: This matches the existing tolerant-key pattern and the spec's stated deviation from spec 012 FR-002.

## R11: The pace line

- **Decision**: `RefreshPaceStatus` (in `UsageCore`) holds the reason and the time, and has a `text(now:calendar:)` that produces the line:
  - `Plan limits next checked at 14:35 (no agent activity)` when an endpoint is in use.
  - `Next refresh at 14:35 (Low Power Mode)` when no endpoint is in use.
  - Reason names: `away`, `Low Power Mode`, `high temperature`, `no agent activity`.
  - The time is shown alone when it is today, otherwise weekday plus time.
  - It is `nil` when every pace equals the base (FR-016).
  - The app keeps the latest status in `AppModel.paceStatus`, updated after each snapshot and on condition changes, and shows it under "Last refreshed" in `.caption` and `.secondary`.
- **Rationale**: Wording logic in the core is testable (lesson from idea inbox `run-out-text-in-core`).

## R12: Diagnostic log

- **Decision**: The coordinator logs with source `refresh`:
  - every change of the timer interval: `pace: timer 600 s (Low Power Mode)`, `pace: timer back to base 300 s`;
  - every change of an endpoint interval: `pace: claude interval 1200 s (no agent activity)`, `pace: codex interval back to base (activity)`;
  - each paced reuse, with the next call time, through the existing `endpoint reused (...)` text of the refresh summary line.

  System condition changes are logged by the app with source `app`.
- **Rationale**: This meets FR-017 with the existing `DiagnosticLog.append`, which sanitizes control characters.

## R13: README

- **Decision**: In Configuration, add a sentence to the General bullet about "Adapt refresh" and an `adaptiveRefresh` line in the example JSON. In "Security and privacy", rewrite the frequency sentence ("a single read-only request per refresh (every 5 minutes by default)") following FR-018. No new host, file or credential appears, so the tables stay as they are (FR-020).
