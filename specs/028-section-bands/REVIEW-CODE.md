# Code Review: Section Bands

**Spec:** specs/028-section-bands/spec.md
**Date:** 2026-10-19
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% (16 of 16 functional requirements, 10 of 10 edge cases; FR-013's capture deferred by the maintainer's go that the requirement itself names)**

- Functional requirements: 16 of 16 compliant (FR-001 to FR-013, with FR-004a, FR-009a, FR-012a)
- Edge cases: 10 of 10
- Acceptance scenarios: US1 1 to 7, US2 1 to 4, US3 1 to 3 traced to code; the stripe rule and strengths are covered by tests
- Success criteria: SC-004 and SC-005 by tests; SC-001 and SC-003 by the code below; SC-002 in the walkthrough on the recaptured shots

No `## Constants` section in the spec, so the constants check was skipped.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | No `Divider` left in `DropdownView.swift` (the remaining ones are in Settings and the price import sheet, out of scope) | Compliant |
| FR-002 | `SectionBands.stripes`: even index plain, odd tinted; Unassigned appended last and drawn with `stripes.last`; a group with members and Details is one `section(for:)` inside one `band` | Compliant |
| FR-003 | `SectionBands` in UsageCore with `SectionBandsTests`; input is `arrangedEntries.count` and `showsUnassigned` (rule unchanged: non-empty breakdown); error lines and "No accounts configured" sit outside the bands and the count | Compliant |
| FR-004 | `band(_:content:)`: full width (`frame(maxWidth: .infinity)` inside the 360 pt frame), 12 pt horizontal inset, 10 pt vertical padding; bands stacked with spacing 0; footer: 10 pt top padding, 12 pt bottom inset | Compliant |
| FR-004a | `.background(Color)` fill, no shape, gradient, shadow or stroke | Compliant |
| FR-005 | `Color.primary.opacity(...)` via `bandFill`; `BandStyle.opacity` ordered plain < tinted < footer in both modes, tested | Compliant |
| FR-006 | `@Environment(\.colorSchemeContrast)`; increased strengths 0.08 and 0.12, tested stronger | Compliant |
| FR-007 | `pinnedFooter` draws the footer band at full width down to the bottom edge in every state; content order unchanged | Compliant |
| FR-008 | Footer outside the `ScrollView`; section bands inside it scroll and are cut at the footer's top edge | Compliant |
| FR-009 | Hover highlight is the row's own background inside the band's content, so drawn above the band; colors unchanged | Compliant |
| FR-009a | Only padding, frame and background added; identifiers and labels unchanged | Compliant |
| FR-010 | Spec 025 User Story 6, Independent Test, scenario 1, FR-011, FR-023, Unassigned assumption, contract "Dividers"; spec 026 Assumptions and (review fix) its contract's footer diagram | Compliant |
| FR-011 | `docs/accounts-and-budgets.md` describes alternating bands and the footer band | Compliant |
| FR-012 | `CoverageReport.sectionStripes`; `defaultScenarioAlternatesSectionBands` pins plain, tinted, plain, tinted for the four entries | Compliant |
| FR-012a | No website change | Compliant |
| FR-013 | Recapture and README image wait for the maintainer's go | Deferred (open release item) |

## Edge cases

All ten are handled: no accounts (text outside the bands, footer band shown), error lines at the top (plain, alternation unchanged), entries hidden from the bar (still sections), empty or one-member groups (one section), empty Unassigned (no stripe), reordering (stripes computed from the current order on every render), an expanded Details (band grows, later stripes unchanged), the height cap (only the sections scroll), Increase contrast (stronger strengths), and the single-section crops (they take the section's band; see FINDING-7 in review-findings.md for the bottom edge of `details` and `harnesses`).

## Extra behavior (not in the spec)

None.

## Spec evolution candidates

- Fixed during review: FR-010 named spec 025's "User Story 1"; the divider story is User Story 6 (0af6b47).

## Conclusion

The code matches the spec. The deep review found no Critical or Important code issue; six Minor findings were fixed (spacing of an error line above the first section, footer band built in one place, one fill helper, the spec 026 contract, two test gaps). The README image and the recapture stay open as the FR-013 release item.

## Code Review Guide

Where a human reviewer gets the most out of their time:

1. `Sources/AgentTacho/DropdownView.swift` `sections(now:)`, `band(_:content:)`, `bandFill(_:)`, `pinnedFooter(now:)`: band layout, paddings (top 2 + 10 pt, 10 + 10 pt between sections and above the footer) and the footer band.
2. `Sources/UsageCore/Dropdown/SectionBands.swift` with `Tests/UsageCoreTests/SectionBandsTests.swift`: the stripe rule and the strengths.
3. In the walkthrough: the tinted band with a hovered row (FR-009), Increase contrast on and off, a Details scrolled under the footer, and the bottom edge of the `details` and `harnesses` crops after the recapture.

## Deep Review Report

**Gate:** PASS (no fix round needed; one cleanup pass for Minor findings)
**Details:** specs/028-section-bands/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 1 | 1 | 0 | completed (+1 Notable) |
| Architecture & Idioms | 5 | 3 | 2 | completed (+1 Notable; FINDING-5 partly fixed) |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 1 | 0 | 1 | completed |
| Test Quality | 3 | 2 | 1 | completed (+1 Notable) |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (initial and re-review) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 1 | 0 | 1 | completed (README image, deferred FR-013) |
| Test Suite (regression) | 0 | 0 | 0 | passed |
| **Total** | **11** | **6** | **5** | |

Severity: 0 Critical, 1 Important (deferred by FR-013), 10 Minor (6 fixed, 4 remaining), 3 Notable (captured to brainstorm/idea-inbox.md).

MVP: Architecture & Idioms (5 findings).

Key fixes applied (4bf9f3a, 0af6b47):

1. An error line above the first section keeps its 10 pt distance (SC-003) (correctness).
2. The footer band is built in `pinnedFooter` alone, with a correct pinning comment; one `bandFill` helper for all bands (architecture).
3. The spec 026 contract no longer draws the footer divider; spec 028 FR-010 names the right user story (architecture, stage 1).
4. Stripe tests check full sequences and a property over 0...7; the default scenario test pins literal stripes without a dead branch (test quality).

Remaining Minor (none blocking, all judgment calls): FINDING-5 (`hasTopLines` repeats the top-line conditions), FINDING-6 (strength values also in a doc comment), FINDING-7 (`details`/`harnesses` crops may catch 1 to 2 pt of the footer band; check at the recapture), FINDING-10 (Unassigned path of the coverage report unreachable from demo scenarios).

Post-fix spec coverage: 16 of 16 requirements verified (FR-013 deferred).

Notable observations: 3 captured to brainstorm/idea-inbox.md (`section-stripe-type`, `section-stripes-single-entry-point`, `footer-band-before-panel-resize`).

Test results after fixes: `make test` 1654 + 65 passed, `make test-release` 253 passed, `make app-demo` built.
