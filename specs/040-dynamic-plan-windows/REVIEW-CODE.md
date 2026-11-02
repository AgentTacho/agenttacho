# Code Review: Dynamic Claude Plan Windows

**Spec:** specs/040-dynamic-plan-windows/spec.md
**Date:** 2026-11-02
**Reviewer:** Claude (speckit.spex-gates.review-code)
**Diff:** `git diff main...HEAD`, reviewed at aacfac2; review fix f8376e6

## Compliance Summary

**Overall Score: 100% (37/37) after the review fix; 97% (36/37) before it**

- Functional Requirements: 20/20 (FR-001 to FR-020; 19/20 before f8376e6, FR-016 README security row)
- Edge Cases: 12/12
- Success Criteria: 5/5

FR-021 (recapture the shots and update the website) is pending the maintainer, as AGENTS.md step 4 requires. It is not scored and is not a finding.

## Functional Requirements

| Req | Implementation | Status |
|---|---|---|
| FR-001 windows from `limits`, model, plan and surface scopes | `UsageEndpointClient.Body.entries()`, `ClaudeLimitEntry`, `ClaudeLimits.resolve` | Compliant |
| FR-002 top-level fallback, lenient | `ClaudeLimits.resolve` (`usedFallback`), `Lenient<WindowBody>`, `WindowBody.window()` | Compliant |
| FR-003 group mapping | `ClaudeLimits.groupLength`, `fiveHourGroups` | Compliant |
| FR-004 identities | `ClaudeLimits.resolve` (`sevenDayRaw`, `fiveHourRaw`, `primaryModelRaw`), `ClaudeWindow`, `ClaudeLimit.isPrimaryModelLimit` | Compliant (a model name with a colon handled since f8376e6) |
| FR-005 names, first of equal identities | `ClaudeLimits.words`, `seen` set in `resolve`; also on the last-good read since f8376e6 | Compliant |
| FR-006 order, no row for an absent window | `ClaudeLimits.ordered`, `DropdownView` `ForEach(status.windows)` | Compliant |
| FR-007 pace only with a length | `ClaudeLimit.paceInputs`, `UsageSnapshot.paceKeys`, `BurnRate` by identity | Compliant |
| FR-008 thresholds per plan window, drop on absence | `ThresholdTracker.observe` (`status.planWindows`, keys kept on a failed fetch) | Compliant |
| FR-009 default window | `SubscriptionStatus.defaultWindow` | Compliant |
| FR-010 chosen window only while present, choice kept | `HeadlineWindow.claude`, `HeadlineWindow.choice(forClaude:status:)` | Compliant |
| FR-011 tags, 100% style, accessibility | `HeadlineWindow.tag(claude:)`, `BarLayout.subscriptionLevel`, `HeadlineWindow.accessibilityName` | Compliant |
| FR-012 window log line and ok summary | `ClaudeWindowReport`, `SubscriptionSource` (`loggedWindowSignatures`), `SubscriptionStatus.windowSummary` | Compliant |
| FR-013 `severity`, `is_active` ignored leniently | `LimitBody` (undeclared fields) | Compliant |
| FR-014 last-good list plus legacy keys | `SavedClaudeLimit`, `SavedClaudeValues` | Compliant (lenient list and legacy fallback since f8376e6) |
| FR-015 old `headlineWindow` values | `HeadlineChoice.parse`, `.claude(ClaudeWindow)` | Compliant |
| FR-016 wording | Settings help text, docs, README feature list, alt text and security section | Compliant after f8376e6 (security row still named the 5-hour window) |
| FR-017 Codex, budgets, alignment unchanged | `RefreshCoordinator` uses `window(.sevenDay)`; Codex untouched | Compliant |
| FR-018 decisions in tested UsageCore | `ClaudeLimits`, `HeadlineWindow`, `ThresholdTracker`, `LastGoodStore`; the tooltip moved to `ClaudeLimit.nameHelp` in f8376e6 | Compliant |
| FR-019 earlier specs amended | specs 001, 010, 025, 027 diffs | Compliant |
| FR-020 demo as a list, coverage test | `ScenarioClaudeLimit`, `default.json`, `DefaultScenarioTests` (`claudeRows`) | Compliant |
| FR-021 shots and website | pending the maintainer | Not scored |

## Edge Cases

All 12 are handled and tested:
- only model entries;
- skipped entries;
- null reset, now also for model limits;
- two unscoped entries of one group;
- a surface-only scope;
- an upper-case or underscored group;
- two limits of one model;
- equal display names;
- no window at all ("No limits reported");
- a failed fetch keeping the saved list;
- two accounts with different lists;
- `severity` and `is_active`.

## Success Criteria

| Criterion | Status | Evidence |
|---|---|---|
| SC-001 no "unavailable" row with today's answer | Met | `WindowRow` has no unavailable state; `DefaultScenarioTests` `claudeRows` |
| SC-002 new window kind without a release | Met | `ClaudeLimitsTests`, `ThresholdTrackerClaudeWindowsTests`, `ClaudeHeadlineWindowListTests` with an unknown group |
| SC-003 old configuration and last-good files load | Met | `LastGoodWindowListTests.previousVersionFileLoadsAsAList`, `ConfigurationTests` |
| SC-004 Codex, budgets and tokens unchanged | Met | `make test` 2452 + 74 tests pass |
| SC-005 log shows reported kinds | Met | `SubscriptionSourceTests.windowLogLineOnFirstFetchAndOnChange` |

## Spec-Declared Constants

The spec has no `## Constants` section, so this check was skipped.

## Deep Review Report

**Gate:** PASS. One fix round, followed by an independent re-review and a CodeRabbit re-review. The re-reviews found 0 Critical and 0 Important findings.

| Severity | Found | Fixed | Remaining |
|---|---|---|---|
| Critical | 1 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 16 | 11 | 5 |
| Notable | 6 | 2 | 4 |

The Critical finding came from CodeRabbit ("double optional after `try?` does not compile"). It is a false positive: the expression compiles, and the tests cover both a null and an unreadable top-level object.

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 2 | 2 | 0 | completed |
| Architecture & Idioms | 9 | 5 | 2 Minor, 2 Notable | completed |
| Security | 3 | 2 | 1 Notable | completed |
| Production Readiness | 1 | 1 | 0 | completed |
| Test Quality | 6 | 3 | 3 Minor | completed (one shared with Correctness) |
| Goal Alignment | 0 | 0 | 0 | skipped (no pull request found) |
| Re-review, fix round 1 | 3 | 2 | 1 Notable | completed |
| CodeRabbit (external) | 2 | 1 | 0 | completed (1 Critical dismissed as a false positive; the re-review of the fixes found 0) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed (no actionable findings) |
| Test Suite (regression) | 0 | 0 | 0 | passed |

**Fix commit:**
- f8376e6 fix(subscription): first model limit by name, lenient saved list, clamped allowance

**Key fixes:**
1. Removed the dead `SubscriptionStatus.barPercent`, whose doc comment contradicted FR-009 and FR-011 (architecture, Important).
2. A model's first limit is decided by its name (`ClaudeLimit.isPrimaryModelLimit`), so a name with a colon keeps its accessibility name, tooltip and legacy `modelLimits` entry. The parsing `ClaudeWindow.modelName` is gone (correctness, test quality, re-review).
3. The last-good read keeps the first window of each identity and reads a `windows` list it cannot decode from the legacy keys (correctness, production readiness).
4. The weekly allowance is clamped through `PercentFormatter.rounded`, so `1e20` cannot trap (security).
5. The README security section and `docs/usage.md` no longer name the 5-hour window, and they list what `last-good.json` now holds (stage 1, security, CodeRabbit, re-review).
6. The model row tooltip moved to `ClaudeLimit.nameHelp` in UsageCore and is tested (FR-018).
7. Stale doc comments in `HeadlineWindow`, `Configuration` and `Scenario` are updated.

**Remaining (Minor, no behavior gap):**
- FINDING-14: the `WindowKind.fiveHour` and `.sevenDay` statics are used only by tests.
- FINDING-15: `ScenarioPlayer.resetDate` is used only by a test.
- FINDING-16: the bar-level "no markers" assertion for an unknown-group window is weak.
- FINDING-17: there is no test for the Settings help text (US1 scenario 4); the text is correct.
- FINDING-18: the FR-012 test does not cover a failed fetch in between or two accounts.

Four Notable observations went to `brainstorm/idea-inbox.md`: `claude-window-type-names`, `claude-limit-entry-scope-enum`, `claude-answer-size-caps` and `model-limit-weekly-wording`.

Details are in [review-findings.md](review-findings.md).

**Tests:** `make test` passes (2452 + 74 tests) and `make test-release` passes (266) at f8376e6.
