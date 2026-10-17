# Deep Review Findings

**Date:** 2026-10-14
**Branch:** 005-macos-distribution
**Rounds:** 2 fix rounds with Critical or Important findings, plus one Minor cleanup commit, plus post-review fixes for FINDING-24 to FINDING-40 (maintainer decisions)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline stage 7)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 8 | 8 | 0 |
| Minor | 32 | 32 | 0 |
| Notable | 8 | 1 | 7 |
| **Total** | **48** | **41** | **7** |

**Agents completed:** 5/5 internal (Correctness, Architecture & Idioms, Security, Production Readiness, Test Quality), plus 2 re-review agents (rounds 1 and 2), plus CodeRabbit (3 runs)
**Skipped:** Goal Alignment (no PR found), Copilot (disabled in config)
**Failed:** Codex (usage limit reached, no findings)

The counts are deduplicated. The draft-failure message was reported by Correctness, Architecture and Production Readiness, and the cask-only draft check by Correctness and Production Readiness; each counts once.

Fix commits:

- `ecc97d0` fix(release): harden notarization check, cask-only update and build guards
- `771469c` test(release): cover build-app.sh, make-dmg.sh and REPLACE draft paths
- `b3042f0` fix(release): refuse the native resource accessor only for distribution
- `43055f5` test(release): isolate DISTRIBUTION and check it in the dry run

Post-review fix commits (FINDING-24 to FINDING-40):

- `9ef8c76` test(release): run assert_status with errexit and isolate the runner
- `7ecf2a3` fix(release): say that brew upgrade quits and reopens AgentTacho
- `6dc3873` refactor(release): one release_defaults and environment-only make variables
- `9a854a6` fix(release): name the reason when a remote command fails
- `faae03c` fix(release): verify the DMG checksum and update the cask only for the latest release
- `6819789` docs(release): document tiers, test-only repo overrides and safe .p12 import
- `0498b05` test(release): cover notarize errors, moved annotated tags and ad-hoc releases

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 72
- **File:** scripts/release/make-dmg.sh:41-46
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** `uvx --from dmgbuild==1.6.7` pinned only dmgbuild. Its dependencies `ds_store>=1.1.0` and `mac_alias>=2.0.1` were resolved from PyPI without an upper bound on every release.

**Why this matters:** The DMG step runs on the maintainer's Mac with an authenticated `gh` and a signing key that `codesign` can use without a prompt. A compromised new upstream release of either dependency would run there.

**How it was resolved:** The call now pins `--with ds_store==1.3.3 --with mac_alias==2.2.3`, the versions in the local uv cache next to dmgbuild 1.6.7. A real `make dmg` run built the DMG with the pinned set.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** scripts/release/lib.sh (notary check), scripts/release/release.sh
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** `notary_available` treated every non-zero exit of `notarytool history` as "profile missing". A network outage, an Apple service error, expired credentials or a locked keychain silently turned a notarizable release into "Developer ID, not notarized", which was then published.

**Why this matters:** FR-014a allows the fallback only when the profile is missing. The downgrade cannot be undone once published, and users would get the first-launch workaround they should not need.

**How it was resolved:** `notary_profile_state` prints `available`, `missing` (only for notarytool's "No Keychain password item found", checked against the real message) or `error <message>`. A real release stops on `error` before building; a dry run only warns. The check moved before the build. Tests cover all three states in lib.sh and in the release flow.

### FINDING-3
- **Severity:** Important
- **Confidence:** 75
- **File:** scripts/release/build-app.sh:37-51
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0; refined in round 2, b3042f0)

**What is wrong:** The resource bundle is copied to `Contents/Resources`. Only the swiftbuild backend's `Bundle.module` accessor looks there. SwiftPM's native backend (the default on older toolchains that the README still allows) looks next to the `.app` and then at an absolute `.build` path on the build machine.

**Why this matters:** A release built with the native backend launches fine on the maintainer's Mac through the absolute path and crashes with `fatalError` on every user's Mac.

**How it was resolved:** build-app.sh looks for the native accessor's message "could not load resource bundle" in the binary. The current Swift 6.4 binary contains only the swiftbuild message "unable to find bundle named", so the check has no false positive here (a path-based check would have, because the build path appears in the symbol table). Builds for distribution (`DISTRIBUTION=1`, set by release.sh for `make dmg` and `make release`) stop; a plain `make app` only warns, so development builds keep working (FR-008, see FINDING-9).

### FINDING-4
- **Severity:** Important
- **Confidence:** 85
- **File:** scripts/release/tests/test_release_flow.sh (notarized path)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** The notarize stub left the DMG unchanged, so no test checked that release.sh recomputes the checksum after stapling.

**Why this matters:** A stale SHA-256 in the `.sha256` asset, `release-info.json` and the cask would break `brew install` (US2 scenario 1).

**How it was resolved:** The stub appends to the DMG like stapling does. The test asserts that `release-info.json` and the `.sha256` file carry the new hash. A mutation check (deleting the re-hash line) makes the test fail.

### FINDING-5
- **Severity:** Important
- **Confidence:** 80
- **File:** scripts/release/tests/test_release_flow.sh (REPLACE tests)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 771469c)

**What is wrong:** `REPLACE=1` was tested only against a published release. The draft branch (which selects the recovery message) and the no-existing-release branch had no test.

**Why this matters:** These branches decide which recovery instructions the maintainer sees after a failure.

**How it was resolved:** New tests: REPLACE on a draft resumes and publishes, a failure there prints the draft message and never "is published", and REPLACE without a release creates a draft and uploads with `--clobber`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 80
- **File:** scripts/release/build-app.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0 and 771469c)

**What is wrong:** Only the missing-icon guard of build-app.sh was tested. The tier output (FR-002), the ad-hoc warning (US3 scenario 4), the cdhash refusal (FR-003), the Developer ID flags (FR-005), the plist stamping (FR-006 to FR-008) and the icon key were never run, because the flow tests stub the script and it ignored `RELEASE_ROOT`.

**Why this matters:** A wiring mistake in the build script would pass every test.

**How it was resolved:** build-app.sh honors `RELEASE_ROOT`. The new `test_build_scripts.sh` builds against a fixture repository with stubbed `swift`, `codesign` and `security` and the real PlistBuddy, and asserts the output lines, the codesign flags per tier, the plist values for release and development versions, the cdhash refusal and the accessor check.

### FINDING-7
- **Severity:** Important
- **Confidence:** 80
- **File:** scripts/release/make-dmg.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0 and 771469c)

**What is wrong:** make-dmg.sh had no tests: argument check, missing icon and background errors, ad-hoc skipping codesign, the background variant passed to dmgbuild and the `.sha256` file.

**Why this matters:** The background variant and checksum feed directly into the release (FR-011, FR-012, FR-009).

**How it was resolved:** make-dmg.sh honors `RELEASE_ROOT`. Tests with a stubbed `uvx` and `codesign` assert the pinned uvx call, the background per tier and notarization, the signing flags, the checksum content and the error messages.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 75
- **File:** scripts/release/release.sh (exit trap)
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent, production-readiness-agent, spec compliance check)
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** After a failed upload the message only offered `gh release delete <tag> --yes`, without `-R` and without the retry path. The spec edge case asks for "how to retry or delete".

**How it was resolved:** The message is now `draft release vX.Y.Z left in place, retry with: make release REPLACE=1, or delete with: gh release delete vX.Y.Z -R <repo> --yes`. README and contract updated.

### FINDING-9
- **Severity:** Important
- **Confidence:** 80
- **File:** scripts/release/build-app.sh:37-51
- **Category:** regression
- **Source:** re-review agent (round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2, b3042f0)

**What is wrong:** The round 1 accessor guard also stopped plain `make app` builds, which on an older toolchain worked locally through the absolute build path.

**Why this matters:** FR-008 requires development builds to keep building.

**How it was resolved:** Only `DISTRIBUTION=1` builds stop; local builds warn. Tests cover both, and the flow tests check that both the dry run and the release pass `DISTRIBUTION=1`.

### FINDING-10
- **Severity:** Minor
- **File:** scripts/release/release.sh:53-58
- **Category:** external
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** release.sh did not itself refuse to publish when `version_info` returned a development version or no tag.

**How it was resolved:** A non-dry run now stops unless the mode is `release` with a tag. Preflight already prevents this, so it is defense in depth.

**External tool analysis (CodeRabbit):**
> After parsing version_info into tag in release.sh, add a guard that stops non-dry-run releases when tag is empty, using the existing error-handling mechanism. Leave dry-run behavior unchanged.

### FINDING-11
- **Severity:** Minor
- **File:** scripts/release/lib.sh (version_info)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (rounds 1 and 2)

**What is wrong:** Bash 3.2 ignores `set -e` inside command substitutions, so git failures in `version_info` produced an empty build number that PlistBuddy then wrote as `CFBundleVersion`.

**How it was resolved:** Each git call dies on failure and the build number must be numeric. Tests run `version_info` inside `v="$(version_info)"` as production does, outside a repository and with a non-numeric count.

### FINDING-12
- **Severity:** Minor
- **File:** scripts/release/lib.sh (preflight)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** A shallow clone only warned, so a release from one (the default for CI checkouts) would publish a build number of 1 (FR-007).

**How it was resolved:** Preflight reports a shallow clone; a release stops, a dry run warns.

### FINDING-13
- **Severity:** Minor
- **File:** scripts/release/update-cask.sh:27-32
- **Category:** correctness
- **Source:** correctness-agent (also reported by: production-readiness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** `make cask` accepted a release that was still a draft and would push a cask whose URL is not public.

**How it was resolved:** update-cask.sh refuses draft releases and names the publish command.

### FINDING-14
- **Severity:** Minor
- **File:** scripts/release/release.sh:60-102
- **Category:** architecture
- **Source:** architecture-agent (also raised as Notable by test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** In a dry run with Developer ID and a working profile, `release-notes.md` and `release-info.json` claimed "notarized" for a DMG that was never notarized.

**How it was resolved:** `notarize` (will be submitted, selects the background preview) and `notarized` (accepted and stapled) are separate; notes and release info use `notarized`. The dry-run test asserts it.

### FINDING-15
- **Severity:** Minor
- **File:** scripts/release/lib.sh (dmg_background)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** `dmg_background` repeated the notarization predicate of `effective_notarized`.

**How it was resolved:** It calls `effective_notarized`.

### FINDING-16
- **Severity:** Minor
- **File:** scripts/release/build-app.sh, scripts/release/make-dmg.sh
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, ecc97d0)

**What is wrong:** release.sh and notarize.sh honored `RELEASE_ROOT`, build-app.sh and make-dmg.sh did not.

**How it was resolved:** Both now `cd "${RELEASE_ROOT:-$SCRIPT_DIR/../..}"`, which also made FINDING-6 and FINDING-7 testable.

### FINDING-17 to FINDING-23 (round 1 and round 2 re-review follow-ups)
- **Severity:** Minor
- **Resolution:** fixed (b3042f0, 43055f5)

1. Contract and research notes described the old notary check, draft message, shallow handling and cask behavior (`contracts/make-targets.md`, `research.md`).
2. The cask test stub failed `release view` together with the download, hiding the download failure path; both paths now have exact-message tests.
3. The build-number validation had no test (added, with a mutation check).
4. The `make app` and `make dmg` contract sections did not mention the accessor warning and the dry run's `DISTRIBUTION=1` build.
5. The contract listed only two of the three partial-failure messages (the published-release retry was missing).
6. The test runner did not unset `DISTRIBUTION` (also `RELEASE_ROOT` and `CASK_TEMPLATE` now).
7. The dry-run flow test did not check `DISTRIBUTION=1`.

## Post-Review Fixes (formerly remaining Minor findings)

None of these blocked the gate. After the review the maintainer decided the ambiguous ones (24, 26, 27, 29, 32) and asked for all of them to be fixed. Each entry keeps the original finding and adds its resolution.

### FINDING-24 (ambiguous, spec evolution)
- **File:** scripts/release/lib.sh:294, 340-341; README.md:50; packaging/homebrew/agenttacho.rb.tmpl:15
- **Source:** production-readiness-agent (confidence 85)
- **Resolution:** fixed (`7ecf2a3`). Verified in the local Homebrew source (7.0.9-64): `Library/Homebrew/cask/artifact/abstract_uninstall.rb:126` records each bundle ID that `uninstall quit:` closed during an upgrade, and `Library/Homebrew/cask/upgrade.rb:498` calls `reopen_apps_after_upgrade` (lines 345 to 370, `open -b <bundle id>`) after a successful upgrade; only `brew upgrade --no-quit` (`cmd/upgrade.rb:130`, `HOMEBREW_NO_UPGRADE_QUIT_CASKS`) skips it. FR-024, the acceptance scenario, contracts/cask.md, data-model.md, research.md, the caveats, the release notes and the README now say that Homebrew quits AgentTacho before an upgrade and opens it again afterwards; non-notarized releases still need the first-launch step after each install or upgrade, and a DMG upgrade needs a manual restart. Every "not restarted after an upgrade" statement is gone.

**What is wrong:** The caveats, release notes and README say an upgrade does not restart AgentTacho. The cask indeed has no restart stanza (FR-024), but Homebrew 7.0.9 itself records apps closed by `uninstall quit:` and reopens them after `brew upgrade` (`Cask::Upgrade.reopen_apps_after_upgrade`, verified in the local Homebrew source by the agent).

**Why this matters:** Homebrew users get a caveat that contradicts what happens, and on non-notarized releases the automatic reopen hits the Gatekeeper block right after the upgrade.

**Proposed fix:** Evolve FR-024 and the caveat text: "Homebrew reopens a running AgentTacho after the upgrade; for releases that are not notarized, allow it once as described above. A DMG upgrade does not restart the app." Keep `uninstall quit:`.

### FINDING-25 (unambiguous)
- **File:** scripts/release/release.sh:34-36, update-cask.sh:21-22, lib.sh:203-204, 315, notarize.sh:20, build-app.sh and make-dmg.sh (`APP_ICON`, output paths)
- **Source:** architecture-agent
- **Resolution:** fixed (`6dc3873`). `release_defaults` in lib.sh holds the defaults of `GH_REPO`, `TAP_REPO`, `NOTARY_PROFILE`, `SIGN_IDENTITY_NAME`, `APP_ICON` and the output paths `APP` and `OUT_DIR`; every entry script and the lib functions reading the configuration call it. Tests cover unset, empty and overridden values.

**What is wrong:** Defaults for `GH_REPO`, `TAP_REPO`, `NOTARY_PROFILE`, `APP_ICON`, `build/AgentTacho.app` and `build/release` are repeated across scripts.
**Proposed fix:** A `release_defaults` function in lib.sh that every entry script calls after sourcing it.

### FINDING-26 (ambiguous)
- **File:** scripts/release/lib.sh:105-109
- **Source:** architecture-agent
- **Resolution:** fixed (`6819789`), no new tier. Spec Key Entities, data-model.md SigningTier, the README maintainer section and comments on `tier_for_name` and `select_identity` state that `self-signed` means any certificate that is not Developer ID.

**What is wrong:** With `SIGN_IDENTITY` naming any other certificate (for example "Apple Development: ..."), the tier is reported as `self-signed` in output, notes and `release-info.json`.
**Proposed fix:** Either accept only Developer ID or `$SIGN_IDENTITY_NAME` for releases, or add an `other` tier label.

### FINDING-27 (ambiguous)
- **File:** packaging/homebrew/agenttacho.rb.tmpl:5, 8; scripts/release/lib.sh (release_notes brew line)
- **Source:** architecture-agent
- **Resolution:** fixed (`6819789`). contracts/make-targets.md, the README variables table and the update-cask.sh header document `GH_REPO` and `TAP_REPO` as overrides for testing only; the cask template keeps the hardcoded `rhuss` URL.

**What is wrong:** `GH_REPO`/`TAP_REPO` are documented as overridable, but the cask URL and the brew command in the notes are hardcoded to `rhuss`.
**Proposed fix:** Add an `@GH_REPO@` placeholder, or document both variables as test-only.

### FINDING-28 (unambiguous)
- **File:** scripts/release/lib.sh:4-8
- **Source:** architecture-agent
- **Resolution:** fixed (`6819789`). The lib.sh header lists the functions that exit through `die` and when.

**What is wrong:** The header says every function signals failure through its exit status, but `select_identity`, `preflight release`, `render_cask` and now `version_info` exit through `die`.
**Proposed fix:** Name those functions in the header comment.

### FINDING-29 (ambiguous)
- **File:** scripts/release/update-cask.sh:34-49, scripts/release/release.sh (cask step)
- **Source:** security-agent
- **Resolution:** fixed (`faae03c`). release.sh compares the `sha256` written to release-info.json with the hash of the final (stapled) DMG and stops before anything reaches GitHub. update-cask.sh downloads the DMG asset with `gh release download` and stops when its hash differs from release-info.json. Tests use a stubbed gh serving fixture DMGs with matching, tampered and missing assets, and a release flow with a stale `.sha256`.

**What is wrong:** The cask checksum comes from `release-info.json` on the release and is never compared with the locally computed hash or the DMG asset itself.
**Proposed fix:** Pass the local hash from release.sh and compare; in cask-only mode download the DMG and recompute its SHA-256.

### FINDING-30 (unambiguous)
- **File:** Makefile:14-16, 56
- **Source:** security-agent
- **Resolution:** fixed (`6dc3873`). The Makefile exports the release variables and the recipes no longer contain their values (`make cask` reads `"$$VERSION"`); `git ls-remote` and `git clone` get `--` before the repository. Tests: `make -n` output of app, dmg, release and cask never contains a variable value, `VERSION="1; touch ..."` runs nothing, and a `TAP_REPO` of `--upload-pack=...` is never read as an option (it was before the fix).

**What is wrong:** Make variables are pasted into shell text (`$(VERSION)` unquoted), so a future CI caller passing untrusted input could inject commands.
**Proposed fix:** `export` the variables and read them as `"$$VERSION"` in the recipes; add `--` before repository arguments to git.

### FINDING-31 (unambiguous)
- **File:** README.md:156-163
- **Source:** security-agent
- **Resolution:** fixed (`6819789`). The README imports the `.p12` with the prompting forms of `security import` and `security set-key-partition-list`, deletes the file afterwards and leaves `-P`/`-k` to CI with secrets.

**What is wrong:** The `.p12` import example passes both passwords on the command line and does not say to delete the exported `.p12`.
**Proposed fix:** Show the prompting form for manual use, keep variables for CI only, and add a step to delete or vault the `.p12`.

### FINDING-32 (ambiguous)
- **File:** scripts/release/release.sh (REPLACE flow and cask step)
- **Source:** production-readiness-agent (related Notable from correctness-agent)
- **Resolution:** fixed (`faae03c`). update-cask.sh, which the release flow also runs, updates the cask only when the version is the highest `vX.Y.Z` among the non-draft releases of `GH_REPO` (`gh release list --exclude-drafts`, numeric order per component); otherwise it prints `cask: v<version> is not the latest release, cask left unchanged` and exits 0. Tests cover an older release, numeric ordering (0.10.0 over 0.9.0), list failures, an empty list, and `make release REPLACE=1` on an older tag with the real update-cask.sh.

**What is wrong:** `REPLACE=1` on an older tag pushes the cask back to that version, and replacing a published release's DMG leaves a window in which the live cask checksum does not match.
**Proposed fix:** Skip the cask update unless the tag is the latest release, or turn the release back into a draft before clobbering.

### FINDING-33 (unambiguous)
- **File:** scripts/release/lib.sh:236, 248; scripts/release/update-cask.sh:51
- **Source:** production-readiness-agent
- **Resolution:** fixed (`9a854a6`). `with_reason` appends the last non-empty stderr line of a failed `git` or `gh` call in parentheses. Deviation: git's generic trailer ("Could not read from remote repository", "Please make sure you have the correct access rights", "and the repository exists.") is skipped, because otherwise every git failure would end in "and the repository exists." instead of the real cause (for example "Permission denied (publickey)").

**What is wrong:** Remote checks discard stderr, so failures (host key, missing SSH key, permission denied) show only a generic message.
**Proposed fix:** Capture stderr and append its last line to the message.

### FINDING-34 (unambiguous, partly fixed)
- **File:** scripts/release/tests/run.sh:108-109
- **Source:** test-quality-agent
- **Resolution:** fixed (`9ef8c76`). The runner unsets every `GIT_*` variable of the caller and all stub control variables; a nested-runner test checks it.

**What is wrong:** `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and the stub control variables (`GH_FAIL_ON`, `NOTARY_OK`, ...) still leak from the caller.
**Proposed fix:** Add them to the `unset` list, or run each test under `env -i` with an allowlist.

### FINDING-35 (unambiguous)
- **File:** scripts/release/notarize.sh:30-39 (tests missing)
- **Source:** test-quality-agent
- **Resolution:** fixed (`0498b05`). Tests for a submission that fails without JSON and for a rejection whose log is not available yet.

**What is wrong:** The "submission failed" and "no log yet" branches have no test.
**Proposed fix:** Stub modes where `submit` fails without JSON and where `log` fails.

### FINDING-36 (unambiguous)
- **File:** scripts/release/update-cask.sh:63 (tests missing)
- **Source:** test-quality-agent
- **Resolution:** fixed (`faae03c`). Tests for a tap whose `pre-receive` hook rejects the push, a `"notarized":"yes"` fixture and a download that writes no release-info.json.

**What is wrong:** The tap push failure, an invalid `notarized` value and a download without `release-info.json` are untested.
**Proposed fix:** A bare tap with a failing `pre-receive` hook, and a fixture with `"notarized":"yes"`.

### FINDING-37 (unambiguous)
- **File:** scripts/release/tests/test_preflight.sh
- **Source:** test-quality-agent
- **Resolution:** fixed (`9a854a6` for the missing `origin` remote, `0498b05` for an annotated tag on origin that points elsewhere).

**What is wrong:** No test for an annotated tag on origin pointing elsewhere, or for a missing `origin` remote.
**Proposed fix:** Add both cases.

### FINDING-38 (unambiguous)
- **File:** scripts/release/tests/test_notes.sh, test_release_flow.sh
- **Source:** test-quality-agent
- **Resolution:** fixed (`0498b05`). The ad-hoc notes test asserts the ad-hoc paragraph, and flow tests cover a release with `ALLOW_ADHOC=1` and the stop without it.

**What is wrong:** No flow test for an `ALLOW_ADHOC=1` release, and the ad-hoc notes test does not assert the ad-hoc paragraph.
**Proposed fix:** Assert "granted again after every upgrade" and add the flow test.

### FINDING-39 (unambiguous)
- **File:** scripts/release/tests/run.sh:56-65, 135
- **Source:** test-quality-agent
- **Resolution:** fixed (`9ef8c76`). `assert_status` runs the command as `(set -e; "$@")` with errexit switched off only around the subshell and restored afterwards; discovery matches one-line test functions. Tests in test_runner.sh cover both (the errexit and discovery tests failed before the fix). All existing tests still pass under errexit.

**What is wrong:** `assert_status` runs the command on the left of `||`, which disables `set -e` inside it, and test discovery skips one-line test functions.
**Proposed fix:** Run the command with `set +e; ( "$@" ); actual=$?; set -e`, and discover tests with `declare -F`.

### FINDING-40 (unambiguous)
- **File:** scripts/release/tests/test_cask.sh:146-170
- **Source:** test-quality-agent
- **Resolution:** fixed (`faae03c`). The version-mismatch and all other update-cask error tests assert the full message; the malformed checksum is split into a short and an uppercase case.

**What is wrong:** The version-mismatch test only checks for "version", and the malformed-sha fixture is both short and uppercase.
**Proposed fix:** Assert the full message and split the sha case in two.

## Notable Observations

### NOTABLE-1
- **File:** scripts/release/lib.sh (release_notes, cask_caveats), scripts/release/render-dmg-backgrounds.swift:99-105, README.md:42-46
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The FR-011 first-launch text lives in four hand-maintained copies.
- **Rationale:** When Apple changes the flow again the copies will drift; one source in lib.sh plus a test that greps each copy for the `xattr` command would keep them aligned.

### NOTABLE-2
- **File:** scripts/release/lib.sh (preflight)
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** Preflight checks `gh auth status`, tap reachability and (after this review) shallow clones, which FR-016 does not list.
- **Rationale:** Sensible additions that the spec should name through evolution.

### NOTABLE-3
- **File:** scripts/release/dmg-settings.py:23, 35-38; scripts/release/render-dmg-backgrounds.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The window size and icon positions are defined in both files.
- **Rationale:** Changing one without re-rendering the PNGs misaligns the arrow; a shared source or at least a back-reference comment would help.

### NOTABLE-4
- **File:** scripts/release/lib.sh:86-147
- **Category:** security
- **Source:** security-agent
- **Description:** The identity is chosen by name only; nothing pins the expected certificate or tier for a release.
- **Rationale:** An expired Developer ID silently falls back to self-signed, changing the designated requirement for all users. An optional `REQUIRE_TIER` or expected SHA-1 or team ID guard would stop that.

### NOTABLE-5
- **File:** README.md:151
- **Category:** security
- **Source:** security-agent
- **Description:** The README tells the maintainer to set "Always Trust" for the self-signed root, which the scripts do not need.
- **Rationale:** It widens the damage of a leaked key on every machine where it is applied; the step could be marked optional or removed.

### NOTABLE-6
- **File:** scripts/release/release.sh (REPLACE on a published release)
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** `--clobber` on a live release removes the old asset before the new upload, so a failure can leave a published release without a DMG.
- **Rationale:** The spec's "stays a draft" guarantee only covers new releases; switching the release back to draft before clobbering would extend it.

### NOTABLE-7
- **File:** scripts/release/lib.sh (codesign_flags)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** Development builds with a Developer ID certificate also use `--timestamp`, which needs Apple's timestamp server.
- **Rationale:** FR-005 asks for it only for releases; offline `make app` would fail once a Developer ID certificate is installed.

## Goal Alignment

Skipped (no PR found for the branch).

## Post-Fix Spec Coverage

The fix loop removed no implementing code (it replaced `notary_available` with `notary_profile_state` and added guards), and every requirement was re-checked after round 2.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 to FR-004 signing order, tier output, certificate-based requirement, override | lib.sh select_identity, codesigning_identities; build-app.sh | ✓ |
| FR-005 hardened runtime and timestamp for Developer ID | lib.sh codesign_flags | ✓ |
| FR-006 icon, fail when missing | build-app.sh, Info.plist CFBundleIconFile | ✓ |
| FR-007, FR-008 version, build number, dev suffix | lib.sh version_info; build-app.sh; AppVersionInfo | ✓ |
| FR-009 to FR-013 DMG, backgrounds, volume icon | make-dmg.sh, dmg-settings.py, lib.sh dmg_background | ✓ |
| FR-014, FR-014a notarization, profile states | notarize.sh; lib.sh notary_profile_state; release.sh | ✓ |
| FR-015 to FR-019 release order, preflight, notes, non-interactive, dry run | release.sh; lib.sh preflight, release_notes | ✓ |
| FR-020 to FR-024 cask, update, cask-only, caveats, zap, quit | packaging/homebrew/agenttacho.rb.tmpl; update-cask.sh; lib.sh render_cask | ✓ (FR-024 evolved after FINDING-24, FR-021 extended by FINDING-29 and FINDING-32) |
| FR-025 README | README.md Installation and Releasing sections | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test / make test-release | 0 / 0 | 0 / 0 | passed (338 tests in 29 suites / 97 tests) |
| 1 | make test / make test-release | 0 / 0 | 0 / 0 | passed (338 / 117) |
| 2 | make test-release | 0 | 0 | passed (120) |
| cleanup | make test / make test-release | 0 / 0 | 0 / 0 | passed (338 / 120) |
| post-review fixes | make test / make test-release / make app SIGN_IDENTITY=- / make dmg | 0 / 0 / 0 / 0 | 0 / 0 | passed (338 / 155) |

A real `make dmg` dry run after round 1 built `build/release/AgentTacho-0.0.0-dev.dmg` with the pinned dmgbuild set (ad-hoc on this machine, no certificate installed). Test suite passed in all fix rounds.
