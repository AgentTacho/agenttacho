# Code Review: Additional Session Directories per Account

**Spec:** specs/035-additional-session-directories/spec.md
**Date:** 2026-10-22
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% (17 of 17 functional requirements, 14 of 14 edge cases)**

- Functional requirements: 17 of 17 compliant. FR-015's website part was checked: the site's privacy section (`src/components/agenttacho/Privacy.astro` on the site's `main`) names no session directory, so no site change is needed. FR-017 holds: the shot list selects only the Menu Bar and Prices tabs of Settings.
- Edge cases: 14 of 14.
- Acceptance scenarios: US1 1 to 7, US2 1 to 7, US3 1 to 4 and US4 1 to 3 are traced to code and tests. The new Settings section is SwiftUI only; its texts and the add rule are tested in UsageCore (`AccountDirectoryTextTests`, `SessionDirectoryEntryTests`).
- Success criteria: SC-001 to SC-005 by tests (`LogIndexTests`, `CodexSessionSourceTests`, `SubscriptionSourceTests`, `CodexLimitsSourceTests`), SC-006 by search (`rg cc-deck Sources Tests docs README.md` finds nothing).

The spec has no `## Constants` section, so the constants check was skipped.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `additionalSessionDirectories` on `SubscriptionSettings`, `CodexSubscriptionSettings`, `TokenBasedSettings`; `AccountKind.additionalSessionDirectories`; `Account.encode` writes trimmed non-blank entries, key only when one exists. | Compliant |
| FR-002 | `DirectoryListSection` below "Subscription", "Codex subscription" and "Usage source" in `AccountSettingsView.swift`; texts in `AccountDirectoryText`; `SessionDirectoryEntry.adding` drops duplicates after trimming; `NewAccountSheet` has no list. | Compliant |
| FR-003 | The list is part of the draft `Configuration`; `needsRefresh` sees it, `needsNetworkRefresh` compares only subscription credential directories. | Compliant |
| FR-004 | `WildcardPattern.matches`, `WildcardExpander.expand` (folders only, symlinks followed, `~` expanded first). | Compliant |
| FR-005 | Expansion on every `collect`; `WildcardExpander.cap` 100 by path order with `matched` before the cap; `WildcardCapLog` per source. | Compliant |
| FR-006 | `SessionDirectoryEntry.refusal` (relative, `**`, home or `/`, bare `*` at top); `Configuration.validate` throws `.sessionDirectoryEntry`; load drops with notes; the expander drops matches whose canonical path is home or `/`. | Compliant |
| FR-007 | `Account.decodeAdditionalDirectories` ignores a non-list value with one note. | Compliant |
| FR-008 | `SessionDirectoryResolver.resolve` (canonical dedup, main first); `LogDirectoryScanner.scan(targets:)` routes additional problems to `additionalNotes`; Codex adds issues for main homes only. | Compliant |
| FR-009 | Additional directories reach only `LogDirectoryScanner` (`projects`) and `CodexSessionSource` (`sessions`). | Compliant |
| FR-010 | `CodexLimitsSource.newestSnapshot(home:)` and `SubscriptionSource` read only the main directory. | Compliant |
| FR-011 | `Attributor` rules unchanged; the directory is used only in the subscription tie-breaker. | Compliant |
| FR-012 | `Attributor.accountId`: one main claim wins, else one additional claim, else Unassigned; `additionalByAccount` holds literal entries and matches. | Compliant |
| FR-013 | `OpenCodeSource.resolve` expands `*` entries; a matched folder without `opencode.db` is skipped silently; databases deduplicated by canonical path; caption in `AccountDirectoryText.openCodeCaption`. | Compliant |
| FR-014 | Invented paths only. | Compliant |
| FR-015 | README "How it works" and "Security and privacy", `docs/configuration.md` (with "Sessions from sandboxes"), `docs/development.md`. | Compliant |
| FR-016 | Claude Code: `directories read <d>` plus one `wildcard "<entry>"` line per entry; Codex: per-home lines for main and literal homes, one summary line per wildcard entry, `<h> home(s) read`. | Compliant |
| FR-017 | No capture step shows the Accounts tab or General > Sources. | Compliant |

## Edge cases

All fourteen are covered: a directory reached several ways, an additional directory equal to the main one, an entry equal to another account's main directory (main ranks first), a Vertex or OpenAI account with an empty main directory, more than 100 matches, a matched folder without a session tree, a missing literal entry, an unreadable additional directory, a relative entry, other glob characters as ordinary characters, `*` in a main directory field, a provider switch (list cleared), removing an account, and the demo build.

## Extra behavior (not in the spec)

- From the review, in contracts/directory-resolution.md: each wildcard level keeps at most 1000 candidates (logged once like the cap line); a bare `*` never lists a folder whose canonical path is the home folder or `/`; a `projects`, `sessions` or `opencode.db` link that leads out of an additional directory is skipped with a log line; an unchanged, readable OpenCode match is not opened again; listing errors carry their reason.

## Spec evolution candidates

- The level budget of 1000 and the link containment rule could move from the contract into FR-005 and FR-009 at the next spec refresh.

## Conclusion

The code matches the spec. The deep review found 0 Critical, 6 Important and 18 Minor findings over three rounds, and all 24 were fixed. The fixes added behavior the contract now describes (contracts/directory-resolution.md): per-directory claim keys instead of entries in the attribution fingerprint, a per-level budget of 1000 candidates, no bare `*` listing of another spelling of the home folder or `/`, links out of an additional directory not followed, and unchanged OpenCode matches not opened again. 2 Notable observations were captured to brainstorm/idea-inbox.md.

## Code Review Guide

These are the places where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Logs/WildcardExpander.swift`: the `*` matching and the expansion (base, per-level listing, folder check, home and `/` exclusion, sort, cap). Read with `WildcardExpanderTests` and the in-memory file system in `Tests/UsageCoreTests/InMemoryDirectoryFileSystem.swift`.
2. `Sources/UsageCore/Config/SessionDirectoryEntry.swift`: the refusal rules and their order, used by load, `validate` and Settings.
3. `Sources/UsageCore/Logs/SessionDirectoryResolver.swift`: main before additional, canonical dedup, `additionalByAccount` for the tie-breaker; then `Attribution.swift` (`accountId`, `claimKey(forDirectory:)`) with its users in `LogIndex.update` and the Codex `built` records.
4. `SessionLogSource.swift`, `LogDirectoryScanner.swift`, `CodexSessionSource.swift`, `OpenCodeSource.swift`: which problems become issues (main only) and which are log lines, and the log line shapes of FR-016.
5. Walkthrough:
   - Add `~/.codex` to a Codex subscription whose home is elsewhere and read the Codex log lines.
   - Add a wildcard entry, create and delete matched folders between refreshes.
   - Type `~/*/claude` into the list: Settings shows "Not applied".
   - Switch a token-based account's provider: the list empties.

## Deep Review Report

**Gate:** PASS (after fix round 3; CodeRabbit found nothing in the round 1 and round 2 changes, the last Codex finding was fixed and verified by `make test`)
**Details:** specs/035-additional-session-directories/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 2 | 1 | 0 | completed (FINDING-2 Notable merged into the CodeRabbit attribution finding, fixed) |
| Architecture & Idioms | 6 | 5 | 0 | completed (FINDING-3 Notable merged into the CodeRabbit attribution finding, fixed) |
| Security | 3 | 2 | 1 | completed (1 Notable) |
| Production Readiness | 5 | 4 | 1 | completed (1 Notable) |
| Test Quality | 9 | 8 | 1 | completed (1 Notable, resolved by rewording two test comments) |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| Round 1 re-review (internal) | 1 | 1 | 0 | completed |
| CodeRabbit (external) | 1 | 1 | 0 | completed (branch: 1; round 1 and round 2 changes: none) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 2 | 2 | 0 | completed (branch: none; round 1 changes: 1; round 2 changes: 1) |
| Test Suite (regression) | 0 | 0 | 0 | passed in every round |
| **Total** | **29** | **24** | **3** | 27 distinct findings after merging, 3 Notable remaining |

Final `make test`: 2067 UsageCore tests and 70 DemoMode tests passed. Final `make app-demo`: built.
