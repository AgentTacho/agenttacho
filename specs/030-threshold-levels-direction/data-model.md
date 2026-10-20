# Data Model: Threshold Levels and Budget Direction

## DisplayDirection (stored)

| Field | Type | Notes |
|---|---|---|
| raw value | `"used"` or `"remaining"` | global key `displayDirection` in the configuration file |

- Missing key, unknown string or wrong type decode as `used` (FR-008). Older versions ignore the key.
- Thresholds are not affected: they stay stored in used percent (FR-015).

## LevelThresholds (derived)

| Field | Type | Rule |
|---|---|---|
| warning | Int | lowest positive threshold, or 80 |
| critical | Int | second lowest positive threshold (duplicates kept), or 100 |

`level(usedPercent: Int?, atRealLimit: Bool) -> BarLevel`

| Input | Result |
|---|---|
| used nil | normal |
| atRealLimit, or used ≥ 100, or used ≥ critical | critical |
| used ≥ warning | warning |
| otherwise | normal |

Real limit (FR-003): used ≥ 100; a Codex window with `limitReached`; for the menu bar entry and the subscription section header only, the Claude 7-day window ≥ 100 while another headline is chosen and any Codex window at its limit.

## BarItem (extended)

| New field | Type | Notes |
|---|---|---|
| overLimit | Bool | the critical level comes from a real limit; accessibility says "over limit" instead of "critical" |
| accessibilityValue | String | the value in words for the direction ("30% left", "15% over budget"); equals `value` in direction used |

`value` holds the directed text ("30%", "−15%") for subscription, Codex and budget items; member items keep the used share.

## DirectedPercent (derived)

| Field | Type | Rule |
|---|---|---|
| usedPercent | Int | rounded used percent |
| direction | DisplayDirection | |
| value | Int | used, or 100 − used |
| text | String | "\(value)%", negative with U+2212 |
| accessibilityText(kind) | String | used: text; remaining: "N% left", or "N% over budget" / "N% over the limit" when used > 100 |

Static: `fill(usedPercent: Double, direction:)` and `tick(expectedPercent: Double, direction:)`, shares clamped to 0...1, not finite → 0.

## RowBar (changed)

| Field | Change |
|---|---|
| fill | share in the direction (FR-010) |
| tick | expected share in the direction |
| level | new: the row's level from its thresholds, its rounded percent and its own `limitReached` |
| tone | `.overLimit` when level is critical (red), otherwise attention or neutral as today |

## PercentTone (derived)

`primary` (normal), `warning` (orange), `critical` (red), from `BarLevel`. Row percents, budget percents and section header percents.

## BudgetAmountLine (derived)

| Case | When | Text |
|---|---|---|
| of(spent) | direction used | "$S of $B/period" (today) |
| left(amount) | remaining, rounded used ≤ 100 | "$(B − S, floored at 0) left of $B/period" |
| over(amount) | remaining, rounded used > 100 | "$(S − B) over $B/period" |

## ThresholdDisplay (derived)

| Function | Used | Remaining |
|---|---|---|
| shown(stored T) | T | 100 − T |
| stored(entered L) | L | 100 − L |
| valid entry L (`hasInvalidStored` on the stored value is false) | L > 0 | L < 100 |
| caption(T) | nil | "(T − 100% over)" when T > 100 |
| placeholders | 80, 100 | 20, 0 |
| field suffix | "%" | "% left" |

## ThresholdNotificationText (derived)

Input: `ThresholdCrossing` (entityName, windowKind, threshold T, percent P, all used), direction.

| Direction | Title | Body |
|---|---|---|
| used | "<name> reached T%" | "<window> window at P%" |
| remaining, T ≤ 100 | "<name> has <100 − T>% left" | P ≤ 100: "<window> window at <100 − P>% left"; P > 100: "<window> window at <P − 100>% over" |
| remaining, T > 100 | "<name> is <T − 100>% over" | as above |
