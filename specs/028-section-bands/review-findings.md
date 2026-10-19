# Deep Review Findings

**Date:** 2026-10-19
**Branch:** 028-section-bands
**Rounds:** 0 fix rounds needed for the gate (no Critical or Important code finding); one cleanup pass for Minor findings
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 0 | 1 (deferred: FR-013, maintainer decision) |
| Minor | 10 | 6 | 4 |
| Notable | 3 | - | 3 |
| **Total** | **14** | **6** | **8** |

**Agents completed:** 5/5 (Goal Alignment skipped: no pull request yet) + 2 external tools (CodeRabbit, Codex). Copilot disabled in config.
**Agents failed:** none

The one Important finding (Codex) is the README image `docs/images/agenttacho-dropdown.png`, which still shows the dividers. Spec FR-013 makes the screenshot recapture and the README image a release item that waits for the maintainer's go (AGENTS.md step 4), so it is deferred, not a code defect, and does not count against the gate.

## Findings

### FINDING-1
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/DropdownView.swift:232-262
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (4bf9f3a)

**What is wrong:** The top lines (demo scenario error, configuration error, "No accounts configured") had 10 pt padding top and bottom, and the first section's band adds its own 10 pt top padding: 20 pt between an error line and the first section, where `main` had 10 pt.

**Why this matters:** SC-003 says the dropdown is not taller than before for the same content.

**How it was resolved:** The top lines keep their top padding and drop the bottom padding when a section band follows; without sections, the bottom padding stays so the footer band keeps its distance.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 80
- **File:** specs/026-dropdown-layout-polish/contracts/dropdown-ui.md:31-38
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (0af6b47)

**What is wrong:** The "Footer (pinned)" diagram of spec 026's contract still drew the divider above the footer.

**Why this matters:** FR-010 asks that earlier specs be amended where they describe the dividers; the contract was missed.

**How it was resolved:** The rule line is replaced by a note on the footer band, citing spec 028 FR-001 and FR-007. In the same commit, spec 028 FR-010 now names spec 025's User Story 6 (the divider story), not User Story 1 (found in the stage 1 compliance check).

### FINDING-3
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/AgentTacho/DropdownView.swift:68, 303 (before the fix)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (4bf9f3a)

**What is wrong:** The expression that turns a `BandStyle` into a fill was written twice, once for the footer and once for the sections.

**Why this matters:** A change to the base color or the contrast mapping would have to be made twice; a miss would let footer and sections drift apart (FR-005).

**How it was resolved:** One `bandFill(_:)` helper (DropdownView.swift:309) used by both.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift:61-68, 306-314 (before the fix)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (4bf9f3a)

**What is wrong:** The footer band was built in two places (top padding in `pinnedFooter`, inset, frame and fill in `body`), and the doc comment gave a wrong reason for the split (pinning comes from the footer sitting outside the scroll view, not from where the fill is applied).

**Why this matters:** The footer's FR-004 and FR-007 rules were split across two functions behind a misleading comment.

**How it was resolved:** `pinnedFooter` (DropdownView.swift:319) builds the whole band; `body` keeps only `fixedSize` and the height measurement. The comment now says why it stays pinned.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift:232-262, 287-292
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** partly fixed (4bf9f3a), remaining

**What is wrong:** `hasTopLines` repeats the three conditions the top lines render, and its doc comment cited no requirement.

**Why this matters:** A new top line added to the VStack but not to `hasTopLines` would never show.

**How it was resolved:** The doc comment now cites spec 028 FR-003 and says to keep both in step. The duplication itself remains; folding the lines into one list is a design choice for a later change (judgment call).

### FINDING-6
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Dropdown/SectionBands.swift:7-11
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The doc comment of `BandStyle.opacity(increasedContrast:)` repeats the literal strengths that the `switch` holds.

**Why this matters:** If the strengths are tuned after the walkthrough (spec Assumptions allow it), the comment goes stale.

**How it was resolved:** Not changed. The values in the comment tell a reader the spec's starting strengths at a glance; whether to keep them is a judgment call. Whoever tunes the values updates both lines.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 70
- **File:** scripts/screenshots/uihelper.swift:256-275, scripts/screenshots/capture.sh:172-184
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** For the `details` and `harnesses` shots, `scrollto` stops once the Details container's bottom is inside the scroll area, and `crop` adds 2 pt of margin, so the crop can take 1 to 2 pt of the footer band below the scroll view. Before this change that strip caught the 1 pt divider.

**Why this matters:** The cropped shots could end in a thin strip of a different tint, against the edge case that a single-section crop shows that section's band.

**How it was resolved:** Not changed: the capture cannot be run without the maintainer's go, and a tooling change that cannot be tried is riskier than the strip. Check the bottom edge of `details` and `harnesses` when reviewing the recaptured shots (FR-013); if the strip shows, stop `scrollto` only when `rect.maxY + 2 <= visible.maxY`.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 90
- **File:** Tests/DemoModeTests/DefaultScenarioTests.swift:96-104
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (4bf9f3a)

**What is wrong:** After asserting that the scenario has no Unassigned usage, the expected value still appended a stripe when `SectionBands.showsUnassigned` (the function under test) said so, a branch that could never contribute; `count >= 3` repeated what the exact comparison already checked.

**Why this matters:** The test looked like it covered "Unassigned plain if shown" without doing so.

**How it was resolved:** The test pins the literal `[.plain, .tinted, .plain, .tinted]`; the comment says why Unassigned is covered in `SectionBandsTests`.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/SectionBandsTests.swift:28-33
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (4bf9f3a)

**What is wrong:** The odd count with Unassigned checked only the count and the last stripe; no test had an odd count without Unassigned, or checked that adding Unassigned leaves the entries' stripes unchanged.

**Why this matters:** An implementation that recolors the entries when Unassigned is added would have passed (FR-002, SC-004).

**How it was resolved:** Full sequences for 3 and 1 entries with Unassigned and 3 without, plus `alternationHoldsForAnyCount` over 0...7: parity per index, count, and the prefix invariant.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/DemoMode/ScenarioCoverage.swift:100-101
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** No test runs `ScenarioCoverage.evaluate` with Unassigned shown, so the `unassignedShown:` wiring in the coverage report has no test.

**Why this matters:** Hard-coding `false` there would leave every test green.

**How it was resolved:** Not changed. A demo scenario cannot produce Unassigned usage: scenario decoding rejects a usage record whose account is not configured (Sources/DemoMode/Scenario.swift:337). The wiring is unreachable from scenarios today, and `SectionBands.showsUnassigned` and the Unassigned stripe are covered in `SectionBandsTests`. Judgment call; NOTABLE-2 describes the structural fix.

### FINDING-11
- **Severity:** Important
- **Confidence:** 75
- **File:** docs/images/agenttacho-dropdown.png (reported against specs/028-section-bands/plan.md:58)
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** deferred (FR-013, maintainer decision)

**What is wrong:** The README image still shows the divider layout.

**Why this matters:** Constitution V and AGENTS.md step 6 ask for a current image when the dropdown changes.

**How it was resolved:** Deferred on purpose: FR-013 ties the recapture and the README image to the maintainer's go for the capture run, before the release that ships the feature. Open release item.

**External tool analysis (Codex):**
> [P2] Replace the dropdown image before merging. For this dropdown layout change, `docs/images/agenttacho-dropdown.png` remains unchanged and still shows the divider layout, even though this plan says to replace it. Capture the demo dropdown and update the image before merge, as required by AGENTS.md:65.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Dropdown/SectionBands.swift:3-34
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `BandStyle` is both the section stripe (plain, tinted) and the band style (plus footer); "sections never get the footer band" is held by a test, not the type.
- **Rationale:** A `SectionStripe` type mapped to `BandStyle` at draw time would make it a compile-time guarantee.

### NOTABLE-2
- **File:** Tests/DemoModeTests/DefaultScenarioTests.swift:92-103
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The coverage report recomputes the stripes with the same calls as the view instead of taking them from it; nothing but the shared calls keeps them together.
- **Rationale:** One `SectionBands.stripes(for:snapshot:)` used by both would remove the drift risk and give FR-003 an explicit test.

### NOTABLE-3
- **File:** Sources/AgentTacho/DropdownView.swift:64-72, 160-162
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** The footer band reaches the bottom edge only once `resizePanel` has matched the window to `panelHeight`; before that, a plain strip could show below it.
- **Rationale:** Not observed; check in the walkthrough.

## Post-Fix Spec Coverage

The cleanup moved the footer's padding and fill from `body` into `pinnedFooter` and removed two assertions from a test; no requirement lost its implementation.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 | no `Divider` in DropdownView.swift | ✓ |
| FR-002, FR-003 | `SectionBands.stripes`, `sections(now:)` | ✓ |
| FR-004, FR-004a | `band(_:content:)`, `pinnedFooter`, top padding `inset - bandPadding` | ✓ |
| FR-005, FR-006 | `BandStyle.opacity`, `bandFill`, `colorSchemeContrast` | ✓ |
| FR-007, FR-008 | `pinnedFooter` below the `ScrollView` | ✓ |
| FR-009, FR-009a | hover highlight in `LimitRowLayout` above the band; fills only | ✓ |
| FR-010 to FR-012a | spec 025/026 amendments, docs/accounts-and-budgets.md, coverage test | ✓ |
| FR-013 | deferred to the maintainer's go | deferred |

All spec requirements verified after the cleanup.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| after cleanup | make test | 0 | 0 | passed (1654 + 65 tests) |
| after cleanup | make test-release | 0 | 0 | passed (253) |
| after cleanup | make app-demo | 0 | - | built |

CodeRabbit re-review of the cleanup commits: 0 findings.

## Remaining Findings

No Critical findings remain. One Important finding is deferred by the maintainer's decision: FINDING-11, the README image, part of FR-013. Four Minor findings remain (FINDING-5, 6, 7, 10), all judgment calls described above.
