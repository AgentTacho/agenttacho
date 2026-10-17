# Research: Pace Forecast

## R1: Where the pace is computed

- **Decision**: A pure `Pace` value and a `Pace.compute(usedPercent:windowStart:resetsAt:observedAt:now:)` function in a new `Sources/UsageCore/Pace/Pace.swift`, plus thin per-entry helpers: `LimitWindow.pace(length:observedAt:now:)`, `ModelLimit.pace(observedAt:now:)`, `CodexLimitWindow.pace(observedAt:now:)` and `GroupEntry.pace(now:)`. The dropdown and `BarLayout` both call these helpers.
- **Rationale**: FR-017 puts all rules (expected share, delta, band, hold back, exclusions) in the tested core. One function with plain inputs makes every entry kind a one-line adapter and keeps the arithmetic in one place for SC-002.
- **Alternatives considered**: Storing a pace in `UsageSnapshot` during the refresh (rejected: the snapshot would grow a derived field that must stay consistent with every carried-over entry, and the computation is cheap); computing in the SwiftUI views (rejected: untestable, violates AGENTS.md).

## R2: Observation and evaluation times

- **Decision**: `observedAt` is `SubscriptionStatus.fetchedAt` for Claude windows and model limits, `CodexLimitObservation.observedAt` for Codex windows, and `UsageSnapshot.generatedAt` for budgets (FR-002). `now` is always `UsageSnapshot.generatedAt`, used only for the "window already reset" exclusion (FR-007).
- **Rationale**: The percent is a fact about the observation time; extrapolating from the snapshot time would invent usage that did not happen. Using the snapshot time (not the wall clock) for the reset check keeps the dropdown stable while it is open (edge case "time passing").
- **Alternatives considered**: Wall-clock `Date()` in the views (rejected: values would drift between refreshes and tests would need a clock).

## R3: Codex windows past their reset

- **Decision**: Compute Codex paces from the effective windows (`CodexLimitsEntry.windows(now:)`), the same list the dropdown and bar already show.
- **Rationale**: FR-007 asks for the reset check on the observed reset time against the snapshot time, before spec 007 FR-010. `effectiveWindows(now:)` turns exactly the windows with `resetsAt <= now` into 0% with `resetsAt == nil`, and a window without a reset time has no pace. Both paths give "no pace" for the same windows, so no second list is needed.
- **Alternatives considered**: Looking up the raw observation window by length (rejected: same result, more code).

## R4: Window lengths

- **Decision**: Claude 5-hour = 5 h, Claude 7-day and model-scoped weekly limits = `WindowResolver.weekSeconds` (7 days), Codex = `lengthMinutes * 60`, budgets = `GroupEntry.window.duration` (28 to 31 days for a month, FR-001).
- **Rationale**: These are the lengths the providers and spec 001/003 define; budgets already carry their `DateInterval`.

## R5: Arithmetic and rounding

- **Decision**:
  - `elapsed = clamp(observedAt - windowStart, 0, length)`, `expected = elapsed / length * 100`.
  - `delta = PercentFormatter.rounded(usedPercent - expected)` (unrounded used percent, FR-003; budgets use `spentUSD / budgetUSD * 100` as Double, not the rounded `GroupEntry.percent`).
  - `status`: `onPace` for `-5...5`, `ahead(delta)` above, `behind(-delta)` below (FR-008).
  - `runOut` only when `status` is ahead, `elapsed / length >= 0.10`, `usedPercent > 0`: `observedAt + (100 - used) * elapsed / used`, kept only if strictly before `resetsAt` (FR-004 to FR-006).
- **Rationale**: Matches the spec examples (19% ahead, Mon 19 Oct 14:53; Tue 05:07). Under the linear model, "ahead" already implies a run-out before the reset, so the `< resetsAt` check is a guard against clamping and rounding edge cases.

## R6: Bar marker and accessibility

- **Decision**: `BarItem` gains `runOutMarker: Bool` (default `false` in the initializer, so existing call sites and tests stay valid). `BarLayout.segments` sets it for subscription, Codex and budget items when `configuration.showsRunOutMarker`, the item's level is `.normal`, it is not stale, and the relevant pace has a `runOut` (FR-012, FR-013). Member items never set it. `BarItem.accessibilitySuffix` (core, tested) is ", projected to run out before reset" with the marker and empty otherwise. In the app, `BarItem.valueText` appends `"↗"` after the value; `BarItem.text` (used for the accessibility label and logs) appends the suffix instead of the glyph (FR-015).
- **Rationale**: The decision is pure layout and testable in `BarLayoutTests`; the glyph stays in the renderer next to `⚠` and `‼`. The Menu Bar tab preview already calls `BarLayout.segments` with the draft, so it follows the toggle and the rules for free (FR-014).
- **Alternatives considered**: A `BarLevel.projected` case (rejected: levels drive threshold styling and notifications; the marker is orthogonal and suppressed by any non-normal level).

## R7: The toggle in the configuration

- **Decision**: `Configuration.showsRunOutMarker: Bool`, JSON key `showsRunOutMarker`, decoded with `decodeIfPresent ?? true` and encoded by the synthesized encoder (FR-014). The Menu Bar tab gets a `Toggle("Mark entries projected to run out before reset", ...)` bound to the draft, so it applies and undoes like every other settings change.
- **Rationale**: Same tolerant pattern as `startAtLogin`; old files without the key keep the marker on, and older AgentTacho versions ignore unknown keys.
- **Alternatives considered**: `UserDefaults` (rejected: every other setting lives in `config.json`, and undo works on the configuration draft).

## R8: Dropdown text and formatting

- **Decision**: `Pace.summary(runOutText:)` in the core composes "on pace", "N% ahead", "N% behind" and " · runs out <text>"; the app passes `UsageFormat.runOutText(_:)`, a new formatter that shows the time only when today and weekday, day, month and time otherwise, also at midnight (FR-009). A small `PaceMeter` view at the end of each row draws a 44 pt track with a tick for even use and a bar left (behind) or right (ahead) of it, its length `Pace.meterOffset` (delta over 50 points, clamped), orange when there is a run-out and secondary otherwise (FR-010); the summary text is its tooltip and accessibility label. A first version showed the text as an extra line below each row; the walkthrough found it took too much space, so the spec moved to the meter (FR-008).
- **Rationale**: The wording rules are testable in the core; only date formatting, which depends on locale, stays in the app, like `resetText`.
- **Alternatives considered**: Reusing `UsageFormat.resetText` (rejected by FR-009: it drops the time at local midnight).
