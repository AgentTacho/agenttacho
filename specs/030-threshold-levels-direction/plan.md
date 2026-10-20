# Implementation Plan: Threshold Levels and Budget Direction

**Branch**: `030-threshold-levels-direction` | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/030-threshold-levels-direction/spec.md`

## Summary

Two changes to how every level value is presented, designed together.

1. **Levels from thresholds.** One level rule in UsageCore (`LevelThresholds`) turns an owner's thresholds into a warning and a critical threshold (lowest and second lowest, defaults 80 and 100) and classifies a used percent, with real limits (used ≥ 100, Codex limit reached, Claude 7-day ≥ 100 while another headline is shown) always critical. `BarLayout`, the dropdown's `RowBar` and a new dropdown percent tone all use it, so the menu bar, the row percents, the section header percents and the red bar agree with the notifications.
2. **Direction switch.** A global `displayDirection` setting (`used` default, `remaining`) is stored in the configuration file. A pure `DirectedPercent` value in UsageCore derives the shown text ("30%", "−15%"), the accessibility words ("30% left", "15% over budget"), the bar fill and the tick share from a used percent and the direction. Markers, budget dollar lines, the thresholds editor and notification texts get small UsageCore helpers that take the direction. The SwiftUI and AppKit layers only pass the direction through and render.

## Technical Context

**Language/Version**: Swift 6 (Swift Package, macOS app built through the Makefile)

**Primary Dependencies**: SwiftUI, AppKit, UserNotifications; no new dependency

**Storage**: the existing JSON configuration file (`ConfigStore`); one new optional global key `displayDirection`

**Testing**: Swift Testing / XCTest via `make test`; release scripts via `make test-release`

**Target Platform**: macOS 14 or later, menu bar app

**Project Type**: desktop app (UsageCore library, DemoMode library, AgentTacho SwiftUI app)

**Performance Goals**: no measurable change; all new logic is constant time per drawn value

**Constraints**: constitution II (logic in UsageCore, test first, doc comments cite FRs), no em or en dash, demo scenario covers the shot states (constitution V)

**Scale/Scope**: about 8 UsageCore files touched or added, 6 app files touched, 2 docs, 1 demo scenario, 8 earlier specs amended

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How |
|---|---|---|
| I. Spec-driven development | Pass | spec 030 with clarifications and review; amendments to specs 001, 011, 012, 017, 025 listed in FR-019 |
| II. Test-first, logic in UsageCore | Pass | `LevelThresholds`, `DisplayDirection`, `DirectedPercent`, `RunOutGlyph`, `BudgetAmountLine`, `ThresholdDisplay`, `ThresholdNotificationText` and the `RowBar` changes are UsageCore types with tests written first; views only render |
| III. Read-only, private by default | Pass | no new file access, credentials or network requests; README "Security and privacy" unchanged |
| IV. One build entry point | Pass | `make test`, `make test-release`, `make app-demo` only |
| V. Screenshots and website follow the UI | Pass | section below; demo scenario gets a threshold-driven red and a coverage check |

Post-design re-check: unchanged, no violations, no complexity tracking needed.

## Screenshots and website

| | |
|---|---|
| Shots that change | menubar, dropdown, plan-limits, budget, pace, groups, menubar-settings (the preview shows the new threshold-driven red); all 22 files are recaptured in one run anyway |
| New shots | none. Remaining mode gets no shot of its own: it is a reading preference, not a feature with its own UI surface, and a second dropdown image would double the capture state for little gain. The card copy mentions it instead |
| Demo scenario | `Resources/demo/default.json`: the Side project own budget gets $30 per week and thresholds `[75, 85]`, so its spend (about $26, 87%) is critical below 100 in the bar entry and the dropdown (chosen at implementation, T036: the ChatGPT Plus candidate `[50, 55]` would make the Codex entry critical, which drops its `↗`, the only `↗` in the bar, and breaks the marker check). Claude Max keeps 80/100, so the 7-day row stays orange with its pace note (the `pace` shot); the Side values do not change between frames, so the one Company budget alert stays the only crossing. New coverage fields `thresholdCriticalRows` and `thresholdCriticalEntries` with `#expect`s in `DefaultScenarioTests`; all existing checks keep passing. The budget above 100% moved to `variants.json` (Team budget $80, about 109%), checked by `someScenarioHasABudgetAboveHundred` and covered by UsageCore tests (FR-020) |
| Website copy | `src/data/features.ts`: the card about the menu bar levels and limits says the thresholds set orange and red, and one sentence (or a small thing, keeping the count at five by rewording an existing one) says usage can read as remaining. Exact entry chosen when editing the site checkout |
| README image | unchanged (the README no longer carries the dropdown image) |

## Design

### Level rule (FR-001 to FR-006, FR-014)

- New `Sources/UsageCore/Bar/LevelThresholds.swift`:
  - `struct LevelThresholds { warning: Int; critical: Int }`, `init(_ thresholds: [Int])`: sort the positive values, keep duplicates; warning = first or 80, critical = second or 100 (FR-002, I-1 decision).
  - `func level(usedPercent: Int?, atRealLimit: Bool) -> BarLevel`: nil → normal; `atRealLimit || used >= 100 || used >= critical` → critical; `used >= warning` → warning; else normal.
  - `func isRealLimit(usedPercent:limitReached:) -> Bool` helper so callers can tell "critical below 100" from "over limit" for the accessibility word (FR-004).
- Every caller uses `LevelThresholds` directly; `BarLayout.level(percent:thresholds:)` and `warningThreshold` are removed. `BarItem` gains `overLimit: Bool` (real limit), set where the cross-window rules already sit (`subscriptionItem`, `codexItem`, `budgetItem`). The level of a group member item keeps using the group's thresholds.
- Section header level: extract the level part of `subscriptionItem`/`codexItem` into `BarLayout.subscriptionLevel(...)` and `BarLayout.codexLevel(...)` (internal statics returning level and overLimit) so the dropdown header (`HeadlineHeader`) uses the same decision, including the cross-window rules (I-4 decision). Budget headers use `level(percent:thresholds:)`.
- Dropdown percent tone: new `enum PercentTone { primary, warning, critical }` with `init(_ level: BarLevel)` in `Sources/UsageCore/Dropdown/RowBar.swift` (or a new `PercentTone.swift`). Row levels use the row's own rounded percent and its own `limitReached` only.
- `RowBar.make(usedPercent:limitReached:thresholds:direction:reading:)` and `RowBar.budget(_:thresholds:direction:reading:)`: `overLimit` becomes `critical`, decided by `LevelThresholds`; the bar exposes `level` so the row percent and the bar never disagree. Warning never colors the bar (FR-006).

### Direction (FR-008 to FR-014)

- New `Sources/UsageCore/Config/DisplayDirection.swift`: `enum DisplayDirection: String, Codable { used, remaining }`. `Configuration.displayDirection` decoded leniently like `levelColor` (missing, unknown or wrong type → `.used`), encoded always or only when not default (follow `levelColor`'s pattern).
- New `Sources/UsageCore/Bar/DirectedPercent.swift`: `struct DirectedPercent(usedPercent: Int, direction:)` with
  - `value: Int` (used, or 100 − used),
  - `text: String` ("30%", "−15%" with U+2212),
  - `accessibilityText(_ kind: Kind) -> String` with `Kind` `.budget` or `.window` (used: "70%" unchanged; remaining: "30% left", "15% over budget", "15% over the limit"),
  - `static func fill(usedPercent: Double, direction:) -> Double` and `tick(expectedPercent:direction:)` clamped to 0...1 (FR-010). Rounding: fill keeps the unrounded share as today; the remaining fill is `1 − usedShare`, clamped.
- `RunOutGlyph.text(burnsFast:direction:)` returns "↗"/"↑" or "↘"/"↓" (FR-011). `BarLayout.segments` stores it on `BarItem.runOutGlyph`, so `BarPresentation.entries` keeps its signature (review-plan decision); the Menu Bar tab label calls it directly.
- A budget of 0 or less keeps today's "$S of $B/period" line in both directions (review-plan decision).
- `BarLayout.segments` reads `configuration.displayDirection` and builds `BarItem.value` through `DirectedPercent` for subscription, Codex and budget items; member items keep the used share (FR-013). `BarItem` gains `accessibilityValue` so `BarPresentation.accessibilityText` reads "Claude Max critical 8% left" and "over limit" only for real limits.
- `HeadlineHeader` takes the direction (value through `DirectedPercent`) and the level.
- `BudgetAmountLine.make(spent:budget:roundedPercent:direction:)` returns `.of(spent)`, `.left(amount)` or `.over(amount)` with `text(amount:budget:period:)` taking the app's formatters; "over" exactly when the rounded percent is above 100 (FR-012, M-7 decision). `RowText.budget` keeps taking the formatted string.
- `RowText.window` uses `DirectedPercent.accessibilityText` for the percent part.

### Thresholds in the chosen direction (FR-015 to FR-017)

- New `Sources/UsageCore/Notifications/ThresholdDisplay.swift`: `shown(stored:direction:) -> Int` (T or 100 − T), `stored(entered:direction:) -> Int`, `caption(stored:direction:) -> String?` ("(20% over)" for T > 100 in remaining), `hasInvalidStored(_:)` (a stored value of 0 or less; equals entries above 0 in used and below 100 in remaining), `validationMessage(direction:)`, `fieldSuffix(direction:)` ("%" or "% left"), `placeholders(direction:)` ("80"/"100" or "20"/"0"), `explanation(limitDescription:direction:)` with both levels (FR-007), and `furtherThresholds(_:direction:)` for the "Also active from the configuration file" line.
- New `Sources/UsageCore/Notifications/ThresholdNotificationText.swift`: `make(_ crossing:direction:) -> (title: String, body: String)` per FR-016 and `logDescription(_:)` (moved from the presenter's private `describe`, stays in used percent, FR-017). `NotificationPresenter` gets `init(log:direction:)` with a closure that `App.swift` binds to the current configuration, called at posting time (M-10 decision).
- Section headers: public `HeadlineWindow.claudeHeader(_:entry:thresholds:direction:now:)` and `codexHeader(_:entry:thresholds:direction:now:)` wrap the internal level statics; `HeadlineHeader` carries `level`, `overLimit` and `accessibilityValue`.
- `ThresholdsEditor` binds through `ThresholdDisplay`; it needs the direction from the configuration and redraws when it changes.

### App layer (thin)

- `SettingsView.swift`: `GeneralSettingsTab` gets `Section("Display")` after "Refresh" with `Picker("Show usage as", selection:)` `.pickerStyle(.segmented)` and the caption; `ThresholdsEditor` takes `direction`.
- `MenuBarSettingsTab.swift`: label "Show \(RunOutGlyph.text(burnsFast: false, direction:)) or \(RunOutGlyph.text(burnsFast: true, direction:)) when …"; the preview passes the direction.
- `DropdownView.swift`: pass direction and thresholds into `RowBar`, `LimitRowLayout` percent color from `PercentTone`, header percents colored, budget percent and amount line from `DirectedPercent`/`BudgetAmountLine`. Member lines unchanged.
- `RowBarView.swift`: no geometry change (fill already starts at the leading edge); colors unchanged.
- `BarLabel.swift`: marker text from the presentation (already), nothing else.
- `NotificationPresenter.swift`: texts from `ThresholdNotificationText`.

### Docs and spec amendments (FR-019)

- `docs/usage.md`: the two levels from the thresholds, the dropdown colors, the direction setting and what does not flip. `docs/configuration.md`: `displayDirection` and that thresholds stay in used percent.
- Amendment notes (dated 2026-10-20, "amended by spec 030") in spec 001 (FR-003, FR-027, FR-028), spec 012 (levels, accessibility words), spec 025 (FR-002, FR-003, FR-007), spec 011 FR-012, spec 017 FR-008.

## Project Structure

### Documentation (this feature)

```text
specs/030-threshold-levels-direction/
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── level-rule.md
│   └── direction-presentation.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Bar/
│   ├── LevelThresholds.swift        # new: FR-001 to FR-003
│   ├── DirectedPercent.swift        # new: FR-009, FR-010, FR-012
│   ├── RunOutGlyph.swift            # new: FR-011
│   ├── BarLayout.swift              # level via LevelThresholds, direction, overLimit flag
│   ├── BarPresentation.swift        # glyphs and accessibility words
│   └── HeadlineWindow.swift         # header value and level
├── Config/
│   ├── DisplayDirection.swift       # new: FR-008
│   └── Configuration.swift          # displayDirection key
├── Dropdown/
│   ├── RowBar.swift                 # critical from thresholds, fill and tick by direction, PercentTone
│   ├── RowText.swift                # accessibility percent words
│   └── BudgetAmountLine.swift       # new: FR-012
└── Notifications/
    ├── ThresholdDisplay.swift       # new: FR-007, FR-015
    └── ThresholdNotificationText.swift  # new: FR-016

Sources/DemoMode/ScenarioCoverage.swift   # thresholdCriticalRows
Sources/AgentTacho/{SettingsView,MenuBarSettingsTab,DropdownView,NotificationPresenter}.swift
Resources/demo/default.json
Tests/UsageCoreTests/{LevelThresholds,DisplayDirection,DirectedPercent,RunOutGlyph,BudgetAmountLine,ThresholdDisplay,ThresholdNotificationText}Tests.swift (new)
Tests/UsageCoreTests/{BarLayout,BarPresentation,RowBar,RowText,HeadlineWindow,Configuration}Tests.swift (extended)
Tests/DemoModeTests/DefaultScenarioTests.swift
docs/usage.md, docs/configuration.md
specs/{001,011,012,017,025}-*/spec.md (amendment notes)
```

**Structure Decision**: the existing three-target layout. New logic sits next to the code it replaces (`Bar/`, `Dropdown/`, `Notifications/`, `Config/`); no new module.

## Complexity Tracking

No constitution violations.
