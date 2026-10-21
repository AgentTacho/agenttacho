# Code Review: Dropdown Theme

**Spec:** specs/032-dropdown-theme/spec.md
**Date:** 2026-10-21
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 96% (22 of 23 checks; FR-015 is pending outside the code)**

- Functional requirements: 14 of 15 compliant (FR-001 to FR-014). FR-015 (recapture and site copy) is a release step in the site repository that needs the maintainer's go for the capture run; it is not done on this branch.
- Edge cases: 8 of 8.
- Acceptance scenarios: US1 1 to 5, US2 1 to 6 and US3 1 to 3 are traced to code. US3 and the Auto/Dark/Light resolution are covered by UsageCore tests; the live switch (US1 3, US2 5) is manual, as SC-002 says.
- Success criteria:
  - By tests: SC-003 (fixed and resolved system colors against all four backgrounds), SC-005 (configuration round trip).
  - By code: SC-001, SC-004.
  - In the walkthrough: SC-002, SC-006.

The spec has no `## Constants` section, so the constants check was skipped.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `DropdownTheme` (auto, dark, light), default Auto in `Configuration.init` and the getter | Compliant |
| FR-002 | `GeneralSettingsTab` Display section: segmented "Dropdown theme" picker below "Show usage as", with a caption like its neighbor | Compliant |
| FR-003 | `Configuration.dropdownThemeValue` (key `dropdownTheme`, nil for Auto), `decodeDropdownTheme` with the `displayDirection` note pattern; `DropdownThemeConfigurationTests` | Compliant |
| FR-004 | `DropdownView.panelStyle` reads `model.configuration`; `.onChange(of: panelStyle)` reapplies the window style; the Settings draft applies itself | Compliant |
| FR-005 | Colors injected only in `DropdownView.body`; Settings, `BarLabel` and the preview untouched; the About tab's update parts take no dropdown colors | Compliant |
| FR-006 | `DropdownTheme.panelStyle(systemIsDark:)`; KVO on `NSApp.effectiveAppearance`; window `appearance` follows the style | Compliant |
| FR-007 | Opaque `palette.background`; `DropdownPalette.backgrounds` (plain, tinted, footer, hover over tinted); tests for fixed and resolved system colors | Compliant |
| FR-008 | Dark palette keeps background and system primary, secondary, orange; critical is fixed `#FF8A84` because system red reaches only 3.6:1 on hover over a tinted band (computed 3.18 with Increase Contrast) | Compliant (allowed change) |
| FR-009 | Light background fixed `#D5D6D9` (maintainer's change f2d8ecb); secondary `#48484A`, warning `#7A2E00`, critical `#8A000A`; worst case 4.65:1 (secondary on hover over a tinted band, Increase Contrast) | Compliant |
| FR-010 | `RowBarView` keeps `Color.orange`/`Color.red` fills | Compliant |
| FR-011 | Bands and hover use `Color.primary` at the `BandStyle` and `hoverOpacity` factors in both schemes; `bandsAreVisibleAndNoStrongerOnTheLightPanel` | Compliant |
| FR-012 | One palette and one `colorScheme` for scroll area, footer, top lines and update line; window background follows | Compliant |
| FR-013 | `DropdownPaletteTests.fixedTextColorsReachContrast`, `resolvedSystemTextColorsReachContrast` | Compliant |
| FR-014 | Demo uses the same configuration path and default; `defaultScenarioShowsWarningAndErrorTextUnderAuto` | Compliant |
| FR-015 | Not on this branch: capture run (needs the maintainer) and the site copy check | Pending |

## Edge cases

All 8 are handled:

- Increase Contrast: system roles keep their system variants; fixed roles are tested at the Increase Contrast band strengths.
- Appearance switch while open: one `panelStyle` drives palette, `colorScheme` and window style together.
- Theme change in Settings while open: same path as FR-004.
- Section bands on the light panel: visible (ratio above 1.0), no edges added.
- Hover and selection fills: same factor on the light foreground.
- Footer, update line, error lines, "Last refreshed": take `colors` from the palette.
- Long dropdown at the cap: scroll area and footer share the panel background, and the window background follows the theme.
- Demo app: same default and setting.

## Extra behavior (not in the spec)

- A caption under the picker ("Auto follows the system appearance. Settings and the menu bar always do."). It matches the style of "Show usage as", which FR-002 asks for. Helpful; no spec change needed.

## Spec evolution candidates

- Resolved: FR-007 now names link-styled buttons; see FINDING-2 in the Deep Review Report.

## Conclusion

The code matches the spec. The deep review found no Critical issues and one Important one, which was fixed in round 1: the band contrast model was not tied to what the views draw. Two Minor findings and two Notables were also fixed. Three Minor findings remain, and none of them blocks. The maintainer's light palette change (f2d8ecb) was reviewed as part of HEAD, and every fixed color still reaches 4.5:1.

## Code Review Guide

These are the places where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Dropdown/DropdownPalette.swift` with `Tests/UsageCoreTests/DropdownPaletteTests.swift`. They hold the two palettes, the four backgrounds, and the tests that resolve the real colors (FR-007 to FR-011, FR-013). Check the dark critical red: it is the only dark color that changes (FR-008).
2. `Sources/AgentTacho/DropdownView.swift` body, `panelStyle`, `applyPanelStyle` and `opened()`. One style drives the palette, the `colorScheme` and the window, both for a system switch and for a Settings change (FR-004, FR-006, FR-012).
3. `Sources/AgentTacho/DropdownColors.swift`. Check how roles map to SwiftUI styles, and that the environment default is the system colors (FR-005).
4. `Sources/UsageCore/Config/Configuration.swift` `decodeDropdownTheme` and the `dropdownTheme` accessor. Auto writes no key, and unknown values add a note (FR-003).
5. Walkthrough: switch the appearance while the dropdown is open; switch it while the dropdown is hidden and reopen; Increase Contrast on the dark panel (footer, hovered tinted row); the update line's link buttons on the light panel.

## Deep Review Report

**Gate:** PASS (after fix round 1; the re-review by CodeRabbit and Codex over 85c7989..HEAD found nothing)
**Details:** specs/032-dropdown-theme/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 2 | 1 | 1 | completed (Notable merged into Architecture's) |
| Architecture & Idioms | 3 | 2 | 1 | completed (+1 Notable) |
| Security | 1 | 0 | 1 | completed (Notable only) |
| Production Readiness | 3 | 2 | 1 | completed (+1 Notable) |
| Test Quality | 4 | 2 | 2 | completed (FINDING-1 merged into Architecture's; 2 Notable) |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch and fix commits) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed (branch and fix commits; tests blocked by its sandbox) |
| Test Suite (regression) | 0 | 0 | 0 | passed |
| **Total** | **13** | **7** | **6** | |

After merging duplicates there are 0 Critical, 1 Important (fixed), 5 Minor (2 fixed, 3 remaining) and 5 Notable findings. Two Notables were acted on, and three were captured to brainstorm/idea-inbox.md.

MVP: Test Quality (4 findings).

Key fixes applied:

1. The band model is now tied to the drawn label color (RGB equal to `foreground`, alpha at most 1), and the FR-011 comparison runs at the drawn alpha. A bar track visibility test was added (ef1a391, architecture, test quality).
2. `DropdownColors` is built once for each panel, so the environment no longer changes on every geometry pass (38813fd, production readiness).
3. The environment default is now the system colors instead of the dark palette (38813fd, architecture, correctness).
4. Opening the panel reapplies the window style, which covers a switch while the panel was hidden (38813fd, production readiness).

Remaining Minor findings (none of them blocks):

- FINDING-2: resolved 2026-10-21 by the maintainer (option a): FR-007 now covers link-styled buttons; the palette has a link role (dark #6CB4FF, light #003E99, both fixed because the system link blue misses 4.5:1 on the footer band), used by the update line and "Show account details" through `DropdownLinkButtonStyle`. Settings > About keeps the system link style (FR-005).
- FINDING-3: the redundant role in `DropdownTextColor.system`, an optional cleanup.
- FINDING-5: possible KVO resubscription in `onReceive`. The publisher is `Equatable`, so this is unverified; measure it in the walkthrough.

Post-fix spec coverage: 14 of 14 code requirements verified. FR-015 is pending (recapture and site copy).

Notable observations: 3 captured to brainstorm/idea-inbox.md (`clip-notes-by-scalars`, `shared-system-color-mapping`, `increase-contrast-system-variants`).

Test results after fixes: `make build` is clean, and `make test` passed (1758 + 69).
