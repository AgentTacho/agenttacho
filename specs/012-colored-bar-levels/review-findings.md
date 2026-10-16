# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 012-colored-bar-levels
**Rounds:** 2
**Gate Outcome:** PASS
**Invocation:** quality-gate (speckit-spex-ship, review-code stage)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 4 | 4 | 0 |
| Minor | 8 | 5 | 3 |
| Notable | 4 | - | 4 |
| **Total** | **16** | **9** | **7** |

**Agents completed:** 5/5 internal (Goal Alignment skipped, no PR found) + 2 external tools (CodeRabbit, Codex). Copilot disabled in config.
**Agents failed:** none. The first CodeRabbit call used an option the installed CLI does not have (`--files`); it was rerun with `--base main --committed`.

Fix commit: 8423ad6 `fix(bar): address deep review findings for colored bar levels`.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 88
- **File:** Sources/AgentMeter/BarLabel.swift (`previewAppearance`)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, refined in round 2)

**What is wrong:**
The preview built its appearance with `NSAppearance(named: .accessibilityHighContrastDarkAqua)` when "Increase contrast" was on. NSAppearance.h documents the accessibility names as valid only for `bestMatch(from:)`, and says `appearanceNamed:` returns NULL for them. A nil appearance makes `BarLabelBuilder.image` skip `performAsCurrentDrawingAppearance`. Orange, red and the pill text color then resolve under the Settings window's appearance instead of dark.

**Why this matters:**
FR-005 requires the preview to render like a dark menu bar. In a light system appearance with Increase contrast on, the preview would show light-appearance level colors on the dark capsule.

**How it was resolved:**
A read-only probe on this machine (macOS 26) showed the runtime does return an appearance for the accessibility names. With the setting off, it resolves the same colors as `.darkAqua`. So the failure did not reproduce, but it depends on behavior the API documents as unsupported. Round 1 switched to `.darkAqua` only. Codex then flagged that this drops the high-contrast variants (FINDING-4). Final code: try the high-contrast dark appearance when contrast is increased, and fall back to `.darkAqua` when AppKit returns nil. The preview can no longer lose its dark rendering. research.md R5 was updated to match.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/PillContrastTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
SC-004 asks for tests "for the resolved fill colors". The test used research R3's hard-coded hex values, which are the palette from before macOS 26. On this system, `systemOrange`/`systemRed` resolve to FF8D28/FF383C (light) and FF9230/FF4245 (dark), confirmed by a probe.

**Why this matters:**
The test proved the WCAG math but not what ships. A palette change had already gone unnoticed.

**How it was resolved:**
Added `resolvedSystemFillsReachContrast`. It resolves the real `systemOrange` and `systemRed` under `.aqua` and `.darkAqua`, the same way `BarLabelBuilder.pillTextColor` does, and asserts at least 4.5:1 for the chosen text color. The hex table was relabeled as reference fills and now includes the macOS 26 values. research.md R3 notes the new palette. The increased-contrast cells cannot be resolved without changing the system setting, so the walkthrough covers them (NOTABLE-4).

### FINDING-3
- **Severity:** Important (Codex P2)
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift (`decodeLevelColor`)
- **Category:** external
- **Source:** codex (related: test-quality-agent FINDING-5 below)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
An explicit `"levelColor": null` returned `.text` with no load note. data-model.md says a non-string value yields `text` plus a note.

**Why this matters:**
Under FR-003, an unreadable value must leave a note in the diagnostic log. Null was the one silent case.

**How it was resolved:**
Removed the `decodeNil` short circuit. A present null now goes through the "not readable" branch and leaves one note. `null` was added to the arguments of `unreadableLevelColorFallsBackToText`.

**External tool analysis (Codex):**
> When a configuration explicitly contains `"levelColor": null`, this guard returns `.text` before adding a load note. A present null is a non-string/unreadable value, so users receive no diagnostic-log explanation despite the tolerant-decoding contract requiring one for non-string values (data-model.md:10).

### FINDING-4
- **Severity:** Important (Codex P2)
- **Confidence:** 75
- **File:** Sources/AgentMeter/BarLabel.swift (`previewAppearance`)
- **Category:** external
- **Source:** codex (fix-loop re-review)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:**
The round 1 fix for FINDING-1 always forced `.darkAqua`, so with Increase contrast on, the preview might not show the high-contrast dark colors (FR-005, FR-011).

**Why this matters:**
The preview would differ from a high-contrast dark menu bar.

**How it was resolved:**
The high-contrast dark appearance is used when contrast is increased, with `.darkAqua` as the nil fallback (see FINDING-1). Codex's round 3 re-review found no actionable defects.

**External tool analysis (Codex):**
> When Increase Contrast is enabled, this still forces the drawing handler to ordinary `.darkAqua`, so `systemOrange` and `systemRed` resolve against the non-accessibility appearance; rebuilding via `.id` only regenerates that same appearance.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/ConfigurationTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, together with FINDING-3)

**What is wrong:** No test covered `"levelColor": null`, which had its own code path.
**Why this matters:** The null behavior could change without any test failing.
**How it was resolved:** `null` is now one of the `unreadableLevelColorFallsBackToText` arguments: it decodes as text with exactly one note.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift (`decodeLevelColor`)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** An unknown `levelColor` string was copied into the diagnostic log note in full, with no length limit. A stray long value or a pasted token would land in `usage.log` whole.
**Why this matters:** README's "Security and privacy" section promises a 5 MB log cap and no credentials in the log. `DiagnosticLog` already escapes control characters, so injection was not possible.
**How it was resolved:** The value is clipped to 32 characters plus `...` (`Configuration.clipped`). The new test `longUnknownLevelColorIsClippedInTheNote` covers it.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/AgentMeter/BarLabel.swift (preview branch)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The preview called `BarPresentation.usesColor` again to choose template or full-color rendering, duplicating the builder's decision.
**Why this matters:** If the builder's template rule changed, the preview would silently drift from the real bar.
**How it was resolved:** The preview now branches on `nsImage.isTemplate`.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/BarLabel.swift (`Layout.measure` doc comment)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The comment said pill extents come "from the same text layout that drawing uses". Measurement uses its own `NSLayoutManager`, while drawing uses `draw(at:)`.
**Why this matters:** It suggested a guarantee that does not exist.
**How it was resolved:** The comment now says a TextKit layout of the same attributed string is used, and that `draw(at:)` lays out a single line without a container width the same way.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/MenuBarSettingsTab.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The type doc comment did not mention the level settings, and the checkbox comment cited FR-010 (the rendering rule) instead of FR-004 (the setting).
**Why this matters:** The project convention is that doc comments cite the requirements they implement.
**How it was resolved:** Both comments were updated.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/BarLabel.swift (run-out marker in `Layout`)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (accepted)

**What is wrong:** The app hardcodes `.neutral` as the run-out marker's tone. `BarEntryPresentation` carries no tone for the marker.
**Why this matters:** FR-020 places tone decisions in UsageCore. Today spec 011 shows the marker only on entries without a level, so neutral is always correct.
**Why it remains:** It changes no behavior, and the invariant is enforced and tested upstream (`BarLayout.marker`, and `runOutMarkerStaysNeutralAndIsSpelledOut` in BarPresentationTests). Worth revisiting if spec 011 ever allows the marker at a level.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/Configuration.swift, Sources/UsageCore/Bar/LevelDisplay.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (accepted)

**What is wrong:** The JSON key `showLevelSymbols` sits next to spec 011's `showsRunOutMarker`. `LevelDisplaySettings` calls the same setting `showSymbols`.
**Why this matters:** Persisted keys are hard to rename after release.
**Why it remains:** The key matches the spec's wording ("show level symbols"), the README and data-model.md. Renaming touches docs and contracts across the feature for a naming preference. Before release it is a cheap human decision.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Config/ConfigurationLoadNotes.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (accepted)

**What is wrong:** The collector is `public`, `@unchecked Sendable` and guarded by its own lock, although only one decode uses it at a time.
**Why this matters:** It adds a small piece of public API and an unneeded lock.
**Why it remains:** `JSONDecoder.userInfo` values must be Sendable under strict concurrency checking. The lock makes the `@unchecked` claim true at negligible cost. Narrowing the visibility is cosmetic.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Bar/BarPresentation.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The pill state is stored three times (`iconTone`, `textTone`, `pill`), so inconsistent combinations are representable.
- **Rationale:** A single `EntryStyle` enum would make invalid states impossible.

### NOTABLE-2
- **File:** Sources/UsageCore/Diagnostics/DiagnosticLog.swift
- **Category:** security
- **Source:** security-agent
- **Description:** `append` never caps the length of a single line, so the 5 MB promise depends on callers.
- **Rationale:** A cap in the sink would cover every caller. FINDING-6 bounds this feature's note.

### NOTABLE-3
- **File:** Sources/AgentMeter/BarLabel.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** The full-color path relies on `MenuBarExtra` redrawing the image under the menu bar's appearance (wallpaper tinting, highlighted state, a second display). The spike was not run, because launching the app was not allowed during implementation.
- **Rationale:** FR-013 to FR-015 depend on it. The walkthrough (quickstart steps 3 to 5) must check it before merge.

### NOTABLE-4
- **File:** Tests/UsageCoreTests/PillContrastTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The increased-contrast cells of SC-004 cannot be resolved in tests without changing the system setting.
- **Rationale:** The walkthrough should check pill legibility with Increase contrast on.

## Post-Fix Spec Coverage

The fix loop removed one guard (`decodeNil`) and changed the preview appearance. Every requirement was rechecked after the fixes.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001, FR-002 settings and defaults | `Configuration.levelColor`, `showLevelSymbols`, `LevelDisplaySettings` | ✓ |
| FR-003 tolerant decoding, notes, write-back | `decodeLevelColor` (now also notes null), `ConfigStore.takeLoadNotes`, `RefreshCoordinator` log | ✓ |
| FR-004 Menu Bar tab controls, no refresh | `MenuBarSettingsTab.levelSettings`, `dataRelevant()` | ✓ |
| FR-005 preview renders as dark bar | `BarLabelView(preview:)`, `previewAppearance` with nil fallback | ✓ |
| FR-006 threshold help text | `ThresholdsEditor` | ✓ |
| FR-007 to FR-010 tones, pill, glyphs | `BarPresentation.entry`, `BarLabelBuilder` | ✓ |
| FR-011 system orange and red | `BarLabelBuilder.color`, `pillFill` | ✓ |
| FR-012 hidden-levels note | `LevelDisplaySettings.hidesLevels`, tab note | ✓ |
| FR-013 to FR-016 neutral color, appearance, highlight, stale marker | template/full-color switch, `.id`, `cacheMode = .never`, value text order | ✓ |
| FR-017 level computation unchanged | levels from `BarLayout` | ✓ |
| FR-018 accessibility text | `BarPresentation.accessibilityText` | ✓ |
| FR-019 notifications and dropdown unchanged | no changes there | ✓ |
| FR-020 decisions testable without drawing | UsageCore `BarPresentation`, `PillContrast`, `LevelDisplaySettings` | ✓ |
| FR-021 README and spec 001 note | README, specs/001 FR-003 note | ✓ |

All spec requirements were verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (758 tests) |
| 1 | make test | 0 | 0 | passed (760 tests) |
| 2 | make test | 0 | 0 | passed (760 tests) |

`make app` built successfully after each round. The app was not launched.

## Remaining Findings

None Critical or Important. Three Minor findings (FINDING-10 to FINDING-12) remain by judgment. The reasons are given above.
