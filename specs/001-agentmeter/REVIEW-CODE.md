# Code Review: AgentMeter

**Spec:** specs/001-agentmeter/spec.md (plus contracts/config-file.md and contracts/external-sources.md)
**Date:** 2026-10-13
**Branch:** 001-agentmeter
**Reviewer:** Claude (speckit-spex-gates-review-code, ship pipeline stage 7)
**Scope:** every file on the branch relative to main: Package.swift, Makefile, Resources/Info.plist, Sources/UsageCore, Sources/AgentMeter, Tests/UsageCoreTests, scripts/sum-vertex.sh, README.md

## Compliance Summary

**Overall Score: 98%** (after the fix for FR-004 and FR-008 in commit 9dbae20)

- Functional Requirements: 38/39 compliant (97%); one minor deviation left as a spec evolution candidate (FR-013 marker semantics)
- Edge Cases: 10/10 (100%)
- Success Criteria: 4 verified by code and tests (SC-001, SC-003, SC-006, SC-007); 4 need measurement on hardware and were not measured here (SC-002, SC-004, SC-005, SC-008)
- Spec-declared constants: no `## Constants` section in the spec, check skipped

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| FR-001 menu bar item, no Dock icon | Resources/Info.plist `LSUIElement`, App.swift `MenuBarExtra` | Compliant | Holds when run from the bundle built by `make app`, as the README states |
| FR-002 label + percent per shown subscription account and group, config order, no token accounts or Unassigned | BarLabel.swift `BarLabelBuilder.segments` | Compliant | Subscription accounts in configuration order, then groups in configuration order |
| FR-003 warning at lowest threshold or 80, critical at 100 | BarLabel.swift `warningThreshold`, `level`, glyph prefix and color | Compliant | Glyph keeps the distinction if MenuBarExtra drops the color |
| FR-004 dropdown lists all accounts and groups plus settings, refresh, quit | DropdownView.swift | Compliant after fix | Token-based accounts were only listed in groups with more than one member; fixed in 9dbae20 |
| FR-005 5-hour and 7-day percent with local reset time; bar shows the higher | DropdownView.swift `WindowRow`, UsageSnapshot.swift `barPercent` | Compliant | |
| FR-006 group spend, budget, percent, reset time | DropdownView.swift `GroupSection` | Compliant | |
| FR-007 last successful refresh shown, stale marking | DropdownView.swift footer, RefreshCoordinator.swift `lastSuccessfulRefreshAt`, `.stale` states | Compliant | |
| FR-008 per-model breakdown and per-day trend for every group and token-based account; tokens only for subscriptions | Aggregator.swift, BreakdownView.swift, DropdownView.swift | Compliant after fix | Per-member breakdown was never rendered; fixed in 9dbae20 |
| FR-009 Unassigned entry, tokens only, weekly window, never in bar | Aggregator.swift `unassigned`, DropdownView.swift `UnassignedSection` | Compliant | Hidden when empty |
| FR-009a nearest whole number, uncapped | UsageSnapshot.swift `PercentFormatter` | Compliant | Half rounds away from zero in both paths; tests added |
| FR-010 subscription and token-based types | Configuration.swift `AccountKind` | Compliant | |
| FR-011 provider usage service with locally stored credentials, credential directory per account, no duplicates, never asks | SubscriptionSource.swift, KeychainCredentialReader.swift, Configuration.swift `validate` | Compliant | |
| FR-011a credentials read at refresh time, never copied anywhere | SubscriptionSource.swift `fetch`, CredentialReader.swift redacted description, UsageEndpointClient.swift | Compliant after fix | `URLSession.shared` could have cached the request with its Authorization header on disk; fixed in 9e9e5f5 with an ephemeral cache-free session |
| FR-012 default log location plus configured directories | SessionLogSource.swift `directories(for:)` | Compliant | |
| FR-013 content markers, built-in rules per type, custom marker per account, directory tie-breaker, Unassigned otherwise | Attribution.swift | Minor deviation | A custom marker replaces the account's built-in rule instead of extending it; the spec wording ("add a custom marker ... for cases the built-in rules do not cover") reads as additive. Judgment call, left for spec evolution |
| FR-014 cost from token counts and per-model prices | PriceTable.swift `cost` | Compliant | |
| FR-015 built-in table, overrides and new entries in settings, overrides win | PriceTable.swift `merging`, SettingsView.swift `PriceSettingsTab` | Compliant | |
| FR-016 unpriced tokens counted and flagged, total incomplete | Aggregator.swift `breakdown`, `GroupEntry.incomplete` | Compliant | Zero-usage placeholder records no longer surface as unpriced (9e9e5f5) |
| FR-017 model allows further harnesses without changing stored format | Configuration.swift `Harness`, `type` discriminator, unknown keys ignored | Compliant | The harness value is stored but not yet consulted by scanner or parser (Notable) |
| FR-018 re-read only changed files, tolerate partial last record | LogIndex.swift size and mtime check, `readCompleteLines` | Compliant | Earlier window start between refreshes now restarts the index (9e9e5f5) |
| FR-019 token account in exactly one group, group has one or more accounts and a budget, create requires a group, last member removal deletes the group | Configuration.swift `validate`, `removingAccount`, `pruningEmptyGroups`, AccountSettingsView.swift `NewAccountSheet` | Compliant after fix | Moving the last member to another group left an undeletable empty group; fixed in 9e9e5f5 |
| FR-020 no budget on subscription accounts | Configuration.swift `SubscriptionSettings` | Compliant | |
| FR-021 window ends at the designated account's next 7-day reset, moves on the same refresh | WindowResolver.swift, RefreshCoordinator.swift re-resolve and re-run | Compliant | |
| FR-022 weekday and hour fallback, default Monday 00:00 | WindowResolver.swift, Configuration.swift `WeekFallback.monday` | Compliant | |
| FR-023 only usage inside the window counts | Aggregator.swift filter (start inclusive, end exclusive) | Compliant | |
| FR-024 interval default 300 s, minimum 60 s, first refresh immediate, no concurrent refresh | Configuration.swift constants and `validate`, App.swift timer and init, RefreshCoordinator.swift `running`/`pending` | Compliant | |
| FR-025 manual refresh from the dropdown | DropdownView.swift "Refresh now" | Compliant | |
| FR-026 one source failing does not block others | RefreshCoordinator.swift task group per source | Compliant | |
| FR-027 whole-number thresholds above 0 per subscription account or group, 5-hour and 7-day independent | Configuration.swift `checkThresholds`, ThresholdTracker.swift | Compliant | |
| FR-028 one notification per threshold per window on crossing, naming entity, window, threshold; baseline on first refresh | ThresholdTracker.swift, NotificationPresenter.swift | Compliant after fix | Posting before authorization was determined lost the first crossing; fixed in 9e9e5f5 and 6cdf844 |
| FR-029 threshold state resets with the window | ThresholdTracker.swift `evaluate` | Compliant | |
| FR-030 single human-readable file | ConfigStore.swift, Paths.swift | Compliant | |
| FR-031 settings window covers accounts, groups, prices, directories, interval, fallback, alignment account | SettingsView.swift, AccountSettingsView.swift | Compliant | Account type is chosen at creation, not editable afterwards; group membership is edited from the account |
| FR-032 labels 1 to 3 characters, unique across accounts and groups | Configuration.swift `validate` | Compliant | |
| FR-033 invalid file keeps last valid config, error in dropdown | ConfigStore.swift `load`, DropdownView.swift config error label | Compliant | |
| FR-034 default configuration on first launch with detected subscription | ConfigStore.swift `makeDefault`, App.swift | Compliant | |
| FR-035 start-at-login toggle, off by default | SettingsView.swift, App.swift `applyStartAtLogin` | Compliant | |
| FR-036 diagnostic log per refresh per source, bounded to 5 MB | DiagnosticLog.swift, RefreshCoordinator.swift, sources | Compliant | Live file is capped at 5 MB; one rotated generation is kept (Notable: total on disk is 10 MB) |
| FR-037 "Open log" entry | DropdownView.swift, App.swift `openLog` | Compliant | |

### Edge Cases

| Edge case | Implementation | Status |
|-----------|---------------|--------|
| Partial last record ignored | LogIndex.swift `readCompleteLines` | Compliant, tested (completion on a later append now tested too) |
| Session spanning the week boundary | Aggregator.swift timestamp filter | Compliant, tested |
| Several configuration directories, never counted twice | LogDirectoryScanner.swift symlink resolution and `seen` set | Compliant, tested |
| Reset never fetched: fallback; fetched then unreachable: last reset kept | RefreshCoordinator.swift `lastAlignmentReset` | Compliant, tested (coordinator memory now isolated in the test) |
| Two subscription accounts: designated one, default first | Configuration.swift `effectiveAlignmentAccountId` | Compliant, tested (added) |
| Provider-specific model id matches the same price | PriceTable.swift `canonicalModel` | Compliant, tested |
| Sleep past a tick: refresh on wake | App.swift `observeWake` | Compliant (manual) |
| More than 10 accounts | No limit anywhere | Compliant |
| Config missing on first launch | ConfigStore.swift `makeDefault` | Compliant, tested |
| Thousands of files: only changed files re-read | LogIndex.swift | Compliant functionally; SC-004 timing not measured |

### Extra Features (Not in Spec)

| Feature | Location | Assessment |
|---------|----------|------------|
| `scripts/sum-vertex.sh` cross-check for SC-003 | scripts/ | Helpful verification aid, not product scope |
| Per-member cost rows in a group section | DropdownView.swift | Helpful; supports FR-004 |
| `subscriptionType` carried in the status | SubscriptionSource.swift | Unused; candidate for removal (Minor) |

## Code Quality Notes

The core is cleanly split from the UI, every external format is parsed defensively, and the suite exercises the core thoroughly. Remaining quality items are listed in review-findings.md: duplicated helpers (canonical path, ISO formatters, dedupe key), comments citing task ids, double logging per source, a long `performRefresh`, and a few dead or write-only members.

## Recommendations

### Critical (Must Fix)
None remaining.

### Spec Evolution Candidates
- [ ] FR-013: state whether a custom marker replaces or extends the built-in rule (code replaces).
- [ ] FR-036: state whether 5 MB bounds the live file or the total on disk (code keeps one rotated generation).
- [ ] FR-028/FR-029: state whether a window that starts above a threshold notifies (code establishes a baseline).

### Optional Improvements
- [ ] The 25 remaining Minor findings in review-findings.md (FINDING-12 to FINDING-36), none of which affect spec compliance.

## Conclusion

Compliance is at 98% with no Critical or Important findings remaining. The one open deviation is a wording question on FR-013 for the spec, not a defect. Ready for verification.

## Deep Review Report

**Gate: PASS** (after fix round 2)
**Agents completed:** 5/5 internal + 1 re-review agent per round + CodeRabbit (3 runs)
**Skipped:** Goal Alignment (no PR), Copilot (disabled in config)
**Failed:** Codex (usage-limit error, no findings)

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 11 | 11 | 0 |
| Minor | 32 | 7 | 25 |
| Notable | 11 | - | 11 |
| **Total** | **54** | **18** | **36** |

Review Agents:

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     9 |     4 |         5 | completed |
| Architecture & Idioms   |    14 |     0 |        14 | completed |
| Security                |     5 |     2 |         3 | completed |
| Production Readiness    |     7 |     0 |         7 | completed |
| Test Quality            |    16 |    10 |         6 | completed |
| Re-review (rounds 1, 2) |     3 |     2 |         1 | completed |
| Goal Alignment          |     0 |     0 |         0 | skipped (no PR found) |
| CodeRabbit (external)   |     4 |     3 |         1 | completed (all 4 duplicates of internal findings) |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled in config) |
| Codex (external)        |     0 |     0 |         0 | failed (usage limit) |
| Test Suite (regression) |     0 |     0 |         0 | passed (128 tests, 15 suites, both rounds) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |    58 |    21 |        37 |           |

Per-agent rows count duplicates reported by more than one agent; the severity table above is deduplicated. Two findings reported as Important were reclassified to Minor with reasons (FINDING-12 source classification trait, FINDING-13 cold-parse memory spike); see review-findings.md.

Agent Leaderboard MVP: Test Quality (16 findings)

Key fixes applied:
1. Window start moving earlier between refreshes restarts the log index instead of losing pruned records (correctness, coderabbit)
2. Group left without members on save is deleted instead of blocking the save (correctness, architecture)
3. Notifications are queued until authorization is granted, requested at launch, and a denial is re-checked later (correctness, production-readiness, coderabbit, re-review)
4. Usage endpoint client uses an ephemeral cache-free session so the bearer token never reaches the URL cache (security)
5. Zero-usage placeholder records are dropped at parse time (correctness)
6. Shell cross-check passes window bounds as jq arguments (security)
7. Thirteen tests added or strengthened: outage memory, attribution change, partial line completion, designated alignment account, SessionLogSource directories and tie-breaker, rounding at .5, token classes, resets_at parse error, zero-usage records, pruning, session configuration (test-quality)

Post-fix spec coverage: 39/39 requirements verified, all covered.

Notable observations: 11 captured to brainstorm/idea-inbox.md

Details: specs/001-agentmeter/review-findings.md
