# Deep Review Findings

**Date:** 2026-10-27
**Branch:** 037-profile-account-matching
**Rounds:** 2 (initial review, fix round 1, re-review, fix round 2)
**Gate Outcome:** PASS
**Invocation:** quality-gate (speckit-spex-ship, review-code stage)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 8 | 8 | 0 |
| Minor | 20 | 15 | 5 |
| Notable | 3 | - | 3 |
| **Total** | **31** | **23** | **8** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR found) + 2 external tools (CodeRabbit, Codex)
**Agents failed:** none. Copilot skipped (disabled in config). cc-review not detected, built-in review used.

Fix commits: 961816d, 6700eaf (round 1), 7798b42 (round 2).

## Findings

### FINDING-1 (Important, fixed round 1)
- **File:** Sources/UsageCore/Logs/SessionProfile.swift (detect)
- **Category:** production-readiness
- **Source:** production-agent

**What is wrong:** Detection scanned the whole shape line once per candidate spelling; with wildcard matches (up to 100 per entry) and large prompt lines this multiplies to gigabytes of scanning on a full re-read.

**Why this matters:** Refresh time grows with candidates times line length inside the session source actor.

**How it was resolved:** `detect` finds each `/projects/` occurrence once and looks up the bytes ending there in spellings grouped by length; the boundary rule is unchanged. Detection also runs only on lines the parser does not take as usage records (FINDING-12).

### FINDING-2 (Important, fixed round 1)
- **File:** Sources/UsageCore/Logs/LogIndex.swift (candidate change)
- **Category:** production-readiness / correctness
- **Source:** production-agent (also reported by: coderabbit)

**What is wrong:** Any change of the candidate key re-read every file with an unnamed shape line, including when a sandbox wildcard match came or went. CodeRabbit reported the opposite gap: a newly configured directory that a named line also mentions makes the line ambiguous, but the file was not re-read.

**Why this matters:** Re-read storms on sandbox churn, and stale attribution after a configuration edit (FR-001).

**How it was resolved:** Entries track none and ambiguous shape lines separately. A candidate change re-reads: named profiles with changed claimants; files with a none line when any spelling was added; files with any shape line when a configured (non-wildcard) spelling was added; files with an ambiguous line when a spelling was removed; and (round 2) files whose named profile lost a spelling. A wildcard match that only appears in a line already named stays unnoticed until the file changes (documented in the code).

**External tool analysis (CodeRabbit):**
> Update candidate-change handling and FileIndexEntry match tracking so files are re-read when a shape line previously attributed to one configured directory becomes ambiguous after another directory is added. Preserve the existing re-read behavior for changed claimants and lines that already named none or multiple profiles.

### FINDING-3 (Important, fixed round 1)
- **File:** Sources/AgentTacho/AccountSettingsView.swift (MatchRuleFields)
- **Category:** architecture
- **Source:** architecture-agent (also: test-agent Notable)

**What is wrong:** The rule pop-up's items and transitions lived in the SwiftUI view while `MatchRule.isOffered` was used by tests only (constitution II).

**How it was resolved:** `MatchRule.choices(for:current:)`, `MatchRule.choosing(_:harness:lastCustom:)` and `MatchRuleChoice` in UsageCore, with table tests per harness; the view binds them.

### FINDING-4 (Important, fixed round 1)
- **File:** Sources/AgentTacho/AccountSettingsView.swift (`lastCustom`)
- **Category:** correctness
- **Source:** codex (also reported by: correctness-agent)

**What is wrong:** `@State lastCustom` carried over between accounts because the editor is not keyed by account, so choosing Custom on account B could fill in account A's field and text, which Settings then saves.

**How it was resolved:** `MatchRuleFields` gets `.id(accountId)` in the account editor.

**External tool analysis (Codex):**
> Switch account A's custom rule to a preset, select another token-based account B, then choose Custom. The editor hierarchy is not keyed by account ID, so SwiftUI retains `lastCustom` and copies A's field and text into B.

### FINDING-5 (Important, fixed round 1)
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift (profileCandidates)
- **Category:** correctness
- **Source:** codex

**What is wrong:** Two additional directories that are symlink aliases of one folder kept only the first spelling, so a shape line naming the second alias was not recognized (FR-002).

**How it was resolved:** `SessionDirectoryResolution.profileSpellings` lists every literal and matched spelling; the candidates search all of them. Test `everyAliasOfAnAdditionalDirectoryIsSearched`.

### FINDING-6 (Important, fixed round 1)
- **File:** Sources/UsageCore/Logs/SessionProfile.swift (Candidates.key)
- **Category:** correctness
- **Source:** codex

**What is wrong:** Replacing a directory spelling with another alias of the same folder changed the searches but not the key, so unnamed lines were not reconsidered until restart.

**How it was resolved:** The key includes every spelling; added spellings re-read files with none lines. Test `newAliasSpellingRereadsUnnamedFiles`.

### FINDING-7 (Important, fixed round 1)
- **File:** Tests/UsageCoreTests/LogIndexTests.swift
- **Category:** test-quality
- **Source:** test-agent

**What is wrong:** No end-to-end test of the P1 topology: three profile directories with `projects` symlinked to one shared folder, refreshed through `SessionLogSource`.

**How it was resolved:** `sharedProjectsFolderThroughTheSource` checks every record's account, the log's `profile named 3, none 0`, and `re-read 0 (0 bytes)` on the second refresh (SC-001, SC-005).

### FINDING-8 (Important, merged into FINDING-2)
CodeRabbit's named-to-ambiguous case; counted with FINDING-2 in the table above as a separate external finding. Test `newlyConfiguredDirectoryCanMakeANamedLineAmbiguous`.

### Minor findings fixed
- FINDING-9: `sawShapeLine` was dead state; now used by the configured-growth re-read rule (architecture).
- FINDING-10: unused `Rank: Comparable` removed (architecture).
- FINDING-11: stale caption doc of `additionalDirectoriesCaption` (architecture).
- FINDING-12: detection ran on every line twice per marker; now only on non-record lines (production).
- FINDING-13: stale "Vertex account"/"provider" doc comments in SessionLogSource, AccountSettingsView, IconDefaults (architecture).
- FINDING-14: unreachable `.openCode` arm in `tokenBasedCaption` now its own case (architecture).
- FINDING-15: `init(source provider:)` local name renamed (architecture).
- FINDING-16: overlap grouping used a debug description as key; now a Hashable struct (architecture).
- FINDING-17: late re-read bytes were not counted in the log line (production).
- FINDING-18: `symlinkedParentMatches` had a tautological assertion; now two profiles linked to one shared `projects` are told apart (test).
- FINDING-19: no LogIndex test for ambiguous lines; `ambiguousShapeLinesAreSkipped` (test).
- FINDING-20: `harnessMismatches` had no positive test; `harnessMismatchesFindsAWrongHarness` (test).
- FINDING-21: `profileCandidates` home and `/` exclusion and spellings untested; covered by the alias test (test).
- FINDING-22 (round 2): a removed spelling of a directory that keeps its claimants did not re-read files named through it; fixed in 7798b42 with `lostSpellingRereadsFilesThatNamedIt` (re-review).
- FINDING-23 (round 2): the shrink-ambiguous rule and late-read bytes had no test; `removedDirectoryLetsAnAmbiguousLineNameOne` and a `bytesRead` assertion (re-review).

## Remaining Findings (Minor, not blocking)

### FINDING-24
- **File:** Sources/UsageCore/Logs/LogIndex.swift (phase 2)
- **Category:** correctness
- **Source:** correctness-agent
A shape line that names no configured directory does not end the profile of an earlier named line in the same file. FR-001's "latest shape line" can be read either way; since a shape line without a memory path cannot be told from one naming an unconfigured directory, keeping the earlier profile was kept. Recorded as a spec clarification candidate in REVIEW-CODE.md.

### FINDING-25
- **File:** Sources/UsageCore/Config/MatchRule.swift (`matches`)
- **Category:** architecture
- **Source:** architecture-agent
`MatchRule.matches` checks the harness for presets but not custom rules; callers check it. Left as is: both callers enforce FR-008 and are tested.

### FINDING-26
- **File:** Sources/UsageCore/Logs/SessionProfile.swift, Attribution.swift
- **Category:** architecture
- **Source:** architecture-agent
`Candidates.standardized` and `Attributor.canonical` repeat the trailing-slash loop. Small duplication, left for a later cleanup.

### FINDING-27
- **File:** Sources/UsageCore/Logs/Attribution.swift:158
- **Category:** architecture
- **Source:** architecture-agent
A subscription's profile additional directories fall back to the tie-breaker map when the caller passes none; token-based accounts do not. The only production caller passes both maps; the fallback serves older tests.

### FINDING-28
- **File:** Sources/AgentTacho/AccountSettingsView.swift (overlap warning)
- **Category:** production-readiness
- **Source:** production-agent
The overlap warning resolves symlinks of a few directories during view rendering. Microseconds on local disks; a stalled network volume could block. Left for a later change that caches overlaps per draft.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Logs/SessionProfile.swift (detect)
- **Category:** security
- **Source:** security-agent
- **Description:** Prompt text (for example a CLAUDE.md that mentions another profile's `<dir>/projects/`) can name a profile or make a line ambiguous.
- **Rationale:** Follows FR-001; no confidentiality impact. Captured to brainstorm/idea-inbox.md.

### NOTABLE-2
- **File:** Sources/UsageCore/Logs/LogIndex.swift (FR-012 counts)
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** The counts use the profile in effect, so an open session keeps counting as named after a format change.
- **Rationale:** A third count would show a format change sooner. Captured to brainstorm/idea-inbox.md.

### NOTABLE-3
- **File:** Sources/AgentTacho/AccountSettingsView.swift
- **Category:** test-quality
- **Source:** test-agent
- **Description:** Pop-up composition was untestable in the view. Resolved together with FINDING-3.

## Post-Fix Spec Coverage

Fix rounds removed code (`occursAtBoundary`, the view's `Choice` enum, the string overlap key, `sawUnnamedShapeLine`); each was replaced, not dropped.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 | SessionProfile.detect, LogIndex phase 2 and re-read rules | ✓ |
| FR-002 | Candidates (expanded and resolved spellings, every alias) | ✓ |
| FR-003 | Attributor.accountId, ruleStep | ✓ |
| FR-004 | detect returns only the canonical directory | ✓ |
| FR-007, FR-015 | MatchRule.choices/choosing, MatchRuleFields | ✓ |
| FR-012 | LogIndexStats profile counts, statsLine | ✓ |
| FR-013 | Configuration.matchOverlaps (Hashable key) | ✓ |
| All other FRs | unchanged by the fix rounds | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (2152 + 71) |
| 1 (first run) | make test | 2 | 1 | `candidateChangeRereadsOnlyAffectedFiles` built a configured entry for what it calls a wildcard match; marked `isWildcardMatch: true` |
| 1 | make test | 0 | 0 | passed (2159 + 72) |
| 2 | make test | 0 | 0 | passed (2161 + 72) |

`make test-release`: 266 passed, 0 failed (baseline, round 1, round 2). `make app-demo`: built `build/AgentTacho Demo.app` (round 1 and round 2).
