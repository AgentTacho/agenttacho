---

description: "Task list for macOS Distribution (signed DMG and Homebrew cask)"
---

# Tasks: macOS Distribution (Signed DMG and Homebrew Cask)

**Input**: Design documents from `specs/005-macos-distribution/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (make-targets, release-info, cask), quickstart.md

**Tests**: Included. The plan requires test-first development for all script logic (`make test-release`) and Swift Testing for the app-side version helper (`make test`). Write each test task before its implementation task and watch it fail.

**Organization**: Tasks are grouped by user story. Signing, versioning and the icon are foundational because every story builds the app bundle.

**Safety rule for implementers**: Do NOT create git tags, GitHub releases, or push to `rhuss/homebrew-tap` while implementing. Publishing is the maintainer's step (quickstart sections 7 to 9). All release and cask code is exercised through stubs and `make dmg` only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1 to US5)

## Path Conventions

Repository root layout per plan.md: release tooling in `scripts/release/`, prepared images in `Resources/dmg/`, cask template in `packaging/homebrew/`, app code in `Sources/AgentTacho/` and `Sources/UsageCore/`, Swift tests in `Tests/UsageCoreTests/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test harness and directory layout for the release scripts.

- [X] T001 Create `scripts/release/tests/run.sh`: a dependency-free Bash 3.2 test runner that sources every `scripts/release/tests/test_*.sh`, runs each function named `test_*` in a subshell, provides `assert_eq <expected> <actual> [msg]`, `assert_contains <haystack> <needle>`, `assert_status <expected> <cmd...>`, `make_stub <name> <script-body>` (writes an executable into a per-test temp dir that is prepended to `PATH`), and `make_git_repo` (temp repo with user config), prints `ok`/`FAIL` per test and `N passed, M failed`, exits non-zero on failures
- [X] T002 Create `scripts/release/lib.sh` with `set -euo pipefail`-safe helpers only (no top-level side effects): `log <prefix> <msg>`, `die <msg>` (prints `error: <msg>` to stderr, exits 1), `warn <msg>`; add a first trivial test `scripts/release/tests/test_lib.sh` for `die`/`warn` output format
- [X] T003 Add `test-release` target to `Makefile` running `bash scripts/release/tests/run.sh` (contracts/make-targets.md), and keep `test` unchanged

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Version computation, signing tier selection, icon and version stamping in `make app`, and the in-app version display. Every user story depends on this phase.

### Tests (write first, must fail)

- [X] T004 [P] Write `scripts/release/tests/test_version.sh` covering `version_info` (data-model.md VersionInfo) against real temp repos: no tags gives `dev 0.0.0 0.0.0-dev`; HEAD exactly at `v0.2.0` with clean tree gives `release 0.2.0 0.2.0` and tag `v0.2.0`; same with an uncommitted change gives `dev 0.2.0 0.2.0-dev`; two commits after `v0.2.0` gives `dev 0.2.0`; tags not matching `vX.Y.Z` (`v1.2`, `release-1`, `v1.2.3-rc1`) are ignored; HEAD carrying both `v0.2.0` and `v0.10.0` gives `release 0.10.0` (highest version by numeric comparison); build number equals `git rev-list --count HEAD`; in a shallow clone (`git clone --depth 1 file://…`) `version_info` still succeeds and prints `warning: shallow clone, build number may be wrong` on stderr
- [X] T005 [P] Write `scripts/release/tests/test_signing.sh` covering `select_identity` with a stubbed `security` printing `find-identity -p codesigning` style output (both the "Policy: Code Signing / Matching identities" and the "Valid identities only" sections, so each identity can appear twice): Developer ID plus self-signed present gives tier `developer-id` and the Developer ID SHA-1; only "AgentTacho Signing" (marked `CSSMERR_TP_NOT_TRUSTED`) gives `self-signed` and its SHA-1; nothing gives `ad-hoc` and `-`; `SIGN_IDENTITY=-` gives `ad-hoc` even when certificates exist; `SIGN_IDENTITY_NAME="Other Cert"` selects that certificate; explicit `SIGN_IDENTITY` named `Developer ID Application: X (TEAM)` derives tier `developer-id`; two certificates with the same name select the first hash; a Developer ID marked `CSSMERR_TP_CERT_EXPIRED` or `CSSMERR_TP_CERT_REVOKED` is skipped (falls through to self-signed), while `CSSMERR_TP_NOT_TRUSTED` is accepted; also cover `codesign_flags <tier>` (`--options runtime --timestamp` for developer-id, `--timestamp=none` otherwise) and `requirement_is_certificate_based <text>` (false for text containing `cdhash` and for empty text; true for `identifier "dev.rhuss.agenttacho" and certificate root = H"…"`, `… and certificate leaf = H"…"` and `anchor apple generic and … certificate leaf[subject.OU] = …`)
- [X] T006 [P] Write `Tests/UsageCoreTests/AppVersionInfoTests.swift` (Swift Testing) for `AppVersionInfo(infoDictionary:)`: `AgentTachoVersionDisplay` "0.2.0-dev" plus `CFBundleVersion` "120" gives `label == "AgentTacho 0.2.0-dev (build 120)"`; missing display key falls back to `CFBundleShortVersionString`; empty dictionary gives "AgentTacho unknown"; missing build omits the "(build …)" part

### Implementation

- [X] T007 Implement `version_info` in `scripts/release/lib.sh` printing `mode short_version display_version build_number tag` (tag empty in dev mode) per research.md R7, choosing the highest `vX.Y.Z` when several point at HEAD and warning when `git rev-parse --is-shallow-repository` is true; make T004 pass
- [X] T008 Implement `select_identity` (prints `tier hash-or-dash name`), `codesign_flags`, `requirement_is_certificate_based` in `scripts/release/lib.sh` per research.md R3 and data-model.md SigningTier; honour `SIGN_IDENTITY` and `SIGN_IDENTITY_NAME` (default `AgentTacho Signing`); make T005 pass
- [X] T009 Update `Resources/Info.plist`: add `CFBundleIconFile` = `AgentTacho`, set `CFBundleShortVersionString` to `0.0.0` and `CFBundleVersion` to `0` as placeholders
- [X] T010 Create `scripts/release/build-app.sh` per plan.md "Build and signing flow" and its Interfaces table: check the icon first (`APP_ICON`, default `Resources/icons/macos/AgentTacho.icns`) and fail with `error: missing app icon: <path>` before any build step (add a case to `scripts/release/tests/test_lib.sh`: `APP_ICON=/nonexistent` exits 1 with that message and a stubbed `swift` records no call); then `swift build -c release` (keep the Makefile's SDKROOT handling by being invoked from make), assemble `build/AgentTacho.app`, copy the icns to `Contents/Resources/AgentTacho.icns`, copy the resource bundle, stamp `CFBundleShortVersionString`, `CFBundleVersion`, `AgentTachoVersionDisplay` with `/usr/libexec/PlistBuddy`, print `version:` and `signing:` lines, sign with `codesign --force --sign <hash|-> --identifier dev.rhuss.agenttacho $(codesign_flags)`, run `codesign --verify --strict`, fail if a non-ad-hoc build's `codesign -d -r-` is not certificate-based, print the ad-hoc warning from contracts/make-targets.md for ad-hoc
- [X] T011 Rewire the `app` target in `Makefile` to call `scripts/release/build-app.sh` (pass `SIGN_IDENTITY`, `SIGN_IDENTITY_NAME`), keep `run` opening `build/AgentTacho.app`; run `make app SIGN_IDENTITY=-` and `make app` and check both succeed
- [X] T012 Implement `Sources/UsageCore/AppVersionInfo.swift` (`public struct AppVersionInfo { init(infoDictionary: [String: Any]); var label: String }`); make T006 pass
- [X] T013 Use `AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])` in `Sources/AgentTacho/App.swift` for the launch log line, show its `label` as a secondary caption at the bottom of the General tab in `Sources/AgentTacho/SettingsView.swift`; remove `UsageCore.version` from `Sources/UsageCore/UsageCore.swift` and the version assertion in `Tests/UsageCoreTests/SmokeTests.swift`; run `make test` and `make build`

**Checkpoint**: `make test`, `make test-release` and `make app` pass; the bundle carries the icon, a stamped version, and a tier-appropriate signature.

---

## Phase 3: User Story 1 - Install from a downloaded DMG (Priority: P1) 🎯 MVP

**Goal**: `make dmg` produces a drag-to-Applications DMG with background, icon, Applications link and the right instructions.

**Independent Test**: quickstart.md sections 4 and 5.

### Tests for User Story 1

- [X] T014 [P] [US1] Write `scripts/release/tests/test_dmg.sh` for `dmg_background <tier> <notarized>` (returns `Resources/dmg/background-notarized.png` only for `developer-id true`, else `background-unnotarized.png`) and `dmg_filename <display_version>` (`AgentTacho-0.2.0.dmg`, `AgentTacho-0.2.0-dev.dmg`)

### Implementation for User Story 1

- [X] T015 [P] [US1] Create `scripts/release/render-dmg-backgrounds.swift` (AppKit, no assets) rendering 660x440 pt backgrounds at 1x and 2x into `Resources/dmg/`: both variants draw an arrow from the app position (165, 175) to Applications (495, 175) and "Drag AgentTacho to Applications"; the unnotarized variant adds, in the lower third, "First launch after each install or upgrade:", "macOS 14: Control-click AgentTacho in Applications, choose Open", "macOS 15 or later: open it, then System Settings > Privacy & Security > Open Anyway", "or run: xattr -dr com.apple.quarantine /Applications/AgentTacho.app"; text dark on a light neutral background readable in both Finder appearances
- [X] T016 [US1] Add `backgrounds` target to `Makefile` (`swift scripts/release/render-dmg-backgrounds.swift`), run it, and commit `Resources/dmg/background-notarized.png`, `background-notarized@2x.png`, `background-unnotarized.png`, `background-unnotarized@2x.png`; inspect the images visually
- [X] T017 [US1] Implement `dmg_background` and `dmg_filename` in `scripts/release/lib.sh`; make T014 pass
- [X] T018 [P] [US1] Create `scripts/release/dmg-settings.py` for dmgbuild: read defines `app`, `background`, `icon`; `format = 'UDZO'`, `files = [app]`, `symlinks = {'Applications': '/Applications'}`, `icon_locations` at (165, 175) and (495, 175), `window_rect = ((200, 120), (660, 440))`, `icon_size = 128`, `text_size = 13`, `show_status_bar = False`, `show_toolbar = False`, `show_sidebar = False`, `badge_icon = None`, volume `icon` from the define
- [X] T019 [US1] Create `scripts/release/make-dmg.sh <app> <display_version> <tier> <notarized> <identity-hash-or-dash>` (positional, per plan.md Interfaces); runs `uvx --from dmgbuild==1.6.7 dmgbuild -s scripts/release/dmg-settings.py -D app=… -D background=… -D icon=Resources/icons/macos/AgentTacho.icns "AgentTacho" build/release/<dmg_filename>`; signs the DMG with the same identity for non-ad-hoc tiers (`codesign --sign <hash> $(codesign_flags)`); writes `<dmg>.sha256` in `shasum -a 256` format; prints the `dmg:` line from contracts/make-targets.md
- [X] T020 [US1] Add `dmg` target to `Makefile` running `make app` then `scripts/release/make-dmg.sh` (notarized=false for the dry run); run `make dmg`, open the DMG and verify window layout, background, volume icon (quickstart section 4)

**Checkpoint**: A DMG built locally installs AgentTacho by drag and drop and shows the first-launch steps.

---

## Phase 4: User Story 4 - Publish a release with one command (Priority: P1)

**Goal**: `make release` runs preflight, build, DMG, optional notarization, draft release, uploads, publish, cask update; `make dmg` reports preflight problems as warnings.

**Independent Test**: quickstart.md section 6 (refusals) with stubs; section 7 is run by the maintainer.

### Tests for User Story 4

- [X] T021 [P] [US4] Write `scripts/release/tests/test_preflight.sh` for `preflight <mode>` (`release` stops, `dry-run` only warns) using temp git repos and stubbed `git ls-remote`/`gh`: dirty tree; HEAD without `vX.Y.Z` tag; tag missing on origin; tag on origin pointing at another commit; an annotated tag and a lightweight tag on origin at HEAD both pass (compare the peeled `refs/tags/vX.Y.Z^{}` when present); `gh auth status` failing; release exists (and passes with `REPLACE=1`); ad-hoc tier (and passes with `ALLOW_ADHOC=1`); tap not reachable; all good returns 0 with no output on stderr; assert that in `release` mode no stubbed `gh release create` was called; in `dry-run` mode a dirty, untagged repo returns 0 and prints each problem as a `warning:` line. Prefer real local bare repositories as `origin` and `TAP_REPO` over stubbing `git`
- [X] T022 [P] [US4] Write `scripts/release/tests/test_notes.sh` for `release_notes <version> <tier> <notarized>` (states tier and "notarized"/"not notarized"; includes the macOS 14, macOS 15+ and xattr steps only when not notarized), `release_info_json <version> <sha256> <tier> <notarized>` (valid per `jq`, exactly the five keys of contracts/release-info.md, `notarized` false unless developer-id), and `notary_available` with a stubbed `xcrun` (`notarytool history --keychain-profile agenttacho-notary` exit 0 vs 1, `NOTARY_PROFILE` override)

### Implementation for User Story 4

- [X] T023 [US4] Implement `preflight <release|dry-run>` in `scripts/release/lib.sh` per contracts/make-targets.md step 1 and the plan.md Interfaces table (calls `version_info` and `select_identity` itself); make T021 pass
- [X] T024 [US4] Implement `release_notes`, `release_info_json`, `notary_available` in `scripts/release/lib.sh`; make T022 pass
- [X] T025 [P] [US4] Create `scripts/release/notarize.sh <dmg>`: `xcrun notarytool submit --wait --timeout 1h --keychain-profile "$NOTARY_PROFILE" --output-format json`; a timeout is treated like a rejection; on status other than Accepted save `xcrun notarytool log <id>` to `build/release/notary-log.json` and die; then `xcrun stapler staple` and `xcrun stapler validate`; print `notary:` lines
- [X] T026 [US4] Create `scripts/release/release.sh [--dry-run]` per the plan.md Interfaces table: source lib.sh; run `preflight release` (or `preflight dry-run` with `--dry-run`); get tier/hash from `select_identity` and versions from `version_info`; run `$BUILD_APP_SH` (default `scripts/release/build-app.sh`); decide notarization (developer-id and `notary_available`, else `warning:` for developer-id); `$MAKE_DMG_SH`; `$NOTARIZE_SH` when applicable and not a dry run; write `build/release/release-notes.md` and `build/release/release-info.json`; unless dry run: `gh release create v$V --draft --verify-tag --title "AgentTacho $V" --notes-file …` (skip when `REPLACE=1` and the release exists), `gh release upload` of DMG, `.sha256`, `release-info.json` (`--clobber` with `REPLACE=1`), `gh release edit v$V --draft=false --notes-file …` (so replaced assets also refresh the tier/notarization notes, FR-017), then `$UPDATE_CASK_SH $V`; `trap` messages for draft and cask failures exactly as in contracts/make-targets.md (with `REPLACE=1` on an already published release, the failure message names the release as published, not as a draft). `update-cask.sh` is created in T033; until then T028 stubs it
- [X] T027 [US4] Add `release` target to `Makefile` (`bash scripts/release/release.sh`) and change `dmg` to `bash scripts/release/release.sh --dry-run`; pass `SIGN_IDENTITY`, `SIGN_IDENTITY_NAME`, `NOTARY_PROFILE`, `ALLOW_ADHOC`, `REPLACE`, `TAP_REPO`, `GH_REPO`
- [X] T028 [US4] Add an end-to-end stub test in `scripts/release/tests/test_release_flow.sh` that runs `release.sh` (stdin from `/dev/null`, FR-018) with `BUILD_APP_SH`, `MAKE_DMG_SH`, `NOTARIZE_SH`, `UPDATE_CASK_SH` pointing at stubs and stubbed `gh`/`security`/`xcrun` on `PATH`, all recording their calls: asserts call order (preflight, build, dmg, create draft, 3 uploads, publish, cask); a failing upload prints the draft-delete hint and never publishes; a failing cask update prints `make cask VERSION=…` and exits non-zero; developer-id with `notary_available` calls notarize before `gh release create`, and a failing notarize stops with no `gh release` write call; developer-id without a profile prints a `warning:`, skips notarize and passes `false` as the notarized flag to make-dmg; `--dry-run` on a dirty untagged repo succeeds and makes no `gh release create/upload/edit`, notarize or cask call
- [X] T029 [US4] Run quickstart section 6 manually on an untagged commit, with `GH_REPO=invalid/invalid TAP_REPO=/nonexistent` as a safety net (`make release` must stop with an `error:` line naming the missing tag and create nothing); do not create real tags

**Checkpoint**: The release flow is fully covered by stubbed tests; `make dmg` still works and now prints preflight warnings.

---

## Phase 5: User Story 2 - Install and upgrade with Homebrew (Priority: P2)

**Goal**: The cask is rendered from release info and pushed to the tap by `make cask` and by the release.

**Independent Test**: quickstart.md sections 7 to 9 (maintainer, after the first release); before that, the rendered cask from tests.

### Tests for User Story 2

- [X] T030 [P] [US2] Write `scripts/release/tests/test_cask.sh` for `render_cask <version> <sha256> <notarized>`: output equals the not-notarized example in contracts/cask.md for `0.2.0 <sha> false`; notarized output's caveats contain only the upgrade paragraph (revised after the code review: "Homebrew quits AgentTacho before an upgrade and opens it again afterwards"); both pass `ruby -c`; `zap` lists the three paths; `uninstall quit: "dev.rhuss.agenttacho"` present

### Implementation for User Story 2

- [X] T031 [P] [US2] Create `packaging/homebrew/agenttacho.rb.tmpl` with placeholders `@VERSION@`, `@SHA256@`, `@CAVEATS@` matching contracts/cask.md
- [X] T032 [US2] Implement `render_cask` in `scripts/release/lib.sh` (substitutes placeholders, builds the caveats heredoc body); make T030 pass
- [X] T033 [US2] Create `scripts/release/update-cask.sh <version>`: `gh release download v<version> -R "$GH_REPO" -p release-info.json` into a temp dir (die if missing), read fields with `jq`, `render_cask`, `git clone --depth 1 "$TAP_REPO"` into `mktemp -d`, create `Casks/` if missing, write `Casks/agenttacho.rb`, commit `agenttacho <version>` (print `cask: already up to date` and exit 0 if unchanged), `git push`; die when `version` in the JSON differs from `<version>` or `sha256` is not 64 lowercase hex characters; add stubbed test cases to `scripts/release/tests/test_cask.sh` using a local bare repo as `TAP_REPO` and a stubbed `gh` that serves a fixture `release-info.json`: first run commits `agenttacho 0.2.0` with `Casks/` created; second run prints `cask: already up to date` and adds no commit; `gh release download` failing (no release or no asset) exits non-zero with no tap commit; a mismatched `version` or malformed `sha256` in the fixture exits non-zero with no tap commit
- [X] T034 [US2] Add `cask` target to `Makefile` (`VERSION` required, error otherwise) calling `scripts/release/update-cask.sh $(VERSION)`

**Checkpoint**: `make test-release` covers cask rendering and the tap update against a local bare repository.

---

## Phase 6: User Story 3 - Permissions survive rebuilds and upgrades (Priority: P2)

**Goal**: Confirm that the foundational signing work delivers persistence with the self-signed tier.

**Independent Test**: quickstart.md section 3.

- [ ] T035 [US3] Check with `security find-identity -p codesigning` whether "AgentTacho Signing" exists. Never create, import or modify certificates or keychain settings. If it is missing, mark this task as pending for the maintainer (quickstart section 3) and continue. If it exists, run `make app`, confirm `codesign -d -r- build/AgentTacho.app` shows a certificate-based requirement (`certificate root` or `certificate leaf`, no `cdhash`), and note the result in `specs/005-macos-distribution/quickstart.md` only if steps differ from the documented ones. **Pending for the maintainer (2026-10-14)**: `security find-identity -p codesigning` lists no identities on the implementation machine, so the self-signed tier could not be verified; run quickstart section 3 after creating the certificate
- [X] T036 [US3] Verify that `make app SIGN_IDENTITY=-` prints the ad-hoc warning and still produces a launchable app (`open build/AgentTacho.app`, then quit it)

---

## Phase 7: User Story 5 - Find installation instructions (Priority: P3)

**Goal**: README documents installation for users and the release process for the maintainer.

**Independent Test**: Read the README and follow it without other help.

- [X] T037 [P] [US5] Add an "Installation" section to `README.md` (after the intro, before "Build and run"): download link `https://github.com/rhuss/agenttacho/releases/latest`, drag to Applications, `brew install --cask rhuss/tap/agenttacho`, the first-launch step after each install or upgrade for macOS 14 and 15+ with the `xattr` alternative, a note that only one copy of AgentTacho should run at a time, and how upgrades handle the running app (revised after the code review: `brew upgrade` quits and reopens it, a DMG upgrade needs a manual restart)
- [X] T038 [US5] Add a "Releasing (maintainer)" section to `README.md`: create the "AgentTacho Signing" self-signed code-signing certificate once in Keychain Access (Certificate Assistant, Code Signing type, 3650 days validity, set "Always Trust" for code signing), export it as `.p12` and import it on another machine or CI (`security import … -T /usr/bin/codesign` plus `security set-key-partition-list -S apple-tool:,apple: …` so `codesign` uses the key without a keychain prompt, FR-018), optional Developer ID plus `xcrun notarytool store-credentials agenttacho-notary`, then `make dmg`, `git tag vX.Y.Z && git push origin vX.Y.Z && make release`, `make cask VERSION=X.Y.Z`, and the variables from contracts/make-targets.md; update "Build and run" to mention that `make app` signs with the best available identity

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T039 Run `make test`, `make test-release`, `make app`, `make dmg` from a clean checkout of the branch and fix any failure; time `make dmg` after a warm `make build` (`time make dmg`) and confirm it stays under 2 minutes (plan.md Performance Goals)
- [X] T040 [P] Review all new scripts for Bash 3.2 compatibility (no associative arrays, no `${var,,}`, no `mapfile`) and quoting of paths with spaces; run each with `bash -n`

(T041 removed in plan review: brainstorm status is handled later with `/speckit-spex-brainstorm --sync`.)

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (Phase 1) has no dependencies.
- Foundational (Phase 2) depends on Setup and blocks all user stories.
- US1 (Phase 3) depends on Foundational.
- US4 (Phase 4) depends on US1 (it packages the DMG).
- US2 (Phase 5) depends on US4 for `release-info.json` and the release flow, but its rendering tests (T030 to T032) can start after Foundational.
- US3 (Phase 6) depends only on Foundational.
- US5 (Phase 7) can start after Foundational; the release section is final once US4 and US2 are done.
- Polish (Phase 8) comes last.

### Within Each Phase

Tests first (they must fail), then lib.sh functions, then scripts, then Makefile wiring, then manual checks.

### Parallel Opportunities

- T004, T005, T006 (independent test files).
- T014 and T015 and T018 (test, Swift renderer, dmgbuild settings).
- T021, T022, T025 (tests and notarize script).
- T030, T031 (cask test and template).
- T037 alongside any implementation phase.

## Parallel Example: User Story 1

```text
T014 Write scripts/release/tests/test_dmg.sh
T015 Create scripts/release/render-dmg-backgrounds.swift
T018 Create scripts/release/dmg-settings.py
```

## Implementation Strategy

1. MVP: Phases 1 to 3. `make dmg` produces an installable, stably signed DMG that can be shared by hand.
2. Release automation: Phase 4, then Phase 5 for Homebrew.
3. Verification and docs: Phases 6 and 7.
4. The maintainer publishes the first real release (`v0.2.0`) after merge, following quickstart sections 7 to 9.
