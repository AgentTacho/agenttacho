# Data Model: Section Bands

No configuration or persisted data changes. Two value types in `UsageCore`.

## BandStyle (enum)

| Case | Meaning | Strength (normal) | Strength (Increase contrast) |
|---|---|---|---|
| `plain` | no fill, the panel shows through | 0 | 0 |
| `tinted` | alternate section | 0.04 | 0.08 |
| `footer` | the pinned footer | 0.07 | 0.12 |

- `opacity(increasedContrast: Bool) -> Double`: the fill as a fraction of the foreground color (spec FR-005, FR-006).
- Invariants (tested): `plain < tinted < footer` in both modes; `tinted` and `footer` are stronger with Increase contrast than without.

## SectionBands (enum namespace)

- `stripes(arrangedCount: Int, unassignedShown: Bool) -> [BandStyle]`: one style per shown section in dropdown order. Index `i` is `plain` when `i` is even, `tinted` when odd; Unassigned, when shown, is the last element and follows the same rule. Never returns `footer`. A negative count is treated as 0. (spec FR-002, FR-003)
- `showsUnassigned(_ snapshot: UsageSnapshot?) -> Bool`: true when the snapshot has an Unassigned entry with a non-empty breakdown, the rule `DropdownView` uses today (spec FR-003: unchanged).

## CoverageReport (DemoMode, extended)

- `sectionStripes: [BandStyle]`: `SectionBands.stripes(arrangedCount: configuration.arrangedEntries.count, unassignedShown: SectionBands.showsUnassigned(snapshot))` after the last frame (spec FR-012).
