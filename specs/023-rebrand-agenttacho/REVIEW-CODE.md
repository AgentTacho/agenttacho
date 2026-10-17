# Code Review: Rebrand AgentMeter to AgentTacho

**Spec:** specs/023-rebrand-agenttacho/spec.md
**Date:** 2026-10-17
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% of the implementable requirements (23/23); 4 operational requirements pending in Phase 8**

- Functional Requirements: 23/23 implemented and compliant (FR-019, FR-020, FR-021 and the homepage part of FR-022 are maintainer operations, tasks T040 to T044, waiting for approval)
- Edge Cases: 10/10 (100%)
- Non-Functional: 3/3 (100%)

Evidence: `make test` 1450 tests in 137 suites pass (19 new: `LegacyDataMoveTests`, `PathsTests`, `RunningInstanceTests` additions), `make test-release` 224 pass (16 new: site deploy, release title, `SITE_REPO` defaults, tap rename, name check), `make app` and `make dmg` build `AgentTacho.app` and `AgentTacho-0.4.1-dev.dmg`.

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 display name, bundle name, executable, `AgentTacho.app` | `Resources/Info.plist`, `Package.swift` (target `AgentTacho`), `build-app.sh` `EXECUTABLE`, `lib.sh` `APP` | Compliant |
| FR-002 user-facing texts, `User-Agent` | `UpdateState`, `UpdateBlockReason`, `BarPresentation.placeholder`, `CredentialAlert`, `DropdownView`, `AboutSettingsTab`, `SingleInstance`; `UpdateClient` and `CodexUsageClient` send `AgentTacho/<version>` | Compliant |
| FR-003 bundle identifier and derived names | `dev.rhuss.agenttacho` in Info.plist and `build-app.sh`; `UpdateOutcome.folderName`; cask `uninstall quit` and `zap`; `ConfigurationLoadNotes` key `agenttacho.configurationLoadNotes` | Compliant |
| FR-004 Info.plist keys | `AgentTacho*` keys in `build-app.sh`, `AppVersionInfo`, `InstallEnvironment`, with tests on both sides | Compliant |
| FR-005 app links, sponsor unchanged | `AppLinks.repository` `AgentTacho/agenttacho`, `#security-and-privacy`; `sponsor` stays `github.com/sponsors/rhuss` | Compliant |
| FR-006 asset names new, images unchanged | `git mv` of every icon file and the asset catalog; 71 binary renames are 100% identical; `Contents.json` file names updated | Compliant |
| FR-007 new folders | `Paths` (`configDirectoryURL`, config, prices, log, last good under `agenttacho`), `PathsTests` | Compliant |
| FR-008 one-time copy, only without the configuration folder, after FR-012, before loading | `LegacyDataMove.run` called in `AppModel.init(paths:)` after the log and before `ConfigStore`; `SingleInstance.ensure()` runs earlier in `AgentTachoApp.init()`; logs not copied (test) | Compliant |
| FR-009 nothing changed in the old folders | `LegacyDataMove` only reads legacy URLs; every test compares a recursive snapshot (bytes and modes) before and after | Compliant |
| FR-010 never a partial file, log per failure | temporary file in the destination folder, then move; removed on error (`aFailedMoveIntoPlaceRemovesTheTemporaryFile`, `anUnwritableDestination...`, `anUnreadableLegacyFile...`) | Compliant |
| FR-011 log of the copied files, once | `LegacyDataMove.logLines`, source `move`; folder created after any `.moved`, so later starts give `.skipped` | Compliant |
| FR-012 running AgentMeter treated as another copy | `RunningInstance.others(from:ownPID:bundleIdentifiers:)`, `appName`; `SingleInstance` queries both identifiers and names the other app; quit exits before `AppModel` exists | Compliant |
| FR-013 DMG name, volume, backgrounds, `release-info.json`, update check | `dmg_filename`, `make-dmg.sh` volume `AgentTacho`, `render-dmg-backgrounds.swift`, `ReleaseEvaluator` expects `AgentTacho-<v>.dmg`; checked on the built DMG | Compliant |
| FR-014 release title, notes, install command | `release.sh` title `AgentTacho $short_version`; `lib.sh` notes with `brew install --cask rhuss/tap/agenttacho`; README | Compliant |
| FR-015 defaults, tap unchanged, notary profile | `release_defaults`: `GH_REPO` `AgentTacho/agenttacho`, `TAP_REPO` unchanged, `NOTARY_PROFILE` `agenttacho-notary`; README "Notarization profile (once)" | Compliant |
| FR-016 cask, rename entry, removal, idempotent | `packaging/homebrew/agenttacho.rb.tmpl` equals the contract; `update-cask.sh` removes `Casks/agentmeter.rb`, merges `cask_renames.json`, one commit; tests for first run, kept entries, later runs, no-op | Compliant |
| FR-017 Homebrew detection and command | `HomebrewDetector.caskName`/`appName`, `UpdateState.homebrewCommand` | Compliant |
| FR-018 site deploy after publish, before cask, warning only | `release.sh` step guarded by `--latest` and `GH_REPO = OFFICIAL_GH_REPO`; tests for order, override, older tag, failure with status 0 | Compliant |
| FR-019 first release 0.5.0 | T043 | Pending (operation) |
| FR-020 transfer before merge | T040, needs approval | Pending (operation) |
| FR-021 redirect checks, `origin` | T041 | Pending (operation) |
| FR-022 homepage, README warning | README warning written; homepage is T041 | Partly pending (operation) |
| FR-023 README and AGENTS.md, former name, moving instructions | README intro "(formerly AgentMeter)", "Moving from AgentMeter" with the steps, the folders and how to repeat the copy; AGENTS.md | Compliant |
| FR-024 security section | new folders, update URL, temporary folder, the AgentMeter row in "What it reads" and the one-time-read paragraph in "What it writes" | Compliant |
| FR-025 doc comments, log texts, script output | renamed throughout; historical spec references keep their numbers and `specs/001-agentmeter` | Compliant |
| FR-026 name check | `scripts/release/tests/test_names.sh` with `names-allowlist.txt`, `names: ok (115 allowed matches)` | Compliant |
| FR-027 copy is silent | no UI call in `LegacyDataMove` or its caller; only log lines | Compliant |

### Edge Cases

| Case | Handling | Status |
|------|----------|--------|
| Both old and new configuration exist | `.skipped` when the configuration folder exists (`anExistingEmptyConfigurationFolderSkipsTheMove`) | Compliant |
| Carried-over file unreadable or invalid | byte copy; unreadable source is a failure for that file only; content checked by the stores | Compliant |
| Copy fails half way | temporary file removed, failure logged, folder created so no retry; README says how to repeat | Compliant |
| Configuration names AgentMeter's folders | files copied as they are, no rewrite | Compliant |
| Notification permission and launch at login | README moving steps 3 and 4 | Compliant |
| AgentMeter and AgentTacho both run | FR-012 alert | Compliant |
| Credentials | reading unchanged (`SecurityToolCredentialReader`) | Compliant |
| Development and update-test builds | `make app` builds `AgentTacho.app`; `AgentTachoUpdateSource` key and `-DAGENTTACHO_UPDATE_TEST` flag, tests in `test_build_scripts.sh` | Compliant |
| Newer AgentMeter release | none; cask renamed | Compliant |
| Spec 022's worktree | superseded; its site deploy requirement is FR-018 | Compliant |

### Non-Functional

| Requirement | Status |
|-------------|--------|
| Logic in `UsageCore`, test first (AGENTS.md) | Compliant: `LegacyDataMove` and `RunningInstance` changes in `UsageCore`, tests written and failing first; `App.swift` and `SingleInstance` only call them |
| No em or en dash | Compliant: diff and commit messages scanned (one older en dash in a touched icon README replaced) |
| README "Security and privacy" kept true in the same change | Compliant (FR-024) |

### Extra Features (Not in Spec)

#### Stricter name check
**Location:** `scripts/release/tests/test_names.sh`
**Description:** each allowlist pattern is removed from the matching line and the rest must be clean, so an allowed phrase cannot hide another use on the same line.
**Assessment:** Helpful. **Recommendation:** added to `contracts/name-check.md` (done).

#### Replacing an existing destination file
**Location:** `LegacyDataMove.copy`
**Description:** if a destination file already exists while the configuration folder is missing, it is replaced as a whole.
**Assessment:** Helpful, keeps "copy" semantics. **Recommendation:** added to `contracts/legacy-data-move.md` (done).

## Spec Evolution Applied

- Notarized DMG title in the rounded **bold** system font instead of semibold, because bold matches the painted weight (research R3 and T032 updated).
- Name check semantics and the extra allowlist files (`LegacyDataMove.swift`, `App.swift`, `PathsTests.swift`) recorded in `contracts/name-check.md`.

## Recommendations

### Critical (Must Fix)
- None.

### Before merge (maintainer)
- [ ] T022: quickstart Q3 on this Mac (stops the running AgentMeter) and Q2 (open the app).
- [ ] T040, T041: transfer and rename on GitHub, redirect checks, `origin`, homepage (FR-020 to FR-022).

## Deep Review

The deep review (review-findings.md) passed after two fix rounds: 5 Important and 30 Minor findings fixed, 6 Notable recorded. It added one requirement change, FR-015's stop for a release without the notarization profile. After it, `make test` runs 1467 tests and `make test-release` 229.

## Conclusion

The implementation matches the spec for every requirement that code can satisfy. The remaining requirements are GitHub and release operations that the spec puts behind the maintainer's approval.
