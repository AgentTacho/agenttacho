# Implementation Plan: Adaptive Refresh

**Branch**: `016-adaptive-refresh` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/016-adaptive-refresh/spec.md`

## Summary

The refresh pace follows what is happening.

- **Endpoint pace.** A pure `AdaptivePace` value in `UsageCore`, owned by `RefreshCoordinator` next to `EndpointPolicy`, decides per usage endpoint (Claude, Codex) whether a scheduled refresh calls it. It doubles an endpoint's interval up to 30 minutes after each scheduled call that found no new records from the harnesses that count for it, and returns it to the base when records newer than the last call appear (research R1, R2).
- **Scan before decision.** The coordinator now collects the local record sources before the Claude source and the self-gating Codex limits source, so each scheduled decision sees the current scan (R3). It reuses the stored Claude result, or tells `CodexLimitsSource` through `RefreshContext.codexPaceDue` that no scheduled request is due (R4).
- **Timer pace.** The same value computes the timer interval from system conditions (idle, Low Power Mode, thermal pressure) that an app-side monitor reads without permissions (R8). It also gives the next scheduled refresh time, which the app's timer sleeps until (R7).
- **New triggers.** `.dropdownOpen` and `.idleReturn` are spaced like wake (R6).
- **Visible parts.** A toggle `adaptiveRefresh` (default on, lenient decoding), a one-line pace status in the dropdown footer, log lines, and README updates complete the feature.
- **Toggle off.** With the toggle off, the fixed timer loop and the endpoint decisions are unchanged.

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10)

**Primary Dependencies**: SwiftUI (`MenuBarExtra`, Settings), AppKit (`NSWorkspace`, `DistributedNotificationCenter`), CoreGraphics (`CGEventSource.secondsSinceLastEventType`), Foundation (`ProcessInfo` power and thermal state); no new third-party dependencies

**Storage**: `~/.config/agenttacho/config.json` (one new top-level key `adaptiveRefresh`); no new files

**Testing**: Swift Testing via `make test` (`Tests/UsageCoreTests`), fake clocks as in `RefreshCoordinatorTests` and `EndpointPolicyTests`

**Target Platform**: macOS 14 or newer, Apple Silicon

**Project Type**: desktop menu bar app (`UsageCore` library plus thin `AgentTacho` executable)

**Performance Goals**: The dropdown-open refresh starts within 1 s of opening. The local scan finishes before network requests start; that adds the scan time (incremental, typically well under 1 s) to the endpoint latency. Idle polling is one `CGEventSource` call per 60 s.

**Constraints**: Logic in `UsageCore`, test first (AGENTS.md). No new hosts, credential reads, files or permission prompts (FR-020). Rate-limit and retry behavior unchanged (FR-014). Toggle off is behavior-identical (SC-004). No em or en dashes.

**Scale/Scope**: 2 paced endpoints, 3 system conditions, 2 new triggers, about 10 subscription accounts at most

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is still the unfilled template, so the project rules in `AGENTS.md` serve as the gate:

| Rule | Status |
|---|---|
| Build and test only through the Makefile | Pass: `make test`, `make app` |
| Logic in `UsageCore`, covered by tests, test first | Pass. `AdaptivePace`, `RefreshPaceStatus`, the trigger handling, `codexPaceDue`, `reachedService` and config decoding are in `UsageCore`, with tests first. The app only reads system conditions, runs the timer and shows the line. |
| Doc comments cite spec requirements | Pass: new code cites `spec 016 FR-...` |
| No em or en dashes | Pass: checked in review |
| Read-only on agent files; Security and privacy section stays true | Pass with update. No new host, credential or file. The frequency sentence in "Security and privacy" is rewritten in the same pull request (FR-018). |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/016-adaptive-refresh/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── refresh-pace.md
│   └── settings-and-dropdown.md
├── checklists/requirements.md
└── tasks.md             # created by /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   └── Configuration.swift          # adaptiveRefresh, lenient decode + load note, not data-relevant
├── Snapshot/
│   ├── AdaptivePace.swift           # NEW: PacedEndpoint, SystemConditions, PaceReason, EndpointPace, AdaptivePace
│   ├── RefreshPaceStatus.swift      # NEW: status value and line text
│   ├── EndpointPolicy.swift         # RefreshTrigger .dropdownOpen, .idleReturn (rank 1, spaced)
│   ├── RefreshCoordinator.swift     # EndpointGatedSource, scan-first order, pace reuse, pace recording, public pace API, log lines
│   └── UsageSnapshot.swift          # SubscriptionEntry.reachedService
└── Subscription/
    ├── SubscriptionSource.swift     # sets reachedService
    ├── CodexLimits.swift            # CodexLimitsEntry.reachedService
    └── CodexLimitsSource.swift      # codexPaceDue for .scheduled, new triggers, sets reachedService

Sources/AgentTacho/
├── App.swift                        # adaptive timer loop, conditions wiring, dropdownOpened(), idleReturn, paceStatus
├── SystemConditionsMonitor.swift    # NEW: Low Power Mode, thermal, idle, lock, display sleep
├── DropdownView.swift               # .onAppear hook, pace line in the footer
└── SettingsView.swift               # "Adapt refresh" toggle in General

Tests/UsageCoreTests/
├── AdaptivePaceTests.swift          # NEW
├── RefreshPaceStatusTests.swift     # NEW
├── RefreshCoordinatorTests.swift    # paced refresh cases
├── EndpointPolicyTests.swift        # new triggers
├── CodexLimitsSourceTests.swift     # codexPaceDue, new triggers, reachedService
├── SubscriptionSourceTests.swift    # reachedService
└── ConfigurationTests.swift         # adaptiveRefresh

README.md                            # Configuration and Security and privacy
```

**Structure Decision**: The existing two-target layout. Every decision is a pure value in `UsageCore/Snapshot`, next to `EndpointPolicy`. The app gets one new file for reading system state.

## Design Notes

1. **Refresh order (R3).** `CodexLimitsSource` adopts a new marker protocol `EndpointGatedSource` (it stays a plain source, not `NetworkBoundSource`). In `performRefresh`, every mode first `collect`s the record sources (neither `NetworkBoundSource` nor `EndpointGatedSource`), then computes `newestActivity` per `PacedEndpoint` from those records, then decides, then collects the Claude source (full mode only) together with the `EndpointGatedSource`s, whose context carries `codexPaceDue`. The window-sensitive re-run after an alignment reset stays as it is.
2. **Pace reuse (R4).** A `.fetch` decision from `EndpointPolicy` for a `.scheduled` trigger becomes the existing `.reprice` mode when the toggle is on, `pace.shouldCall(.claude, ...)` is false, a stored Claude result exists and `lastNetworkDirectories == directories`. The reuse reason is `adaptive pace, next call <time>`. `endpointCalled` is false, so `lastSuccessfulRefreshAt` and `lastNetworkRefreshAt` keep their meaning, and `EndpointPolicy.record` is not called. For every `.scheduled` refresh, in every mode, `codexPaceDue = pace.shouldCall(.codex, ...)`; for other triggers it is `true` (ignored by the source).
3. **Recording calls (R5).** After collecting, for each endpoint whose fresh (not reused) entries include `reachedService == true`, call `pace.recordCall(endpoint, at: started, scheduled: trigger == .scheduled, newestActivity:)` and log any interval change. Reused results never record a call, even though their stored entries may carry `reachedService == true`. `pace.refreshCompleted(at: started)` runs for every completed refresh.
4. **Public coordinator API.**
   - `setConditions(_:)` updates the pace and logs timer changes. It returns whether the timer must be re-armed. With the toggle off it only stores the conditions, returns false and logs nothing.
   - `configurationChanged(_:)` calls `pace.update(configuration:)` at once, so toggling `adaptiveRefresh` or changing the interval (which cause no refresh) takes effect immediately.
   - `nextScheduledRefresh() -> Date?` returns nil when the toggle is off.
   - `shouldRefreshOnOpen() -> Bool`, false while a refresh runs.
   - `paceStatus() -> RefreshPaceStatus?`, nil when the toggle is off.
   - `pace.update(configuration:)` also runs at the start of each refresh.
5. **App timer (R7).** `restartTimer` branches on `configuration.adaptiveRefresh`. Off keeps the existing loop byte for byte in behavior. On runs `while !cancelled { let next = await coordinator.nextScheduledRefresh(); sleep until next; request .scheduled }`. `startConsumingSnapshots` re-arms the adaptive loop after each snapshot, because the next time depends on the last refresh and calls. Wake, condition changes and configuration saves re-arm too.
6. **Conditions (R8).** `SystemConditionsMonitor` publishes `SystemConditions` changes to `AppModel`. The model forwards them to the coordinator, re-arms the timer, and on a transition from idle to not idle requests `.idleReturn` unless a wake refresh ran in the last 60 s. The model records the wake time in `observeWake`.
7. **Dropdown (R9, R11).** `DropdownView.onAppear` calls `model.dropdownOpened()`. The footer shows `model.paceStatus?.text(now:calendar:)` under "Last refreshed".
8. **Config (R10).** `adaptiveRefresh` is decoded leniently with a load note, written by the encoder, and cleared in the data-relevance copy like `levelColor`. A save or a reload that changes it or the interval calls `coordinator.configurationChanged(_:)`, refreshes `paceStatus`, and re-arms the timer (fixed loop when off, adaptive loop when on), without a network refresh.
9. **Logging (R12).** Pace changes go through `DiagnosticLog.append` with source `refresh`, condition changes with source `app`.

## Complexity Tracking

No constitution violations. One deliberate deviation is documented in the spec (FR-001): `adaptiveRefresh` decodes a non-boolean leniently, unlike other booleans.
