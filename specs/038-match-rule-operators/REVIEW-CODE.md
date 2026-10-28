# Code Review: Session Kinds and Match Conditions for Token-Based Accounts

**Spec:** specs/038-match-rule-operators/spec.md (reworked 2026-10-28)
**Date:** 2026-10-28
**Reviewer:** Claude (speckit.spex-gates.review-code)
**Diff:** `git diff main...HEAD`, reviewed at f86875c; review fixes e434102, 4ff559b, 0d56a35, b28dc48, 1bb35ab

This replaces the review of the first version of this spec.

## Compliance Summary

**Overall Score: 97% (38/39) after the review fixes; 95% (37/39) before them**

- Functional Requirements: 19/20 (FR-020 release notes depend on the merge commit subject)
- Edge Cases: 13/13
- Success Criteria: 6/6 (SC-005 timing and SC-006 checked by tests and the walkthrough)

## Functional Requirements

| Req | Implementation | Status |
|---|---|---|
| FR-001 kinds per harness, order, default | `SessionKind` cases and `kinds(for:)`, `default(for:)` | Compliant |
| FR-002 exact kind checks | `SessionKind.matches(record:)` (`req_vrtx_`, no `req_` prefix, `apikey`, OpenCode providers) | Compliant |
| FR-003 directory decides first | `Attributor.accountId` profile step before `ruleStep` | Compliant |
| FR-004 condition narrows, fields per harness | `CandidateKind.matchesKind` before `conditionMatch`; `MatchField.fields(for:)`; `offersCondition`, `requiresCondition` | Compliant (review fix 4ff559b: a remembered condition follows the harness) |
| FR-005 operators, labels, case, literal | `MatchCondition.compile`, `find`, `search`; `SessionMatchText.operatorLabel` | Compliant |
| FR-006 conditioned beats plain, subscription markers narrow | `Attributor.ruleStep`, `Candidate.hasCondition` | Compliant |
| FR-007 50 ms, sit out, retry, give up | `MatchRuntime`, `Attributor.tracking`; LogIndex, Codex, OpenCode retries | Compliant (review fixes e434102, b28dc48: active files settle, retries ordered in every source) |
| FR-008 refuse invalid or blank, load anyway | `validate`, `validateForSaving`, `ConfigStore.save`, `notingPattern` load note | Compliant |
| FR-009 overlap warning | `Configuration.matchOverlaps`, `MatchCondition.overlapKey` | Compliant |
| FR-010 stored form, new form only on save | `Account.encode` (`sessionKind`, `condition`), `StoredCondition` | Compliant |
| FR-011 migration of every earlier form | `Account.decodeSessions`, `StoredMatchRule.migrated`, `LegacyProvider` | Compliant |
| FR-012 section rows, Codex sentence, subtitle | `TokenBasedEditor`, `SessionsFields`, `AccountBudgetDescription.sourceName` | Compliant |
| FR-013 notes in order, warnings | `SessionMatchText.noteLines`, `DirectoryOnlyConflict` | Compliant |
| FR-014 Only when, kind and field transitions | `TokenBasedSettings.choosingKind`, `settingConditionOn`, `MatchCondition.withField` | Compliant |
| FR-015 stable pop-up widths, wrapping, labels | `StableWidthPicker`, `ConditionControls` (`ViewThatFits`) | Compliant (layout checked in the walkthrough) |
| FR-016 new account sheet | `NewAccountSheet` with `SessionsFields`, directory field, `validateForSaving` on Add | Compliant |
| FR-017 wording | `SessionMatchText`, `AccountDirectoryText`; no "profile", "Match rule", "Custom", "preset" in token-based UI | Compliant |
| FR-018 subscription marker narrows, captions | `ruleStep`, `SectionNotes` in "Session matching (advanced)" | Compliant (review fix 1bb35ab: the caption shown on Codex subscriptions named only the Claude Code directory) |
| FR-019 autosave, undo, Not applied | settings are part of the draft; `ConfigStore.save` refuses | Compliant |
| FR-020 docs, README, release notes | docs/configuration.md, README "How it works"; release notes from `feat`/`fix` subjects | Partial: release notes depend on the commit subjects that land on main |

## Edge Cases

All 13 are handled: blank text, metacharacters, `x*` on an empty field, slow pattern, kind change, harness change, OpenCode Other provider without a condition, two plain accounts of a kind, Directory only on a shared directory, Anthropic API key per token (documented), record of a kind no account has, Unicode case, different patterns that overlap.

## Spec-Declared Constants

The spec has no `## Constants` section; check skipped.

## Notes

- FR-020: release notes are built from `feat`/`fix`/`perf` subjects since the last tag. If the branch is squashed, the squash subject or body must say: token-based accounts choose a session kind with an optional condition; conditions ignore case; v0.8.0 markers became conditions of the Vertex kind (a gateway needs Other provider); subscription markers only decide among their subscription's own records.
- Codex left a scratch copy of the repository at `/private/tmp/038-review-repro` during its review; it is outside the worktree.

## Deep Review Report

**Gate:** PASS, conditional. Two fix rounds, each re-reviewed by an independent agent. No Critical finding; three Important findings fixed with regression tests that fail without the fix (checked by reverting); one Important finding (FINDING-4, the one-time re-read after a cold-start time-out) is a design trade-off left for the maintainer. Details in `review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 3 | 2 | 1 Notable | completed |
| Architecture & Idioms | 10 | 4 | 5 Minor, 1 Notable | completed |
| Security | 1 | 1 (docs) | 1 Notable | completed |
| Production Readiness | 4 | 2 | 1 Important (design decision), 1 Minor | completed |
| Test Quality | 7 | 4 | 3 Minor | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review round 1 | 3 | 2 | 1 Notable | completed |
| Re-review round 2 | 1 | 0 | 1 Minor | completed |
| CodeRabbit (external) | 1 | 0 | 1 Minor (RUNBOOK, rewritten by the walkthrough) | completed |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 2 | 2 | 0 | completed (both also found internally) |
| Test Suite (regression) | 0 | 0 | 0 | passed in every round |

**Fix commits:**
- e434102 fix(attribution): sat-out retries settle for active files and every database
- 4ff559b fix(accounts): a remembered condition follows the harness
- 0d56a35 refactor(accounts): review cleanups for session kinds
- b28dc48 fix(attribution): retry unchanged sat-out files before grown ones
- 1bb35ab fix(settings): subscription marker caption names the Codex home too

**Needs a human decision:**
- FINDING-4: after a cold-start time-out, the files the condition then sat out on are read once more in full on the next refresh. Accept, re-read only from the first skipped record, or cap the bytes per refresh.
- NOTABLE-4 / FR-007 wording: a sat-out file that grew counts as retried including its new lines, so a time-out on a new line gives the condition up. The spec could say so.
- NOTABLE-3 / FR-011: an unreadable Codex condition falls back to API key without a condition (counts every API-key session). A spec evolution could keep the kind with a condition that matches nothing.
- NOTABLE-1: the regex limit is per record; a per-refresh budget per condition would also stop moderately slow patterns.
- FR-020: the release notes need a squash subject (or kept `feat` subjects) that names the session kinds, case-insensitive conditions, the v0.8.0 marker migration and the narrowed subscription markers.

**Final `make test`:** 2264 tests in 236 suites passed (UsageCore), 73 tests in 7 suites passed (DemoMode).

## Maintainer Decisions (2026-10-28, rework)

- FINDING-4 (one-time re-read of the affected Claude Code files after a time-out early in a first scan): accepted as designed; FR-007 says so.
- FR-007 wording: a grown sat-out file counts as retried, including its new lines; written into the spec.
- FR-011: an unreadable stored condition drops the setting to the harness default (Codex: every API-key session) with a load note; kept, written into the spec.
- FR-020: the squash subject names session kinds with an optional condition, case-insensitive conditions, v0.8.0 markers as Vertex conditions and subscription markers that only narrow.
