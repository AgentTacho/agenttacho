# Deep Review Findings

**Date:** 2026-10-19
**Branch:** 026-dropdown-layout-polish
**Rounds:** 1
**Gate Outcome:** PASS (FINDING-1, first deferred as needs judgment, fixed after the maintainer chose the screen-aware cap)
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 11 | 8 | 3 |
| Notable | 2 | - | 2 |
| **Total** | **16** | **11** | **5** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR found) + CodeRabbit + Codex (Copilot disabled in config)
**Agents failed:** none. A first CodeRabbit call failed on the unsupported `--files` option and was rerun with `--committed --base main`.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 72
- **File:** Sources/AgentTacho/DropdownView.swift:26, 123-141
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (maintainer decision: screen-aware cap now)

**What is wrong:**
The panel's height cap is the constant `maxHeight = 640`. Neither the sections' height nor `resizePanel(to:)` looks at the visible height of the screen the panel is on.

**Why this matters:**
On a display with less than about 640 pt of visible height below the menu bar (a 13" laptop on the "Larger Text" scaled resolution), the bottom of the panel is off screen. With the footer now pinned to the panel's bottom edge, the refresh, Settings and Quit icons and any source errors would be off screen and unreachable by scrolling, which defeats FR-010 and SC-003 on such screens. The fixed cap is older than this spec (spec 025 had the same cap, with the footer at the end of the scroll content), so this is not a regression of this branch.

**How to resolve:**
Needs judgment, because it changes what "the panel's height cap" means (a constant in spec 025 and 026). Options: (a) cap at min(640, distance from the panel's top to the bottom of `screen.visibleFrame` minus a margin), updated on screen changes; (b) keep the constant and record small screens as a known limit; (c) a follow-up spec for screen-aware sizing.

**How it was resolved:**
The maintainer chose option (a). Spec 026 gained FR-010a and a short-screen edge case; FR-010 and FR-011 refer to it. `FooterLayout.room(available:)` and `FooterLayout.cap(available:)` compute the screen room (panel top to the bottom of `visibleFrame`, minus 8 pt) and the cap min(640, room), with 640 when the screen is unknown; `sectionsHeight` takes the room and lets the 160 pt floor yield when the room is smaller than footer plus 160 pt. `DropdownView` measures the room from the panel's frame and its screen (main screen as fallback) when the panel opens, when the window is found, and on `NSApplication.didChangeScreenParametersNotification`. `ScreenAwareCapTests` (8 tests, written first and failing) cover plenty of room, a short room, an unknown screen, room below footer plus 160, a footer that fills the room, and a sweep checking the panel never exceeds the cap or the room.

### FINDING-2
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Dropdown/CompactFormat.swift:17-27, Tests/UsageCoreTests/CompactFormatTests.swift
- **Category:** test-quality (real defect, confirmed by a failing test)
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`CompactFormat.usd` cut "<1" at `value < 0.5` and whole dollars at `value < 1000`, but formatted with the format's default rounding (half to even). New boundary tests confirmed `usd(0.5)` returned "0" and `usd(999.5)` and `usd(999.99)` returned "1,000".

**Why this matters:**
FR-009: "<1" for small amounts, whole dollars below 1,000, then "1.6K". A day or a Σ of $0.50 read "0", like a day without usage, and a monthly budget sum of $999.60 read "1,000".

**How it was resolved:**
`usd` rounds once to whole dollars with the same rule the format uses (`NSDecimalRound`, `.bankers`) and takes both cut-offs from that value; amounts from 999.50 go to the compact form ("1K"). New test `usdBoundariesFollowTheRoundedValue` covers 0.49, 0.5, 0.51, 999.5, 999.99 and 1,000. All earlier outputs are unchanged.

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/DayRowTotalTests.swift:11-28
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The test helper put all tokens into `inputTokens`, so no test checked that Σ adds all four token kinds as FR-009 and the day columns do.

**Why this matters:**
A regression to summing only input tokens would pass while Σ disagreed with the day values (cache reads are most of Claude's tokens).

**How it was resolved:**
Added `tokenRowSumsAllFourKinds` (1M + 2M + 3M + 4M gives "10" and "Total: 10,000,000 tokens").

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/BreakdownView.swift:129-132
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The (i) legend for cost rows said Σ is "the sum of all days in the row"; a monthly row wraps, and Σ sums the whole period.
**How it was resolved:** The legend now reads "the sum of all shown days, after the last day".

### FINDING-5
- **Severity:** Minor
- **Confidence:** 78
- **File:** Sources/AgentTacho/BreakdownView.swift:389-403, Sources/UsageCore/Dropdown/DayRowTotal.swift:22-38
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** Σ's value and tooltip are in core, but the day cells' value and tooltip (`dayValue`, `dayHelp`) stay in the view. The "same format as the day values" rule of FR-009 is split across two modules, and the currency tooltip format exists twice.
**What is needed:** A core `DayCell` text (value and tooltip per day) next to `DayRowTotal`, used by the view, with a test that Σ's tooltip equals "Total: " plus a day tooltip's value part.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 74
- **File:** Sources/AgentTacho/DropdownView.swift:773-775
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `MemberDisplay.showsAccountsButton`, the tested FR-007 predicate, was only read by tests; the view decided from a separate `compactMap`.
**How it was resolved:** The budget section passes member tables only when `display.showsAccountsButton` is true.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Dropdown/FooterText.swift:22-27
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The `paceTooltip` doc comment described the removed "Last refreshed" line and called the pace text the tooltip.
**How it was resolved:** The comment now says it is the status text's accessibility value and one part of `statusTooltip`.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/DropdownView.swift:30-33, 236
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The `inset` doc comment also describes `footerGap`, which has no comment and sets two gaps (above the divider and between divider and footer lines).
**What is needed:** A comment per constant; split `footerGap` if the two gaps should vary separately.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift:121-130
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The FR-011 formula min(content, max(160, cap - footer)) was computed inline in the view, untested (constitution II).
**How it was resolved:** `FooterLayout.sectionsHeight` in `UsageCore/Dropdown/FooterText.swift`, called by the view, with `FooterLayoutTests` for the fitting, capped and floor cases.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/CompactFormatTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** All format tests used en_US, so dropping `.locale(locale)` would go unnoticed.
**How it was resolved:** `formatsFollowThePassedLocale` checks de_DE output ("1.000" millions) and that the compact dollar form follows the locale.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 75
- **File:** specs/025-minimal-dropdown/spec.md:62, 118
- **Category:** external
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** User Story 2 scenario 5 and User Story 5 scenario 3 of spec 025 still described member Details and the "This week" line.
**How it was resolved:** Both scenarios amended, citing spec 026 FR-001 to FR-003, FR-008 and FR-009. The clarification and quickstart keep their historical wording.

**External tool analysis (CodeRabbit):**
> Update User Story 2 scenario 5 to state that member lines have no individual Details and that member tables appear in the group's Details behind "Show accounts." Update User Story 5 scenario 3 to describe the Σ column as holding the week's total instead of a "This week" first line.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 75
- **File:** specs/007-codex-plan-limits/spec.md:152
- **Category:** external
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Spec 007 FR-013 still said the week's token total is the first line "This week: 45.1M tokens".
**How it was resolved:** FR-013 now names the Σ column, citing spec 025 FR-014 and spec 026 FR-008, FR-009.

**External tool analysis (CodeRabbit):**
> Update FR-013 to state that the week's token total appears in the Σ column at the end of the expanded Details day row, citing spec 025 FR-014 and spec 026 FR-008 and FR-009.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 75
- **File:** specs/020-about-tab-update-layout/spec.md:82
- **Category:** external
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** remaining (out of scope)

**What is wrong:** Spec 020 still mentions the gear menu that spec 025 FR-028 removed.
**Why remaining:** This is stale wording from spec 025, not from this spec; it belongs to a spec 025 follow-up or the next spec refactoring.

**External tool analysis (CodeRabbit):**
> Update User Story 2, acceptance scenario 5 to refer only to Settings > About, and remove or mark as superseded the gear-menu assumption in the Assumptions section.

## Notable Observations

### NOTABLE-1
- **File:** Sources/AgentTacho/DropdownView.swift:92-96, 133-141
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** Heights start at 0 and `resizePanel` returns early while `panel` is nil; if both measurements arrive before `WindowAccessor` sets the panel, `onChange(of: panel)` does not resize to the current height.
- **Rationale:** Older than this branch and possibly harmless (MenuBarExtra sizes from the content's fitting size), but there are now two measured heights that can land in that window. Calling `resizePanel(to: panelHeight)` from `onChange(of: panel)` would close it.

### NOTABLE-2
- **File:** Sources/DemoMode/ScenarioCoverage.swift:31-33, 91-97
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `memberDisplays` is keyed by group name and silently keeps the first of two groups with the same name.
- **Rationale:** Group names are editable labels; keying by group id would make the coverage robust for future scenarios.

## Re-review (round 1)

CodeRabbit (`--uncommitted`) and Codex (`--uncommitted`) reviewed the fix round: 0 findings each.

## Post-Fix Spec Coverage

No code was removed in the fix round (the changes add a rounding step, a core height helper, tests and wording). All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (1554 + 64) |
| 1 (tests first) | make test | 2 | 4 | failed as intended: new boundary and locale tests exposed FINDING-2 |
| 1 (after fixes) | make test | 0 | 0 | passed (1560 + 64) |
| 1 | make test-release | 0 | 0 | passed (252) |
| 1 | make app, make app-demo | 0 | 0 | built |
| FINDING-1 (tests first) | make test | 2 | build | failed as intended: `FooterLayout.room`, `cap` and the `room:` argument did not exist |
| FINDING-1 (after fix) | make test | 0 | 0 | passed (1568 + 64) |

Test suite passed after the fix round.

## Remaining Findings

- FINDING-1 (Important): fixed after the maintainer's decision (screen-aware cap, spec 026 FR-010a).
- FINDING-5, FINDING-8 (Minor): day cell formatting in core; constant comments.
- FINDING-13 (Minor, out of scope): spec 020 gear menu wording.
