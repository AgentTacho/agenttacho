# Implementation Plan: Name the app AgentTacho

**Branch**: `023-rebrand-agenttacho` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/023-rebrand-agenttacho/spec.md`

## Summary

Give the app, its identifiers, data folders, release artifacts, Homebrew cask, repository and docs the name AgentTacho (brainstorm 22). Most of the work is naming across the sources, resources, scripts and tests. Two release changes come with it: the site deploy trigger after a latest release, and a stop for a Developer ID release without the notarization profile. The notarized DMG background gets a title-less base so the title is rendered from text.

## Technical Context

**Language/Version**: Swift 5.10 (package tools), bash for release scripts, Python for `dmg-settings.py`

**Primary Dependencies**: SwiftUI, AppKit, ServiceManagement, Foundation; `gh`, `jq`, `git`, `hdiutil`, `dmgbuild` in the release scripts

**Storage**: JSON files in the user's home (`config.json`, `imported-prices.json`, `last-good.json`), a text log

**Testing**: Swift Testing via `make test`; bash release tests via `make test-release` (stubbed `gh`, local bare git repositories)

**Target Platform**: macOS 14+ on Apple Silicon

**Project Type**: desktop menu bar app with a core library and release tooling

**Performance Goals**: no change to refresh behavior

**Constraints**: never write to the agents' files (AGENTS.md); README "Security and privacy" updated in the same change; no em or en dash anywhere

**Scale/Scope**: about 90 files name the app; 2 new image files (the title-less DMG background base)

## Constitution Check

The constitution file is an unfilled template, so the gates come from AGENTS.md:

| Gate | Status |
|---|---|
| Build and test only through the Makefile | Pass: `make test`, `make test-release`, `make app`, `make backgrounds`, `make dmg` |
| Logic in `UsageCore`, covered by tests, test first | Pass: update names (source, DMG, cask, User-Agent) live in `UsageCore` with tests updated first |
| Doc comments cite spec requirements | Pass: new code cites `spec 023 FR-0xx` |
| No em or en dash | Pass: enforced by review |
| Read-only toward agents' files; README security section kept true | Pass: no new reads or writes; the README section is updated in this change (FR-024) |

Re-check after design: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/023-rebrand-agenttacho/
├── spec.md
├── plan.md               # this file
├── research.md           # R1, R3, R6 to R9
├── data-model.md         # Paths and identifiers
├── contracts/
│   └── release-and-tap.md
├── quickstart.md         # Q0 to Q5
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code (repository root)

```text
Package.swift                                  # package agenttacho, product and target AgentTacho
Sources/
├── UsageCore/
│   ├── Config/Paths.swift                     # agenttacho data folders (FR-007)
│   ├── AppLinks.swift                         # AgentTacho/agenttacho
│   ├── AppVersionInfo.swift                   # AgentTacho* Info.plist keys
│   ├── Config/ConfigurationLoadNotes.swift    # identifier
│   └── Update/                                # UpdateSource, ReleaseEvaluator (DMG name),
│                                              # HomebrewDetector, UpdateState, UpdateBlockReason,
│                                              # UpdateOutcome, UpdateClient (User-Agent)
└── AgentTacho/
    ├── App.swift                              # AgentTachoApp
    └── ...                                    # user-facing strings
Tests/UsageCoreTests/                          # expectations and fixtures with the AgentTacho names
Resources/
├── Info.plist                                 # AgentTacho, dev.rhuss.agenttacho
├── dmg/background-notarized-base(.png|@2x.png)  # NEW: title-less artwork
└── icons/                                     # AgentTacho file and asset catalog names
packaging/homebrew/agenttacho.rb.tmpl
scripts/release/
├── lib.sh, build-app.sh, make-dmg.sh, notarize.sh, release.sh, update-cask.sh, dmg-settings.py
├── render-dmg-backgrounds.swift               # draws titles on both backgrounds
└── tests/test_*.sh                            # AgentTacho expectations; site deploy cases
README.md, AGENTS.md, docs/images/agenttacho-dropdown.png
```

**Structure Decision**: Keep the existing two-target layout; the executable target is `AgentTacho`, the library stays `UsageCore`.

## Implementation approach

1. **Names in small, reviewable commits**: (a) `git mv` of directories and files (target, icons, cask template, image), so history follows; (b) `Package.swift`, Info.plist, Info.plist keys across `build-app.sh`, `AppVersionInfo`, `InstallEnvironment`; (c) user-facing strings; (d) update logic names (source, DMG name, cask, User-Agent, folder name); (e) data folders in `Paths`; (f) test expectations and fixtures. Run `make test` after each.
2. **Release tooling**: defaults (`GH_REPO`, `SITE_REPO`, `NOTARY_PROFILE`, `SIGN_IDENTITY_NAME`, `APP_ICON`), names (DMG, volume, release title, notes, cask), site deploy step; tests first in `scripts/release/tests/`.
3. **Backgrounds**: create the title-less notarized base (research R3), extend `render-dmg-backgrounds.swift`, run `make backgrounds`, check both scales by eye.
4. **Docs**: README (name, security section, release section with the notary profile, Homebrew commands), AGENTS.md, icon READMEs.
5. **Operations** (maintainer, research R9): repository settings, merge, notary profile, `make release` 0.5.0, Q3 to Q5.

## Risks

| Risk | Mitigation |
|---|---|
| Filled title band in the notarized background shows seams | Checked in Q2 at both scales; fallback is regenerating the artwork (R3) |
| Merge conflicts with `021-recover-stuck-offline` | Implement after 021 lands and rebase first (R9) |
| The release ships without notarization because the profile is missing | The release stops before building unless `ALLOW_UNNOTARIZED=1` (FR-015) |

## Complexity Tracking

No constitution violations.
