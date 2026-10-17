# Implementation Plan: Rebrand AgentMeter to AgentTacho

**Branch**: `023-rebrand-agenttacho` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/023-rebrand-agenttacho/spec.md`

## Summary

Rename the app, its identifiers, data folders, release artifacts, Homebrew cask, repository and docs from AgentMeter to AgentTacho as a clean break (brainstorm 22). Two pieces of new logic carry the user across: a one-time, read-only copy of AgentMeter's `config.json`, `imported-prices.json` and `last-good.json` (`LegacyDataMove` in `UsageCore`), and the single-instance check extended to a running AgentMeter. Everything else is renaming, plus three release changes: the cask rename in the tap, the site deploy trigger (from spec 022), and a name check test that keeps the old name from creeping back. The notarized DMG background gets a title-less base so the title is rendered from text.

## Technical Context

**Language/Version**: Swift 5.10 (package tools), bash for release scripts, Python for `dmg-settings.py`

**Primary Dependencies**: SwiftUI, AppKit, ServiceManagement, Foundation; `gh`, `jq`, `git`, `hdiutil`, `dmgbuild` in the release scripts

**Storage**: JSON files in the user's home (`config.json`, `imported-prices.json`, `last-good.json`), a text log

**Testing**: Swift Testing via `make test`; bash release tests via `make test-release` (stubbed `gh`, local bare git repositories)

**Target Platform**: macOS 14+ on Apple Silicon

**Project Type**: desktop menu bar app with a core library and release tooling

**Performance Goals**: the one-time copy adds at most a few file copies at first launch; no change to refresh behavior

**Constraints**: never write to AgentMeter's folders (FR-009) or to the agents' files (AGENTS.md); README "Security and privacy" updated in the same change; no em or en dash anywhere

**Scale/Scope**: about 90 files name the app (715 lines outside specs); 4 new source or test files; 1 new release test

## Constitution Check

The constitution file is an unfilled template, so the gates come from AGENTS.md:

| Gate | Status |
|---|---|
| Build and test only through the Makefile | Pass: `make test`, `make test-release`, `make app`, `make backgrounds`, `make dmg` |
| Logic in `UsageCore`, covered by tests, test first | Pass: `LegacyDataMove` and the `RunningInstance` change live in `UsageCore` with tests written first; `SingleInstance` and `AppModel` only call them |
| Doc comments cite spec requirements | Pass: new code cites `spec 023 FR-0xx` |
| No em or en dash | Pass: enforced by review; the name check does not cover dashes |
| Read-only toward agents' files; README security section kept true | Pass: the move reads AgentMeter's own folders only and never writes there; the README section is updated in this change (FR-024) |

Re-check after design: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/023-rebrand-agenttacho/
├── spec.md
├── plan.md               # this file
├── research.md           # R1 to R9
├── data-model.md         # Paths, LegacyDataMove, RunningInstance, renamed identifiers
├── contracts/
│   ├── legacy-data-move.md
│   ├── release-and-tap.md
│   └── name-check.md
├── quickstart.md         # Q0 to Q7
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code (repository root)

```text
Package.swift                                  # package agenttacho, product and target AgentTacho
Sources/
├── UsageCore/
│   ├── Config/Paths.swift                     # new folders, legacy* URLs
│   ├── Config/LegacyDataMove.swift            # NEW: one-time copy (FR-008 to FR-011)
│   ├── RunningInstance.swift                  # bundle identifier set, appName (FR-012)
│   ├── AppLinks.swift                         # AgentTacho/agenttacho
│   ├── AppVersionInfo.swift                   # AgentTacho* Info.plist keys
│   ├── Config/ConfigurationLoadNotes.swift    # identifier
│   └── Update/                                # UpdateSource, ReleaseEvaluator (DMG name),
│                                              # HomebrewDetector, UpdateState, UpdateBlockReason,
│                                              # UpdateOutcome, UpdateClient (User-Agent)
└── AgentTacho/                                # git mv from Sources/AgentMeter
    ├── App.swift                              # AgentTachoApp; AppModel runs LegacyDataMove and logs it
    ├── SingleInstance.swift                   # queries own and legacy identifiers
    └── ...                                    # user-facing strings
Tests/UsageCoreTests/
├── LegacyDataMoveTests.swift                  # NEW
├── RunningInstanceTests.swift                 # legacy identifier cases
└── ...                                        # expectations and fixtures renamed
Resources/
├── Info.plist                                 # AgentTacho, dev.rhuss.agenttacho
├── dmg/background-notarized-base(.png|@2x.png)  # NEW: title-less artwork
└── icons/                                     # files and asset catalog renamed, images unchanged
packaging/homebrew/agenttacho.rb.tmpl          # git mv + new content
scripts/release/
├── lib.sh, build-app.sh, make-dmg.sh, notarize.sh, release.sh, update-cask.sh, dmg-settings.py
├── render-dmg-backgrounds.swift               # draws titles on both backgrounds
└── tests/
    ├── test_names.sh                          # NEW: name check (contracts/name-check.md)
    ├── names-allowlist.txt                    # NEW
    └── test_*.sh                              # expectations renamed; deploy and tap rename cases
README.md, AGENTS.md, docs/images/agenttacho-dropdown.png
```

**Structure Decision**: Keep the existing two-target layout; only the executable target is renamed. New logic goes to `UsageCore` per AGENTS.md.

## Implementation approach

1. **Tests first for the new logic**: `LegacyDataMoveTests` (contract cases), `RunningInstanceTests` for the legacy identifier and app names. Then `LegacyDataMove`, `Paths` and `RunningInstance`.
2. **Mechanical rename** in small, reviewable commits: (a) `git mv` of directories and files (target, icons, cask template, image); (b) `Package.swift`, Info.plist, Info.plist keys across `build-app.sh`, `AppVersionInfo`, `InstallEnvironment`; (c) user-facing strings; (d) update logic names (source, DMG name, cask, User-Agent, folder name); (e) test expectations and fixtures. Run `make test` after each.
3. **Wire the move and the alert**: `AppModel.init(paths:)` runs the move after the log exists and logs the outcome; `SingleInstance.ensure()` passes both identifiers.
4. **Release tooling**: defaults (`GH_REPO`, `SITE_REPO`, `NOTARY_PROFILE`, `SIGN_IDENTITY_NAME`, `APP_ICON`), names (DMG, volume, release title, notes), site deploy step, tap rename; tests first in `scripts/release/tests/`.
5. **Backgrounds**: create the title-less notarized base (research R3), extend `render-dmg-backgrounds.swift`, run `make backgrounds`, check both scales by eye.
6. **Name check**: `test_names.sh` and the allowlist; fix leftovers until it passes.
7. **Docs**: README (name, "formerly AgentMeter", moving instructions, security section, release section with notary profile and redirect warning, Homebrew commands), AGENTS.md, icon READMEs.
8. **Operations** (maintainer, research R9): transfer and rename on GitHub after approval, Q1 checks, merge, notary profile, `make release` 0.5.0, Q5 to Q7.

## Risks

| Risk | Mitigation |
|---|---|
| `brew upgrade` keeps `AgentMeter.app` after the cask rename | Verified in Q6; README tells users to delete it (R1) |
| Filled title band in the notarized background shows seams | Checked in Q4 at both scales; fallback is regenerating the artwork (R3) |
| Merge conflicts with `021-recover-stuck-offline` | Implement after 021 lands and rebase first (R9) |
| A missed string keeps the old name | `test_names.sh` fails `make test-release` (contracts/name-check.md) |
| Old GitHub path stops redirecting | README warns never to recreate `rhuss/agentmeter` (FR-022); Q1 checks before release |

## Complexity Tracking

No constitution violations.
