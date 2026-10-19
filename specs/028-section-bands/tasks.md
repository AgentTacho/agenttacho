# Tasks: Section Bands

**Input**: Design documents from `specs/028-section-bands/`

**Prerequisites**: plan.md, spec.md (FR-001 to FR-013), research.md (R1 to R6), data-model.md, contracts/dropdown-bands.md, quickstart.md

**Tests**: Required. Constitution II: every new `UsageCore` or `DemoMode` behavior gets its tests first (Swift Testing, `@Test`, `#expect`), and they must fail before the implementation. Run tests only with `make test` / `make test-release`, build only with `make app` / `make app-demo`.

## Conventions for every task

- Doc comments cite the spec requirements they implement (for example `spec 028 FR-002`).
- No em dash or en dash anywhere (code, comments, docs, commit messages).
- `Sources/AgentTacho` only lays out and fills; the stripe and the strengths come from `UsageCore`.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.
- Do NOT run `scripts/screenshots/capture.sh`, do NOT push, do NOT touch the site repository (the screenshot round needs the maintainer's go, see Notes).

## Interfaces

```swift
// T002, Sources/UsageCore/Dropdown/SectionBands.swift (all public; the app and DemoMode are separate modules)
public enum BandStyle: Equatable, Hashable, Sendable {
    case plain, tinted, footer
    /// Fill strength as a fraction of the foreground color (spec 028 FR-005, FR-006):
    /// plain 0 / 0, tinted 0.04 / 0.08, footer 0.07 / 0.12 (normal / increased contrast).
    public func opacity(increasedContrast: Bool) -> Double }
public enum SectionBands {
    /// One style per shown section in dropdown order: even index plain, odd tinted;
    /// Unassigned, when shown, is the last element; never .footer; negative count as 0 (FR-002, FR-003).
    public static func stripes(arrangedCount: Int, unassignedShown: Bool) -> [BandStyle]
    /// True when the snapshot has Unassigned usage with a non-empty breakdown, the rule DropdownView uses today (FR-003).
    public static func showsUnassigned(_ snapshot: UsageSnapshot?) -> Bool }
// T005, Sources/DemoMode/ScenarioCoverage.swift: CoverageReport gains `public let sectionStripes: [BandStyle]` (FR-012)
```

## Phase 1: Setup

- [X] T001 Confirm the baseline: run `make test` on the branch and note the passing count in the commit message of T003 (no code change)

## Phase 2: Foundational (stripe rule and strengths)

- [X] T002 [P] Write failing tests in Tests/UsageCoreTests/SectionBandsTests.swift: `stripes(arrangedCount: 0, unassignedShown: false)` is empty; `0, true` is `[.plain]`; `1, false` is `[.plain]`; `4, false` is `[.plain, .tinted, .plain, .tinted]`; `4, true` is `[.plain, .tinted, .plain, .tinted, .plain]`; `3, true` ends with `.tinted`; a negative count behaves as 0; no result contains `.footer`; for both `increasedContrast` values `plain < tinted < footer`; `tinted` and `footer` are each stronger with increased contrast; `plain` is 0 in both; `showsUnassigned(nil)` is false, a snapshot whose `unassigned` is `.empty` is false, with a non-empty breakdown is true (build snapshots the way existing tests in Tests/UsageCoreTests build `UsageSnapshot` values)
- [X] T003 Implement `BandStyle` and `SectionBands` in Sources/UsageCore/Dropdown/SectionBands.swift per Interfaces until T002 passes (`make test`); doc comments cite spec 028 FR-002, FR-003, FR-005, FR-006

**Checkpoint**: `make test` passes; commit `feat(dropdown): add the section band rule and strengths`.

## Phase 3: User Story 1, sections apart without lines (P1)

**Goal**: no dividers; sections alternate plain and tinted full-width bands. **Independent test**: open the demo dropdown and see four sections, the second and fourth on a faint full-width band, no lines.

- [X] T004 [US1] Write a failing assertion in Tests/DemoModeTests/DefaultScenarioTests.swift: `report.sectionStripes` for the `default` scenario equals `[.plain, .tinted, .plain, .tinted]` plus `.plain` when `SectionBands.showsUnassigned(report.snapshot)` is true (spec 028 FR-012); also assert the scenario has at least three sections, and pin the concrete value of `report.snapshot.unassigned.breakdown.isEmpty` for the `default` scenario (read it once from a run) so a scenario change that adds or drops Unassigned shows up
- [X] T005 [US1] Add `sectionStripes: [BandStyle]` to `CoverageReport` in Sources/DemoMode/ScenarioCoverage.swift, computed as `SectionBands.stripes(arrangedCount: configuration.arrangedEntries.count, unassignedShown: SectionBands.showsUnassigned(snapshot))`, until T004 passes
- [X] T006 [US1] In Sources/AgentTacho/DropdownView.swift `sections(now:)`: remove both `Divider()`s; set the `VStack` spacing to 0; compute `let stripes = SectionBands.stripes(arrangedCount: entries.count, unassignedShown: SectionBands.showsUnassigned(snapshot))`; wrap each section (and Unassigned, using `SectionBands.showsUnassigned` instead of the inline check) in a band: `.padding(.horizontal, Self.inset)`, `.padding(.vertical, Self.bandPadding)` (new constant 10), `.frame(maxWidth: .infinity, alignment: .leading)`, `.background(Color.primary.opacity(style.opacity(increasedContrast:)))`; the demo error, configuration error and "No accounts configured" lines go into their own `VStack(alignment: .leading, spacing: 10)` with `.padding(.horizontal, Self.inset)` and `.padding(.vertical, Self.bandPadding)` and no fill, shown only when at least one of them is present (spec 028 Edge Cases); `.background(Color)` adds no accessibility element, so FR-009a holds; keep the doc comment, now citing spec 028 FR-001 to FR-004 instead of spec 025 FR-011
- [X] T007 [US1] In Sources/AgentTacho/DropdownView.swift `body`: remove `.padding(.horizontal, Self.inset)` from the sections container, change its top padding from `Self.inset` to `Self.inset - Self.bandPadding` (first content stays 12 pt below the top) and its bottom padding from `Self.footerGap` to 0 (research R4); add `@Environment(\.colorSchemeContrast) private var colorSchemeContrast` and pass `colorSchemeContrast == .increased` to every `opacity(increasedContrast:)` call (FR-006, research R3)
- [X] T008 [US1] Run `make test` and `make app-demo`; open the demo dropdown and check: no lines, plain, tinted, plain, tinted bands edge to edge, text not touching band edges, bands meet without gaps, the first content 12 pt below the top edge (spec 028 User Story 1); turn System Settings > Accessibility > Display > Increase contrast on and off while the dropdown is open and check the bands get stronger and back (FR-006). *Implement: `make test` and `make app-demo` pass; the visual check is left to the walkthrough.*

**Checkpoint**: `make test` passes; commit `feat(dropdown): separate sections by alternating bands instead of dividers`.

## Phase 4: User Story 2, a footer that stands apart (P1)

**Goal**: the pinned footer has its own stronger band, no divider. **Independent test**: open the dropdown with an even number of sections (last tinted) and see the footer band still distinct; scroll with expanded Details and see the footer band stay.

- [X] T009 [US2] In Sources/AgentTacho/DropdownView.swift `pinnedFooter(now:)`: remove the `Divider()` and the `VStack` around it; add `.padding(.top, Self.bandPadding)` to the footer content; in `body` keep `.padding(.horizontal, Self.inset)` and `.padding(.bottom, Self.inset)` inside the band, then `.frame(width: Self.width)` and `.background(Color.primary.opacity(BandStyle.footer.opacity(increasedContrast:)))` so the fill covers the full width down to the panel's bottom edge; the footer height measurement (`onGeometryChange`) must still include the padding; remove the now unused `footerGap` and update the doc comment on `inset` that mentions the footer's divider; doc comment cites spec 028 FR-007, FR-008
- [X] T010 [US2] Run `make app-demo`; check the footer band against the tinted fourth section, expand Details until the sections scroll and check the footer band stays pinned and sections clip at its top edge (spec 028 User Story 2). *Implement: `make app-demo` passes; the visual check is left to the walkthrough.*

**Checkpoint**: `make test` passes; commit `feat(dropdown): give the pinned footer its own band`.

## Phase 5: User Story 3, hover and markers on a band (P2)

**Goal**: hover highlight, `○`, bar track and pace marker stay visible on a tinted band. **Independent test**: hover a non-headline row of the Codex section (tinted) in the demo.

- [X] T011 [US3] In Sources/AgentTacho/DropdownView.swift `LimitRowLayout`: confirm the hover highlight is drawn as the row's own `.background` (above the section band) and keeps `Color.primary.opacity(0.06)`; add a doc comment line citing spec 028 FR-009 (drawn above the band); no color changes to `RowBarView` or the marker
- [X] T012 [US3] Run `make app-demo`; hover the Codex 5-hour row (tinted band) and a Claude row (plain band) and compare; check the bar track and pace tick on the tinted band (spec 028 User Story 3). *Implement: `make app-demo` passes; the visual check is left to the walkthrough.*

**Checkpoint**: commit if anything changed: `docs(dropdown): note the hover drawn above the band`.

## Phase 6: Polish and cross-cutting

- [X] T013 [P] Amend specs/025-minimal-dropdown/spec.md: User Story 1 text and its Independent Test, acceptance scenario 1, FR-011, FR-023 and the Unassigned edge case, each with "(amended by spec 028: alternating bands, no dividers)" and the new wording (spec 028 FR-010)
- [X] T014 [P] Replace the "Dividers" section of specs/025-minimal-dropdown/contracts/dropdown-ui.md with a "Bands" section pointing to specs/028-section-bands/contracts/dropdown-bands.md (spec 028 FR-010)
- [X] T015 [P] Amend specs/026-dropdown-layout-polish/spec.md Assumptions ("The pinned footer's divider above it stays") to say the footer has its own band since spec 028 (FR-010)
- [X] T016 [P] Update docs/accounts-and-budgets.md: replace "separated by dividers" with sections set apart by alternating background bands and the footer by its own band (spec 028 FR-011)
- [X] T017 Run `make test` and `make test-release`; run `rg -n '\x{2014}|\x{2013}' Sources Tests docs specs/025-minimal-dropdown specs/026-dropdown-layout-polish specs/028-section-bands` and fix any hit; commit `docs: amend specs 025 and 026 and the docs for section bands`

## Dependencies

- T002 before T003; the Phase 2 checkpoint (T003 passing) before T004, because `make test` compiles both test targets and T004 does not compile until T005.
- T004 before T005; T005 before T006, T009.
- T006 and T007 before T009 (same file, footer relies on the new container padding).
- US1 (Phase 3) before US2 (Phase 4) and US3 (Phase 5): all edit `DropdownView.swift`.
- Phase 6 tasks T013 to T016 are independent of each other and of the code ([P]); T017 last.

## Parallel examples

- T013, T014, T015 and T016 (different docs) in parallel.

## Implementation strategy

MVP is Phases 2 and 3 (bands without lines); Phase 4 makes the footer stand apart and must ship with it, since removing the dividers removes the footer's separation. Phase 5 is a verification with a doc note.

## Notes

- Screenshot round (constitution V, spec FR-013), not a task for implement: after the maintainer's go, run `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`, review `plan-limits`, `pace`, `budget`, `groups`, `details`, `harnesses`, `dropdown` in both appearances, replace `docs/images/agenttacho-dropdown.png` with `magick dropdown-light.webp docs/images/agenttacho-dropdown.png`, open the site pull request and link it from the app pull request (AGENTS.md steps 4 to 8). No website copy changes (FR-012a).
