# Code Review: Headline window switch

**Spec:** specs/027-headline-window-switch/spec.md
**Date:** 2026-10-19
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% (16 of 16 functional requirements, 13 of 13 edge cases)**

- Functional requirements: 16 of 16 compliant (FR-001 to FR-016; FR-016's recapture is deferred by the recorded maintainer decision the requirement itself names)
- Edge cases: 13 of 13
- Acceptance scenarios: US1 1 to 7 (with 3a), US2 1 to 3, US3 1 to 4, US4 1 to 3 traced to code; the UsageCore parts are covered by tests
- Success criteria: SC-005 by tests; SC-001 to SC-004 by the code below and the walkthrough

No `## Constants` section in the spec, so the constants check was skipped. The spec example "✳ 5h ⚠ ~85%" shows a space between the level glyph and the stale marker; the bar draws them without one, as it did before this spec. That is a spec wording point, not a code deviation.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `LimitRowLayout` `.contentShape` + `headlineSwitch` (tap on the whole row); `SubscriptionSection`/`CodexPlanSection` forward `HeadlineWindow.choice(forClaude:)` / `choice(forCodex:)` to `AppModel.setHeadline`; the default row stores nil; no refresh, the dropdown stays open | Compliant |
| FR-002 | 12 pt marker slot on every window row, `●` on `headline.claudeWindow` / `codexHeadlineIndex`, also for the default; hover: rounded `Color.primary.opacity(0.06)` behind name line and bar plus `○`, only when `isHeadline == false`; window order unchanged | Compliant |
| FR-003 | `accessibilityAction(named: "Show in menu bar")`, `.isSelected` on the headline row, `RowText.window(isHeadline:)` appends ", shown in menu bar" | Compliant |
| FR-004 | budget, member and Unassigned rows pass no `isHeadline` (no slot, no tap); `BarLayout.budgetItem`/`memberItem` carry no tag | Compliant |
| FR-005 | `HeadlineWindow.claude` (7-day default), `HeadlineWindow.codex` (`barWindow`, the longest effective window) | Compliant |
| FR-006 | fixed choices always resolve; `.claudeModel` only with a limit of exactly that name; Codex by exact name, else the longest; the stored choice is never touched by the fallback | Compliant |
| FR-007 | `BarLayout.subscriptionItem`/`codexItem`: value, level, pace and burn key from the headline; Claude critical also when the effective 7-day window is at or above 100%; Codex keeps `anyLimitReached`; a fixed window without values reads "--" | Compliant |
| FR-008 | `HeadlineWindow.tag(claude:)` / `tag(codexName:)` ("5h", "Nh", "wk", "Nd", model name cut to 7 + "…" above 8); header tag secondary and regular (`HeadlineHeaderText`); "5h --"; no tag for "…", not signed in, Codex without windows | Compliant |
| FR-009 | `BarLabelBuilder`: tag after the icon in the icon's tone inside the pill, before glyph, stale marker and value; `BarPresentation.accessibilityText` names the window in full; the Settings preview uses `BarLayout.segments` on the draft, which keeps the dropdown's choices | Compliant |
| FR-010 | `headlineWindow` per account, encoded only when set; tolerant `Account.decodeHeadline` with load notes for unknown, wrong-kind and non-string values; `keepingHeadlineChoices` in Settings `applyNow` and `onChange`; removal drops the account with its choice | Compliant |
| FR-011 | `AppModel.setHeadline` saves via `ConfigStore.update` with no refresh, timer restart or notification; `dataRelevant()` drops `headlineWindow` | Compliant |
| FR-012 | threshold tracker, pace line, row percent, bar, reset text, notes and tooltips untouched | Compliant |
| FR-013 | resolution, tag, level, markers, wording and coding in UsageCore with `HeadlineWindowTests`, `HeadlineChoiceTests`, `HeadlineBarLayoutTests`, `HeadlineFallbackBarLayoutTests`, `ConfigurationTests`, `ConfigStoreTests`, `RowTextTests`, `BarPresentationTests` | Compliant |
| FR-014 | specs 001 FR-005, 007 FR-012, 011 FR-012, 017 FR-008 and the spec 025 dropdown contract amended; `docs/usage.md` and `docs/configuration.md` updated | Compliant |
| FR-015 | `default.json` sets `acc-max` to `fiveHour`; coverage checks `barTags`, `barValues` ("58%") and `headlineRows`; the existing level, marker and pace checks pass | Compliant |
| FR-016 | recapture, README image and site copy recorded for the shared round in the idea inbox (`minimal-dropdown-screenshots`), per spec 026 FR-018 | Compliant (deferred by decision) |

## Edge cases

All thirteen are handled: clicking the headline row (no change), clicks on reset text or bar (whole-row tap, tooltips kept), "…" and "--" placeholders without tag and with the choice kept, stale values ("5h ~58%"), a reset window ("5h 0%"), a Codex window that became the longest (default, no tag, choice kept), a one-window Codex plan, an account hidden from the bar, Settings open during a click, two Claude accounts, long model names, notifications and the pace line unchanged.

## Extra behavior (not in the spec)

- `ConfigStore.update(_:)` (review fix): a click is applied to the file on disk, so a hand edit made since the last refresh is kept and a broken file is never written over. This makes FR-010 ("survive a restart", "the next save writes the value in effect") hold together with the existing hand-edit rule; no spec change needed.

## Spec evolution candidates

- None required. Optional wording fix: the FR-009 example "✳ 5h ⚠ ~85%" could drop the space between "⚠" and "~" to match the bar.

## Conclusion

The code matches the spec. The two Important findings (a click could write over a hand edit or a broken file; then adopt a hand edit without its side effects) were fixed in UsageCore with tests.

## Code Review Guide

Where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Bar/HeadlineWindow.swift`: resolution, fallback, tags and the click-to-choice helpers (FR-005 to FR-008), with `HeadlineWindowTests`.
2. `Sources/UsageCore/Bar/BarLayout.swift` `subscriptionItem` / `codexItem`: the critical rule with a non-default headline (FR-007) and the tag on "--" vs. placeholders.
3. `Sources/UsageCore/Config/Configuration.swift` (`decodeHeadline`, `settingHeadline`, `keepingHeadlineChoices`) and `ConfigStore.update`: tolerant decoding and the save path of a click.
4. `Sources/AgentTacho/SettingsView.swift` `onChange` / `applyNow`: how a dropdown click survives a pending Settings draft and undo.
5. `Sources/AgentTacho/DropdownView.swift` `LimitRowLayout`: marker slot, hover, tap and accessibility; check hover after closing the panel with Esc in the walkthrough (FINDING-11).

## Deep Review Report

**Gate:** PASS (after fix round 2 of 3)
**Details:** specs/027-headline-window-switch/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 0 | 0 | 0 | completed (1 below-threshold note, same as FINDING-11) |
| Architecture & Idioms | 8 | 3 | 5 | completed (1 Notable) |
| Security | 1 | 1 | 0 | completed |
| Production Readiness | 2 | 1 | 1 | completed |
| Test Quality | 6 | 6 | 0 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (initial and both re-reviews) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 1 | 1 | 0 | completed (0 initial, 1 in re-review 1, 0 in re-review 2) |
| Re-review round 1 (agent) | 4 | 3 | 1 | completed (2 Notable) |
| Test Suite (regression) | 0 | 0 | 0 | passed |
| **Total** | **22** | **15** | **7** | |

Severity: 0 Critical, 2 Important (2 fixed), 17 Minor (12 fixed, 5 remaining), 3 Notable (1 addressed, 2 captured to the idea inbox).

MVP: Architecture & Idioms (8 findings).

Key fixes applied:

1. A headline click goes through `ConfigStore.update`, which builds on the file on disk under one lock: a hand edit is kept, a broken or vanished file is never written over (production readiness; commits cbe2970, 6457996).
2. The in-memory configuration takes only the click; a hand edit is left to the next refresh with its side effects (Codex re-review).
3. The click's log line clips the stored value (security).
4. One source for the Codex default window; bar doc comments name the headline rule (architecture).
5. New tests: Codex level and fast-burn negatives, the 7-day critical rule with "5h --" and a reset 7-day window, reset windows at 0% with their tag, a stored Codex choice that became the only window, `HeadlineChoice` Codable, the demo value "58%", five `ConfigStore.update` cases; tautological assertions removed (test quality, re-review).

Remaining Minor (none blocking): FINDING-6 (headline inputs picked in three places), FINDING-7 (tag placeholder rule in two places), FINDING-8 (redundant `windowName` gate, unused `isDefault`), FINDING-10 (`isHeadline` + `onSelect` pair), FINDING-11 (hover state may survive an Esc close; check in the walkthrough).

Post-fix spec coverage: no implementation code removed; all 16 requirements verified.

Notable observations: 2 captured to brainstorm/idea-inbox.md (`headline-window-module-placement`, `settings-pending-edit-overwrites-hand-edit`).

Test results after fixes: `make test` 1640 + 64 passed, `make test-release` 252 passed, `make app` built.
