# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 018-account-budget-subtitle
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 5 | 3 | 2 |
| Notable | 2 | - | 2 |
| **Total** | **8** | **4** | **4** |

**Agents completed:** 5/6 internal (Goal Alignment skipped: no PR found), plus a fix-round re-review agent, plus 2 external tools (CodeRabbit, Codex). Copilot skipped (disabled in config).
**Agents failed:** none. The first CodeRabbit run failed because CLI 0.7.6 no longer accepts `--files`; it was rerun with `--agent --committed --base main` and spec/brainstorm files were excluded from the result (it reported 0 findings overall).

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift:62-68 (before the fix)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit e7f6325)

**What is wrong:**
`otherLocalesKeepThePeriodWording` checked only `hasSuffix(" / month")`, `contains("400")` and `contains("$")` for a de_DE amount of 400. The en_US output "$400 / month" satisfies all three assertions.

**Why this matters:**
FR-003 requires number and currency formatting to follow the user's locale. This was the only non-en_US test, and it would keep passing if the `locale` parameter were ignored or replaced with `.current` or `en_US`.

**How it was resolved:**
The test now formats 1234.5 in de_DE and asserts `hasPrefix("1.234,50")` (German grouping and decimal separator), `hasSuffix("$ / month")` (symbol after the number; independent of the non-breaking space) and inequality with the en_US text. A whole amount of 400 weekly asserts `hasPrefix("400")`, no comma, and `hasSuffix("$ / week")`.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/AgentTacho/AccountSettingsView.swift:101-106 (before the fix)
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit e7f6325)

**What is wrong:**
`subscriptionSubtitle(_:)` replaced its exhaustive switch over `AccountKind` with `case .codexSubscription` plus `default: "Claude subscription"`. The default also covers `.tokenBased` and any future account kind.

**Why this matters:**
Output was correct today, but a new account kind, or a later change that lets `AccountBudgetDescription.make` return nil for some token-based account, would silently read "Claude subscription" (FR-006) without a compiler warning.

**How it was resolved:**
The switch lists `.subscription`, `.codexSubscription` and `.tokenBased` again; the token-based branch returns the provider name and carries a comment that it is unreachable while `make` covers every token-based account. FR-006 output is unchanged.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift:46-48, 156-165 (before the fix)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit e7f6325)

**What is wrong:**
The US1 scenario 3 literal "$99.50 / month" was not asserted (all fractional cases were weekly), and no own-budget case used a fractional amount, so the own-budget VoiceOver text with cents was untested.

**Why this matters:**
SC-002 asks for both periods with whole and fractional amounts across budget kinds.

**How it was resolved:**
Added the "$99.50 / month" assertion and a fractional monthly own budget asserting both "OpenAI · own budget, $99.50 / month" and "OpenAI, own budget, $99.50 per month".

### FINDING-4
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift:50-60 (before the fix)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit e7f6325)

**What is wrong:**
Negative amounts were tested only with a whole number; neither a negative fractional amount nor half-cent rounding of a negative value was pinned.

**Why this matters:**
The spec's edge case shows amounts of 0 or less "as entered", and the formatter documents half-away-from-zero rounding; a switch to another rounding mode would only be caught for positive values.

**How it was resolved:**
Added "-$5.50 / week" for -5.5 and "-$0.13" for -0.125.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Config/AccountBudgetDescription.swift:52-94
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, not in the fix loop)

**What is wrong:**
The struct stores seven fields, five of them derived from `provider` and `budget` (`iconId` duplicates the `.group` payload, `visibleText` equals `visiblePrefix + visibleSuffix`, `visiblePrefix` holds the whole text when there is no icon). The single space between the icon and the group name is added in the view (`Text(" " + description.visibleSuffix)`).

**Why this matters:**
Fields that must agree are maintained by hand in three switch arms, and "prefix" is a misleading name for the full text. A literal in the view is a small departure from FR-008's "all text in testable logic".

**How it can be resolved:**
Store `provider` and `budget` (plus formatted amounts) and compute the rest, or expose segments such as `(leading, iconId, trailing)` with `trailing` already starting with the space. A refactor with no behavior change; left for a follow-up.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/AccountBudgetDescription.swift:24-29
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, not in the fix loop)

**What is wrong:**
`BudgetAmountFormatter.unit(_:)` is a third mapping of `BudgetPeriod` to wording, next to `BudgetPeriod.adjective` and `.perUnit` in Configuration.swift; DropdownView.swift:553 inlines the same "month"/"week" ternary.

**Why this matters:**
A new period would get compiler help for the properties on `BudgetPeriod` but not for the scattered copies.

**How it can be resolved:**
Add `BudgetPeriod.unit` beside `perUnit` and use it in the formatter (and optionally in DropdownView).

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Config/AccountBudgetDescription.swift:1-123
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The file named after `AccountBudgetDescription` also holds `BudgetAmountFormatter` and `GroupListSubtitle`, while the app's other currency formatting (`UsageFormat`, including the near-duplicate `UsageFormat.budget`) lives in the view layer (DropdownView.swift).
- **Rationale:** Two homes for amount formatting; moving `UsageFormat`'s pure functions into UsageCore would bring all formatting under the testable-logic rule.

### NOTABLE-2
- **File:** Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift (`bothListsShowTheSameAmountText`)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The SC-004 test derives its expected value from the same `BudgetAmountFormatter.text` both lists call and checks with `contains`, so it only catches a list that stops calling the formatter.
- **Rationale:** The exact-string assertions in the group and Groups-list tests pin SC-004 more strongly; the test could use the literal "$400 / month".

## Goal Alignment

Skipped: no pull request exists for the branch yet.

## Post-Fix Spec Coverage

The fix round removed no implementation code (it replaced a `default:` branch with explicit cases and added test assertions), so the post-fix coverage check was not required. Spot check: FR-001 to FR-008 remain implemented in `AccountBudgetDescription.swift` and `AccountSettingsView.swift`. All spec requirements verified after fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| before review | make test | 0 | 0 | passed (1369 tests) |
| 1 | make test | 0 | 0 | passed (1369 tests) |
| 1 | make app | 0 | 0 | built (pre-existing UpdateInstaller.swift warnings only) |

Test suite passed in all fix rounds.

## Remaining Findings

None Critical or Important. Minor FINDING-5 and FINDING-6 are refactors with no behavior change.
