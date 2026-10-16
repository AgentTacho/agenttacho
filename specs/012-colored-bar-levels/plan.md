# Implementation Plan: Colored Bar Levels

**Branch**: `012-colored-bar-levels` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/012-colored-bar-levels/spec.md`

## Summary

Bar levels are shown by color instead of the `⚠` and `‼` glyphs. Two new configuration settings, `levelColor` (Text by default, Pill, Off) and `showLevelSymbols` (off by default), control the presentation. A pure `BarPresentation` in `UsageCore` decides for each bar entry which parts carry which tone, whether a glyph or pill is drawn, and the accessibility text; `PillContrast` picks black or white text for a pill. The app's `BarLabelBuilder` keeps drawing one image for the `MenuBarExtra` label: a template image as today when nothing is colored, a full-color image with dynamic system colors resolved at draw time when a level color is shown (research R1, R2). The Menu Bar tab gets the two controls, a hidden-levels note and a preview that renders with dark-appearance colors.

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10)

**Primary Dependencies**: SwiftUI (`MenuBarExtra`, Settings), AppKit (`NSImage`, `NSColor`, `NSAppearance`, `NSBezierPath`); no new third-party dependencies

**Storage**: `~/.config/agentmeter/config.json` (two new top-level keys)

**Testing**: Swift Testing via `make test` (`Tests/UsageCoreTests`)

**Target Platform**: macOS 14 or newer, Apple Silicon

**Project Type**: desktop menu bar app (`UsageCore` library plus thin `AgentMeter` executable)

**Performance Goals**: bar redraw after an appearance change within 1 s (FR-014); drawing cost unchanged in magnitude (one image per bar update)

**Constraints**: logic in `UsageCore` with tests first; the app layer stays thin (AGENTS.md); no writes to agent files; no network changes; no em or en dashes

**Scale/Scope**: about 10 bar entries at most; 6 setting combinations times 3 levels times fresh or stale

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is still the unfilled template, so the project rules in `AGENTS.md` serve as the gate:

| Rule | Status |
|---|---|
| Build and test only through the Makefile | Pass: `make test`, `make app` |
| Logic in `UsageCore`, covered by tests, test first | Pass: `BarPresentation`, `PillContrast`, configuration decoding and load notes are in `UsageCore` with tests written first; the app maps tones to `NSColor` and draws |
| Doc comments cite spec requirements | Pass: new types cite `spec 012 FR-...` |
| No em or en dashes | Pass: checked in review |
| Read-only on agent files; Security and privacy section stays true | Pass: no credential, network or agent-file change |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/012-colored-bar-levels/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── bar-rendering.md
│   └── menu-bar-tab-level-settings.md
├── checklists/requirements.md
└── tasks.md             # created by /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Bar/
│   ├── BarLayout.swift            # unchanged (levels, items)
│   ├── LevelDisplay.swift         # NEW: LevelColorStyle, LevelDisplaySettings
│   ├── BarPresentation.swift      # NEW: BarTone, BarEntryPresentation, BarPresentation
│   └── PillContrast.swift         # NEW: RGB, luminance, contrast, black/white choice
├── Config/
│   ├── Configuration.swift        # levelColor, showLevelSymbols, tolerant decoding, dataRelevant
│   ├── ConfigurationLoadNotes.swift  # NEW: decoder userInfo collector
│   └── ConfigStore.swift          # passes the collector, takeLoadNotes()
└── Snapshot/
    └── RefreshCoordinator.swift   # logs load notes with source "config"

Sources/AgentMeter/
├── BarLabel.swift                 # renders BarEntryPresentation; template or full color; pill
├── App.swift                      # passes configuration.levelDisplay to BarLabelView
├── MenuBarSettingsTab.swift       # Level color picker, symbols checkbox, note, preview appearance
└── SettingsView.swift             # threshold help text (FR-006)

Tests/UsageCoreTests/
├── BarPresentationTests.swift     # NEW: decision table, accessibility text, usesColor, hidesLevels
├── PillContrastTests.swift        # NEW: luminance, ratios, four appearance conditions
├── ConfigurationTests.swift       # new keys: absent, known, unknown, encode, dataRelevant
└── ConfigStoreTests.swift         # load notes once per file read

README.md                          # bar marker sentence (FR-021)
specs/001-agentmeter/spec.md       # note on FR-003 pointing to spec 012 (FR-021)
```

**Structure Decision**: Existing two-target layout. New pure logic goes into `Sources/UsageCore/Bar` next to `BarLayout`; AppKit drawing stays in `Sources/AgentMeter/BarLabel.swift`.

## Implementation Notes

- **Order of work**: settings model and decoding (with tests), then `PillContrast` and `BarPresentation` (with tests), then the app renderer, then the Menu Bar tab, then help text, README and spec 001 note.
- **Renderer** (`BarLabelBuilder.image(_ entries:, appearance: NSAppearance?)`): builds the attributed text from presentations. If `BarPresentation.usesColor` is false it draws in black and sets `isTemplate = true` (today's look). Otherwise it creates a drawing-handler image with `cacheMode = .never`; inside the handler, `appearance?.performAsCurrentDrawingAppearance` (preview) or the current drawing appearance (bar) resolves `labelColor`, `systemOrange`, `systemRed`. Pills are drawn first (rounded rects behind each pill entry's text range, from the layout manager's glyph rects or measured substrings), then the text. Pill text color: convert the resolved fill to sRGB, call `PillContrast.textColor(onFill:)`.
- **Redraw on appearance change**: `BarLabelView` reads `@Environment(\.colorScheme)` and `\.colorSchemeContrast` and uses them in the view's identity so SwiftUI rebuilds the image (FR-014). If the walkthrough shows that the bar does not pick up the menu bar's appearance from the drawing context, the bar passes an explicit appearance derived from those environment values (research R1 fallback).
- **Removed**: `BarItem.text` and `BarItem.valueText` app extensions (replaced by `BarEntryPresentation`), the `tint` parameter of `BarLabelView` (replaced by a `preview` flag).
- **Risk**: whether `MenuBarExtra` redraws the label image with the status button's appearance. Mitigated by R2 (template whenever nothing is colored) and the R1 fallback; checked in the walkthrough (quickstart steps 3 to 5).

## Complexity Tracking

No violations.
