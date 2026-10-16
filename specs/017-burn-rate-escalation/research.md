# Research: Burn Rate Escalation

## R1: Where the observations live

- **Decision**: A pure value type `ObservationLog` in `Sources/UsageCore/Pace/ObservationLog.swift` holds the observations per window (`[BurnWindowKey: [RateObservation]]`). `RefreshCoordinator` owns one instance in a private property, updates it from every snapshot it publishes (the regular refresh in `runLoop` and the early result of `publishSavedValues`), and attaches a copy to the snapshot as `UsageSnapshot.observations` before yielding it.
- **Rationale**: The bar (`BarLayout.segments(snapshot:configuration:)`), the Menu Bar tab preview and the dropdown all render from a `UsageSnapshot`. Carrying the log in the snapshot keeps these three consumers pure functions of the snapshot, so the preview follows the same rules for free (FR-010) and the tests need no clock or coordinator. The coordinator is the only place that sees every snapshot in order, which the log needs. The log is never encoded or written (FR-003, FR-013).
- **Alternatives considered**: A log in the app's view model (rejected: logic outside `UsageCore`, violates FR-015 and AGENTS.md); deriving rates from `previousSnapshot` only (rejected: one previous value cannot give a 60-minute lookback with a 15-minute minimum span); storing derived rates instead of observations in the snapshot (rejected: the observations make the rates reproducible in tests and keep one source of truth).

## R2: Window identity

- **Decision**: `BurnWindowKey` is an enum with unlabeled payloads: `.claude(accountId, ClaudeWindow)` with `ClaudeWindow` = `.fiveHour`, `.sevenDay`, `.model(name)`; `.codex(accountId, windowName)`; `.group(groupId)` for groups and `.accountBudget(accountId)` for accounts with their own budget (a group and an account may share an id, spec 008, so the two budget owners are separate cases).
- **Rationale**: Matches the spec's Key Entities. Codex windows are identified by `CodexLimitWindow.name` throughout the codebase (spec 007 FR-009, research R7): several lengths can round to the same name, and observations deduplicate by name, so the name is the stable identity across live results and session-log snapshots.
- **Alternatives considered**: A string key (rejected: easy to mistype, no exhaustiveness).

## R3: Which values are observed

- **Decision**: `ObservationLog.updated(with snapshot:, budgetPricesChanged:)` walks the snapshot:
  - Claude: for every subscription entry with a status, the 5-hour, 7-day and each model limit **that has a pace** (`SubscriptionStatus.fiveHourPace(now:)` and so on, which already apply spec 011 FR-007), observed at `status.fetchedAt` with the unrounded `utilizationPercent` and `resetsAt`.
  - Codex: every window of `CodexLimitsEntry.windows(now:)` with a pace, keyed by its `name`, observed at `observation.observedAt`.
  - Budgets: every `GroupEntry` in `groups` and `accountBudgets` with a pace and `stale == false`, observed at `snapshot.generatedAt` with the unrounded `spentUSD / budgetUSD * 100`, reset time `window.end`.
  - A key whose window has no pace in this snapshot, or that is no longer in the snapshot, is removed (FR-003 "an entry that has no pace at a refresh discards its observations").
- **Rationale**: Reuses the pace accessors, so the exclusions of spec 011 (not started, at or above 100%, limit reached, empty group, window already reset) apply identically. Stale budgets are carried-over values with a fresh snapshot time; recording them would add flat observations that did not happen, so they add nothing (they also never show a marker, FR-009). Stale Claude and Codex values keep their old observation time and are skipped by the "later than the newest" rule.

## R4: Discard rules

- **Decision**: For a key with existing observations, before appending:
  - new observation time not later than the newest kept one: no append, nothing discarded (FR-003);
  - reset time differs from the newest kept one by 60 s or more, or used percent lower than any kept one: discard the kept observations, then append;
  - budgets only: a fingerprint of `budgetUSD`, `period`, sorted `members` differs from the stored one: discard, then append; the reset time rule already covers a moved window (`window.end`);
  - budgets only: `budgetPricesChanged` is true: discard, then append.
  After appending, observations with `observedAt < now - 3600` are dropped (an observation exactly 60 minutes old is kept).
- **Rationale**: One-to-one with FR-003 and the clarification on prices. Claude reset times arrive already normalized to the minute by `UsageEndpointClient.normalizedReset`; Codex reset times come from raw epochs (live results and session logs can differ by seconds), so every key treats reset times less than 60 s apart as the same reset (a tolerance avoids the half-minute rounding boundary that rounding both values would have). A stale budget entry adds no observation and keeps its existing ones, which the lookback prunes.

## R5: Detecting a price change

- **Decision**: `budgetPricesChanged` is true for a refresh when (a) `configuration.priceOverrides` differs from the overrides of the previous refresh (a manual override edit), or (b) `requestReprice()` was called since the last refresh. `requestReprice()` is used by the app only after a price import and after removing an import (`App.swift`), so it sets a coordinator flag `pricesMayHaveChanged`. The run loop consumes it at the start of an iteration, before `performRefresh`, so a reprice requested while a refresh is in flight is seen by the follow-up refresh that actually reprices. A flag survives trigger coalescing, which a trigger check would not. The overrides of the previous refresh are kept in the coordinator; the first refresh after launch counts as no change. The early result from saved values never discards budget observations (it has no budgets).
- **Rationale**: The coordinator does not see the effective price table (the sources build it from the imported store and the overrides), but it does see both events that change it. No new file reads and no new requests.
- **Alternatives considered**: Passing the imported price store into the coordinator to fingerprint it (rejected: a new dependency for the same information); discarding on every `.local` or `.settings` refresh (rejected: more than FR-003 asks, and settings edits are frequent while tuning the bar).

## R6: Recent rate

- **Decision**: `ObservationLog.recentRate(for:now:)` takes the kept observations of the key with `observedAt >= now - 3600`, the oldest `o` and the newest `n`. It returns `RecentRate(perHour: (n.used - o.used) / hours(n.t - o.t), observedAt: n.t, usedPercent: n.used)` only when `n.t - o.t >= 900` seconds and `n.used - o.used >= 2` (FR-004). The lookback and thresholds are static constants on `BurnRate` (`lookback = 3600`, `minimumSpan = 900`, `minimumChange = 2`, `factor = 2`).
- **Rationale**: Anchoring at the snapshot time `now` makes a burst older than an hour expire even when no new observation arrives (Codex quiet periods). The newest observation is the entry's current observation, so the recent run-out uses the shown value (FR-007).

## R7: Burn decision

- **Decision**: `BurnRate.compute(pace:usedPercent:windowStart:resetsAt:observedAt:now:recent:)` takes a non-nil pace and returns nil when `resetsAt <= observedAt` (a future-dated observation, which would make the sustainable rate undefined). Otherwise:
  - `sustainable = (100 - used) / hours(resetsAt - observedAt)` (FR-001);
  - `average = used / hours(observedAt - windowStart)`, nil when the elapsed time is 0 or less (FR-002);
  - average qualifies when `pace.runOut != nil` (spec 011 counted run-out, not withheld) and `average >= factor * sustainable`; its run-out is `observedAt + (100 - used) / average` (FR-006, FR-007);
  - recent qualifies when `recent != nil` and `recent.perHour >= factor * sustainable_at(recent)`, where the sustainable rate is evaluated at the recent observation (the same observation, so the same value); its run-out is `recent.observedAt + (100 - recent.usedPercent) / recent.perHour`;
  - a run-out at or before `now` disqualifies that rate; `fastRunOut` is the earlier of the qualifying run-outs, nil when none qualifies.
  `BurnRate.burnsFast` is `fastRunOut != nil`.
- **Rationale**: The average run-out equals spec 011's `Pace.runOut` (same linear model), so the dropdown never shows two different times for the same rate. FR-005's "at least k times" uses `>=`.

## R8: Bar marker

- **Decision**: `BarItem` keeps `runOutMarker: Bool` and gains `burnsFast: Bool = false` (true only together with `runOutMarker`). `BarLayout.marker` becomes `markers(pace:burn:level:stale:enabled:) -> (runOut: Bool, fast: Bool)`: suppressed exactly as today; the burn rate is looked up only when the item's pace is not nil, so the bar's pace guards (for example no 7-day percent) hold for `↑` too; otherwise `fast = burn?.burnsFast == true`, `runOut = fast || pace?.runOut != nil`. `BarPresentation` renders `"↑"` when `burnsFast`, `"↗"` otherwise. `BarItem.accessibilitySuffix` returns ", burning fast, projected to run out well before reset" when `burnsFast` (FR-011).
- **Rationale**: The default parameter keeps every existing `BarItem` call site and spec 011 test valid; the glyph choice stays in `BarPresentation`, where `"↗"` is chosen today.
- **Alternatives considered**: Replacing the Bool with an enum (rejected: churn in spec 011 tests for no behavioral gain).

## R9: Dropdown

- **Decision**: `Pace.summary(runOutText:fastRunOut:)` gains an optional `fastRunOut: Date?` (default nil). With it, the text is the delta text plus " · burning fast · runs out <text>", replacing the spec 011 run-out (FR-012). `PaceMeter` gets an optional `burn: BurnRate?`; its color is orange when `pace.runOut != nil || burn?.burnsFast == true`. Rows pass the burn rate from `UsageSnapshot.burnRate(for:)`; `BudgetSection` gains an `ownerId` input and `CodexPlanSection` a `snapshot` input, which they lack today.
- **Rationale**: Wording stays in the tested core; the view only chooses the color, as in spec 011.

## R10: Snapshot accessor

- **Decision**: `UsageSnapshot.burnRate(for key: BurnWindowKey) -> BurnRate?` resolves the key to the entry's pace inputs (the same ones the pace accessors use), asks `observations.recentRate(for:now: generatedAt)` and calls `BurnRate.compute`. The bar and the dropdown call only this accessor.
- **Rationale**: One place maps a key to its window, so the bar's 7-day, Codex longest window and budget choices (spec 011 FR-012) and the dropdown rows cannot disagree.

## R11: Toggle and README

- **Decision**: The Menu Bar tab toggle label becomes "Show ↗ or ↑ when an entry will run out before it resets"; `Configuration.showsRunOutMarker` is unchanged (FR-010). README lines on the bar markers (Features, "Alerts") and the Menu Bar tab describe `↑` and the new label (FR-014). The "Security and privacy" section is not touched (FR-013).
