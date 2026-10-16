# Tasks: Colored Bar Levels

**Input**: Design documents from `specs/012-colored-bar-levels/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/bar-rendering.md, contracts/menu-bar-tab-level-settings.md, quickstart.md

**Tests**: Required. AGENTS.md asks for test-first development of all `UsageCore` logic; test tasks come before their implementation and must fail first. Run tests only with `make test`, build only with `make app`.

**Organization**: Shared model and pure presentation logic are foundational; each user story then adds rendering or Settings UI.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story from spec.md (US1 to US4)

## Conventions for every task

- Doc comments cite the spec requirements they implement (for example `spec 012 FR-007`).
- No em dash or en dash characters anywhere (code, comments, docs, commit messages).
- Every phase ends with a checkpoint: `make test` passes (and `make app` builds from Phase 3 on). Fix failures before the next phase.
- Commit after each phase with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Settings model, tolerant decoding with load notes, and the pure presentation decisions all stories render from. Start by running `make test` once to confirm the baseline passes.

### Tests first

- [x] T001 [P] Add tests to `Tests/UsageCoreTests/ConfigurationTests.swift` (FR-001 to FR-003, SC-005):
  - a JSON without `levelColor` and `showLevelSymbols` decodes to `.text` and `false`;
  - `"text"`, `"pill"`, `"off"` and `true` decode as given;
  - an unknown string (`"rainbow"`), a wrong-case string (`"Pill"`) and a non-string value (`3`) each decode to `.text`, do not throw, and record exactly one note in a `ConfigurationLoadNotes` collector passed through `JSONDecoder.userInfo`;
  - a non-boolean `showLevelSymbols` (for example `"yes"`) is a decoding error, consistent with `startAtLogin`;
  - encoding writes both keys, and a configuration decoded from an unknown value encodes `"levelColor": "text"`;
  - changing only `levelColor` or `showLevelSymbols` makes `needsRefresh(comparedTo:)` and `needsNetworkRefresh(comparedTo:)` false;
  - `levelDisplay` returns both values; `LevelDisplaySettings.hidesLevels` is true only for `.off` with symbols off.
- [x] T002 [P] Add tests to `Tests/UsageCoreTests/ConfigStoreTests.swift` (FR-003): loading a file with an unknown `levelColor` makes `takeLoadNotes()` return the note once (a second call returns empty); a reload of an unchanged file adds no note; a valid file yields no notes; the configuration loads without a `ConfigurationError`; a file with an unknown `levelColor` that also fails validation (for example an invalid refresh interval) yields a `ConfigurationError` and no notes.
- [x] T003 [P] Create `Tests/UsageCoreTests/BarPresentationTests.swift` covering every row of `contracts/bar-rendering.md` for the six combinations of `LevelColorStyle` and `showSymbols`, at `.normal`, `.warning` and `.critical`, fresh and stale (SC-003): `glyph`, `valueText` (stale `~` directly before the value, after the glyph), `iconTone`, `textTone`, `pill`. Also `usesColor` (false for all-normal bars and for `.off` with or without symbols, true otherwise when an entry is at a level) and `accessibilityText` (FR-018: "Vertex warning 85%", "Vertex over limit 104%", "Vertex warning ~85%", "Vertex 42%", entries joined by two spaces, never `⚠` or `‼`, empty bar "AgentMeter"). Include a `.critical` item with value "60%" (Codex limit reached) to show it is treated as over limit, and items with values `--` and `…` at `.normal`.

### Implementation

- [x] T004 Create `Sources/UsageCore/Bar/LevelDisplay.swift` with `LevelColorStyle` and `LevelDisplaySettings` per `data-model.md`.
  Interfaces: `public enum LevelColorStyle: String, CaseIterable, Codable, Sendable { case text, pill, off }`; `public struct LevelDisplaySettings: Equatable, Sendable { public var levelColor: LevelColorStyle; public var showSymbols: Bool; public init(levelColor: LevelColorStyle = .text, showSymbols: Bool = false); public static let default: LevelDisplaySettings; public var hidesLevels: Bool }`.
- [x] T005 Create `Sources/UsageCore/Config/ConfigurationLoadNotes.swift` (research R4).
  Interfaces: `public final class ConfigurationLoadNotes: @unchecked Sendable { public init(); public func append(_ note: String); public var notes: [String]; public static let userInfoKey: CodingUserInfoKey }` with a lock around the array.
- [x] T006 Update `Sources/UsageCore/Config/Configuration.swift` to make T001 pass:
  - add `public var levelColor: LevelColorStyle` and `public var showLevelSymbols: Bool` (init parameters with defaults `.text` and `false`, coding keys `levelColor` and `showLevelSymbols`);
  - decode `levelColor` with `(try? c.decodeIfPresent(String.self, forKey: .levelColor)) ?? nil`; when the key is present but unreadable or not a known raw value, use `.text` and append a note such as `levelColor "rainbow" is not known, using text` (or `levelColor is not readable, using text`) to the collector from `decoder.userInfo[ConfigurationLoadNotes.userInfoKey]`;
  - decode `showLevelSymbols` with `try c.decodeIfPresent(Bool.self, ...) ?? false` (a wrong type stays a decoding error);
  - add `public var levelDisplay: LevelDisplaySettings`;
  - reset both fields in `dataRelevant()` (presentation only, like `arrangement`).
- [x] T007 Update `Sources/UsageCore/Config/ConfigStore.swift` to make T002 pass: on every actual file read, pass a fresh `ConfigurationLoadNotes` in `JSONDecoder.userInfo`; keep its notes as the pending notes only when decoding and `validate()` both succeed; add `public func takeLoadNotes() -> [String]` that returns and clears the pending notes under the lock.
- [x] T008 Update `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`: after `configStore.load()`, append each note from `configStore.takeLoadNotes()` to the diagnostic log with source `config` (FR-003). Add a test to `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` that a configuration file with an unknown `levelColor` produces one `config` log line containing the note.
- [x] T009 Create `Sources/UsageCore/Bar/BarPresentation.swift` per `data-model.md` and `contracts/bar-rendering.md`; make T003 pass.
  Interfaces: `public enum BarTone: Equatable, Sendable { case neutral, warning, overLimit, onPill(BarLevel) }`; `public struct BarEntryPresentation: Equatable, Sendable { public let id, icon: String; public let glyph: String?; public let valueText: String; public let iconTone, textTone: BarTone; public let pill: BarLevel?; public let accessibilityText: String; public init(...) }` (public memberwise init); `public enum BarPresentation { public static let placeholder = "AgentMeter"; public static func entries(_ items: [BarItem], settings: LevelDisplaySettings) -> [BarEntryPresentation]; public static func usesColor(_ entries: [BarEntryPresentation]) -> Bool; public static func accessibilityText(_ entries: [BarEntryPresentation]) -> String }`.

**Checkpoint**: `make test` passes; no visible change yet.

---

## Phase 2: User Story 1 - Levels stand out at a glance (Priority: P1) 🎯 MVP

**Goal**: With default settings an entry's value turns orange at the warning level and red at the over-limit level; a bar without levels looks exactly as before.

**Independent Test**: quickstart.md manual steps 1 to 5.

- [x] T010 [US1] Spike decision (research R1), without launching the app: another AgentMeter build from a parallel session is running on this machine, and a second instance would raise the single-instance alert, so the built app MUST NOT be started during implementation. Instead, add a "Spike result" paragraph to research.md R1 recording the decision: use the R1 primary path (no explicit appearance for the bar; dynamic colors resolve under the current drawing appearance at draw time). Reason: if `MenuBarExtra` draws the image through the status button, colors follow the menu bar exactly; if it rasterizes once, the current drawing appearance is the app's effective appearance, which is what the fallback would derive from `colorScheme` anyway, and the `.id` on `colorScheme` and `colorSchemeContrast` forces a rebuild on changes. The runtime check (handler appearance, wallpaper-dependent menu bar, two displays, highlighted state) moves to the walkthrough, quickstart steps 3 to 5; if it fails there, switching to the explicit appearance is a one-line change in `BarLabelView`.
- [x] T011 [US1] Rewrite `BarLabelBuilder` in `Sources/AgentMeter/BarLabel.swift` to render `[BarEntryPresentation]` on the path chosen in T010:
  - shared attributed-text layout: icon via `IconFont.attributed`, a space, glyph, value text (stale marker included), two spaces between entries, `BarPresentation.placeholder` when empty;
  - when `BarPresentation.usesColor` is false, draw in black with `isTemplate = true` exactly as today (research R2, FR-013);
  - otherwise return a non-template drawing-handler image with `cacheMode = .never`, mapping `.neutral` to `labelColor` (or to the `neutralOverride` color when given), `.warning` to `systemOrange` and `.overLimit` to `systemRed`, resolved under the explicit `appearance` via `performAsCurrentDrawingAppearance`, or under the current drawing appearance when nil (FR-007, FR-011, FR-014, FR-015);
  - the glyph takes the entry's `textTone` and comes before the stale marker; `.off` with symbols stays a template image (FR-009, FR-010, FR-016);
  - remove the `BarItem.text` and `valueText` extensions and `plainText`.
  Interfaces: `static func image(_ entries: [BarEntryPresentation], appearance: NSAppearance? = nil, neutralOverride: NSColor? = nil) -> NSImage`.
- [x] T012 [US1] Update `BarLabelView` in `Sources/AgentMeter/BarLabel.swift`. Interfaces: `struct BarLabelView: View { let items: [BarItem]; let display: LevelDisplaySettings; var preview: Bool = false }`. Read `@Environment(\.colorScheme)` and `@Environment(\.colorSchemeContrast)` and use them in the image's identity (`.id(...)`) so the image is rebuilt on appearance changes (FR-014). With `preview` true, render with `NSAppearance(named: .darkAqua)` (`.accessibilityHighContrastDarkAqua` when `colorSchemeContrast == .increased`) and `neutralOverride: .white`, and draw the template image in white as today (FR-005, research R5). With the R1 fallback chosen in T010, the bar also passes an explicit appearance derived from the two environment values. Set `accessibilityLabel` from `BarPresentation.accessibilityText` (FR-018). Remove the `tint` parameter.
- [x] T013 [US1] Update `Sources/AgentMeter/App.swift` to build `BarLabelView(items: model.barItems, display: model.configuration.levelDisplay)`, and the preview in `Sources/AgentMeter/MenuBarSettingsTab.swift` to `BarLabelView(items: ..., display: draft.levelDisplay, preview: true)`.

**Checkpoint**: `make test` passes and `make app` builds; default settings show colored values; the Settings preview matches.

---

## Phase 3: User Story 2 - Choose a pill instead of colored text (Priority: P2)

**Goal**: "Level color" Pill draws a rounded level-colored background with readable black or white content.

**Independent Test**: quickstart.md manual step 6.

- [x] T014 [P] [US2] Create `Tests/UsageCoreTests/PillContrastTests.swift`: WCAG relative luminance of black (0), white (1) and a mid gray; `contrastRatio` is symmetric and black on white is 21:1; `textColor(onFill:)` for the eight fills in research R3 returns the expected color and its ratio is at least 4.5 (SC-004).
- [x] T015 [US2] Create `Sources/UsageCore/Bar/PillContrast.swift`; make T014 pass.
  Interfaces: `public enum PillContrast { public struct RGB: Equatable, Sendable { public var red, green, blue: Double; public init(red: Double, green: Double, blue: Double) }; public static func relativeLuminance(_ color: RGB) -> Double; public static func contrastRatio(_ a: RGB, _ b: RGB) -> Double; public static func textColor(onFill fill: RGB) -> PillTextColor }` and `public enum PillTextColor: Equatable, Sendable { case black, white }`.
- [x] T016 [US2] Extend the colored path of `BarLabelBuilder` in `Sources/AgentMeter/BarLabel.swift` (FR-008, `contracts/bar-rendering.md` layout):
  - insert 3 pt of advance (kern) before and after each pill entry's text range, so the full two-space separator stays between adjacent pills and a pill at either end of the bar fits inside the image; no extra advance for entries without a pill;
  - draw a rounded rectangle (corner radius half the pill height, capped at 4 pt; inset vertically to the bar height) behind the entry's range, including the padding, in the resolved level color before drawing the text;
  - convert the resolved fill to sRGB components and draw the entry's `onPill` parts in black or white from `PillContrast.textColor(onFill:)`.
- [x] T017 [US2] Add the "Level color" segmented picker (Text, Pill, Off) bound to `draft.levelColor` below the preview in `Sources/AgentMeter/MenuBarSettingsTab.swift` per `contracts/menu-bar-tab-level-settings.md` (FR-004).

**Checkpoint**: `make test` passes and `make app` builds.

---

## Phase 4: User Story 3 - Keep the symbols (Priority: P2)

**Goal**: The "Also show ⚠ / ‼ symbols" checkbox brings the glyphs back with any color style; VoiceOver names levels in every setting.

**Independent Test**: quickstart.md manual steps 7 and 9.

- [x] T018 [US3] Add the "Also show ⚠ / ‼ symbols" checkbox bound to `draft.showLevelSymbols` below the picker in `Sources/AgentMeter/MenuBarSettingsTab.swift` (FR-004, FR-010).

**Checkpoint**: `make app` builds.

---

## Phase 5: User Story 4 - Hide levels from the bar (Priority: P3)

**Goal**: Off with symbols off is valid and Settings explains the consequence.

**Independent Test**: quickstart.md manual step 8.

- [x] T019 [US4] Show the note "Levels will not appear in the menu bar. Notifications and the dropdown still show them." as a secondary caption below the checkbox in `Sources/AgentMeter/MenuBarSettingsTab.swift` when `draft.levelDisplay.hidesLevels` is true (FR-012).

**Checkpoint**: `make app` builds.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T020 [P] Replace the threshold help sentence about `⚠` and `‼` in `Sources/AgentMeter/SettingsView.swift` with the text from `contracts/menu-bar-tab-level-settings.md` (FR-006).
- [x] T021 [P] Update the "Alerts" bullet in `README.md` so the bar markers read: levels show in orange (close to the limit) and red (over it) by default, as a pill or with `⚠` and `‼` if chosen in the Menu Bar tab, and `~` means the value may be out of date (FR-021).
- [x] T022 [P] Add a note below FR-003 in `specs/001-agentmeter/spec.md`: "How levels are shown (color, pill, symbols, or not at all) is defined by spec 012 (colored bar levels)." (FR-021)
- [x] T023 Final gate: search all changed files for em dash and en dash characters and remove any (AGENTS.md); run `make test` and `make app`; all tests pass and the app builds.

---

## Dependencies & Execution Order

- Phase 1: T001, T002, T003 in parallel first (tests must fail), then T004, T005, then T006, T007, T008 in order; T009 after T004.
- Phase 2 (US1) depends on Phase 1. T010 (spike) before T011 and T012; T013 after T012. MVP.
- Phase 3 (US2): T014 and T015 depend only on Phase 1 and can run alongside Phase 2; T016 depends on T011; T017 depends on T013.
- Phase 4 (US3): T018 after T017 (same file).
- Phase 5 (US4): T019 after T018 (same file).
- Phase 6 after all stories; T020 to T022 in parallel; T023 last.

## Parallel Examples

- Phase 1 tests: T001, T002, T003 (three different test files).
- US2 logic while US1 renders: T014 then T015 in `UsageCore` alongside T010 to T013 in the app.
- Polish: T020, T021, T022.

## Implementation Strategy

1. MVP: Phases 1 and 2 give the default colored-text bar with correct accessibility and an unchanged look without levels.
2. Add the pill (Phase 3), then the symbols checkbox (Phase 4), then the hidden-levels note (Phase 5).
3. Polish docs and run the final gate.
4. Manual checks of quickstart.md (including two adjacent pills with one at the bar's edge, a dark wallpaper in Light mode, and two displays) happen in the walkthrough after implementation.
