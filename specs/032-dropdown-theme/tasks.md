# Tasks: Dropdown Theme

**Input**: Design documents from `specs/032-dropdown-theme/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/dropdown-theme.md, quickstart.md

**Tests**: Required. Constitution II: logic in UsageCore, tests written first and failing before the implementation. Every new or changed UsageCore type cites its FRs in doc comments (`spec 032 FR-00x`).

**Rules for every task**: build and test only with `make test` (and `make test-release` at the end), never `swift build` or `xcodebuild`. No em dash or en dash characters anywhere. Conventional Commits with the "Assisted-By: 🤖 Claude Code" trailer.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 to US3 from spec.md

---

## Phase 1: Setup

- [X] T001 Run `make test` on the branch before any change and note the baseline (all tests pass) in the commit message of T005; no file change.

---

## Phase 2: Foundational (blocks all stories)

**Purpose**: the theme type, its resolution and the configuration key are used by every story.

- [X] T002 [P] Write failing tests in `Tests/UsageCoreTests/DropdownThemeTests.swift` for `DropdownTheme.panelStyle(systemIsDark:)`: auto with true gives `.dark`, auto with false gives `.light`, dark gives `.dark` and light gives `.light` for both arguments; `PanelStyle.isDark`; `DropdownTheme.allCases` is `[.auto, .dark, .light]` and the raw values are `"auto"`, `"dark"`, `"light"` (spec 032 FR-001, FR-006).
- [X] T003 [P] Write failing tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for `Configuration.dropdownTheme`, following the existing `displayDirection` tests there: `{}` and `Configuration()` give `.auto`; `"dark"`, `"light"` and `"auto"` decode to their value; `"Dark"`, `"sepia"`, `42`, `true` and `null` decode to `.auto` without failing the file; the load notes are exactly `dropdownTheme "sepia" is not known, using auto` (also for `"Dark"`) and `dropdownTheme is not readable, using auto` (number, bool, null), and no note for a missing key or `"auto"`; encoding a configuration with `.auto` produces JSON without a `dropdownTheme` key, and with `.dark`/`.light` produces `"dropdownTheme":"dark"`/`"light"` and round-trips; setting `.auto` after `.dark` makes the configuration equal to one that never had a theme; the theme is presentation only (changing it does not change the result the existing data-relevance tests use, see how `displayDirection` is tested against `dataRelevant`) (FR-003).
- [X] T004 Implement `Sources/UsageCore/Config/DropdownTheme.swift`: `public enum DropdownTheme: String, Codable, CaseIterable, Sendable { case auto, dark, light }` with `panelStyle(systemIsDark:) -> PanelStyle`, and `public enum PanelStyle: Equatable, Sendable { case light, dark }` with `isDark`. Doc comments cite spec 032 FR-001, FR-006. T002 passes.
- [X] T005 Add the key to `Sources/UsageCore/Config/Configuration.swift` (research R2): stored `dropdownThemeValue: DropdownTheme?` with `case dropdownThemeValue = "dropdownTheme"` in `CodingKeys`; public computed `dropdownTheme` (nil reads `.auto`, setting `.auto` stores nil); init parameter `dropdownTheme: DropdownTheme = .auto` after `displayDirection`; `decodeDropdownTheme(_:notes:)` modeled on `decodeDisplayDirection`, where a string `"auto"` stores nil without a note; `copy.dropdownTheme = .auto` in `dataRelevant()` with the comment "The dropdown theme is presentation only (spec 032 FR-003)." Doc comment on the property cites FR-001 and FR-003. T003 passes; `make test` passes.

**Checkpoint**: `make test` passes; no visible change yet.

---

## Phase 3: User Story 1, Dropdown follows the system appearance (P1) 🎯 MVP

**Goal**: with Auto, the dropdown shows an opaque light panel in light appearance and today's dark panel in dark appearance, follows a switch while open, and every text color reaches 4.5:1.

**Independent Test**: `make app-demo`, open the dropdown in light and dark appearance (quickstart steps 1 and 2).

### Tests for User Story 1

- [X] T006 [P] [US1] Write failing tests in `Tests/UsageCoreTests/DropdownPaletteTests.swift` (import AppKit and Testing, like `PillContrastTests.swift`) for `DropdownPalette` (data-model.md "DropdownPalette" and "Invariants"):
  - `forStyle(.dark)` and `forStyle(.light)` return the table's background, foreground and `text(_:)` values exactly; the dark background is sRGB (0.12, 0.12, 0.13) and dark primary, secondary and warning are `.system` (FR-008).
  - `backgrounds(increasedContrast:)` returns `plain`, `tinted`, `footer`, `hoverOnTinted`, composited with `BandStyle.opacity(increasedContrast:)` and `DropdownPalette.hoverOpacity` (0.06), checked against hand-computed values for one case.
  - for both styles and both contrast settings, every `.fixed` text color reaches `PillContrast.contrastRatio >= 4.5` against every background (FR-007).
  - for both styles, every `.system` role resolved under the style's `NSAppearance` (`.aqua` for light, `.darkAqua` for dark) via `performAsCurrentDrawingAppearance` and `usingColorSpace(.sRGB)` (`labelColor`, `secondaryLabelColor`, `systemOrange`, `systemRed` for primary, secondary, warning, critical) and alpha-blended onto each normal-contrast background reaches 4.5:1 (FR-007, FR-013). Document in a comment that the increased-contrast system variants are covered by the walkthrough, as in spec 012.
  - for every band style except `.plain` (`[.tinted, .footer]`, listed explicitly as in `SectionBandsTests.swift`, since `BandStyle` is not `CaseIterable`) and both contrast settings, the band's ratio to the plain panel is above 1.0 in both palettes, and the light ratio is at most the dark ratio (FR-011). Also for `hoverOnTinted`.
- [X] T007 [P] [US1] Add a test to `Tests/DemoModeTests/DefaultScenarioTests.swift` (FR-014): the default scenario's configuration decodes with `dropdownTheme == .auto`, and its coverage report has a non-empty `attentionRows` (orange text) and a non-empty `thresholdCriticalRows` (red text), the states the light shots rely on. Reuse how the file already loads the default scenario and its report.

### Implementation for User Story 1

- [X] T008 [US1] Implement `Sources/UsageCore/Dropdown/DropdownPalette.swift` (plan "Palette", research R3): `DropdownTextRole`, `DropdownTextColor` (`.system(role)`, `.fixed(PillContrast.RGB)`), `DropdownPalette` with `style`, `background`, `foreground`, `text(_:)`, `forStyle(_:)`, `hoverOpacity`, and the instance method `backgrounds(increasedContrast: Bool) -> [Background]` returning nested `DropdownPalette.Background` values with `kind: Background.Kind` (`enum Kind: CaseIterable, Sendable { case plain, tinted, footer, hoverOnTinted }`) and the composited `rgb: PillContrast.RGB` (blend per data-model.md). Colors: dark background (0.12, 0.12, 0.13), foreground white, critical `.fixed` #FF8A84; light background #D5D6D9, foreground black, secondary #48484A, warning #7A2E00, critical #8A000A; other roles `.system`. Doc comments cite spec 032 FR-007 to FR-011 and say why the dark critical is fixed (it missed 4.5:1 on bands, clarification Q3). T006 passes.
- [X] T009 [US1] Make T007 pass; change `Resources/demo/default.json` only if a check fails, and then in the smallest way that keeps the existing coverage checks passing.
- [X] T010 [US1] Add `DropdownColors` in `Sources/AgentTacho/DropdownColors.swift`: a struct with `primary`, `secondary`, `warning`, `critical: AnyShapeStyle` built from a `DropdownPalette` (`.system(.primary)` → `AnyShapeStyle(.primary)` and `.system(.secondary)` → `AnyShapeStyle(.secondary)`, the hierarchical styles the views use today, so the dark panel is unchanged (FR-008); `.system(.warning)` → `Color.orange`, `.system(.critical)` → `Color.red`, `.fixed(rgb)` → `Color(.sRGB, red:green:blue:)`; where a call site needs a `Color` (for example `NoteStyle.color`), return the style type instead and update the caller), a `static let dark` default, an `EnvironmentKey` and `EnvironmentValues.dropdownColors`, and a `Color` initializer from `PillContrast.RGB` for the panel background. Doc comment cites spec 032 FR-007 to FR-009.
- [X] T011 [US1] In `Sources/AgentTacho/DropdownView.swift` (plan "App layer"): add `@State private var systemIsDark` seeded from `NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua` and updated by `.onReceive(NSApp.publisher(for: \.effectiveAppearance))`; compute `panelStyle` from `configuration.dropdownTheme.panelStyle(systemIsDark:)` and `palette = DropdownPalette.forStyle(panelStyle)`; replace `panelBackground` with the palette background in `.background(...)` and `window.backgroundColor`; replace `.environment(\.colorScheme, .dark)` with the panel style's scheme; set `window.appearance` to `.darkAqua` or `.aqua` in `onChange(of: panel)` and in a new `onChange(of: panelStyle)` (also updating `backgroundColor`); inject `.environment(\.dropdownColors, DropdownColors(palette))`; use `DropdownPalette.hoverOpacity` for the 0.06 hover fill. Update the "Always dark and opaque" comment to cite spec 032 FR-006, FR-007 (opaque in every theme).
- [X] T012 [US1] In `Sources/AgentTacho/DropdownView.swift`, replace every text color of the dropdown with `@Environment(\.dropdownColors)` lookups: `.foregroundStyle(.secondary)` → `colors.secondary`, `.foregroundStyle(.orange)` and `Color.orange` text → `colors.warning`, `.foregroundStyle(.red)` and `Color.red` text → `colors.critical` (configuration and demo error labels, footer source error lines, "stale", notes, percents). Change `NoteStyle.color` and `PercentTone.color` into functions taking `DropdownColors` and update their callers. Leave bar fills (`RowBarView`) and band fills untouched (FR-010). Search the file with `rg -n "\.secondary|\.orange|\.red|Color\.(secondary|orange|red)"` and account for every hit in the commit message (changed, or a fill left alone and why).
- [X] T013 [P] [US1] In `Sources/AgentTacho/BreakdownView.swift` and `Sources/AgentTacho/UpdateViews.swift`, replace the text colors the same way as T012 (`.secondary`, `Color.orange` for "unpriced", the `InfoHover` icon), reading `@Environment(\.dropdownColors)` in each view that draws them. In `UpdateViews.swift` change only `UpdateLine`'s container `.foregroundStyle(.secondary)`; `UpdateStatusText` and `UpdateButtons` are also used by `AboutSettingsTab` and stay unchanged (FR-005).
- [X] T014 [US1] Run `make test` and `make app-demo`; open the demo dropdown in the current appearance and check it renders (no blank panel, no wrong-scheme strip at the footer or the scroll area). Record what was checked in the commit message. Do not switch the system appearance without asking the maintainer.

**Checkpoint**: US1 complete; the dropdown follows the system with Auto.

---

## Phase 4: User Story 2, Choose a fixed theme in Settings (P2)

**Goal**: Settings > General > Display has a "Dropdown theme" picker; Dark and Light ignore the system; the choice persists.

**Independent Test**: quickstart step 3 and 4.

- [X] T015 [US2] In `Sources/AgentTacho/SettingsView.swift`, in `Section("Display")` of `GeneralSettingsTab`, below the "Show usage as" caption, add `Picker("Dropdown theme", selection: $draft.dropdownTheme)` with `Text("Auto").tag(DropdownTheme.auto)`, `Text("Dark").tag(DropdownTheme.dark)`, `Text("Light").tag(DropdownTheme.light)`, `.pickerStyle(.segmented)`, and the caption `Text("Auto follows the system appearance. Settings and the menu bar always do.")` in `.font(.caption)` `.foregroundStyle(.secondary)` (contracts/dropdown-theme.md). Comment cites spec 032 FR-002, FR-004, FR-005.
- [X] T016 [US2] Check with `rg` that `BarLabel.swift`, `MenuBarSettingsTab.swift` and the Settings window code do not read `dropdownTheme` or the palette (FR-005); no file change expected. Run `make test`.

**Checkpoint**: US1 and US2 work; the theme is chosen in Settings and persists through the configuration file.

---

## Phase 5: User Story 3, Hand-edited configuration (P3)

**Goal**: the key is documented for people who edit the file by hand. The behavior itself is covered by T003 and T005.

- [X] T017 [P] [US3] Document `dropdownTheme` in `docs/configuration.md` next to `displayDirection`: values `auto`, `dark`, `light`, default `auto` (not written), unknown values fall back to `auto` with a note in the log, the theme affects only the dropdown.
- [X] T018 [P] [US3] In `docs/usage.md`, say that the dropdown follows the system appearance and that Settings > General > Display > "Dropdown theme" can fix it to Dark or Light.

---

## Phase 6: Polish and cross-cutting

- [X] T019 [P] Add dated amendment notes ("Amended by spec 032 (2026-10-21): the panel follows the dropdown theme, light or dark, and stays opaque.") to `specs/025-minimal-dropdown/spec.md` (the Assumptions line about the always-dark panel) and `specs/028-section-bands/spec.md` (the panel definition in the terminology paragraph and the Assumptions line), without rewriting the original text.
- [X] T020 Run `make test` and `make test-release`; both pass. Run `rg -n "\x{2014}|\x{2013}" Sources Tests docs specs/032-dropdown-theme` and fix any hit.
- [X] T021 Screenshots and website (AGENTS.md steps 4 to 7, plan "Screenshots and website"). **Ask the maintainer before capturing**: the capture quits AgentTacho, switches the system appearance and moves the mouse. If the maintainer is not available in this run, leave this task unchecked and report it as pending. Otherwise: `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`, review every changed shot in both appearances (light variants of glance, budget, harnesses, same-provider show the light panel; no real names, no German formats), search the site's `src/` for copy that calls the dropdown dark and change it, run the site's check, build and tests, open the site pull request and link it from the app pull request. Done 2026-10-21: 14 shots recaptured, no copy change needed, site PR https://github.com/AgentTacho/agenttacho.github.io/pull/15.

---

## Dependencies and execution order

- Phase 1 → Phase 2 → US1 → US2 → US3 → Polish. US3's docs (T017, T018) only need Phase 2 and can run in parallel with US1.
- T002 and T003 in parallel; T004 after T002; T005 after T003 and T004.
- T006 and T007 in parallel; T008 after T006 and T004; T009 after T007 and T005.
- T010 after T008; T011 after T010; T012 after T011; T013 after T010 (parallel with T011 and T012, other files); T014 after T012 and T013.
- T015 after T005 and T011; T016 after T015.
- T021 after everything else, and only with the maintainer's go.

## Parallel examples

- Phase 2: T002 (`DropdownThemeTests.swift`) with T003 (`ConfigurationTests.swift`).
- US1 tests: T006 (`DropdownPaletteTests.swift`) with T007 (`DefaultScenarioTests.swift`).
- US1 views: T013 (`BreakdownView.swift`, `UpdateViews.swift`) alongside T011 and T012 (`DropdownView.swift`).
- Docs: T017, T018 and T019 together.

## Implementation strategy

- MVP: Phases 1 to 3. With only US1, every user in light appearance gets a matching dropdown and the dark panel stays as it was (except the critical text color).
- Then US2 (the picker), US3 (docs), Polish. The screenshot run (T021) happens once, at the end, with the maintainer.
