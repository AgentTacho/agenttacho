# Deep Review Findings

**Date:** 2026-11-02
**Branch:** 040-dynamic-plan-windows
**Rounds:** 1 (plus a re-review of the fixes)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline, autonomous)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 16 | 11 | 5 |
| Notable | 6 | 2 | 4 |
| **Total** | **24** | **14** | **9** |

The one Critical finding (CodeRabbit) was dismissed as a false positive: the code it flags compiles and is covered by passing tests. Remaining counts only Minor and Notable findings.

**Agents completed:** 5/6 (Goal Alignment skipped: no pull request yet) + CodeRabbit, Codex, a re-review agent
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Critical (dismissed)
- **Confidence:** 75
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:261-262
- **Category:** external
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** dismissed (false positive)

**What is wrong:** CodeRabbit says `(try? container.decodeIfPresent(Lenient<WindowBody>.self, ...))??.value` does not compile because Swift flattens `try?`.

**Why this matters:** It would be a build break.

**How it was resolved:** Not a defect: `Lenient.value` is itself optional, the expression compiles, and `make test` exercises both a null and an unreadable top-level object (`UsageEndpointWindowsTests`). No change.

**External tool analysis (CodeRabbit):**
> Update the `five_hour` and `seven_day` assignments to avoid double optional chaining after `try?`; use an optional expression that compiles with Swift's flattened `try?` result while preserving nil when decoding fails or the key is absent.

### FINDING-2
- **Severity:** Important
- **Confidence:** 90
- **File:** Sources/UsageCore/Snapshot/UsageSnapshot.swift:54-60
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** `SubscriptionStatus.barPercent` survived from the fixed 5-hour/7-day model. Only tests used it, and its doc comment still claimed it was the default headline window that decides the at-or-above-100% style.

**Why this matters:** Both claims contradict FR-009 and FR-011. A future caller could reuse it as "the bar percent" and bring back the fixed 7-day default.

**How it was resolved:** Removed. The parser tests use a private `sevenDayPercent` helper. The old `barShowsTheSevenDayWindowOnly` test is now `defaultWindowIsTheSevenDayWindowWhenReported`, which also asserts the FR-009 fallback to the 5-hour window.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Pace/ObservationLog.swift, Sources/UsageCore/Bar/HeadlineWindow.swift, Sources/UsageCore/Snapshot/LastGoodStore.swift, Sources/AgentTacho/DropdownView.swift
- **Category:** correctness
- **Source:** correctness-agent (also reported by: test-quality-agent, re-review)
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** Whether a window is a model's first limit was decided by parsing the identity (`ClaudeWindow.modelName` treated any colon after `model:` as the further-limit separator). A model display name containing a colon was therefore classified as a further limit. That gave the wrong VoiceOver name (FR-011) and the wrong tooltip, and dropped the model from the legacy `modelLimits` key (FR-014 downgrade).

**Why this matters:** Model names come from the answer and AgentTacho does not control them.

**How it was resolved:** Added `ClaudeLimit.isPrimaryModelLimit` (identity equals `.model(modelName)`) and `ClaudeLimit.nameHelp`. Used them in `HeadlineWindow.accessibilityName`, the legacy write and the dropdown tooltip, which now comes from UsageCore (FR-018). Removed the parsing `ClaudeWindow.modelName`. Tests cover "Opus: Max" for the accessibility name, the tooltip and the legacy key. Identity collisions between model "A" kind "b" and a model named "A:b" remain theoretical; the builder keeps the first (FR-005).

### FINDING-4
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Snapshot/LastGoodStore.swift:111-125
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** A legacy file with two model limits of one name produced two windows with the same identity. That breaks `ForEach(id: \.identity)` and the uniqueness FR-005 guarantees for live answers.

**Why this matters:** SwiftUI gets duplicate row ids while offline with an old file.

**How it was resolved:** `SavedClaudeValues.status(now:)` keeps the first window of each identity, for the legacy branch and the `windows` list alike. Tested by `legacyModelLimitsOfOneNameKeepTheFirst` and `savedListWithADuplicateIdentityKeepsTheFirst`.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 90
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:289-297
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** `Int(allowance.rounded())` traps for a finite allowance out of Int range (for example `1e20`).

**Why this matters:** One bad answer would crash every refresh.

**How it was resolved:** The allowance now goes through `PercentFormatter.rounded`, which clamps every other percent of the answer. The test uses `1e20`.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 75
- **File:** README.md:66, 81
- **Category:** security
- **Source:** security-agent (also reported by: stage 1 compliance, re-review)
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** The "Security and privacy" section still named "your 5-hour, 7-day and model limits". It also did not list the window kinds, groups, identities, names and lengths that `last-good.json` now holds.

**Why this matters:** FR-016 and constitution III require the section to stay true.

**How it was resolved:** Row 66 now says "your plan windows, model limits and free limit resets". The `last-good.json` sentence lists "the Claude window kinds and groups as Anthropic reports them with the identities, names and lengths AgentTacho derives from them". The website privacy section is out of scope for this run (FR-021 is pending the maintainer); the request and the data read are unchanged.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 75
- **File:** docs/usage.md:13
- **Category:** external
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** "Notifications still check every window" overstates FR-008, because model limits get no threshold notifications.

**How it was resolved:** Changed to "every plan window".

### FINDING-8
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Bar/HeadlineWindow.swift:11-15, 51, 134; Sources/UsageCore/Config/Configuration.swift:114-115
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** Doc comments still described "fixed windows", "5h --" and "the 7-day window" as the default.

**How it was resolved:** Reworded to the default window of FR-009 and the "--" cases of FR-009 and FR-010.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/DemoMode/Scenario.swift:8, 22, 353-354
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** The `ScenarioError` path examples showed the removed `sevenDay` shape, and a double blank line was left over.

**How it was resolved:** The examples now read `frames[0].claude.acc-max.limits.sevenDay.used` and `claude.acc-max.limits[0].used`, and the blank line is gone. The message "no plan windows to change in claude" stays, because it is a tested error contract (ScenarioTests).

### FINDING-10
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/DropdownView.swift:771-822
- **Category:** architecture
- **Source:** architecture-agent (also reported by: test-quality-agent as Notable)
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** The model row's tooltip duplicated the "first limit or further limit" decision in the SwiftUI layer.

**How it was resolved:** The tooltip is now `ClaudeLimit.nameHelp` in UsageCore and is tested (`modelLimitNameHelp`). The two row views were not merged; they render the same layout and differ only by the tooltip.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/UsageEndpointClientTests.swift:80-109
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, f8376e6)

**What is wrong:** `malformedLimitsAreIgnored` claimed to check the raw index alignment, but its shares were not an array, so every allowance was nil whatever the indices.

**How it was resolved:** The test now maps a share to index 1 behind a malformed entry at index 0 and expects Fable's allowance 50. It keeps the "not an array" case and adds the `1e20` case.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Pace/ObservationLog.swift:26-35
- **Category:** architecture
- **Source:** re-review
- **Round found:** 2 (re-review)
- **Resolution:** fixed (f8376e6)

**What is wrong:** After the fix for FINDING-3, the public `ClaudeWindow.modelName` was left with no caller and still had the colon bug.

**How it was resolved:** Removed together with its test. A doc note on `ClaudeWindow.model(_:)` points to `ClaudeLimit.isPrimaryModelLimit`.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 72
- **File:** README.md:81
- **Category:** security
- **Source:** re-review
- **Round found:** 2 (re-review)
- **Resolution:** fixed (f8376e6)

**What is wrong:** The first README fix said window names and lengths come "as Anthropic reports them", but AgentTacho derives them.

**How it was resolved:** Reworded as in FINDING-6.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:17-18
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `WindowKind.fiveHour` and `.sevenDay` are now used only by tests. They repeat the raw values and names that `ClaudeWindow` and `ClaudeLimits` own.

**What needs to happen:** Either derive them from `ClaudeWindow`/`ClaudeLimits` or build the test kinds from `ClaudeLimit`. This is a cleanup with no behavior change.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/DemoMode/ScenarioPlayer.swift:57-60
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `resetDate(_: ScenarioClaudeLimit)` is used only by a test. `DemoSources` computes `launch + resetsIn` itself.

**What needs to happen:** Route `DemoSources` through one player helper, or test the source output instead.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift (WindowListBarLayoutTests.contractTable)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The daily window's "no markers" assertions use 40% without observations, so they would also pass for a window with a length. Lower layers do cover "no pace without a length" (`HeadlineWindowTests`, `PaceTests`, `BurnRateTests`).

**What needs to happen:** Add a high-usage unknown-group case next to a 5-hour control case.

### FINDING-17
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/AccountSettingsView.swift:211-214
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** No test covers US1 scenario 4 (the threshold help text names no 5-hour window), because the text is a literal in the SwiftUI layer. The text itself is correct.

**What needs to happen:** Move the text to a UsageCore constant and test it.

### FINDING-18
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/SubscriptionSourceTests.swift (windowLogLineOnFirstFetchAndOnChange)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The FR-012 test does not cover success, then failure, then success with the same set, and it does not cover two accounts. The code handles both cases: the signature changes only on success and is keyed per account.

**What needs to happen:** Extend the test with a 500 between two identical answers and with a second account.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Pace/ObservationLog.swift:1-36
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** In code, `ClaudeWindow` is the identity and `ClaudeLimit` is the window, the reverse of the spec glossary. The identity type lives in the Pace folder.
- **Rationale:** The names are harder to follow; this is a candidate for a follow-up rename. Captured in the idea inbox.

### NOTABLE-2
- **File:** Sources/UsageCore/Subscription/ClaudeLimits.swift:75-125
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The scope of `ClaudeLimitEntry` is spread over three independent fields; an enum would make contradictory states unrepresentable.
- **Rationale:** Captured in the idea inbox.

### NOTABLE-3
- **File:** Sources/UsageCore/Subscription/ClaudeLimits.swift
- **Category:** security
- **Source:** security-agent
- **Description:** String lengths and the number of `limits` entries from the answer are not capped. Log injection is already prevented by `DiagnosticLog.singleLine`.
- **Rationale:** Only a misbehaving endpoint could exploit it. Captured in the idea inbox.

### NOTABLE-4
- **File:** Sources/UsageCore/Snapshot/LastGoodStore.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** A strict decode of `windows` would drop the whole file on a future format change.
- **Rationale:** Addressed in f8376e6 (lenient decode with a legacy fallback, tested).

### NOTABLE-5
- **File:** Sources/AgentTacho/DropdownView.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The tooltip decision lived in the view.
- **Rationale:** Addressed in f8376e6 (`ClaudeLimit.nameHelp`, tested).

### NOTABLE-6
- **File:** Sources/UsageCore/Subscription/ClaudeLimits.swift (`nameHelp`), Sources/UsageCore/Bar/HeadlineWindow.swift
- **Category:** spec awareness
- **Source:** re-review
- **Description:** A model's first limit is always called "<model> weekly limit" (FR-011 "as today"), even when the model's only limit is not weekly.
- **Rationale:** Matches the spec's wording; it would only matter if a model ever reported only a daily limit. Captured in the idea inbox.

## Goal Alignment

Skipped: no pull request exists for the branch yet.

## Post-Fix Spec Coverage

The fix round removed code: `barPercent`, `ClaudeWindow.modelName`, and the tooltip logic in the view. Each removal was checked against the requirements:

| Requirement | Implementation after the fixes | Status |
|-------------|-------------------------------|--------|
| FR-004 identities | `ClaudeLimits.resolve`, `ClaudeLimit.isPrimaryModelLimit` | ✓ |
| FR-009 default window | `SubscriptionStatus.defaultWindow`, `BarLayout.subscriptionLevel` | ✓ |
| FR-011 tags and accessibility names | `HeadlineWindow.tag(claude:)`, `HeadlineWindow.accessibilityName` | ✓ |
| FR-014 legacy keys and list | `SavedClaudeValues.init(credentialDirectory:status:)`, `status(now:)` | ✓ |
| FR-006 row tooltips unchanged | `ClaudeLimit.nameHelp` via `ModelLimitRow` | ✓ |

All spec requirements were verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (2448 + 74 tests) |
| 1 | make test | 0 | 0 | passed (2453 + 74 tests) |
| 1 | make test-release | 0 | 0 | passed (266) |
| final (f8376e6) | make test | 0 | 0 | passed (2452 + 74 tests) |
| final (f8376e6) | make test-release | 0 | 0 | passed (266) |

The test suite passed in all fix rounds.

## Remaining Findings

No Critical or Important finding remains. The five Minor findings FINDING-14 to FINDING-18 are cleanups and test hardening with no behavior gap. They are left for the maintainer.
