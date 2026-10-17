# Implementation Plan: macOS Distribution (Signed DMG and Homebrew Cask)

**Branch**: `005-macos-distribution` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-macos-distribution/spec.md`

## Summary

Turn the ad-hoc `make app` build into a distributable product. Every app build selects the best available signing identity (Developer ID, then the stable self-signed "AgentTacho Signing" certificate, then ad-hoc) and stamps the version from git tags into the bundle along with the new app icon. A dry-run target produces a drag-to-Applications DMG built with `dmgbuild` (no Finder scripting), with one of two prepared backgrounds depending on notarization. A release target adds preflight checks, optional notarization through a `notarytool` keychain profile, a draft-then-publish GitHub release with checksum and `release-info.json`, and an update of the `agenttacho` cask in a fresh clone of `rhuss/homebrew-tap`. A cask-only target finishes a failed cask update. The app shows its version in Settings. README gains installation and maintainer sections. See [research.md](research.md) for the decisions behind each step.

## Technical Context

**Language/Version**: Bash 3.2-compatible scripts (macOS `/bin/bash`) for release tooling; Swift 5.10 for the small app change; one Swift script (AppKit) for rendering DMG backgrounds; Python only inside `dmgbuild` via `uvx`

**Primary Dependencies**: Apple CLIs (`codesign`, `security`, `hdiutil` via dmgbuild, `iconutil`, `PlistBuddy`, `xcrun notarytool`, `xcrun stapler`), `gh` (authenticated), `git`, `jq` (bundled as `/usr/bin/jq` on macOS 15 and later, Homebrew on macOS 14), `uvx` running `dmgbuild==1.6.7`

**Storage**: Files only: bundle `Info.plist`, `build/release/` artifacts, `release-info.json` release asset, cask file in the tap repository

**Testing**: Swift Testing for app code (`make test`); a dependency-free Bash test runner for release scripts (`make test-release`) with `PATH` stubs for `security`, `gh`, `xcrun`, real temporary git repositories for version logic, and `ruby -c` for rendered casks

**Target Platform**: macOS 14 or newer on Apple Silicon (arm64), for both the app and the maintainer's release machine

**Project Type**: Desktop app (menu bar) plus release tooling

**Performance Goals**: A dry run (`make dmg`) completes in under 2 minutes on the maintainer's Mac after a warm Swift build; notarization time is Apple's

**Constraints**: No interactive prompts (FR-018); no global tool installs (uv rule); no secrets in the repository; works from a git worktree; must not publish anything when any preflight check fails (SC-005)

**Scale/Scope**: One app bundle, one DMG per release, one cask; roughly 8 scripts, 5 new Makefile targets (`dmg`, `release`, `cask`, `test-release`, `backgrounds`) plus the reworked `app`, 4 background images, 1 cask template, small Swift change in Settings and launch logging

## Global Constraints

Copied from the spec; every task inherits them.

- AgentTacho supports Apple Silicon and macOS 14 or newer only; no universal (Intel) build. The cask declares `depends_on arch: :arm64` and `depends_on macos: ">= :sonoma"`.
- Bundle identifier `dev.rhuss.agenttacho`; app `AgentTacho.app`; icon `Resources/icons/macos/AgentTacho.icns`.
- Signing order: Developer ID Application, then the self-signed certificate found by name (default "AgentTacho Signing", overridable per build), then ad-hoc (FR-001).
- Notarization keychain profile default name "agenttacho-notary", overridable per release (FR-014a).
- DMG name `AgentTacho-X.Y.Z.dmg`; tag format `vX.Y.Z`; build number is the number of commits reachable from the built commit (FR-007).
- Development builds keep a numeric `CFBundleShortVersionString` (nearest `vX.Y.Z` tag or "0.0.0"); "-dev" appears only in the app's own version display (FR-008).
- Tap repository `rhuss/homebrew-tap`, cask `agenttacho`, always cloned fresh (FR-021). GitHub repository `rhuss/agenttacho`.
- Zap paths: `~/.config/agenttacho`, `~/Library/Logs/agenttacho`, `~/Library/Preferences/dev.rhuss.agenttacho.plist` (FR-023).
- No interactive prompts when all inputs are provided (FR-018). Preflight failures change nothing on GitHub or in the tap (SC-005).
- Implementation never creates tags, GitHub releases or tap commits; publishing is the maintainer's step.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is still the unfilled template; no project principles are ratified. No gates apply. Practices followed anyway from the project's history: test-first for logic (Bash tests before script logic, Swift Testing for app changes), no third-party Swift packages, Makefile as the single entry point.

Post-design re-check: unchanged, no violations.

## Project Structure

### Documentation (this feature)

```text
specs/005-macos-distribution/
├── plan.md              # This file
├── research.md          # Phase 0 decisions
├── data-model.md        # Version info, signing tier, release info, cask inputs
├── quickstart.md        # End-to-end validation guide
├── contracts/
│   ├── make-targets.md      # Commands, variables, exit codes, outputs
│   ├── release-info.md      # release-info.json schema
│   └── cask.md              # Rendered cask contract
└── tasks.md             # Created by /speckit-tasks
```

### Source Code (repository root)

```text
Makefile                                  # app target reworked; new: dmg, release, cask, test-release, backgrounds
Resources/
├── Info.plist                            # CFBundleIconFile=AgentTacho, version placeholders 0.0.0 / 0
├── icons/macos/AgentTacho.icns           # existing (committed with the icon set)
└── dmg/
    ├── background-notarized.png          # + @2x
    └── background-unnotarized.png        # + @2x
scripts/release/
├── lib.sh                                # pure functions: version, tier selection, notes, cask rendering, preflight checks
├── build-app.sh                          # build, assemble bundle, icon, version stamp, sign, verify requirement
├── make-dmg.sh                           # dmgbuild with background variant and volume icon, optional DMG signing
├── notarize.sh                           # profile detection, submit, staple, validate, log on failure
├── release.sh                            # orchestrator: preflight, build, dmg, notarize, draft release, upload, publish, cask
├── update-cask.sh                        # cask-only: fetch release-info.json, render, clone tap, commit, push
├── dmg-settings.py                       # dmgbuild settings (reads defines: app path, background, icon)
├── render-dmg-backgrounds.swift          # generates Resources/dmg/*.png
└── tests/
    ├── run.sh                            # runner + assertions + make_stub/make_git_repo
    ├── test_lib.sh                       # die/warn format, icon check
    ├── test_version.sh
    ├── test_signing.sh
    ├── test_dmg.sh
    ├── test_preflight.sh
    ├── test_notes.sh
    ├── test_cask.sh                      # render_cask + update-cask.sh against a local bare repo
    └── test_release_flow.sh              # release.sh end to end with stubbed helpers
packaging/homebrew/agenttacho.rb.tmpl     # cask template
Sources/UsageCore/
├── AppVersionInfo.swift                  # reads AgentTachoVersionDisplay / CFBundleShortVersionString / CFBundleVersion
└── UsageCore.swift                       # remove the hard-coded version constant
Sources/AgentTacho/
├── App.swift                             # launch log uses AppVersionInfo
└── SettingsView.swift                    # General tab footer shows the version
Tests/UsageCoreTests/
├── AppVersionInfoTests.swift             # Swift Testing for AppVersionInfo
└── SmokeTests.swift                      # drop the version assertion
README.md                                 # Installation + Maintainer sections
```

**Structure Decision**: Release tooling lives in `scripts/release/` next to the existing helper scripts, with pure logic isolated in `lib.sh` so it can be unit-tested without signing or publishing. Generated-but-committed images live in `Resources/dmg/`, mirroring `Resources/icons/`. The cask template lives in `packaging/homebrew/` because the tap repository receives only rendered output. App-side changes stay minimal: one new file and two call sites. `AppVersionInfo` lives in `UsageCore` (not the app target) because the test target depends only on `UsageCore`.

## Design Notes

### Build and signing flow (`make app`, used by every other target)

1. `swift build -c release` (unchanged SDK handling from the Makefile).
2. Assemble `build/AgentTacho.app`; copy the icon (fail if missing), the resource bundle and `Info.plist`.
3. Compute version info (`lib.sh: version_info`) and stamp the bundle's `Info.plist`.
4. Select the signing tier (`lib.sh: select_identity`), print `signing: <tier> (<identity name>)`.
5. `codesign --force` with tier-specific flags; verify with `codesign --verify --strict` and check the designated requirement is certificate-based for non-ad-hoc tiers (no `cdhash`; a self-signed certificate may yield `certificate root = H"…"` rather than `certificate leaf`, both are accepted). For ad-hoc, print "permissions will not persist across rebuilds".

### Dry run (`make dmg`)

`release.sh --dry-run`: `preflight dry-run` (problems printed as warnings), build, then `make-dmg.sh` chooses the background variant (notarized only if a notarization profile exists and the tier is Developer ID, i.e. what a real release would ship), builds `build/release/AgentTacho-<version>.dmg` (dev builds use the display version, for example `AgentTacho-0.2.0-dev.dmg`), signs the DMG for non-ad-hoc tiers, writes the `.sha256`. The dry run never runs `notarize.sh`, never calls `gh release create/upload/edit` and never runs `update-cask.sh`.

### Release (`make release`)

Preflight (all before any build): clean tree, HEAD exactly at a `vX.Y.Z` tag, tag on `origin` at the same commit (compare the peeled `refs/tags/vX.Y.Z^{}` from `git ls-remote`, falling back to `refs/tags/vX.Y.Z` for lightweight tags, against `git rev-parse HEAD`), `gh auth status` ok, no existing release (unless `REPLACE=1`), non-ad-hoc tier (unless `ALLOW_ADHOC=1`), tap repository reachable (`git ls-remote`). Then build, DMG, notarize (if possible), write release notes and `release-info.json`, create draft release, upload, publish, update cask. Any failure before publishing leaves at most a draft release, which the output names.

### Failure handling

Each script uses `set -euo pipefail`, prints `error: <reason>` and exits non-zero. `release.sh` traps failures after draft creation and prints the `gh release delete vX.Y.Z --yes` command; after publishing, a cask failure prints `make cask VERSION=X.Y.Z`.

### Interfaces

Names and signatures shared across tasks. All `lib.sh` functions print results on stdout and signal failure by exit status; they read configuration from the environment variables in contracts/make-targets.md.

| Function / script | Signature | Output |
|---|---|---|
| `log` / `warn` / `die` | `log <prefix> <msg>`, `warn <msg>`, `die <msg>` | `<prefix>: <msg>` on stdout; `warning: <msg>` / `error: <msg>` on stderr; `die` exits 1 |
| `version_info` | no args, runs in the current git repo | one line `mode short_version display_version build_number tag` (tag empty in dev mode) |
| `select_identity` | no args; env `SIGN_IDENTITY`, `SIGN_IDENTITY_NAME` | one line `tier hash-or-dash name...` (name is the rest of the line, may contain spaces) |
| `codesign_flags` | `<tier>` | flags for `codesign` |
| `requirement_is_certificate_based` | `<codesign -d -r- text>` | exit 0 when certificate based, 1 otherwise |
| `dmg_background` | `<tier> <notarized:true\|false>` | repo-relative PNG path (1x name; dmgbuild finds `@2x`) |
| `dmg_filename` | `<display_version>` | `AgentTacho-<display_version>.dmg` |
| `preflight` | `<release\|dry-run>`; env `REPLACE`, `ALLOW_ADHOC`, `TAP_REPO`, `GH_REPO`; calls `version_info` and `select_identity` itself | `release`: first problem via `die`; `dry-run`: every problem via `warn`, returns 0 |
| `notary_available` | no args; env `NOTARY_PROFILE` | exit 0 when the profile works |
| `release_notes` | `<version> <tier> <notarized>` | Markdown |
| `release_info_json` | `<version> <sha256> <tier> <notarized>` | JSON per contracts/release-info.md |
| `render_cask` | `<version> <sha256> <notarized>` | cask Ruby per contracts/cask.md |
| `build-app.sh` | no args; env `SIGN_IDENTITY`, `SIGN_IDENTITY_NAME`, `APP_ICON` (default `Resources/icons/macos/AgentTacho.icns`) | `build/AgentTacho.app`; `version:`/`signing:` lines |
| `make-dmg.sh` | `<app> <display_version> <tier> <notarized> <identity-hash-or-dash>` | `build/release/<dmg_filename>` and `.sha256`; `dmg:` line |
| `notarize.sh` | `<dmg>`; env `NOTARY_PROFILE` | stapled DMG; `notary:` lines |
| `release.sh` | `[--dry-run]`; helper paths overridable via `BUILD_APP_SH`, `MAKE_DMG_SH`, `NOTARIZE_SH`, `UPDATE_CASK_SH` (default: sibling scripts) for tests | see contracts/make-targets.md |
| `update-cask.sh` | `<version>`; env `GH_REPO`, `TAP_REPO` | `cask:` lines |

`release.sh` obtains tier, hash and version by calling `select_identity` and `version_info` itself (same inputs give the same results as inside `build-app.sh`); it does not parse `build-app.sh` output.

## Complexity Tracking

No constitution violations to justify.
