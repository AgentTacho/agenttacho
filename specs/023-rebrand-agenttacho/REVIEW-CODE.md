# Code Review: Name the app AgentTacho

**Spec:** specs/023-rebrand-agenttacho/spec.md
**Date:** 2026-10-17
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% of the implementable requirements (16/16); FR-020 done as a maintainer operation; FR-019 pending with the 0.5.0 release**

- Functional Requirements: 16/16 implemented and compliant (FR-019 is checked with the 0.5.0 release, tasks T043 and T044)
- Edge Cases: 4/4 (100%)
- Non-Functional: 3/3 (100%)

Evidence: `make test` and `make test-release` pass, `make app` and `make dmg` build `AgentTacho.app` and `AgentTacho-0.4.1-dev.dmg`.

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 display name, bundle name, executable, `AgentTacho.app` | `Resources/Info.plist`, `Package.swift` (target `AgentTacho`), `build-app.sh` `EXECUTABLE`, `lib.sh` `APP` | Compliant |
| FR-002 user-facing texts, `User-Agent` | `UpdateState`, `UpdateBlockReason`, `BarPresentation.placeholder`, `CredentialAlert`, `DropdownView`, `AboutSettingsTab`, `SingleInstance`; `UpdateClient` and `CodexUsageClient` send `AgentTacho/<version>` | Compliant |
| FR-003 bundle identifier and derived names | `dev.rhuss.agenttacho` in Info.plist and `build-app.sh`; `UpdateOutcome.folderName`; cask `uninstall quit` and `zap`; `ConfigurationLoadNotes` key `agenttacho.configurationLoadNotes` | Compliant |
| FR-004 Info.plist keys | `AgentTacho*` keys in `build-app.sh`, `AppVersionInfo`, `InstallEnvironment`, with tests on both sides | Compliant |
| FR-005 app links, sponsor link | `AppLinks.repository` `AgentTacho/agenttacho`, `#security-and-privacy`; `sponsor` is `github.com/sponsors/rhuss` | Compliant |
| FR-006 asset names, images unchanged | `git mv` of every icon file and the asset catalog; 71 binary moves are 100% identical; `Contents.json` file names updated | Compliant |
| FR-007 data folders | `Paths` (config, prices, log, last good under `agenttacho`), `PathsTests` | Compliant |
| FR-013 DMG name, volume, backgrounds, `release-info.json`, update check | `dmg_filename`, `make-dmg.sh` volume `AgentTacho`, `render-dmg-backgrounds.swift`, `ReleaseEvaluator` expects `AgentTacho-<v>.dmg`; checked on the built DMG | Compliant |
| FR-014 release title, notes, install command | `release.sh` title `AgentTacho $short_version`; `lib.sh` notes with `brew install --cask rhuss/tap/agenttacho`; README | Compliant |
| FR-015 defaults, tap, notary profile | `release_defaults`: `GH_REPO` `AgentTacho/agenttacho`, `TAP_REPO` `rhuss/homebrew-tap`, `NOTARY_PROFILE` `agenttacho-notary`; a Developer ID release stops without the profile unless `ALLOW_UNNOTARIZED=1`; README "Notarization profile (once)" | Compliant |
| FR-016 cask `agenttacho` in the tap | `packaging/homebrew/agenttacho.rb.tmpl` equals the contract; `update-cask.sh` writes `Casks/agenttacho.rb` in one commit and nothing else; tests for an update, kept tap content and a no-op second run | Compliant |
| FR-017 Homebrew detection and command | `HomebrewDetector.caskName`/`appName`, `UpdateState.homebrewCommand` | Compliant |
| FR-018 site deploy after publish, before cask, warning only | `release.sh` step guarded by `--latest` and `GH_REPO = OFFICIAL_GH_REPO`; tests for order, override, older tag, failure with status 0 | Compliant |
| FR-019 first release 0.5.0 | T043 | Pending (after the merge) |
| FR-020 repository and homepage | `AgentTacho/agenttacho`, homepage `https://agenttacho.github.io`, `origin` set (T040, T041) | Done (operation) |
| FR-023 README and AGENTS.md | README title, intro, download and Homebrew lines; AGENTS.md | Compliant |
| FR-024 security section | data folders, update URL, temporary folder | Compliant |
| FR-025 doc comments, log texts, script output | AgentTacho throughout; references to other specs keep their numbers | Compliant |

### Edge Cases

| Case | Handling | Status |
|------|----------|--------|
| Notification permission and launch at login | asked and set per bundle identifier by macOS | Compliant |
| Credentials | reading unchanged (`SecurityToolCredentialReader`) | Compliant |
| Development and update-test builds | `make app` builds `AgentTacho.app`; `AgentTachoUpdateSource` key and `-DAGENTTACHO_UPDATE_TEST` flag, tests in `test_build_scripts.sh` | Compliant |
| Release without the notarization profile | stops before building (FR-015), tests in `test_release_flow.sh` | Compliant |

### Non-Functional

| Requirement | Status |
|-------------|--------|
| Logic in `UsageCore`, test first (AGENTS.md) | Compliant: update names live in `UsageCore`, tests updated first |
| No em or en dash | Compliant: diff and commit messages scanned (one older en dash in a touched icon README replaced) |
| README "Security and privacy" kept true in the same change | Compliant (FR-024) |

## Spec Evolution Applied

- Notarized DMG title in the rounded **bold** system font instead of semibold, because bold matches the painted weight (research R3 and T032 updated).
- FR-015 gained the stop for a Developer ID release without the notarization profile (deep review).

## Recommendations

### Critical (Must Fix)
- None.

## Deep Review

The deep review (review-findings.md) passed after two fix rounds. It added one requirement change, FR-015's stop for a release without the notarization profile.

## Conclusion

The implementation matches the spec for every requirement that code can satisfy. The repository settings are done; the 0.5.0 release follows the merge.
