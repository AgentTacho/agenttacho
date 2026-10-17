# Tasks: Name the app AgentTacho

**Input**: Design documents from `specs/023-rebrand-agenttacho/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/release-and-tap.md, quickstart.md

**Tests**: Required. AGENTS.md asks for test-first development of all `UsageCore` logic; new test cases come before their implementation and must fail first. Changed expectations in existing tests are updated in the same task as the code they check. Run Swift tests only with `make test`, release tests only with `make test-release`, build only with `make app`.

## Format: `[ID] [P?] [Story] Description`

## Conventions for every task

- Doc comments of new or changed code cite the spec requirements they implement (for example `spec 023 FR-007`); comments citing older specs keep their numbers.
- No em dash or en dash characters anywhere (code, comments, docs, commit messages).
- Use `git mv` for every file or directory move, so history follows.
- The names: app `AgentTacho`, lower case `agenttacho`, bundle identifier `dev.rhuss.agenttacho`, app repository `AgentTacho/agenttacho`, cask `agenttacho/tap/agenttacho`. Never touch `github.com/sponsors/rhuss`, `.github/FUNDING.yml`, `rhuss/cc-spex` or `rhuss/cc-rhuss-marketplace`.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.

---

## Phase 1: Setup

- [X] T001 Commit any uncommitted spec artifacts in `specs/023-rebrand-agenttacho/` (`docs(spec): AgentTacho spec, plan and tasks`). Confirm `021-recover-stuck-offline` is merged into `main` (`git log main --oneline | rg -i 'stuck|offline'`). If not, stop and tell the maintainer. If it is, rebase this branch on `main` and resolve conflicts in favour of `main`.
- [X] T002 Run `make test` and `make test-release` once to record the baseline (both must pass before any change).

---

## Phase 2: Foundational (identity, target and resources; blocks every story)

- [X] T003 Move directories and files with `git mv` so they carry the name: the executable target `Sources/AgentTacho`; `Resources/icons/macos/AgentTacho.icns`, `AgentTacho.png`, `AgentTacho.iconset`; `Resources/icons/mono/AgentTacho-mono.png`; `Resources/icons/mono/AgentTachoMonochrome.xcassets` with its image sets `AgentTachoSolid`, `AgentTachoOutline`, `AgentTachoBadge` (and the `filename` entries in each `Contents.json` where they hold the name); `Resources/icons/masters/agenttacho-*.png`; `packaging/homebrew/agenttacho.rb.tmpl`; `docs/images/agenttacho-dropdown.png`; and the named files under `Resources/icons/mono/png/` and `Resources/icons/mono/masters/` (list with `git ls-files Resources/icons`).
- [X] T004 Update `Package.swift`: package name `agenttacho`, executable product and target `AgentTacho` with path `Sources/AgentTacho`. The app struct in `Sources/AgentTacho/App.swift` is `AgentTachoApp`.
- [X] T005 Update `Resources/Info.plist`: `CFBundleExecutable`, `CFBundleName`, `CFBundleDisplayName`, `CFBundleIconFile` are `AgentTacho`; `CFBundleIdentifier` is `dev.rhuss.agenttacho` (spec 023 FR-001, FR-003).
- [X] T006 Use the Info.plist keys `AgentTachoVersionDisplay`, `AgentTachoCommit`, `AgentTachoBuildDate`, `AgentTachoReleaseTag`, `AgentTachoSigning`, `AgentTachoNotarized`, `AgentTachoUpdateSource` together in `scripts/release/build-app.sh`, `Sources/UsageCore/AppVersionInfo.swift`, `Sources/AgentTacho/InstallEnvironment.swift`, `Tests/UsageCoreTests/AppVersionInfoTests.swift` and `scripts/release/tests/test_build_scripts.sh` (spec 023 FR-004).
- [X] T007 Update `scripts/release/build-app.sh` and `Makefile` for the names: `APP_NAME = AgentTacho`, `EXECUTABLE="AgentTacho"`, the bundle identifier `dev.rhuss.agenttacho`, `MONO_ICON="Resources/icons/mono/AgentTacho-mono.png"`, the copied icon names `AgentTacho.icns` and `AgentTacho-mono.png`, and the header comments; update `Sources/AgentTacho` code that loads `AgentTacho-mono.png` by name. Update `scripts/release/tests/test_build_scripts.sh` expectations accordingly.
- [X] T008 Run `make test`, `make test-release` and `make app`; `build/AgentTacho.app` exists and launches. Commit `refactor: name the app target, bundle and resources AgentTacho`.

**Checkpoint**: the app builds and runs as AgentTacho with its bundle identifier; strings, folders and release names follow in the next phases.

---

## Phase 3: User Story 1 - Everything the user sees says AgentTacho (Priority: P1)

**Goal**: every user-facing text and link says AgentTacho (spec 023 FR-002, FR-005, FR-006).

**Independent Test**: quickstart Q1.

- [X] T009 [P] [US1] Update `Tests/UsageCoreTests/AppLinksTests.swift` to expect `https://github.com/AgentTacho/agenttacho`, `.../issues/new` and `.../#security-and-privacy` and the sponsor link `https://github.com/sponsors/rhuss`; then change `Sources/UsageCore/AppLinks.swift` (spec 023 FR-005). `make test`.
- [X] T010 [P] [US1] Update the texts in `Sources/UsageCore/Update/UpdateState.swift` and `Sources/UsageCore/Update/UpdateBlockReason.swift` ("AgentTacho is up to date", "AgentTacho <v> available", "Move AgentTacho to Applications...", etc.) and their tests `Tests/UsageCoreTests/UpdateStateTests.swift`, `Tests/UsageCoreTests/UpdateBlockReasonTests.swift` (spec 023 FR-002). Leave `homebrewCommand` for T024.
- [X] T011 [P] [US1] Update user-facing and accessibility texts in `Sources/UsageCore/Bar/BarPresentation.swift`, `Sources/UsageCore/Notifications/CredentialAlert.swift`, `Sources/UsageCore/Notifications/CredentialHealth.swift` and their tests (`BarPresentationTests.swift`, `CredentialAlertTests.swift`); use the name AgentTacho in `AggregatorTests.swift`, `ProjectResolverTests.swift`, `CodexLimitsSourceTests.swift`, `OpenCodeSourceTests.swift` and `CodexUsageClientTests.swift`.
- [X] T012 [P] [US1] Update every user-facing string, window title, alert text and accessibility label in `Sources/AgentTacho/` (`DropdownView.swift`, `AboutSettingsTab.swift`, `NotificationPresenter.swift`, `MenuBarOpener.swift`, `Updater.swift`, `UpdateInstaller.swift`, `App.swift`, settings views). Leave `SingleInstance.swift` for T020.
- [X] T013 [US1] Set the `User-Agent` in `Sources/UsageCore/Update/UpdateClient.swift` to `AgentTacho/<version>`, and `Sources/UsageCore/Config/ConfigurationLoadNotes.swift`'s identifier to `agenttacho.configurationLoadNotes`; update `UpdateClientTests.swift` (spec 023 FR-002, FR-003).
- [X] T014 [US1] Name the app AgentTacho in doc comments and log texts across `Sources/UsageCore/` (`Configuration.swift`, `LastGoodStore.swift`, `CodexLimits.swift`, `CodexSessionParser.swift`, `OpenCodeSource.swift`, `CodexUsageClient.swift`, `UpdatePolicy.swift`, `UpdateSource.swift` comments only) and `Sources/AgentTacho/` (spec 023 FR-025). Run `make test`, `make app`; open the app and walk through quickstart Q1. Commit `feat: name the app AgentTacho in every user-facing text`.

**Checkpoint**: US1 complete.

---

## Phase 4: Data folders and the single-instance alert

**Goal**: the data folders carry the name (spec 023 FR-007), and the alert for a second running copy says AgentTacho (FR-002).

**Independent Test**: `PathsTests` and `RunningInstanceTests`.

- [X] T016 [P] Update `Tests/UsageCoreTests` expectations that name the data folders (`LastGoodStoreTests.swift`, `ConfigStoreTests.swift`, `PathsTests.swift`) to the `agenttacho` folders.
- [X] T017 Change `Sources/UsageCore/Config/Paths.swift`: the URLs are under `~/.config/agenttacho/`, `~/Library/Logs/agenttacho/` and `~/Library/Application Support/agenttacho/`, with doc comments citing spec 023 FR-007. `make test` (T016 passes).
- [X] T019 [P] Update `Tests/UsageCoreTests/RunningInstanceTests.swift`: processes carry `dev.rhuss.agenttacho`, and `summary` reads "AgentTacho <version> (build <n>) is already running from /Applications/AgentTacho.app (process <pid>)."
- [X] T020 Update `Sources/UsageCore/RunningInstance.swift` and `Sources/AgentTacho/SingleInstance.swift` so the summary and the alerts say AgentTacho ("AgentTacho is already running", "The running AgentTacho did not quit"). `make test`.

**Checkpoint**: data folders and the single-instance alert complete.

---

## Phase 5: User Story 2 - A release publishes AgentTacho (Priority: P1)

**Goal**: app-side update names, release tooling, cask, site deploy trigger, DMG backgrounds (spec 023 FR-013 to FR-018).

**Independent Test**: `make test-release` with the new cases; quickstart Q2.

- [X] T023 [P] [US2] Update `Tests/UsageCoreTests` for the release names, then the code: `UpdateSource.official` is `AgentTacho/agenttacho` (`UpdateSourceTests.swift`, `UpdateSource.swift`); `ReleaseEvaluator` expects `AgentTacho-<version>.dmg` (`ReleaseEvaluatorTests.swift`, fixtures `Fixtures/update/release-info*.json`, `releases-latest*.json` with `AgentTacho/agenttacho` URLs and `AgentTacho-*.dmg` asset names); `UpdateHostPolicyTests.swift`, `UpdateClientTests.swift`, `UpdatePolicyTests.swift`, `UpdateVerificationTests.swift`, `DiskImageCheckTests.swift`, `InstallLocationTests.swift` use `AgentTacho` names and `dev.rhuss.agenttacho` (spec 023 FR-013).
- [X] T024 [P] [US2] Update `HomebrewDetector` (`caskName = "agenttacho"`, `appName = "AgentTacho.app"`), `UpdateState.homebrewCommand = "brew upgrade --cask agenttacho"`, `UpdateOutcome.folderName = "dev.rhuss.agenttacho-update"`, and `UpdateInstaller.swift`'s comment; tests `HomebrewDetectorTests.swift`, `UpdateStateTests.swift`, `UpdateOutcomeTests.swift` first (spec 023 FR-003, FR-017). `make test`.
- [X] T025 [P] [US2] Write failing release tests per `contracts/release-and-tap.md`: defaults in `scripts/release/tests/test_lib.sh` (`GH_REPO`, `SITE_REPO`, `NOTARY_PROFILE=agenttacho-notary`, `SIGN_IDENTITY_NAME="AgentTacho Signing"`, `APP_ICON`); names in `test_dmg.sh` (DMG and volume), `test_notes.sh` (AgentTacho text and `brew install --cask agenttacho/tap/agenttacho`), `test_signing.sh` (identifier), `test_preflight.sh`, `helpers.sh`.
- [X] T026 [P] [US2] Write failing tests in `scripts/release/tests/test_release_flow.sh`: release title `AgentTacho X.Y.Z` and the three asset names; `gh workflow run deploy.yml -R AgentTacho/agenttacho.github.io` called once, after publishing and before the cask step, for a latest release; not called for an older tag or an overridden `GH_REPO`; a failing call prints `release: warning: could not start the site deploy` with the manual command, the cask step still runs, exit status 0.
- [X] T027 [P] [US2] Write failing tests in `scripts/release/tests/test_cask.sh`: the rendered cask matches the template in `contracts/release-and-tap.md`; with a local bare tap, an update writes and pushes `Casks/agenttacho.rb` in one commit and keeps the existing tap content; a second run logs `already up to date (agenttacho X.Y.Z)` and makes no commit.
- [X] T028 [US2] Implement in `scripts/release/lib.sh`: defaults (`GH_REPO=AgentTacho/agenttacho`, new `SITE_REPO=AgentTacho/agenttacho.github.io` exported, `NOTARY_PROFILE=agenttacho-notary`, `SIGN_IDENTITY_NAME="AgentTacho Signing"`, `APP_ICON=Resources/icons/macos/AgentTacho.icns`, `APP="build/AgentTacho.app"`), `dmg_filename` gives `AgentTacho-$1.dmg`, release notes and cask caveats say AgentTacho with `brew install --cask agenttacho/tap/agenttacho` (spec 023 FR-014, FR-015). Update `scripts/release/make-dmg.sh` (volume name and comments), `scripts/release/notarize.sh`, `scripts/release/dmg-settings.py` (app name). Add `SITE_REPO` to the `Makefile` variables and export list.
- [X] T029 [US2] Implement the site deploy step in `scripts/release/release.sh` per `contracts/release-and-tap.md` and research R8; release title `AgentTacho $short_version` (spec 023 FR-018). `make test-release` (T026 passes).
- [X] T030 [US2] Write `packaging/homebrew/agenttacho.rb.tmpl` per `contracts/release-and-tap.md`, and make `scripts/release/update-cask.sh` write `Casks/agenttacho.rb` in one idempotent commit, with messages naming `agenttacho` (spec 023 FR-016). `make test-release` (T025, T027 pass).
- [X] T031 [US2] Create the title-less notarized background `Resources/dmg/background-notarized-base.png` and `@2x.png` from the current artwork (research R3): replace the title band (1x about x 190 to 640, y 70 to 110; 2x doubled) with background pixels sampled from the same rows left and right of the text, blended across the band; write the one-off command used into the commit message. Open both at full size and check for seams; if seams show, stop and ask the maintainer for a regenerated base.
- [X] T032 [US2] Extend `scripts/release/render-dmg-backgrounds.swift` to also render the notarized backgrounds: draw "Drag AgentTacho to Applications" on the base images, centered at the painted title's position, in `NSFont.systemFont(ofSize:weight: .bold)` (semibold in the first draft; bold matches the painted weight) with the rounded design (`NSFontDescriptor.SystemDesign.rounded`), in the teal sampled from the original title; the unnotarized texts say AgentTacho (`AgentTacho.app` in the `xattr` line). Update the `Makefile` comment of `backgrounds`. Run `make backgrounds` and `make dmg`; check quickstart Q2. Commit `feat(release): publish AgentTacho releases and start the site deploy`.

**Checkpoint**: US2 complete (except the actual 0.5.0 release, Phase 8).

---

## Phase 6: User Story 3 - The repository and its docs carry the name (Priority: P2)

**Goal**: README and AGENTS.md say AgentTacho, with the updated security section (spec 023 FR-023 to FR-025).

**Independent Test**: read both files.

- [X] T033 [P] [US3] Write `README.md` for AgentTacho: title and intro; download and Homebrew lines (`AgentTacho-X.Y.Z.dmg`, `brew install --cask agenttacho/tap/agenttacho`, `brew upgrade --cask agenttacho`); repository links to `AgentTacho/agenttacho`; image path `docs/images/agenttacho-dropdown.png` (spec 023 FR-023).
- [X] T034 [US3] In `README.md`'s "Security and privacy" section: the update request `https://api.github.com/repos/AgentTacho/agenttacho/releases/latest`, the data folders and the temporary folder `dev.rhuss.agenttacho-update` (FR-024). In the release section: variables table (`GH_REPO`, new `SITE_REPO`), the notary profile `agenttacho-notary` with the `xcrun notarytool store-credentials` command, the self-signed identity name and the site deploy step.
- [X] T035 [P] [US3] Update `AGENTS.md` (project name, `AgentTacho` in the intro and conventions; keep the cc-spex and marketplace links), `Resources/icons/README.md`, `Resources/icons/mono/README.md` and `Resources/icons/mono/generation-prompts.json` (names only, prompts otherwise unchanged).
- [X] T036 [US3] Commit `docs: name the app AgentTacho in README and AGENTS.md`.

**Checkpoint**: US3 complete.

---

## Phase 7: Polish & Cross-Cutting

- [X] T038 Search the whole diff for em and en dashes (`git diff main --name-only | xargs rg -n '[\x{2013}\x{2014}]'`) and remove any.
- [X] T039 Run `make test`, `make test-release`, `make app`, `make dmg`; run quickstart Q0, Q1 and Q2 and record the results in `quickstart.md`. Commit any fixes.

---

## Phase 8: Repository and release operations (maintainer approval required)

**Goal**: the repository settings match the name, and 0.5.0 is released (spec 023 FR-019, FR-020).

**Independent Test**: quickstart Q3, Q4, Q5.

- [x] T040 [US3] With the maintainer's explicit approval, confirm that `gh repo view AgentTacho/agenttacho` answers, and set `git remote set-url origin git@github.com:AgentTacho/agenttacho.git` in the main checkout (spec 023 FR-020).
- [x] T041 [US3] Set the repository homepage: `gh repo edit AgentTacho/agenttacho --homepage https://agenttacho.github.io` (FR-020).
- [x] T042 Merge this branch to `main` through the usual finish flow and push.
- [x] T043 [US2] Ask the maintainer to store the notary profile (`xcrun notarytool store-credentials agenttacho-notary ...`). Then tag `v0.5.0` on `main`, push the tag, run `make release`, and run quickstart Q3 (spec 023 FR-019).
- [x] T044 [US2] Run quickstart Q4 (`brew install --cask agenttacho/tap/agenttacho` on a test Mac or user account) and Q5 (the update check of the installed AgentTacho); record results in `quickstart.md` (SC-004, SC-005).

---

## Dependencies & Execution Order

- **Phase 1** (T001, T002) before everything; T001 depends on `021` being on `main`.
- **Phase 2** (T003 to T008) blocks all stories: target, bundle and resource names.
- **US1** (Phase 3), the data folders (Phase 4) and **US2** (Phase 5) depend only on Phase 2 and can proceed in parallel; within each, tests before implementation as listed.
- **US3** (Phase 6) after Phases 4 and 5 (the README describes their folders and release names).
- **Polish** (Phase 7) after Phases 3 to 6.
- **Phase 8** last: T040 and T041 need approval; T043 after T042; T044 after T043.

## Parallel Opportunities

- Phase 3: T009, T010, T011, T012 touch different files.
- Phase 4: T016 and T019 are test files; T017 follows T016; T020 follows T019.
- Phase 5: T023, T024 (Swift) and T025, T026, T027 (bash tests) in parallel; T028 to T030 after their tests; T031 and T032 independent of the scripts.
- Across stories: US1, the data folders and US2 can run as three tracks after Phase 2.

## Implementation Strategy

1. **MVP**: Phases 1 and 2 plus US1 (an app that builds, runs and reads as AgentTacho everywhere).
2. Add the data folders, then US2 (release tooling), then US3 (docs), checking each independent test.
3. Polish, then the operations in Phase 8, which need the maintainer's approval at T040 and T043.
