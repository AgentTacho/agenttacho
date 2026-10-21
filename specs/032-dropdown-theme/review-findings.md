# Deep Review Findings

**Date:** 2026-10-21
**Branch:** 032-dropdown-theme
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

The review covers the branch up to the maintainer's palette change f2d8ecb (light background `#D5D6D9`, secondary `#48484A`, warning `#7A2E00`, critical `#8A000A`), which is a deliberate decision and not a finding. With it, the lowest text ratio on the light panel is 4.65:1 (secondary on a hover over a tinted band with Increase Contrast).

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 5 | 2 | 3 |
| Notable | 5 | 2 (acted on) | 3 |
| **Total** | **11** | **5** | **6** |

13 raw findings, 11 after merging duplicates.

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR), plus CodeRabbit and Codex.
**Agents failed:** none. Copilot is disabled in the config. Codex could not run `make test` inside its sandbox; it reviewed the code only.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Dropdown/DropdownPalette.swift (foreground, backgrounds), Sources/AgentTacho/DropdownView.swift (bandFill, hover fill), Tests/UsageCoreTests/DropdownPaletteTests.swift
- **Category:** architecture
- **Source:** architecture agent (also reported by: test quality agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, ef1a391)

**What is wrong:**
The contrast tests blend `DropdownPalette.foreground` (pure white or black) into the bands and hover backgrounds. The views draw those fills with `Color.primary`, which is the label color and has its own alpha of about 0.85. No code tied the two together, and the doc comment mentioned "selection fills", which do not exist.

**Why this matters:**
The model happens to be conservative today. Still, if a view changed its fill color, the FR-007/FR-011 tests would keep passing against a background the dropdown never draws.

**How it was resolved:**
The drawing was not changed: drawing from `palette.foreground` would make the dark bands stronger, which conflicts with FR-008. Instead:
- A new test (`drawnBandsMatchTheModel`) resolves `labelColor` under both appearances. It asserts that the RGB equals `foreground` and the alpha is at most 1, so the model is an upper bound. It also repeats the FR-011 comparison at the drawn alpha.
- The doc comments on `foreground` and `bandFill` now say how the model relates to the drawing.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/UpdateViews.swift:55-80 (UpdateButtons, `.buttonStyle(.link)`)
- **Category:** correctness
- **Source:** correctness agent
- **Round found:** 1
- **Resolution:** remaining (needs a decision)

**What is wrong:**
The update line's buttons ("Install", "Release notes", "Cancel", "Release page") use the system link color, not the palette. Against `#D5D6D9`, a link blue of about `#0068DA` reaches the ratios below. The dark panel reaches about 4.8:1 on its footer.

| Background | Ratio |
|---|---|
| Plain panel | 3.6:1 |
| Footer band | 3.1:1 |
| Footer band, Increase Contrast | 2.8:1 |

**Why this matters:**
FR-007 lists four text roles (primary, secondary, warning, error) and FR-012 says the update line follows the theme. Link text is not one of the four roles, so the spec does not settle whether it is covered. The light theme still makes the only actionable text in the footer harder to read.

**How it was resolved:**
Not fixed. Either add a link role to the palette and apply it inside `UpdateLine` only (About shares `UpdateButtons`), with a visual check that `.buttonStyle(.link)` honors the tint. Or state in the spec that link buttons keep the system link color.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Dropdown/DropdownPalette.swift:10-17, Sources/AgentTacho/DropdownColors.swift (style)
- **Category:** architecture
- **Source:** architecture agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
`DropdownTextColor.system(DropdownTextRole)` carries a role that always equals its slot. A test has to assert `systemRole == role`.

**Why this matters:**
An invalid combination such as `primary: .system(.secondary)` would compile.

**How it was resolved:**
Left as is. This is a small type cleanup with no behavior impact, better done on its own.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift:78-79, 167-170; Sources/AgentTacho/DropdownColors.swift
- **Category:** production-readiness
- **Source:** production readiness agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 38813fd)

**What is wrong:**
Every body evaluation built a new `DropdownColors` with four fresh `AnyShapeStyle` boxes and injected it. The environment key's default was a computed property that allocated on each read.

**Why this matters:**
Every reader of `dropdownColors` was invalidated on each geometry pass, including the breakdown grids.

**How it was resolved:**
The dark and light `DropdownColors` are now static values handed out through `DropdownColors.forStyle(_:)`. The environment default is a `static let`.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/DropdownView.swift:111-113
- **Category:** production-readiness
- **Source:** production readiness agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
`NSApp.publisher(for: \.effectiveAppearance)` is created inside `body`. The agent suspects that `onReceive` resubscribes on every update.

**Why this matters:**
That would mean KVO observer churn and a state write during the update.

**How it was resolved:**
Left as is. `NSObject.KeyValueObservingPublisher` is `Equatable`, so SwiftUI can keep the existing subscription. The `@State` write is a no-op when the value does not change. A fix could not be verified without profiling the running app, and a change here touches the FR-006 live switch. A follow-up can measure this in the walkthrough.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/DropdownPaletteTests.swift
- **Category:** test-quality
- **Source:** test quality agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ef1a391)

**What is wrong:**
No test covered the bar track (`Color.secondary` at 0.25), which FR-010 places under FR-011. The band test also ended in a loop that only checked constants.

**Why this matters:**
A track that disappears on the light panel would go unnoticed.

**How it was resolved:**
`barTrackIsVisible` resolves `secondaryLabelColor` under each appearance and asserts that the track differs from the plain panel and from a tinted band, with and without Increase Contrast. The constant-only loop is gone.

## Notable Observations

### NOTABLE-1 (acted on, 38813fd)
- **File:** Sources/AgentTacho/DropdownColors.swift
- **Category:** architecture
- **Source:** architecture agent (also reported by: correctness agent)
- **Description:** The environment default was the dark palette, whose critical color is a fixed light red. A dropdown view reused outside the dropdown would draw a pale red in Settings.
- **Rationale:** This is a latent FR-005 trap. The default is now the system colors the views used before spec 032.

### NOTABLE-2 (acted on, 38813fd)
- **File:** Sources/AgentTacho/DropdownView.swift (opened)
- **Category:** production-readiness
- **Source:** production readiness agent
- **Description:** The window's appearance and background were reapplied only on SwiftUI updates. A switch while the panel was hidden might show a stale rim on the first frame after reopening.
- **Rationale:** `opened()` now calls `applyPanelStyle(to:)`, which is cheap and idempotent.

### NOTABLE-3
- **File:** Sources/UsageCore/Config/Configuration.swift (clipped)
- **Category:** security
- **Source:** security agent
- **Description:** Load-note values are clipped by grapheme clusters. A value made of combining marks passes the 32-character bound.
- **Rationale:** This only bloats the log, and log lines stay single-line. The helper is older than this feature. Captured as `clip-notes-by-scalars`.

### NOTABLE-4
- **File:** Tests/UsageCoreTests/DropdownPaletteTests.swift, Sources/AgentTacho/DropdownColors.swift
- **Category:** test-quality
- **Source:** test quality agent
- **Description:** The test maps system roles to `NSColor` separately from `DropdownColors`.
- **Rationale:** Captured as `shared-system-color-mapping`.

### NOTABLE-5
- **File:** Tests/UsageCoreTests/DropdownPaletteTests.swift
- **Category:** test-quality
- **Source:** test quality agent
- **Description:** Increase Contrast system variants are covered only in the walkthrough, which the spec's assumptions allow.
- **Rationale:** Captured as `increase-contrast-system-variants`. The walkthrough should check the dark panel with Increase Contrast: the footer, and a hovered tinted row with an orange note.

## Post-Fix Spec Coverage

The fix round removed no implementation code; it removed one test loop and replaced one default. FR-001 to FR-014 are still implemented at the locations listed in REVIEW-CODE.md. FR-015 (recapture and site copy) is pending outside the code.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| before review | make test | 0 | 0 | passed (1756 + 69) |
| 1 | make build, make test | 0 | 0 | passed (1758 + 69) |

## External Tools

| Tool | Initial | Re-review (85c7989..HEAD, includes f2d8ecb) |
|---|---|---|
| CodeRabbit | 0 findings | 0 findings |
| Codex | 0 findings | 0 findings |
| Copilot | skipped (disabled in config) | skipped |

## Remaining Findings

No Critical or Important finding remains. FINDING-2 (link button contrast on the light panel) needs a requirement decision. FINDING-3 and FINDING-5 are optional cleanups.
