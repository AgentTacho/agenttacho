# Code Review: Settings Sidebar and Per-Account Directories

**Spec:** specs/034-settings-sidebar-directories/spec.md
**Date:** 2026-10-22
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% (16 of 16 functional requirements, 10 of 10 edge cases)**

- Functional requirements: 16 of 16 compliant (FR-001 to FR-015 with FR-006a). FR-014's website part (the site's privacy copy) and FR-015 (screenshot check) are outside the app code; the spec's assumption that no screenshot shows the General or Accounts tab holds (`scripts/screenshots/capture.sh` selects only the Menu Bar and Prices tabs).
- Edge cases: 10 of 10.
- Acceptance scenarios: US1 1 to 9, US2 1 to 8 and US3 1 to 3 are traced to code. The sidebar, the page switching and the "Usage source" section are SwiftUI only and are checked in the walkthrough; their titles, order, captions and prompts are tested in UsageCore (`GeneralSettingsPageTests`, `AccountDirectoryTextTests`).
- Success criteria: SC-001 by code (every old option sits on exactly one page), SC-002 by code (no global list left), SC-003 and SC-004 by tests, SC-005 by search (`rg cc-deck Sources Tests docs README.md` finds nothing).

The spec has no `## Constants` section, so the constants check was skipped.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `GeneralSettingsPage` (six cases, titles, system images); `GeneralSettingsTab` with a 170 pt `.sidebar` `List` next to the page. | Compliant |
| FR-002 | `RefreshSettingsPage`, `AppearanceSettingsPage`, `WeeklyWindowSettingsPage`, `NotificationSettingsPage`, `SourcesSettingsPage`, `StartupSettingsPage`; texts moved unchanged, "Display" renamed "Appearance", "Launch" and "Updates" merged into "Startup". | Compliant |
| FR-003 | `@AppStorage(GeneralSettingsPage.defaultsKey)`; `GeneralSettingsPage(stored:)` falls back to Refresh. | Compliant |
| FR-004 | Every page binds the same `draft`; apply, undo and "Not applied" are untouched. | Compliant |
| FR-005 | Tabs and the 720 by 560 window are unchanged. | Compliant |
| FR-006 | "Claude Code directory" label and `AccountDirectoryText.subscriptionCaption`; Codex caption without the "more than one" sentence. | Compliant |
| FR-006a | `SubscriptionSettings.credentialDirectory` and `CodexSubscriptionSettings.codexHome` return the default for a blank entry; sessions, login and tie-breaker use them. | Compliant |
| FR-007 | `TokenBasedSettings.enteredSessionDirectory` with a provider `didSet`; `claudeCodeDirectory` / `codexHome` decoded leniently with load notes, written only when not blank; "Usage source" section between "Token-based" and "Budget". | Compliant |
| FR-008 | `Account.agentDirectory(for:)` feeds `SessionLogSource` (only `projects/**`) and `CodexSessionSource` (only `sessions/**`); canonical dedup; no credential or network path reaches a token-based directory. | Compliant |
| FR-009 | `Attributor` unchanged; a Vertex directory adds sessions without joining the subscription tie-breaker. | Compliant |
| FR-010 | No Claude Code or Codex directory list in Settings. | Compliant |
| FR-011 | `LegacyDirectoryNotes.notes` with the contract's default, covered and generic rows and the not-a-list note. | Compliant |
| FR-012 | The legacy keys are not `CodingKeys`; tests check the saved text. | Compliant |
| FR-013 | Invented paths in prompts, captions, docs and tests. | Compliant |
| FR-014 | README "How it works" and "Security and privacy", docs/configuration.md, docs/development.md, docs/installation.md, docs/usage.md. | Compliant |
| FR-015 | No capture step shows the changed tabs. | Compliant |

## Edge cases

All ten are covered: two accounts on one directory (read once), a directory equal to the default, a Vertex account used with OpenCode only, a missing account directory (no source error), equivalent spellings, removing an account, switching the provider, an empty subscription directory, a hand-edited token-based directory, and the demo build.

## Extra behavior (not in the spec)

- From the review: a blank subscription directory is compared as entered in the duplicate check, so a file that loaded before the upgrade still loads, with a load note when it shares the default with another account. Settings does not let an edit create that state, but keeps a loaded one editable and undoable. contracts/configuration.md and docs/configuration.md describe this.
- From the review: directories are read without surrounding whitespace, as the old lists' Add button trimmed them; the file keeps every directory field as typed.
- From the review: an account field holding the home directory or `/` adds no Claude Code directory, so a pause while typing `~/` never walks `~/projects`.

## Spec evolution candidates

- The blank-on-default load note and the Settings rule are in contracts/configuration.md but not in the spec's FR text; a spec refresh could add them next to FR-006a.

## Conclusion

The code matches the spec. The deep review found 0 Critical, 3 Important and 15 Minor findings over two fix rounds, and all 18 were fixed. 2 Notable observations were captured to brainstorm/idea-inbox.md.

## Code Review Guide

These are the places where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Config/Configuration.swift`: `SubscriptionSettings`, `CodexSubscriptionSettings` and `TokenBasedSettings` (entered value versus effective value, the provider `didSet`), `Account.decodeSessionDirectory` and `encode`, `Account.agentDirectory(for:)`, and the duplicate checks in `validate`. Read with `TokenBasedSessionDirectoryTests`, `TokenBasedDirectoryCodingTests` and `AccountDirectoryLookupTests`.
2. `Sources/UsageCore/Config/LegacyDirectoryNotes.swift` (the upgrade notes, FR-011) and `SharedDefaultDirectory.swift` (the blank-on-default note and Settings rule, FR-006a), with `LegacyDirectoryNotesTests` and `LegacyDirectoryConfigurationTests`.
3. `Sources/UsageCore/Logs/SessionLogSource.swift` and `CodexSessionSource.swift`: which directories are scanned, the canonical dedup and the home guard (FR-008).
4. `Sources/AgentTacho/SettingsView.swift` and `AccountSettingsView.swift`: the sidebar and the "Usage source" section; check them by hand in the demo build.
5. Walkthrough:
   - Click through the six pages, close Settings and reopen it on the same page.
   - Type a directory into a Vertex account, switch it to OpenAI and back.
   - Load a configuration with `logDirectories` and `codexHomes` and read Settings > Log.
   - Clear a Claude subscription's directory while another account uses `~/.claude`: Settings shows "Not applied".

## Deep Review Report

**Gate:** PASS (after fix round 2; CodeRabbit and Codex found nothing in the round 2 changes)
**Details:** specs/034-settings-sidebar-directories/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 3 | 2 | 1 | completed (1 Notable; FINDING-1 merged with Production) |
| Architecture & Idioms | 6 | 5 | 1 | completed (1 Notable) |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 2 | 2 | 0 | completed |
| Test Quality | 5 | 5 | 0 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| Round 1 re-review (internal) | 3 | 3 | 0 | completed |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch, round 1 and round 2 changes) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 1 | 1 | 0 | completed (branch: none; round 2: 1 undo finding, then clean) |
| Test Suite (regression) | 1 | 1 | 0 | 1 failure in round 1 (a test pinned the untrimmed path), then passed |
| **Total** | **21** | **19** | **2** | |

After merging duplicates and leaving out the test-suite row: 0 Critical, 3 Important (all fixed), 15 Minor (all fixed) and 2 Notable findings. The Notables were captured to brainstorm/idea-inbox.md.

MVP: Architecture & Idioms (6 findings).

Key fixes applied:

1. A configuration that loaded before spec 034 with a cleared subscription directory next to the default no longer fails validation; a load note explains the shared login, and Settings rejects creating that state while keeping a loaded one editable and undoable (098ed38, 2cd02c7; production, correctness, Codex).
2. Account directories are read without surrounding whitespace and saved as typed (098ed38, 2cd02c7; correctness).
3. A field holding `~` or `/` never makes a refresh walk `~/projects` (098ed38; production).
4. One provider-to-key mapping, one `Account.agentDirectory(for:)` rule for the scanners and the legacy notes, `LegacyDirectoryKey` as the coding key, the Settings field mapping in UsageCore (098ed38, 2cd02c7; architecture).
5. Tests for US3 scenario 3 with a subscription account, the Codex tie-breaker, the OpenAI blank key, SC-003 totals for an OpenAI home, symlink and `..` spellings, and the home guard (098ed38; test quality).

Post-fix spec coverage: 16 of 16 functional requirements verified.

Notable observations: 2 captured to brainstorm/idea-inbox.md (`legacy-notes-injected-paths`, `directory-vocabulary`).

Test results after fixes: `make test` passed (1954 + 70 tests), `make app-demo` built.
