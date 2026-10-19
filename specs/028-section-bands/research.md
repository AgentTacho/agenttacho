# Research: Section Bands

## R1: Where the stripe rule lives

- **Decision**: A new `UsageCore` type `SectionBands` in `Sources/UsageCore/Dropdown/SectionBands.swift` with `stripes(arrangedCount:unassignedShown:) -> [BandStyle]` and `showsUnassigned(_ snapshot: UsageSnapshot?) -> Bool`. The dropdown and `ScenarioCoverage` both call it.
- **Rationale**: Constitution II; FR-003 wants the rule tested. Moving the "Unassigned shown" check (`snapshot?.unassigned` with a non-empty breakdown) next to it gives the view and the coverage test one definition; the rule itself is unchanged (spec FR-003).
- **Alternatives considered**: a stripe computed from `index % 2` inside `DropdownView` (untestable, rejected); passing the full `ArrangedEntry` list (the rule needs only the count).

## R2: Band strengths and how they are drawn

- **Decision**: `BandStyle.opacity(increasedContrast:)` returns the fill strength as a fraction of the foreground color: plain 0, tinted 0.04 (0.08 with Increase contrast), footer 0.07 (0.12). The view fills each band with `Color.primary.opacity(...)`; the panel is forced to the dark color scheme (`DropdownView`), so `Color.primary` is the light foreground and the fill lightens the panel.
- **Rationale**: FR-005 asks for foreground-derived tints and a tested order; keeping the numbers in `UsageCore` makes the order and the contrast step testable (plain < tinted < footer in both modes; each stronger with Increase contrast). The hover highlight stays `Color.primary.opacity(0.06)` drawn above the band (FR-009), so a hovered row on a tinted band reads at about 0.10 against 0.04.
- **Alternatives considered**: `NSColor.quaternarySystemFill` and friends (system-defined but the strengths are not ours to order or test, and their dark-mode values are close to the hover fill); fixed RGB (rejected by FR-005).

## R3: Increase contrast

- **Decision**: Read `@Environment(\.colorSchemeContrast)` in the dropdown; `.increased` selects the increased strengths.
- **Rationale**: `BarLabel` already reads the same environment value for spec 012 FR-011; SwiftUI updates it live when the setting changes.
- **Alternatives considered**: `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` with a notification (more code, same result).

## R4: Full-width bands with the existing insets

- **Decision**: The sections `VStack` gets `spacing: 0` and no horizontal padding. Each section (and the top error lines) gets its own horizontal inset of 12 pt; each section gets 10 pt vertical padding inside its band and `.frame(maxWidth: .infinity, alignment: .leading)` before `.background(...)`, so the fill spans the 360 pt panel. The top padding of the sections container shrinks from 12 to 2 pt so the first section's content stays 12 pt below the panel's top edge (spec Assumptions), and its bottom padding goes from 10 to 0. The pinned footer drops its `Divider`; its band covers the footer with 10 pt top padding and the existing 12 pt bottom inset.
- **Rationale**: FR-004 (edge to edge, no gaps), SC-003: two sections' content was 10 + 1 + 10 = 21 pt apart, now 10 + 10 = 20 pt; last section to footer was 10 + 1 + 10 = 21 pt (sections bottom padding, divider, the footer stack's spacing), now 20 pt. The top error lines get the same 10 pt vertical padding in a stack of their own, so they keep 12 pt from the top edge and 10 pt between each other.
- **Alternatives considered**: drawing bands with negative padding outside the inset (works but fragile with the scroll view's clipping); a `Canvas` background behind the whole list (needs section heights, more code).

## R5: Scrolling and the footer

- **Decision**: No change to the scroll structure of spec 026: the sections, each with its band, live in the `ScrollView`; the footer with its band sits below it. A partly scrolled section is clipped at the scroll view's bottom edge, which is the footer band's top edge.
- **Rationale**: FR-007, FR-008 hold by construction.

## R6: Screenshots

- **Decision**: All dropdown crops change (`plan-limits`, `pace`, `budget`, `groups`, `details`, `harnesses`, `dropdown`). The demo `default` scenario already has four arranged entries; its stripe sequence is plain, tinted, plain, tinted (Max, Codex, Company budget, Side), plus Unassigned plain when the scenario shows it. The capture run and the site pull request follow the AGENTS.md order of work and need the maintainer's go for the capture (step 4).
- **Rationale**: Constitution V, spec FR-012, FR-013.
