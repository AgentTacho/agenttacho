# Implementation Plan: Auto-Update

**Branch**: `013-auto-update` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/013-auto-update/spec.md`

## Summary

An own small updater, no new dependency (FR-024):

- **Core decisions (UsageCore/Update/).** `ReleaseVersion`, decoding of the GitHub release and `release-info.json`, `ReleaseEvaluator` (ignored / not newer / available, with or without a download target), `UpdatePolicy` (checks allowed, action install / homebrew / download with reason), `UpdateSchedule` (5 minutes after launch, then 24 hours wall clock), `UpdateHostPolicy` (host allowlist (starting URLs and redirects)), `DiskImageCheck`, `UpdateVerification` (verdict over the R4 chain), `HomebrewDetector` (Caskroom symlink matches the running path), `UpdateState` with its line texts, `UpdateOutcome` (FR-001 to FR-008, FR-012, FR-016, FR-019, FR-023; research R1 to R7, R9).
- **Client (UsageCore).** `UpdateClient`: ephemeral session, `AgentTacho/X.Y.Z` user agent, allowlisted redirects, 64 KB limit for release info, 100 MB streaming limit for the DMG, progress callback, cancellable (FR-004, FR-005, FR-014; R1 to R3). Same layer as the existing usage clients.
- **App (Sources/AgentTacho/).** `Updater` (`@MainActor` observable): schedule loop and wake trigger, check, install pipeline (download, checksum, `spctl` on DMG, `hdiutil` mount, contents, `SecStaticCode` requirement, `spctl` on app, stage with `ditto`, trash and move, rollback, outcome file, relaunch), launch cleanup, logging. `InstallEnvironment` gathers `InstallContext` facts (team from own signature, translocation, read-only volume, writability, Homebrew). UI: update line in `DropdownView`, "Check for Updates…" in the gear menu, Updates group in `AboutSettingsTab` (FR-009 to FR-013, FR-017, FR-018, FR-020, FR-021; R4, R5, R6, R8, R10).
- **Configuration.** `checksForUpdates`, default true, lenient decoding (FR-002; R12).
- **Build.** `make app-update-test` with `UPDATE_TEST`/`UPDATE_SOURCE` in build-app.sh, release.sh guard, release script tests (FR-025; R11).
- **Docs.** README Installation and "Security and privacy" (FR-022).

## Technical Context

**Language/Version**: Swift 5.10 (toolchain 6.x), macOS 14+

**Primary Dependencies**: Foundation, CryptoKit (SHA-256), Security (code signing, translocation), SwiftUI, AppKit. System tools `/usr/bin/hdiutil`, `/usr/sbin/spctl`, `/usr/bin/ditto`, `/bin/sh`, `/usr/bin/open`. No package dependencies.

**Storage**: `config.json` gains `checksForUpdates`. Temporary folder `$TMPDIR/dev.rhuss.agenttacho-update/` (download, mount point, `outcome.json`). Nothing else.

**Testing**: Swift Testing via `make test`; new `Tests/UsageCoreTests/Update*Tests.swift` with JSON fixtures under `Fixtures/update/`; `UpdateClient` tested with a `URLProtocol` stub session (host allowlist (starting URLs and redirects), size limits, headers). Release script tests in `scripts/release/tests` for the `UPDATE_TEST` guard and the new target. End-to-end per quickstart.md.

**Target Platform**: macOS 14+ on Apple Silicon, menu bar app.

**Project Type**: desktop app (`AgentTacho`) with core library (`UsageCore`).

**Performance Goals**: Install under one minute on broadband (SC-002); a check is two small requests.

**Constraints**:
- No credentials or identifiers in update requests; host allowlist (starting URLs and redirects) (FR-005).
- Nothing replaced unless every R4 step passes (SC-003).
- Development builds make no request (FR-008, SC-007); release builds never read a release source setting (FR-025).
- AgentTacho still never writes to the agents' files; it writes only its own bundle, the temporary folder and the Trash (FR-022).

**Scale/Scope**: about 10 new core files, 1 new client, 3 new app files, 3 changed app files, 1 changed config file, 2 changed scripts, 1 Makefile target, about 9 new test suites, README.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is an unfilled template. The plan follows AGENTS.md and specs 001 to 011: logic in `UsageCore` with tests written first, thin SwiftUI layer, Makefile-only build and test, FR citations in doc comments, no em or en dashes, read-only access to agent files, and the README security section updated in the same change because this feature adds a network request. Post-design re-check: no violations.

## Project Structure

### Documentation (this feature)

```text
specs/013-auto-update/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── update-requests.md
│   ├── update-ui.md
│   └── make-targets.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Update/                         # NEW folder
│   ├── UpdateBlockReason.swift     # reasons and their texts (FR-019)
│   ├── ReleaseVersion.swift        # X.Y.Z parse and compare (FR-006)
│   ├── ReleaseInfo.swift           # GitHubRelease, ReleaseInfo decoding (FR-004)
│   ├── ReleaseEvaluator.swift      # ReleaseCheckResult, AvailableRelease, DownloadTarget
│   ├── UpdatePolicy.swift          # InstallContext, UpdateAction, UpdateBlockReason, checksAllowed
│   ├── UpdateSchedule.swift        # isDue (FR-001)
│   ├── UpdateHostPolicy.swift      # host allowlist (starting URLs and redirects) (FR-005)
│   ├── DiskImageCheck.swift        # contents rule (FR-016)
│   ├── UpdateVerification.swift    # verdict over the R4 chain
│   ├── HomebrewDetector.swift      # Caskroom symlink match (R7)
│   ├── UpdateState.swift           # states, transitions, line texts (contracts/update-ui.md)
│   ├── UpdateOutcome.swift         # outcome.json (R10)
│   └── UpdateClient.swift          # requests (contracts/update-requests.md)
└── Config/Configuration.swift      # checksForUpdates

Sources/AgentTacho/
├── Updater.swift                   # NEW: observable state, schedule loop, check, install, cleanup, log
├── UpdateInstaller.swift           # NEW: tools (hdiutil, spctl, ditto), SecStaticCode, swap, rollback, relaunch
├── InstallEnvironment.swift        # NEW: InstallContext facts, own team id, update source
├── App.swift                       # create Updater, launch cleanup, wake hook, config changes
├── DropdownView.swift              # update line, gear menu item, close detection
├── SettingsView.swift              # pass updater and draft to AboutSettingsTab
└── AboutSettingsTab.swift          # Updates group, toggle

scripts/release/
├── build-app.sh                    # UPDATE_TEST / UPDATE_SOURCE handling
├── release.sh                      # refuse UPDATE_TEST
└── tests/                          # guard tests
Makefile                            # app-update-test target
README.md                           # Installation, Security and privacy

Tests/UsageCoreTests/
├── ReleaseVersionTests.swift
├── ReleaseEvaluatorTests.swift
├── UpdatePolicyTests.swift
├── UpdateScheduleTests.swift
├── UpdateHostPolicyTests.swift
├── DiskImageCheckTests.swift
├── UpdateVerificationTests.swift
├── HomebrewDetectorTests.swift
├── UpdateStateTests.swift
├── UpdateClientTests.swift
├── ConfigurationTests.swift        # checksForUpdates cases
└── Fixtures/update/                # releases-latest*.json, release-info*.json
```

**Structure Decision**: Existing two-target layout. All decisions are pure functions in a new `UsageCore/Update/` folder; the network client sits in `UsageCore` next to the other clients so its redirect and size rules are unit tested. The app target only runs tools, touches files, signs nothing, and renders.

## Risks

- **App Management prompt** (R8): mitigated by replacing in-process with the same team; the denial path rolls back and offers Download. Verified in the quickstart end-to-end run.
- **`spctl` on the app needs network** for the notarization ticket lookup: the check runs right after a successful download; an offline failure becomes `appNotNotarized` with Download, never a replacement.
- **First update**: 0.2.x has no updater; the first one-click update is from the first release with this feature (spec Assumptions).

## Complexity Tracking

No constitution violations to justify.
