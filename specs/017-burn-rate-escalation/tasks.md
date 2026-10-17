# Tasks: Burn Rate Escalation

**Input**: Design documents from `/specs/017-burn-rate-escalation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/burn-rate-display.md, quickstart.md

**Tests**: Included (AGENTS.md: write the test first). Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task before its implementation and confirm it fails once the package compiles. Use fixed dates and a fixed calendar, never `Date()`.

**Global constraints** (from plan.md):
- Rates use observation times and the snapshot time (`UsageSnapshot.generatedAt`), never the wall clock.
- Existing call sites stay source compatible: `BarItem(..., runOutMarker:)` keeps working (new `burnsFast` defaults to false), `Pace.summary(runOutText:)` keeps working (new `fastRunOut` defaults to nil), `UsageSnapshot(...)` keeps working (new `observations` defaults to empty).
- No network requests, credential reads, files or notifications (FR-013). No em dash or en dash characters. Doc comments cite spec 017 FR ids (for example `spec 017 FR-004`).
- Build and test only through the Makefile (`make test`, `make app`).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 (recent burst), US2 (average escalation), US3 (dropdown text and accessibility)

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline).

---

## Phase 2: Foundational (blocking): burn rate core, snapshot accessor, bar marker

- [X] T002 [P] Create `Tests/UsageCoreTests/BurnRateTests.swift` with tests for `BurnRate.compute(pace:usedPercent:windowStart:resetsAt:observedAt:now:recent:)` (research R7, data-model.md): sustainable rate is `(100 - used) / hours(resetsAt - observedAt)`; average rate is `used / hours(observedAt - windowStart)` and nil when the elapsed time is zero or less; the average qualifies only when `pace.runOut != nil` and `average >= 2 * sustainable` (exactly 2x qualifies); its fast run-out equals `pace.runOut` to the second; a `RecentRate` qualifies when `perHour >= 2 * sustainable`, also when the pace is `.behind` or `.onPace` or inside the 10% hold back (no `pace.runOut`); its run-out is `recent.observedAt + (100 - recent.usedPercent) / perHour` hours; when both qualify the earlier run-out wins; a run-out at or before `now` disqualifies that rate (and with no other qualifying rate `fastRunOut` is nil); `burnsFast == (fastRunOut != nil)`; `compute` returns nil when `resetsAt <= observedAt` (a future-dated observation). Include the spec numbers: US2 AS1 (7-day 62% with 43% elapsed burns fast, ratio about 2.2) and US2 AS2 (55% with 45% elapsed does not, while `pace.runOut` is set); US1 AS1 recent 7.2 points per hour at 36% with 66 h left burns fast; US1 AS3 budget recent 4.5 points per hour at 40% with 360 h left burns fast; US1 AS2 recent 1.2 points per hour at 31% with 66 h left does not.
- [X] T003 [P] Create `Sources/UsageCore/Pace/ObservationLog.swift` with only the shared value types (no logic yet): `public enum ClaudeWindow: Hashable, Sendable { case fiveHour, sevenDay, model(String) }`, `public enum BurnWindowKey: Hashable, Sendable { case claude(String, ClaudeWindow); case codex(String, String); case budget(String) }` (payloads: account id and window; account id and Codex window `name`; owner id; construct them unlabeled, for example `.claude(id, .sevenDay)`, `.codex(id, window.name)`, `.budget(id)`), `public struct RateObservation: Equatable, Sendable { observedAt: Date; usedPercent: Double; resetsAt: Date }`, `public struct RecentRate: Equatable, Sendable { perHour: Double; observedAt: Date; usedPercent: Double }`, and `public struct ObservationLog: Equatable, Sendable` with `public init()` and an empty `entries` dictionary plus `public func recentRate(for: BurnWindowKey, now: Date) -> RecentRate?` returning nil for now (research R2, data-model.md).
- [X] T004 Create `Sources/UsageCore/Pace/BurnRate.swift` with `public struct BurnRate: Equatable, Sendable` (`sustainablePerHour`, `averagePerHour: Double?`, `recentPerHour: Double?`, `fastRunOut: Date?`, computed `burnsFast`), constants `factor = 2.0`, `lookback: TimeInterval = 3600`, `minimumSpan: TimeInterval = 900`, `minimumChange = 2.0`, and `public static func compute(pace: Pace, usedPercent: Double, windowStart: Date, resetsAt: Date, observedAt: Date, now: Date, recent: RecentRate?) -> BurnRate?`, nil when `resetsAt <= observedAt` (spec 017 FR-001, FR-002, FR-005 to FR-007). T002 passes.
- [X] T005 Add tests to `Tests/UsageCoreTests/BurnRateTests.swift` for `UsageSnapshot.burnRate(for:)` (research R10): `.claude(id, .sevenDay)`, `.fiveHour` and `.model(name)` use the same inputs as `SubscriptionStatus.sevenDayPace(now:)`, `fiveHourPace(now:)` and `pace(of:now:)` (observation time `fetchedAt`, unrounded `utilizationPercent`, `resetsAt`); `.codex(id, name)` resolves the window with that `name` in `CodexLimitsEntry.windows(now:)` observed at `observation.observedAt`; `.budget(id)` looks in `groups` then `accountBudgets` and uses `spentUSD / budgetUSD * 100`, `window.start`, `window.end` and `generatedAt`; nil whenever the matching pace is nil (window not started, at or above 100%, limit reached, empty group, unknown key); with an empty `observations` the recent rate is nil and only the average can make it burn fast.
- [X] T006 Add `public var observations: ObservationLog` (init parameter `observations: ObservationLog = ObservationLog()`, last in the initializer) to `UsageSnapshot` in `Sources/UsageCore/Snapshot/UsageSnapshot.swift`, and implement `extension UsageSnapshot { public func burnRate(for key: BurnWindowKey) -> BurnRate? }` in `Sources/UsageCore/Pace/BurnRate.swift`, calling `observations.recentRate(for: key, now: generatedAt)`. T005 passes; all existing suites still compile and pass.
- [X] T007 [P] Add tests to `Tests/UsageCoreTests/BarPresentationTests.swift`: an item with `runOutMarker: true, burnsFast: true` presents `runOutMarker == "↑"`; `runOutMarker: true, burnsFast: false` presents `"↗"`; no marker otherwise; the accessibility text ends with ", burning fast, projected to run out well before reset" for a fast item and with ", projected to run out before reset" for a `↗` item (spec 017 FR-008, FR-011, contracts/burn-rate-display.md).
- [X] T008 Add `public let burnsFast: Bool` to `BarItem` in `Sources/UsageCore/Bar/BarLayout.swift` (init parameter `burnsFast: Bool = false` after `runOutMarker`), make `accessibilitySuffix` return ", burning fast, projected to run out well before reset" when `runOutMarker && burnsFast`, and in `Sources/UsageCore/Bar/BarPresentation.swift` present `"↑"` when `burnsFast`, `"↗"` otherwise. Update the doc comments (spec 017 FR-008, FR-011). T007 passes.
- [X] T009 Add tests to `Tests/UsageCoreTests/BarLayoutTests.swift` for the marker decision with burn rates: replace `marker(_:level:stale:enabled:)` behavior expectations so that a subscription, Codex or budget item whose bar window burns fast gets `runOutMarker == true` and `burnsFast == true`; one with only a spec 011 run-out gets `runOutMarker == true, burnsFast == false`; a fast entry at a warning or critical level, stale, or with `showsRunOutMarker == false` gets neither; group member share items never get either; a Claude subscription without a bar percent (no 7-day values) gets neither even when `snapshot.burnRate(for:)` would burn fast (spec 017 FR-008, FR-009, FR-010; spec 011 FR-012, FR-013). The bar window is the 7-day window for Claude, the longest effective Codex window and the budget itself.
- [X] T010 In `Sources/UsageCore/Bar/BarLayout.swift` replace `marker(_:level:stale:enabled:)` with a helper returning both flags from `pace` and `snapshot.burnRate(for:)` of the bar window key (`.claude(account.id, .sevenDay)`, `.codex(account.id, name)` of the last `windows(now:)` element, `.budget(id)`), and pass `burnsFast` to `BarItem` in `subscriptionItem`, `codexItem` and `budgetItem`. Look up the burn rate only when the item's `pace` is not nil, so the bar's existing pace guards (for example no percent) also hold for `↑` (research R8). T009 passes.

**Checkpoint**: the burn decision is complete and tested from the average rate; with an empty observation log, `↑` already appears for US2. No recent rate yet.

---

## Phase 3: User Story 1 - See a burst that will hit the limit soon (P1) MVP

**Goal**: recent observations kept in memory turn a burst into `↑`.

**Independent Test**: `ObservationLogTests` and the coordinator test feed observation sequences and check the recent rate and the bar marker (spec US1 Independent Test).

- [X] T011 [P] [US1] Create `Tests/UsageCoreTests/ObservationLogTests.swift` with tests for `ObservationLog.recentRate(for:now:)` and `ObservationLog.updated(with:budgetPricesChanged:)` (research R3, R4, R6): an observation is appended only when its time is later than the newest kept one (a repeated `fetchedAt` adds nothing); observations with time before `now - 3600` are dropped and one exactly 3600 s old is kept; a changed reset time or a lower used percent than any kept observation discards the earlier ones, where reset times count as unchanged when they differ by less than 60 s (a Codex reset 1 s off keeps the observations, also across a half-minute boundary; one 2 minutes off discards them); for budgets a changed `budgetUSD`, `period` or member list discards, a changed `window.end` discards, `budgetPricesChanged == true` discards budget keys only (Claude and Codex keys are kept); stale budget entries add nothing and keep their existing observations, which are pruned by the lookback; a Codex window observed alternately from a live result and a session log keeps one list, and a lower reading from either source discards per FR-003; a key whose window has no pace in the new snapshot (no reset time, at or above 100%, limit reached, empty group) or that disappeared is removed; the recent rate uses the oldest and newest observation within the lookback and is nil when they are less than 900 s apart or the change is below 2 points; US1 AS1 (30% at 13:10, 36% at 14:00 gives 7.2 points per hour), US1 AS2 (30% to 31% gives nil), US1 AS3 (37% to 40% over 40 minutes gives 4.5), US1 AS4 (span under 15 minutes gives nil); after an hour without new observations (Codex quiet) the recent rate is nil; Claude 5-hour, 7-day and model limits, every Codex window (keyed by its `name`) and both budget kinds are recorded under their `BurnWindowKey`.
- [X] T012 [US1] Implement `ObservationLog.updated(with snapshot: UsageSnapshot, budgetPricesChanged: Bool) -> ObservationLog` and `recentRate(for:now:)` in `Sources/UsageCore/Pace/ObservationLog.swift`, reusing the pace accessors of `Sources/UsageCore/Pace/Pace.swift` to decide which windows have a pace, `private struct BudgetFingerprint: Equatable, Sendable { budgetUSD: Decimal; period: BudgetPeriod; members: [String] }` (members sorted) stored per owner id, reset times treated as unchanged when they differ by less than 60 s, and the `BurnRate` constants (spec 017 FR-003, FR-004). T011 passes.
- [X] T013 [US1] Add tests to `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` (use the existing `makeCoordinator` helper and a controllable clock): two refreshes 50 minutes apart whose Claude source reports 30% then 36% for the 7-day window publish a second snapshot whose `observations.recentRate(for: .claude(id, .sevenDay), now:)` is 7.2 points per hour and whose `BarLayout.segments` item has `burnsFast == true`; the early result of `publishSavedValues()` records its values, so a refresh 20 minutes later already has a recent rate; `requestReprice()` (price import or removal) and a changed `priceOverrides` in the loaded configuration discard budget observations but keep Claude ones; `requestReprice()` called while a refresh is in flight still discards budget observations in the follow-up reprice; the first refresh after launch counts as no price change; nothing new is written to the coordinator's storage directory, and the diagnostic log has no request lines beyond those of the same refreshes without observations (SC-005).
- [X] T014 [US1] In `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` add `private var observations = ObservationLog()`, `private var pricesMayHaveChanged = false` (set in `requestReprice()`) and `private var lastPriceOverrides: [PriceEntry]?`. In `runLoop`, consume the flag at the start of each iteration, before `await performRefresh` (`let pricesChanged = pricesMayHaveChanged; pricesMayHaveChanged = false`), so a reprice requested during an in-flight refresh is seen by the follow-up refresh. Inside `performRefresh`, compare the loaded `configuration.priceOverrides` with `lastPriceOverrides` (nil on the first refresh means no change), store them, and set `private var overridesChangedInLastRefresh` for `runLoop` to read (`performRefresh` returns only the snapshot); `overridesChanged` below is that property. After `performRefresh`, set `observations = observations.updated(with: snapshot, budgetPricesChanged: pricesChanged || overridesChanged)` and assign `snapshot.observations = observations` before `latestSnapshot`, `previousSnapshot` and `continuation.yield`. In `publishSavedValues()` build the snapshot with `var`, update with `budgetPricesChanged: false` and leave the flag alone (spec 017 FR-003, research R1, R5). T013 passes.

**Checkpoint**: a burst shows `↑` in the bar (US1 MVP).

---

## Phase 4: User Story 2 - Tell a close run-out from a distant one (P1)

**Goal**: the average rate escalates `↗` to `↑` right after launch, without samples.

**Independent Test**: bar layout tests with entries between 1x and 2x and at or above 2x of the sustainable rate (spec US2 Independent Test).

- [X] T015 [US2] Add tests to `Tests/UsageCoreTests/BarLayoutTests.swift` for US2 with an empty observation log: US2 AS1 (Claude 7-day 62% at 43% elapsed) gives `↑`; US2 AS2 (55% at 45% elapsed) gives `↗`; US2 AS3 (an entry that would burn fast at its warning threshold) gives neither, and its presentation shows the warning glyph only; the same for a monthly budget and a Codex weekly window. These pass on the Phase 2 implementation; fix `Sources/UsageCore/Bar/BarLayout.swift` if not.

**Checkpoint**: both triggers work in the bar.

---

## Phase 5: User Story 3 - Understand why the arrow points up (P2)

**Goal**: the dropdown pace meter and VoiceOver explain the fast burn.

**Independent Test**: the pace meter text and color for an entry fast by the recent rate and one fast by the average rate; the status item's accessibility text (spec US3 Independent Test).

- [X] T016 [P] [US3] Add tests to `Tests/UsageCoreTests/PaceTests.swift` for `Pace.summary(runOutText:fastRunOut:)`: with a `fastRunOut` the text is "8% behind · burning fast · runs out X" (behind, no spec 011 run-out) and "19% ahead · burning fast · runs out Y" where Y is the fast run-out, replacing the spec 011 " · runs out" part; without it the spec 011 texts are unchanged (spec 017 FR-012, contracts/burn-rate-display.md).
- [X] T017 [US3] Extend `summary` in `Sources/UsageCore/Pace/Pace.swift` with `fastRunOut: Date? = nil` (spec 017 FR-012). T016 passes.
- [X] T018 [US3] In `Sources/AgentTacho/DropdownView.swift` give `PaceMeter` an optional `burn: BurnRate?` (default nil): orange when `pace.runOut != nil || burn?.burnsFast == true`, text `pace.summary(runOutText: UsageFormat.runOutText, fastRunOut: burn?.fastRunOut)`; pass `snapshot.burnRate(for:)` from `WindowRow` (5-hour and 7-day of `SubscriptionSection`), `ModelLimitRow`, `CodexWindowRow` (give `CodexPlanSection` a `snapshot: UsageSnapshot?` input from its call site, since it has only `limits` and `now` today) (key `.codex(accountId, window.name)`) and `BudgetSection` (add an `ownerId: String` input, passed from its call sites for groups and own budgets; key `.budget(ownerId)`); the dropdown does not depend on `showsRunOutMarker` (spec 017 FR-012). `make app` builds.
- [X] T019 [US3] In `Sources/AgentTacho/MenuBarSettingsTab.swift` change the toggle label to "Show ↗ or ↑ when an entry will run out before it resets" (spec 017 FR-010); the bound setting stays `draft.showsRunOutMarker`. `make app` builds.

**Checkpoint**: all three stories work.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T020 [P] Update `README.md`: in the "Alerts" feature line say that `↑` means the entry burns at least twice as fast as the remaining time allows (it will run out in half the time left or less) and that the meter's tooltip then says "burning fast"; in the Menu Bar tab description replace the toggle label with "Show ↗ or ↑ when an entry will run out before it resets" and say it turns both markers on or off. Do not change the "Security and privacy" section (spec 017 FR-013, FR-014).
- [X] T021 Run `make test` and `make app`; all suites pass and the app builds.
- [X] T022 Run `rg -n "\x{2014}|\x{2013}" Sources Tests README.md specs/017-burn-rate-escalation` and confirm no em or en dash was added; confirm every new doc comment cites a spec 017 FR id, and `git diff main -- README.md` leaves the "Security and privacy" section unchanged.

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 (T002 and T003 in parallel; T004 after T002 and T003; T005 → T006; T007 → T008; T009 → T010 after T006 and T008).
- Phase 3 (US1) after Phase 2: T011 → T012 → T013 → T014.
- Phase 4 (US2) after Phase 2; independent of Phase 3.
- Phase 5 (US3) after Phase 2: T016 → T017 → T018; T019 independent.
- Phase 6 after all stories.

## Parallel Examples

- Phase 2: T002 (BurnRateTests) with T003 (ObservationLog types) and T007 (BarPresentationTests).
- Phase 5: T016 (PaceTests) with T019 (toggle label).
- Phase 6: T020 (README) with any remaining story task.

## Implementation Strategy

- MVP: Phases 1 to 3 (burst detection in the bar). Phase 4 verifies the average trigger that Phase 2 already provides. Phase 5 adds the explanation. Phase 6 documents.
- Commit after each phase with Conventional Commits messages (`feat(pace): ...`, `test(pace): ...`, `docs: ...`).
