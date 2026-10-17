# Tasks: Rebrand AgentMeter to AgentTacho

**Input**: Design documents from `specs/023-rebrand-agenttacho/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (legacy-data-move.md, release-and-tap.md, name-check.md), quickstart.md

**Tests**: Required. AGENTS.md asks for test-first development of all `UsageCore` logic; new test cases come before their implementation and must fail first. Renamed expectations in existing tests are updated in the same task as the code they check. Run Swift tests only with `make test`, release tests only with `make test-release`, build only with `make app`.

## Format: `[ID] [P?] [Story] Description`

## Conventions for every task

- Doc comments of new or changed code cite the spec requirements they implement (for example `spec 023 FR-008`); comments citing older specs keep their numbers.
- No em dash or en dash characters anywhere (code, comments, docs, commit messages).
- Use `git mv` for every file or directory rename, so history follows.
- "Rename the name" means: `AgentMeter` becomes `AgentTacho`, `agentmeter` becomes `agenttacho`, `dev.rhuss.agentmeter` becomes `dev.rhuss.agenttacho`, `rhuss/agentmeter` (as the app repository) becomes `AgentTacho/agenttacho`, `rhuss/tap/agentmeter` becomes `rhuss/tap/agenttacho`. Never touch `github.com/sponsors/rhuss`, `rhuss/homebrew-tap`, `rhuss/tap` itself, `.github/FUNDING.yml`, `rhuss/cc-spex`, `rhuss/cc-rhuss-marketplace`, or anything under `specs/`, `brainstorm/`, `docs/superpowers/`.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.

## Interfaces (names are binding)

```swift
// Sources/UsageCore/Config/Paths.swift (additions; existing properties now point to agenttacho folders)
public var configDirectoryURL: URL            // ~/.config/agenttacho
public var legacyConfigFileURL: URL           // ~/.config/agentmeter/config.json
public var legacyImportedPricesFileURL: URL   // ~/.config/agentmeter/imported-prices.json
public var legacyLastGoodFileURL: URL         // ~/Library/Application Support/agentmeter/last-good.json

// Sources/UsageCore/Config/LegacyDataMove.swift (spec 023 FR-008 to FR-011)
public enum LegacyDataMove {
    public struct Failure: Equatable, Sendable { public let file: String; public let reason: String }
    public enum Outcome: Equatable, Sendable {
        case skipped                                   // new config folder exists
        case nothingToMove                             // new folder missing, no legacy file
        case moved(copied: [String], failed: [Failure]) // file names, in the order config, prices, last good
    }
    public static func run(paths: Paths, fileManager: FileManager = .default) -> Outcome
    /// Log lines for `AppModel` (source "move"); empty for .skipped and .nothingToMove.
    public static func logLines(for outcome: Outcome) -> [String]
}

// Sources/UsageCore/RunningInstance.swift (spec 023 FR-012)
public static let ownBundleIdentifier = "dev.rhuss.agenttacho"
public static let legacyBundleIdentifier = "dev.rhuss.agentmeter"
public var appName: String                     // "AgentTacho" or "AgentMeter", from the process's bundle identifier
public static func others(from processes: [Process], ownPID: Int32, bundleIdentifiers: Set<String>) -> [RunningInstance]
public static func appName(forBundleIdentifier id: String?) -> String  // legacy id gives "AgentMeter", anything else "AgentTacho"
```

---

## Phase 1: Setup

- [X] T001 Commit any uncommitted spec artifacts in `specs/023-rebrand-agenttacho/` (`docs(spec): rebrand to AgentTacho spec, plan and tasks`). Confirm `021-recover-stuck-offline` is merged into `main` (`git log main --oneline | rg -i 'stuck|offline'`). If not, stop and tell the maintainer. If it is, rebase this branch on `main` and resolve conflicts in favour of `main`.
- [X] T002 Run `make test` and `make test-release` once to record the baseline (both must pass before any change).

---

## Phase 2: Foundational (identity, target and resources; blocks every story)

- [X] T003 Rename directories and files with `git mv`: `Sources/AgentMeter` to `Sources/AgentTacho`; `Resources/icons/macos/AgentMeter.icns`, `AgentMeter.png`, `AgentMeter.iconset` to `AgentTacho.*`; `Resources/icons/mono/AgentMeter-mono.png` to `AgentTacho-mono.png`; `Resources/icons/mono/AgentMeterMonochrome.xcassets` to `AgentTachoMonochrome.xcassets` and its image sets `AgentMeterSolid`, `AgentMeterOutline`, `AgentMeterBadge` to `AgentTacho*` (update the `filename` entries in each `Contents.json` only if they contain the old name); `Resources/icons/masters/agentmeter-*.png` to `agenttacho-*.png`; `packaging/homebrew/agentmeter.rb.tmpl` to `agenttacho.rb.tmpl`; `docs/images/agentmeter-dropdown.png` to `agenttacho-dropdown.png`. Also rename any `agentmeter-*` files under `Resources/icons/mono/png/` and `Resources/icons/mono/masters/` (list with `git ls-files Resources/icons | rg -i agentmeter`).
- [X] T004 Update `Package.swift`: package name `agenttacho`, executable product and target `AgentTacho` with path `Sources/AgentTacho`. Rename `struct AgentMeterApp` to `AgentTachoApp` in `Sources/AgentTacho/App.swift`.
- [X] T005 Update `Resources/Info.plist`: `CFBundleExecutable`, `CFBundleName`, `CFBundleDisplayName`, `CFBundleIconFile` are `AgentTacho`; `CFBundleIdentifier` is `dev.rhuss.agenttacho` (spec 023 FR-001, FR-003).
- [X] T006 Rename the Info.plist keys `AgentMeterVersionDisplay`, `AgentMeterCommit`, `AgentMeterBuildDate`, `AgentMeterReleaseTag`, `AgentMeterSigning`, `AgentMeterNotarized`, `AgentMeterUpdateSource` to the `AgentTacho` prefix together in `scripts/release/build-app.sh`, `Sources/UsageCore/AppVersionInfo.swift`, `Sources/AgentTacho/InstallEnvironment.swift`, `Tests/UsageCoreTests/AppVersionInfoTests.swift` and `scripts/release/tests/test_build_scripts.sh` (spec 023 FR-004).
- [X] T007 Update `scripts/release/build-app.sh` and `Makefile` for the new names: `APP_NAME = AgentTacho`, `EXECUTABLE="AgentTacho"`, the bundle identifier `dev.rhuss.agenttacho`, `MONO_ICON="Resources/icons/mono/AgentTacho-mono.png"`, the copied icon names `AgentTacho.icns` and `AgentTacho-mono.png`, and the header comments; update `Sources/AgentTacho` code that loads `AgentMeter-mono.png` by name. Update `scripts/release/tests/test_build_scripts.sh` expectations accordingly.
- [X] T008 Run `make test`, `make test-release` and `make app`; `build/AgentTacho.app` exists and launches. Commit `refactor: rename the app target, bundle and resources to AgentTacho`.

**Checkpoint**: the app builds and runs as AgentTacho with the new bundle identifier; strings, folders and release names still say AgentMeter.

---

## Phase 3: User Story 1 - Everything the user sees says AgentTacho (Priority: P1)

**Goal**: no user-facing text or link says AgentMeter (spec 023 FR-002, FR-005, FR-006).

**Independent Test**: quickstart Q2; `rg -n 'AgentMeter' Sources` finds only the legacy identifiers added in US2.

- [X] T009 [P] [US1] Update `Tests/UsageCoreTests/AppLinksTests.swift` to expect `https://github.com/AgentTacho/agenttacho`, `.../issues/new` and `.../#security-and-privacy` and the unchanged sponsor link; then change `Sources/UsageCore/AppLinks.swift` (spec 023 FR-005). `make test`.
- [X] T010 [P] [US1] Update the texts in `Sources/UsageCore/Update/UpdateState.swift` and `Sources/UsageCore/Update/UpdateBlockReason.swift` ("AgentTacho is up to date", "AgentTacho <v> available", "Move AgentTacho to Applications...", etc.) and their tests `Tests/UsageCoreTests/UpdateStateTests.swift`, `Tests/UsageCoreTests/UpdateBlockReasonTests.swift` (spec 023 FR-002). Leave `homebrewCommand` for T024.
- [X] T011 [P] [US1] Update user-facing and accessibility texts in `Sources/UsageCore/Bar/BarPresentation.swift`, `Sources/UsageCore/Notifications/CredentialAlert.swift`, `Sources/UsageCore/Notifications/CredentialHealth.swift` and their tests (`BarPresentationTests.swift`, `CredentialAlertTests.swift`); rename every occurrence of the name in `AggregatorTests.swift`, `ProjectResolverTests.swift`, `CodexLimitsSourceTests.swift`, `OpenCodeSourceTests.swift` and `CodexUsageClientTests.swift` (none of them holds a legacy identifier; T037 catches anything missed).
- [X] T012 [P] [US1] Update every user-facing string, window title, alert text and accessibility label in `Sources/AgentTacho/` (`DropdownView.swift`, `AboutSettingsTab.swift`, `NotificationPresenter.swift`, `MenuBarOpener.swift`, `Updater.swift`, `UpdateInstaller.swift`, `App.swift`, settings views). Leave `SingleInstance.swift` for T020.
- [X] T013 [US1] Change the `User-Agent` in `Sources/UsageCore/Update/UpdateClient.swift` to `AgentTacho/<version>`, and `Sources/UsageCore/Config/ConfigurationLoadNotes.swift`'s identifier to `agenttacho.configurationLoadNotes`; update `UpdateClientTests.swift` (spec 023 FR-002, FR-003).
- [X] T014 [US1] Rename the name in doc comments and log texts across `Sources/UsageCore/` (`Configuration.swift`, `LastGoodStore.swift`, `CodexLimits.swift`, `CodexSessionParser.swift`, `OpenCodeSource.swift`, `CodexUsageClient.swift`, `UpdatePolicy.swift`, `UpdateSource.swift` comments only) and `Sources/AgentTacho/` (spec 023 FR-025). Run `make test`, `make app`; open the app and walk through quickstart Q2. Commit `feat: name the app AgentTacho in every user-facing text`.

**Checkpoint**: US1 complete.

---

## Phase 4: User Story 2 - Moving from AgentMeter keeps the user's setup (Priority: P1)

**Goal**: new data folders, a one-time read-only copy of the carried-over files, and the running-copy alert for AgentMeter (spec 023 FR-007 to FR-012, FR-027).

**Independent Test**: `LegacyDataMoveTests` and `RunningInstanceTests`; quickstart Q3.

- [X] T015 [P] [US2] Write failing tests in `Tests/UsageCoreTests/LegacyDataMoveTests.swift` for every case in `contracts/legacy-data-move.md` (temporary home per test via `Paths(home:)`): all three files copied byte for byte; only `config.json`; only `last-good.json` (configuration folder exists afterwards); new configuration folder exists and empty gives `.skipped`; no legacy files gives `.nothingToMove` and no new folder; unwritable destination gives a failure, no file at the destination name and no temporary file left; an unreadable legacy `config.json` (permissions `000`) gives a failure naming `config.json` while `imported-prices.json` and `last-good.json` are still copied; for every case, a recursive listing with contents of the legacy tree is identical before and after; `logLines(for:)` gives `["copied from AgentMeter: config.json, imported-prices.json, last-good.json"]` for a full copy and `"could not copy <file> from AgentMeter: <reason>, starting with defaults"` per failure.
- [X] T016 [P] [US2] Update `Tests/UsageCoreTests` expectations that name the data folders (`LastGoodStoreTests.swift`, `ConfigStoreTests.swift`, any `Paths` test) to the `agenttacho` folders, and add a test for `configDirectoryURL` and the three `legacy*` URLs.
- [X] T017 [US2] Change `Sources/UsageCore/Config/Paths.swift`: existing URLs to `~/.config/agenttacho/`, `~/Library/Logs/agenttacho/`, `~/Library/Application Support/agenttacho/`; add `configDirectoryURL` and the `legacy*` URLs per the Interfaces block, with doc comments citing spec 023 FR-007 and FR-008. `make test` (T016 passes).
- [X] T018 [US2] Implement `Sources/UsageCore/Config/LegacyDataMove.swift` per the Interfaces block and `contracts/legacy-data-move.md`: copy to a uniquely named temporary file in the destination folder, then move into place; remove the temporary file on error; never write under the legacy folders; create the configuration folder after any `.moved` outcome. `make test` (T015 passes).
- [X] T019 [P] [US2] Write failing tests in `Tests/UsageCoreTests/RunningInstanceTests.swift`: `others(from:ownPID:bundleIdentifiers:)` with both identifiers returns an AgentMeter process; a process with another identifier is ignored; `appName` is "AgentMeter" for the legacy identifier and "AgentTacho" otherwise; `summary` reads "AgentMeter 0.4.1 (build 9) is already running from /Applications/AgentMeter.app (process 2512)." for a legacy process and starts with "AgentTacho" for an own one. Update the existing expectations to `dev.rhuss.agenttacho`.
- [X] T020 [US2] Implement the `RunningInstance` changes per the Interfaces block, replacing `others(from:ownPID:bundleIdentifier:)` with the set-based `others(from:ownPID:bundleIdentifiers:)` (its only caller is `SingleInstance`), then change `Sources/AgentTacho/SingleInstance.swift` to query `NSRunningApplication.runningApplications(withBundleIdentifier:)` for both identifiers, pass both to `others`, and show the alert with the other app's `appName`; its doc comment cites spec 023 FR-012. `make test`.
- [X] T021 [US2] In `Sources/AgentTacho/App.swift` `AppModel.init(paths:)`, right after `let log = DiagnosticLog(...)` and before `ConfigStore` is created, call `LegacyDataMove.run(paths:)` and append each of `logLines(for:)` with source `move`; no UI (spec 023 FR-011, FR-027). Comment that `SingleInstance.ensure()` in `AgentTachoApp.init()` runs before, as FR-012 requires. `make test`, `make app`.
- [ ] T022 [US2] Run quickstart Q3 on the maintainer's Mac only with the maintainer's go-ahead (it stops the running AgentMeter); otherwise run it with a copy of the folders in a test user account. Record the result in `specs/023-rebrand-agenttacho/quickstart.md` under Q3. Commit `feat: copy AgentMeter's settings once and recognise a running AgentMeter`.

**Checkpoint**: US2 complete.

---

## Phase 5: User Story 3 - A release publishes AgentTacho to its new home (Priority: P1)

**Goal**: app-side update names, release tooling, cask and tap rename, site deploy trigger, DMG backgrounds (spec 023 FR-013 to FR-019).

**Independent Test**: `make test-release` with the new cases; quickstart Q4.

- [X] T023 [P] [US3] Update `Tests/UsageCoreTests` for the new release names, then the code: `UpdateSource.official` is `AgentTacho/agenttacho` (`UpdateSourceTests.swift`, `UpdateSource.swift`); `ReleaseEvaluator` expects `AgentTacho-<version>.dmg` (`ReleaseEvaluatorTests.swift`, fixtures `Fixtures/update/release-info*.json`, `releases-latest*.json` with `AgentTacho/agenttacho` URLs and `AgentTacho-*.dmg` asset names); `UpdateHostPolicyTests.swift`, `UpdateClientTests.swift`, `UpdatePolicyTests.swift`, `UpdateVerificationTests.swift`, `DiskImageCheckTests.swift`, `InstallLocationTests.swift` use `AgentTacho` names and `dev.rhuss.agenttacho` (spec 023 FR-013).
- [X] T024 [P] [US3] Update `HomebrewDetector` (`caskName = "agenttacho"`, `appName = "AgentTacho.app"`), `UpdateState.homebrewCommand = "brew upgrade --cask agenttacho"`, `UpdateOutcome.folderName = "dev.rhuss.agenttacho-update"`, and `UpdateInstaller.swift`'s comment; tests `HomebrewDetectorTests.swift`, `UpdateStateTests.swift`, `UpdateOutcomeTests.swift` first (spec 023 FR-003, FR-017). `make test`.
- [X] T025 [P] [US3] Write failing release tests per `contracts/release-and-tap.md`: defaults in `scripts/release/tests/test_lib.sh` (`GH_REPO`, `SITE_REPO`, `NOTARY_PROFILE=agenttacho-notary`, `SIGN_IDENTITY_NAME="AgentTacho Signing"`, `APP_ICON`); names in `test_dmg.sh` (DMG and volume), `test_notes.sh` (AgentTacho text and `brew install --cask rhuss/tap/agenttacho`), `test_signing.sh` (identifier), `test_preflight.sh`, `helpers.sh`.
- [X] T026 [P] [US3] Write failing tests in `scripts/release/tests/test_release_flow.sh`: release title `AgentTacho X.Y.Z` and the three asset names; `gh workflow run deploy.yml -R AgentTacho/agenttacho.github.io` called once, after publishing and before the cask step, for a latest release; not called for an older tag or an overridden `GH_REPO`; a failing call prints `release: warning: could not start the site deploy` with the manual command, the cask step still runs, exit status 0.
- [X] T027 [P] [US3] Write failing tests in `scripts/release/tests/test_cask.sh`: rendered cask matches the template in `contracts/release-and-tap.md`; with a local bare tap holding `Casks/agentmeter.rb`, the first update removes it, writes `Casks/agenttacho.rb` and `cask_renames.json` with `{"agentmeter": "agenttacho"}`; an existing `cask_renames.json` with another entry keeps it; a second run logs `already up to date (agenttacho X.Y.Z)` and makes no commit.
- [X] T028 [US3] Implement in `scripts/release/lib.sh`: defaults (`GH_REPO=AgentTacho/agenttacho`, new `SITE_REPO=AgentTacho/agenttacho.github.io` exported, `NOTARY_PROFILE=agenttacho-notary`, `SIGN_IDENTITY_NAME="AgentTacho Signing"`, `APP_ICON=Resources/icons/macos/AgentTacho.icns`, `APP="build/AgentTacho.app"`), `dmg_filename` gives `AgentTacho-$1.dmg`, release notes and cask caveats say AgentTacho with `brew install --cask rhuss/tap/agenttacho` (spec 023 FR-014, FR-015). Update `scripts/release/make-dmg.sh` (volume name and comments), `scripts/release/notarize.sh`, `scripts/release/dmg-settings.py` (app name). Add `SITE_REPO` to the `Makefile` variables and export list.
- [X] T029 [US3] Implement the site deploy step in `scripts/release/release.sh` per `contracts/release-and-tap.md` and research R8; release title `AgentTacho $short_version` (spec 023 FR-018). `make test-release` (T026 passes).
- [X] T030 [US3] Rewrite `packaging/homebrew/agenttacho.rb.tmpl` per `contracts/release-and-tap.md`, and implement the tap rename in `scripts/release/update-cask.sh` (write `Casks/agenttacho.rb`, `git rm` `Casks/agentmeter.rb` if present, merge the rename entry into `cask_renames.json` with `jq`, one commit, idempotent, messages with `agenttacho`) (spec 023 FR-016). `make test-release` (T025, T027 pass).
- [X] T031 [US3] Create the title-less notarized background `Resources/dmg/background-notarized-base.png` and `@2x.png` from the current artwork (research R3): replace the title band (1x about x 190 to 640, y 70 to 110; 2x doubled) with background pixels sampled from the same rows left and right of the text, blended across the band; write the one-off command used into the commit message. Open both at full size and check for seams; if seams show, stop and ask the maintainer for a regenerated base.
- [X] T032 [US3] Extend `scripts/release/render-dmg-backgrounds.swift` to also render the notarized backgrounds: draw "Drag AgentTacho to Applications" on the base images, centered at the old title's position, in `NSFont.systemFont(ofSize:weight: .bold)` (semibold in the first draft; bold matches the painted weight) with the rounded design (`NSFontDescriptor.SystemDesign.rounded`), in the teal sampled from the original title; change the unnotarized texts to AgentTacho (`AgentTacho.app` in the `xattr` line). Update the `Makefile` comment of `backgrounds`. Run `make backgrounds` and `make dmg`; check quickstart Q4. Commit `feat(release): publish AgentTacho releases, rename the cask, start the site deploy`.

**Checkpoint**: US3 complete (except the actual 0.5.0 release, Phase 8).

---

## Phase 6: User Story 5 - The repository and its docs carry the new name (Priority: P2)

**Goal**: README and AGENTS.md say AgentTacho, with moving instructions and the updated security section (spec 023 FR-022 to FR-025).

**Independent Test**: read both files; the name check (T037) passes with the README's allowed sentences.

- [X] T033 [P] [US5] Rewrite `README.md` for AgentTacho: title and intro with one "formerly AgentMeter" sentence near the top; download and Homebrew lines (`AgentTacho-X.Y.Z.dmg`, `brew install --cask rhuss/tap/agenttacho`, `brew upgrade --cask agenttacho`); repository links to `AgentTacho/agenttacho`; image path `docs/images/agenttacho-dropdown.png`; a short "Moving from AgentMeter" section per spec 023 FR-023 (settings copied once, allow notifications, launch at login, delete `AgentMeter.app` or `brew upgrade`, optional deletion of `~/.config/agentmeter`, `~/Library/Logs/agentmeter`, `~/Library/Application Support/agentmeter`, how to repeat the copy by hand).
- [X] T034 [US5] In `README.md`'s "Security and privacy" section: the update request `https://api.github.com/repos/AgentTacho/agenttacho/releases/latest`, the new folders, the temporary folder `dev.rhuss.agenttacho-update`, and one paragraph on the one-time read of AgentMeter's folders (FR-008, FR-009, FR-024). In the release section: variables table (`GH_REPO`, new `SITE_REPO`), the notary profile `agenttacho-notary` with the `xcrun notarytool store-credentials` command, the self-signed identity name, the site deploy step, and the sentence that no new repository named `rhuss/agentmeter` may be created (FR-022).
- [X] T035 [P] [US5] Update `AGENTS.md` (project name, `AgentTacho` in the intro and conventions; keep the cc-spex and marketplace links), `Resources/icons/README.md`, `Resources/icons/mono/README.md` and `Resources/icons/mono/generation-prompts.json` (names only, prompts otherwise unchanged).
- [X] T036 [US5] Commit `docs: rename AgentMeter to AgentTacho in README and AGENTS.md`.

**Checkpoint**: US5 complete.

---

## Phase 7: Polish & Cross-Cutting

- [X] T037 Write `scripts/release/tests/test_names.sh` and `scripts/release/tests/names-allowlist.txt` per `contracts/name-check.md`, register it in `scripts/release/tests/run.sh`, and run `make test-release`. Fix every leftover it reports in the files it names (anything not on the allowlist), until it prints `names: ok`. Each allowlist line carries a comment with its requirement.
- [X] T038 Search the whole diff for em and en dashes (`git diff main --name-only | xargs rg -n '[\x{2013}\x{2014}]'`) and remove any.
- [X] T039 Run `make test`, `make test-release`, `make app`, `make dmg`; run quickstart Q0, Q2 and Q4 and record the results in `quickstart.md`. Commit `test: name check against leftovers of the old name`.

---

## Phase 8: User Story 4 and release operations (maintainer approval required)

**Goal**: the repository lives at `AgentTacho/agenttacho`, old copies are redirected, 0.5.0 is released (spec 023 FR-019 to FR-021).

**Independent Test**: quickstart Q1, Q5, Q6, Q7.

- [x] T040 [US4] Ask the maintainer for explicit approval to transfer the repository. After approval: `gh api -X POST repos/rhuss/agentmeter/transfer -f new_owner=AgentTacho`, wait until `gh repo view AgentTacho/agentmeter` succeeds, then `gh repo rename agenttacho -R AgentTacho/agentmeter --yes` (spec 023 FR-020).
- [x] T041 [US4] Run quickstart Q1 (redirect checks) and record the output in `quickstart.md`. If any check fails, stop and report; do not release. Then `git remote set-url origin git@github.com:AgentTacho/agenttacho.git` in the main checkout and `gh repo edit AgentTacho/agenttacho --homepage https://agenttacho.github.io` (FR-021, FR-022).
- [ ] T042 [US4] Merge this branch to `main` through the usual finish flow and push.
- [ ] T043 [US3] Ask the maintainer to store the notary profile (`xcrun notarytool store-credentials agenttacho-notary ...`) and, before the release, to install the `agentmeter` cask on a test account for Q6. Then tag `v0.5.0` on `main`, push the tag, run `make release`, and run quickstart Q5 (spec 023 FR-019).
- [ ] T044 [US4] Run quickstart Q6 (Homebrew) and Q7 (installed 0.4.1 sees 0.5.0); record results in `quickstart.md`. If `AgentMeter.app` survives `brew upgrade`, note it there; the README already covers it.

---

## Dependencies & Execution Order

- **Phase 1** (T001, T002) before everything; T001 depends on `021` being on `main`.
- **Phase 2** (T003 to T008) blocks all stories: target, bundle and resource names.
- **US1** (Phase 3), **US2** (Phase 4) and **US3** (Phase 5) depend only on Phase 2 and can proceed in parallel; within each, tests before implementation as listed.
- **US5** (Phase 6) after US2 and US3 (the README describes their folders and release names).
- **Polish** (Phase 7) after US1, US2, US3, US5.
- **Phase 8** last: T040 needs approval; T041 before T042 (FR-020: transfer before merge); T043 after T042; T044 after T043.

## Parallel Opportunities

- Phase 3: T009, T010, T011, T012 touch different files.
- Phase 4: T015, T016, T019 are test files; T017 and T018 follow T015 and T016; T020 follows T019.
- Phase 5: T023, T024 (Swift) and T025, T026, T027 (bash tests) in parallel; T028 to T030 after their tests; T031 and T032 independent of the scripts.
- Across stories: US1, US2 and US3 can run as three tracks after Phase 2.

## Implementation Strategy

1. **MVP**: Phases 1 and 2 plus US1 (an app that builds, runs and reads as AgentTacho everywhere).
2. Add US2 (the move from AgentMeter), then US3 (release tooling), then US5 (docs), checking each story's independent test.
3. Polish with the name check, then the operations in Phase 8, which need the maintainer's approval at T040 and T043.
