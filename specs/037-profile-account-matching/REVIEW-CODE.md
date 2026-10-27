# Code Review: Account Matching by Profile and Match Rules

**Spec:** specs/037-profile-account-matching/spec.md
**Date:** 2026-10-27
**Reviewer:** Claude (speckit.spex-gates.review-code)
**Changes:** `git log main..HEAD` (9 commits, 2182214 to 6095b7d)

## Compliance Summary

**Overall Score: 95% (41/43)**

- Functional Requirements: 17/19 (FR-016 partial, FR-017 pending)
- Success Criteria: 7/7
- Edge Cases: 17/17 (one interpretation noted)
- Spec-declared constants: none (no `## Constants` section)

## Functional Requirements

| Req | Implementation | Status | Notes |
|---|---|---|---|
| FR-001 | `Logs/SessionProfile.swift` (`detect`, `Candidates`), `Logs/LogIndex.swift` phase 2 and re-read rules | Compliant | Byte search for configured directories + `/projects/`; latest shape line per record, first one before it; ambiguous lines skipped; profile carried to appended lines (`startProfile`); late first profile re-reads the file (`namedLate`); candidate key change re-reads files with named or unnamed shape lines. |
| FR-002 | `SessionProfile.Candidates.init`, `TokenBasedSettings.effectiveSessionDirectory` | Compliant | Searches expanded and symlink-resolved spellings, each followed by `/projects/` (never resolved); empty field is `~/.claude`. |
| FR-003 | `Attributor.accountId(for:...)`, `ruleStep` | Compliant | One main claimant wins, else one additional; several at the deciding rank restrict the pool; then custom, presets/subscription, tie-breaker; else nil. |
| FR-004 | `SessionProfile.detect` returns only the canonical directory; shape lines are not parsed as records | Compliant | Test `shapeLineTextIsNotKept`, `onlyTheDirectoryLeavesTheLine`. |
| FR-005 | Profile step guarded by `record.harness == .claudeCode` | Compliant | |
| FR-006 | `TokenBasedSettings.harness`, `AccountSettingsView` harness pickers, OpenCode caption | Compliant | Provider picker removed. |
| FR-007 | `Config/MatchRule.swift`, `MatchRuleText`, `MatchRuleFields` view | Compliant | Presets per harness with captions, custom fields per harness with "Anywhere" last, None for Claude Code only, case-sensitive, first preset default. |
| FR-008 | `MatchRule.matches` and `Candidate.customMatch` check the harness | Compliant | |
| FR-009 | Subscriptions keep `customMarker` and implicit rules; marker section shown only for subscriptions | Compliant | |
| FR-010 | `ruleStep`: custom matches replace built-in matches | Compliant | |
| FR-011 | `Configuration.validate` refuses blank custom text; `needsNetworkRefresh` ignores token-based fields | Compliant | Undo/redo and "Not applied" use the existing draft flow. |
| FR-012 | `LogIndexStats.filesWithProfile/filesWithoutProfile`, `SessionLogSource.statsLine` | Compliant | |
| FR-013 | `Config/MatchOverlap.swift`, inline `Label` in Session matching | Compliant | |
| FR-014 | `Account.decodeHarnessAndRule`, `encode(to:)` | Compliant | Stored `harness` of old files ignored; load note per migrated account. |
| FR-015 | `StoredMatchRule.rule(for:)` returns nil, account gets `.none` with a load note | Compliant | |
| FR-016 | README and `docs/configuration.md` updated | Partial | The website's privacy section lives in the site repository, which this pipeline must not touch; it lands with the site pull request (AGENTS.md "Screenshots and website", maintainer step). |
| FR-017 | Commit subjects | Pending | No `feat` subject yet says that accounts now match by profile and rule and that OpenCode usage needs its own account; `docs/configuration.md` has the longer migration note. The squash in `speckit-spex-finish` must write that subject. |
| FR-018 | Invented paths and models (`~/agent-profiles/...`, `intranet/`) | Compliant | |
| FR-019 | `Resources/demo/default.json`, `ScenarioCoverage.harnessMismatches`, `DefaultScenarioTests` | Compliant | Plan section not reviewed (plan.md excluded from this review by instruction). |

## Success Criteria

| SC | Evidence | Status |
|---|---|---|
| SC-001 | `LogIndexTests.threeProfilesShareOneProjectsFolder`, `AttributionTests` | Compliant |
| SC-002 | `AttributionTests` rule tables per harness | Compliant |
| SC-003 | `ConfigurationTests` migration tests | Compliant |
| SC-004 | `LogIndexTests.shapeLineTextIsNotKept`, `SessionProfileTests.onlyTheDirectoryLeavesTheLine` | Compliant |
| SC-005 | Phase 1 skips unchanged files; existing re-read tests | Compliant |
| SC-006 | `MatchOverlapTests` | Compliant |
| SC-007 | `rg cc-deck Sources Tests docs README.md` finds nothing | Compliant |

## Edge Cases

All listed edge cases are handled. One interpretation: a shape line that names no configured directory (`.none`) does not end the profile of an earlier named shape line in the same file. The spec's "latest shape line" wording could be read either way; since a shape line without a memory path cannot be told apart from one naming an unconfigured directory, keeping the earlier profile is the safer reading. Recorded as a spec clarification candidate, not a defect.

## Extra Features (Not in Spec)

- `IconDefaults.openCode` and icons that follow harness and rule (`defaultIcon(harness:rule:)`): helpful, documented in `docs/configuration.md` "Icons".
- `MatchRuleFields` keeps the last custom field and text when switching to a preset and back: helpful UI detail.

## Recommendations

### Spec Evolution Candidates
- [ ] Clarify whether a shape line naming no configured directory resets the profile within a file (edge case above).

### Pending process items
- [ ] FR-016: website privacy section in the site pull request.
- [ ] FR-017: release-notes `feat` subject at squash time.

## Conclusion

Compliance 95% meets the deep review threshold. The two open items are process steps outside this pipeline stage, not code gaps.

## Deep Review Report

**Gate: PASS** (after fix round 2). Details: [review-findings.md](review-findings.md).

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 2 | 1 | 1 | completed |
| Architecture & Idioms | 11 | 8 | 3 | completed |
| Security | 1 (Notable) | 0 | 1 Notable | completed |
| Production Readiness | 6 | 4 | 1 + 1 Notable | completed |
| Test Quality | 6 | 5 | 1 Notable (resolved with the architecture fix) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 1 | 1 | 0 | completed (round 2 re-review: 0 findings) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 3 | 3 | 0 | completed |
| Re-review (round 2) | 2 | 2 | 0 | completed |
| Test Suite (regression) | 1 | 1 | 0 | passed after fix |

After deduplication: 0 Critical, 8 Important (all fixed), 20 Minor (15 fixed, 5 open), 3 Notable.

MVP: Architecture & Idioms (11 findings)

Key fixes applied:
1. Profile detection in one pass over `/projects/` occurrences, only on non-record lines (production).
2. Re-read rules on candidate change split by none, ambiguous, configured growth and lost spelling, so wildcard churn no longer re-reads every unnamed file and a new directory can make a named line ambiguous (production, CodeRabbit, re-review).
3. Every alias spelling of an additional directory is searched and part of the key (Codex).
4. Remembered custom rule keyed by account in Settings (Codex, correctness).
5. Rule pop-up items and transitions moved into UsageCore with tests (architecture).
6. End-to-end test of three profiles sharing a symlinked `projects` folder through the source (test quality).

Fix commits: 961816d, 6700eaf, 7798b42.

Open Minor findings (not blocking): `.none` shape line keeps the earlier profile (spec clarification candidate), harness check split between `MatchRule.matches` and its callers, duplicated standardize helper, subscription-only fallback for profile additional directories, symlink resolution in the overlap warning during rendering.

Post-fix spec coverage: all FRs verified.

Notable observations: 2 captured to brainstorm/idea-inbox.md.

Final checks: `make test` 2161 + 72 passed; `make test-release` 266 passed; `make app-demo` built.
