# Research: Threshold Levels and Budget Direction

No item of the Technical Context was left open. These are the design decisions behind the plan.

## R1: One level type instead of patching each call site

- **Decision**: a `LevelThresholds` value built from an owner's `[Int]`, with `level(usedPercent:atRealLimit:)`. `BarLayout.level`, `RowBar` and the dropdown header all call it.
- **Rationale**: today the rule lives in `BarLayout.level` (critical fixed at 100) and again in `RowBar.make`/`RowBar.budget` (red at a rounded 100). Two copies drifted once already (the dropdown ignores thresholds). One type makes SC-001 testable in one place.
- **Alternatives**: adding a `critical` parameter to `BarLayout.level` only (keeps the duplicate in `RowBar`); a protocol per owner (more code, no gain).

## R2: Duplicate thresholds

- **Decision**: duplicates count separately, so `[90, 90]` gives warning 90 and critical 90 (review-spec I-1). `ThresholdTracker` keeps its de-duplicated set for notifications; only the level rule keeps duplicates.
- **Rationale**: a user who types 90 twice expects red at 90.

## R3: Telling "critical" from "over limit"

- **Decision**: `BarItem.overLimit` (and the same flag in the header decision) marks a real limit; `BarPresentation` reads "over limit" for it and "critical" for a threshold-driven critical level (FR-004). The tone name `BarTone.overLimit` stays as the red role.
- **Rationale**: `BarLevel` is used in many places (coverage report, presentation, tests); adding a fourth case would ripple through all of them while only the accessibility word differs.

## R4: Where the direction lives

- **Decision**: `Configuration.displayDirection`, a global key next to `levelColor`, decoded leniently (missing, unknown or wrong type → used). Views read it from the configuration they already observe, so a change redraws at once (FR-009).
- **Alternatives**: `UserDefaults` (would split settings between two stores; spec 008 keeps every setting in the file).

## R5: Remaining value from the rounded used percent

- **Decision**: shown remaining = 100 − rounded used percent; the bar fill uses the unrounded share (1 − used/100, clamped), as the used fill does today. The red state uses the rounded percent, so "0%" left and a red bar always appear together (spec Edge Cases).
- **Rationale**: the text and color must agree with direction used exactly (FR-014); a fill that differs by under 1% is invisible.

## R6: Budget dollar line boundary

- **Decision**: "over" exactly when the rounded used percent is above 100; the amount is `spent − budget` for over and `budget − spent` (floored at 0) for left (review-spec M-7). The amount formats stay in the app (`UsageFormat`), UsageCore picks the wording and the amount.
- **Rationale**: a rounded 100% next to "$0.40 over" would contradict the percent and the bar.

## R7: Thresholds editor in remaining mode

- **Decision**: shown value = 100 − T; entered L stored as 100 − L; valid when L < 100 (negatives allowed); a stored T > 100 shows as a negative number with "(N% over)" (review-spec M-1).
- **Rationale**: every positive stored threshold stays reachable and the stored meaning never changes (FR-015, SC-004).

## R8: Notification wording at posting time

- **Decision**: `NotificationPresenter` builds texts when it posts, reading the current configuration's direction; queued crossings carry only used percents (review-spec M-10). The log line stays in used percent (FR-017).

## R9: Demo scenario for a threshold-driven red

- **Decision**: lower one Codex owner's thresholds so its weekly window (60%) is critical below 100; keep Claude Max at 80/100 so the 7-day row keeps its orange pace note for the `pace` shot. A new coverage field asserts a row that is critical below 100%.
- **Alternatives**: lowering Claude Max's thresholds (turns the 7-day bar red, which removes the pace note the `pace` shot needs); a budget (its percent moves with the scenario frame, so whether it sits between the critical threshold and 100 depends on launch time; a subscription window value is fixed).

## R10: No remaining-mode screenshot

- **Decision**: no new stem; the feature card copy mentions the setting.
- **Rationale**: AGENTS.md reserves new stems for features that earn a card; the direction is a reading preference of existing surfaces.
