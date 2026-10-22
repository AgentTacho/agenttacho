# Deep Review Findings

**Date:** 2026-10-22
**Branch:** 034-settings-sidebar-directories
**Rounds:** 2
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 15 | 15 | 0 |
| Notable | 2 | - | 2 |
| **Total** | **20** | **18** | **2** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR), plus 2 external tools (CodeRabbit, Codex). Copilot is disabled in config.
**Agents failed:** none.

The counts are after merging duplicates: Production FINDING-1 and Correctness FINDING-1 report the same upgrade lock-out (FINDING-1 below). Round 1 fixed FINDING-1 to FINDING-14 (098ed38); its re-review (a combined internal agent, CodeRabbit, Codex) found FINDING-15 to FINDING-18, fixed in round 2 (2cd02c7). CodeRabbit and Codex found nothing in the round 2 changes.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift (validate, subscription and Codex subscription duplicate checks)
- **Category:** production-readiness
- **Source:** production-readiness-agent (also reported by: correctness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The duplicate checks compared effective directories, so a blank `credentialDirectory` (now `~/.claude`, FR-006a) next to an account naming `~/.claude` collided. On `main` the same file was valid: clearing the field wrote `""`, and `expand("")` did not collide. The same held for `codexHome`.

**Why this matters:** `ConfigStore` rejects a file that fails validation and falls back to the default configuration. A user upgrading with such a file would lose every account in the app until the file is edited by hand, and a later save from Settings could write the default over it.

**How it was resolved:** Validation compares a blank entry as entered, as before spec 034, so such a file still loads. Two blank entries and two spellings of the same directory still collide. A new load note names the blank account and the account it shares the default with (`Configuration.blankDirectoriesOnSharedDefault`), and Settings rejects an edit that creates this state (FINDING-16). contracts/configuration.md and docs/configuration.md describe the rule. Tests: `blankEntryNextToTheDefaultStaysValid`, `blankEntryNextToTheDefaultLoadsWithANote`, `blankSubscriptionSharingTheDefaultIsNoted`.

### FINDING-2
- **Severity:** Important
- **Confidence:** 88
- **File:** Tests/UsageCoreTests/LegacyDirectoryNotesTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** No test had a Claude subscription as the account covering a `logDirectories` entry: a Vertex account always matched first, or the default row won.

**Why this matters:** US3 scenario 3 is most common for subscription profile directories that users also listed globally. A regression would tell them to set a directory they already set.

**How it was resolved:** `coveredBySubscriptionAccount` (notes level) and `entryCoveredBySubscriptionAccount` (decode level) assert the "already covered by account \"Max\"" note and that the directory is still read.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/AccountSettingsView.swift, Sources/UsageCore/Logs/SessionLogSource.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The new Vertex directory field auto-applies after a pause. A pause at `~` or `~/` added the home directory as a Claude Code directory, so a refresh walked `~/projects/**/*.jsonl`.

**Why this matters:** A large `~/projects` tree makes that refresh slow and can count stray JSONL files.

**How it was resolved:** `SessionLogSource.directories` never adds the home directory or `/` from an account field. Test: `homeAndRootAreNeverAClaudeCodeDirectory`.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/Configuration.swift (AccountDirectory, TokenBasedSettings.sessionDirectory)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** A directory pasted with surrounding whitespace was read as typed, so it named a path that does not exist. The old global lists trimmed their entries.

**Why this matters:** A directory moved from the old list onto an account could silently read nothing (SC-003), and the legacy note would not see it as covered.

**How it was resolved:** `AccountDirectory.trimmed` and `effective` trim for reading; the field and the file keep the entry as typed. The legacy notes compare trimmed paths. Tests: `surroundingWhitespaceIsNotRead`, `typedEntryIsReturnedTrimmed`, `coveredThroughSymlinkAndDotDot`.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Config/Configuration.swift (Provider.sessionDirectoryKey, Account.sessionDirectoryKey(for:), decodeSessionDirectory), AccountDirectoryText.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The provider-to-key mapping was written three times, and `Provider.defaultSessionDirectory` had no production caller.

**Why this matters:** A key renamed in one place would pass the tests while the file format changed.

**How it was resolved:** The private coding key is built from `Provider.sessionDirectoryKey`; the other provider's key comes from iterating `Provider.allCases`. `tokenBasedCaption` interpolates `defaultSessionDirectory`.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Config/LegacyDirectoryNotes.swift, Configuration.swift (accountClaudeCodeDirectories, accountCodexHomes)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The rule "which account owns a Claude Code directory or Codex home" was written twice, once for the scanners and once for the legacy notes.

**Why this matters:** The notes could disagree with what is scanned after a later change.

**How it was resolved:** `Account.agentDirectory(for:)` is the single rule; both lookups and the notes use it.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift, LegacyDirectoryNotes.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** Two parallel enums (`LegacyCodingKeys`, `LegacyDirectoryKey`) and three `key == .logDirectories ? A : B` ternaries.

**How it was resolved:** `LegacyDirectoryKey` is the `CodingKey` and `CaseIterable`, with `harness`, `defaultDirectory` and `fieldLabel`.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/LegacyDirectoryNotes.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** `notes(key:entries:readable:...)` carried one fact in two parameters.

**How it was resolved:** `readable` is gone; nil `entries` means the value is not a list of strings.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/AccountSettingsView.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The "empty field stores no directory" rule lived in a view-level `Binding` adapter, untested.

**How it was resolved:** `TokenBasedSettings.sessionDirectoryField` in UsageCore, bound with `$settings.sessionDirectoryField`. Test: `fieldTextMapsEmptyToNoDirectory`.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/AttributionTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** FR-006a's tie-breaker rule was tested only for Claude, not for a blank Codex home.

**How it was resolved:** `blankCodexHomeTiesOnTheDefault`.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/ConfigurationTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The "blank own key gives no note and is not written" rule was tested only for Vertex.

**How it was resolved:** `blankValueIsOmittedOnSave` runs for both providers.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/CodexSessionSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The SC-003 test for an OpenAI home checked only a record count, and its attribution check was vacuous with one OpenAI account.

**How it was resolved:** `openAIAccountHomeCountsWithTheSameTotals` compares account, model, tokens and cost from the home with the same file in `~/.codex`.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/LegacyDirectoryNotesTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The notes' canonical comparison was not tested with a symlink or a `..` spelling.

**How it was resolved:** `coveredThroughSymlinkAndDotDot`.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/LegacyDirectoryNotes.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 098ed38)

**What is wrong:** The test `blankEntriesGiveNoNote` passed `entries: nil, readable: true`, a combination that meant nothing (see FINDING-8).

**How it was resolved:** Removed with the parameter; nil entries are covered by `unreadableValueGivesOneNoteForTheKey`.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Config/Configuration.swift (Account.encode)
- **Category:** correctness
- **Source:** re-review agent (round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2, 2cd02c7)

**What is wrong:** After FINDING-4, a token-based directory was saved trimmed while the subscription fields were saved as typed, against the updated contract.

**How it was resolved:** The encoder writes the entered value unless it is blank. Test: `directoriesAreSavedAsTyped`.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift (validate), Sources/AgentTacho/SettingsView.swift (applyNow)
- **Category:** correctness
- **Source:** re-review agent (round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2, 2cd02c7)

**What is wrong:** The FINDING-1 fix also let a Settings edit clear a subscription directory next to an account on the default, silently creating two accounts on one login (and two usage requests per refresh with the same token).

**How it was resolved:** `Configuration.checkNoNewSharedDefault(comparedTo:)` rejects an edit that creates the state; Settings shows it as "Not applied". A configuration loaded in that state stays editable. Test: `settingsEditMayNotCreateASharedDefault`.

### FINDING-17
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/LegacyDirectoryNotes.swift
- **Category:** architecture
- **Source:** re-review agent (round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2, 2cd02c7)

**What is wrong:** The shared-default note lived in the legacy notes and used the legacy keys as harness descriptors, so removing a legacy key would have dropped it.

**How it was resolved:** `SharedDefaultDirectory.swift` holds the check, the note and the Settings rule, keyed by harness; `Account.enteredSubscriptionDirectory(for:)` sits next to `agentDirectory(for:)`.

### FINDING-18
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/SettingsView.swift (applyNow)
- **Category:** external
- **Source:** codex (round 2 re-review)
- **Round found:** 2
- **Resolution:** fixed (round 2, 2cd02c7)

**What is wrong:** The first version of the FINDING-16 check compared only with the applied configuration, so undoing an edit back to a loaded shared-default state was rejected.

**How it was resolved:** The check also accepts states held by the undo target (`comparedTo: [applied, undoTarget]`). The test covers an undo back to the loaded state.

**External tool analysis (Codex):**
> When a loaded configuration has one blank subscription directory alongside another account using the default, changing the blank directory or removing either account saves successfully. Undo then restores the original configuration, but this check compares it against `applied`, where sharing no longer exists, and rejects the restoration as a new conflict. Honor the trusted `undoTarget` when checking grandfathered states so existing configurations remain undoable.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Config/Configuration.swift (noteDirectories)
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** The legacy notes expand `~` with a fresh `Paths()`, not the `Paths` the store and sources were built with.
- **Rationale:** Identical in production; with an injected home the notes could disagree with what is scanned.

### NOTABLE-2
- **File:** Sources/UsageCore (doc comments in Notifications, Snapshot, Logs)
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The UI says "Claude Code directory", many comments still say "credential directory".
- **Rationale:** Matches the stored key, but mixes vocabulary.

Both were captured to brainstorm/idea-inbox.md.

## Post-Fix Spec Coverage

The fix rounds removed code only in refactors (duplicate mappings, the `readable` parameter, the view-level binding). Every FR still has its implementation:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 to FR-005 | `GeneralSettingsPage`, `GeneralSettingsTab` and its six pages | ✓ |
| FR-006, FR-006a | `AccountDirectoryText`, `SubscriptionSettings.credentialDirectory`, `CodexSubscriptionSettings.codexHome` | ✓ |
| FR-007 | `TokenBasedSettings` (provider `didSet`, `sessionDirectoryField`), `Account.decodeSessionDirectory` and `encode`, "Usage source" section | ✓ |
| FR-008 | `Account.agentDirectory(for:)`, `accountClaudeCodeDirectories`, `accountCodexHomes`, `SessionLogSource`, `CodexSessionSource` | ✓ |
| FR-009 | `Attributor` unchanged; token-based directories add sessions only | ✓ |
| FR-010 | No Claude Code or Codex list in `SourcesSettingsPage` | ✓ |
| FR-011, FR-012 | `LegacyDirectoryKey`, `LegacyDirectoryNotes.notes`, `Configuration.noteDirectories`; keys not in `CodingKeys` | ✓ |
| FR-013, FR-014 | Invented paths; README, docs | ✓ |
| FR-015 | No screenshot shows the changed tabs (spec assumption) | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 1 (first run) | 1 | `typedEntryIsReturnedAsTyped` pinned the untrimmed path; updated to the FINDING-4 rule |
| 1 | make test | 0 | 0 | passed (1952 + 70 tests) |
| 1 | make app-demo | 0 | 0 | built |
| 2 | make test | 0 | 0 | passed (1954 + 70 tests) |
| 2 | make app-demo | 0 | 0 | built |
