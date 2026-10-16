# Data Model: Pace Forecast

## Pace (new, `UsageCore`, value type, not persisted)

| Field | Type | Meaning |
|---|---|---|
| `expectedPercent` | Double | Elapsed share of the window at the observation time, 0 to 100 (FR-001) |
| `delta` | Int | Rounded unrounded-used minus expected, percentage points (FR-003) |
| `status` | `PaceStatus` | `.onPace`, `.ahead(points)`, `.behind(points)`; band -5...+5 inclusive is on pace (FR-008) |
| `runOut` | Date? | Linear run-out; set only when ahead, at least 10% elapsed, used > 0, strictly after the snapshot time and strictly before the reset (FR-004 to FR-006) |

Constants: `Pace.tolerancePoints = 5`, `Pace.holdBackShare = 0.10`, `Pace.fiveHourSeconds = 5 * 60 * 60`, `Pace.meterScalePoints = 50`.

Computed: `meterOffset: Double` in -1...1, the pace meter's bar as a share of its half track: 0 when on pace, otherwise `delta / 50` clamped (FR-008).

Construction: `Pace.compute(usedPercent:windowStart:resetsAt:observedAt:now:) -> Pace?` returns nil when `usedPercent` is not finite or rounds to 100 or more (the shown percent), the window length is not positive, or `resetsAt <= now` (FR-007).

Adapters (each returns nil when the entry has no pace):

- `LimitWindow.pace(length:observedAt:now:)`: nil when `resetsAt == nil`.
- `ModelLimit.pace(observedAt:now:)`: 7-day length.
- `CodexLimitWindow.pace(observedAt:now:)`: nil when `resetsAt == nil` or `limitReached`.
- `GroupEntry.pace(now:)`: nil when `members` is empty (empty group, spec 009) or `budgetUSD <= 0`; used percent from `spentUSD / budgetUSD * 100`; window from `window`; observed at `now` (the snapshot time).
- `Pace.summary(runOutText:) -> String`: "on pace" / "N% ahead" / "N% behind", plus " · runs out <runOutText(runOut)>" when `runOut` is set.

## BarItem (changed)

| Field | Change |
|---|---|
| `runOutMarker: Bool` | New, default `false`. True only for subscription, Codex and budget items when the marker is enabled, level is `.normal`, not stale, and the bar window's pace has a `runOut` (FR-012, FR-013). |
| `accessibilitySuffix: String` | New computed property: ", projected to run out before reset" when `runOutMarker`, empty otherwise (FR-015). |

## Configuration (changed)

| Field | Change |
|---|---|
| `showsRunOutMarker: Bool` | New, JSON key `showsRunOutMarker`, default `true` when absent (FR-014). |

No other stored data. The snapshot, the threshold state and the diagnostic log are unchanged (FR-016).
