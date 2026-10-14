---
runbook_version: 1
feature: 005-macos-distribution
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 8462d4f
drafted_fingerprint: 9a301d394386e7904e15563eaf4a7610fcc8cab336a1fe3190c2309f18efc5ce
tested_at: 4ee5e87
tested_fingerprint: 40bc9471b169aa57572ddbb41ff837ab8fd46a9f48b38395c727d9d496085916
updated: 2026-10-14
---

# Try it: macOS Distribution (Signed DMG and Homebrew Cask)

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (9 passed) · Mode: light · Tested at 4ee5e87 · 2026-10-14
<!-- /runbook-status -->










## What you're testing

AgentMeter can now be built as a signed app with its icon and a version from git tags, packaged into a drag-to-Applications DMG, released to GitHub and installed through a Homebrew cask. This walkthrough tries everything that works without publishing: the release script tests, an ad-hoc and a self-signed build (permissions that survive rebuilds), the version shown in Settings, the DMG window with its first-launch instructions, the preflight that refuses an untagged release, the rendered cask, and the README sections.

Order of the journey: tests, ad-hoc build, self-signed certificate and build, version in Settings, DMG, preflight refusal, cask preview, README.

All commands run from the repository root of the feature branch (the worktree `.claude/worktrees/005-macos-distribution`, or `main` after merge).

## Test environment

No fixtures. The steps need the Xcode Command Line Tools, `uv` (for `uvx dmgbuild`), and network access for the first `uvx` download. Nothing is published: the release step uses invalid repository names on purpose.

## Steps

### Step 1 of 9: Run the release script tests (US4)

**Why this step:** The release, DMG and cask logic is covered by stubbed tests; a green run shows the logic works before anything touches the network.

**Run:**

```
make test-release
```

**What you should see:** One `ok` line per test and a final line `155 passed, 0 failed` (or more passed if tests were added), exit status 0.

**If you see something else:** A `FAIL` line names the test and the assertion; a missing `uvx` or `ruby` shows up as a failing DMG or cask test.

**Result:** passed (run by the agent). Output: 157 lines, saved to `specs/005-macos-distribution/.walkthrough/step-1.log`.

- ✔ one `ok` line per test → 155 `ok` lines, no `FAIL` line
- ✔ final `155 passed, 0 failed` → line 157: `155 passed, 0 failed`
- ✔ exit status 0 → exit status: 0

### Step 2 of 9: Build the app with an ad-hoc signature (US3)

**Why this step:** Shows the tier selection, the version stamp and the icon, and the warning that ad-hoc builds lose permissions on every rebuild.

**Run:**

```
make app SIGN_IDENTITY=- && plutil -p build/AgentMeter.app/Contents/Info.plist | grep -E 'CFBundleIconFile|CFBundleShortVersionString|CFBundleVersion|AgentMeterVersionDisplay' && codesign -d -r- build/AgentMeter.app 2>&1 | grep designated
```

**What you should see:** Output lines `version: <x.y.z>-dev (build <n>)`, `signing: ad-hoc (no certificate)` and the `warning: ad-hoc signature, ...will not persist across rebuilds` line; the plist shows `CFBundleIconFile => "AgentMeter"`, a numbers-only `CFBundleShortVersionString`, and `AgentMeterVersionDisplay` ending in `-dev`; the designated requirement contains `cdhash`.

**If you see something else:** `error: missing app icon` means `Resources/icons/macos/AgentMeter.icns` is not in the checkout; a SwiftUI macro error means the build ran outside the Makefile.

**Result:** passed (run by the agent). Output: 31 lines, saved to `specs/005-macos-distribution/.walkthrough/step-2.log`. No `vX.Y.Z` tag exists yet, so the version is `0.0.0`.

- ✔ `version: <x.y.z>-dev (build <n>)` → line 22: `version: 0.0.0-dev (build 74)`
- ✔ `signing: ad-hoc (no certificate)` → line 23: `signing: ad-hoc (no certificate)`
- ✔ ad-hoc warning → line 25: `warning: ad-hoc signature, notification permission and start at login will not persist across rebuilds`
- ✔ `CFBundleIconFile => "AgentMeter"` → line 28
- ✔ numbers-only `CFBundleShortVersionString` → line 29: `"0.0.0"`
- ✔ `AgentMeterVersionDisplay` ends in `-dev` → line 27: `"0.0.0-dev"`
- ✔ designated requirement contains `cdhash` → line 31: `# designated => cdhash H"e128c29f..."`

Other output: linker search path warnings and one `appendInterpolation` deprecation warning in `IconPickerSheet.swift:94`, both unrelated to this feature.

### Step 3 of 9: Create the "AgentMeter Signing" certificate once (US3)

**Why this step:** The stable self-signed tier needs a certificate in your login keychain. This is the one-time maintainer setup; the build never creates it.

**Do:**

1. Open Keychain Access, choose Keychain Access > Certificate Assistant > Create a Certificate.
2. Name: `AgentMeter Signing` (exactly, no space; the build matches the name exactly), Identity Type: Self Signed Root, Certificate Type: Code Signing. Check "Let me override defaults" and set the validity to 3650 days.
3. Key pair: RSA, 2048 bits (the default). Key Usage: only "Signature". Extended Key Usage: "Code Signing". Leave Basic Constraints unchecked and uncheck Subject Alternative Name (it is checked by default but stays empty). Keychain: login.
4. Open the new certificate, expand Trust, set "Code Signing" to Always Trust.
5. Check in Terminal: `security find-identity -p codesigning | grep "AgentMeter Signing"`

**What you should see:** The `security` command prints one line with a 40-character hash and `"AgentMeter Signing"` (with or without `CSSMERR_TP_NOT_TRUSTED`; both work).

**If you see something else:** No line means the certificate was created as a different type or under a different name; delete the certificate with its public and private key and repeat.

**Result:** passed on the second try (run by the user, checked by the agent).

- ✘ first try: `1) C92B19F9... "Agent Meter Signing" (CSSMERR_TP_NOT_TRUSTED)`. The name had a space, so `select_identity` (exact match against `SIGN_IDENTITY_NAME`) would have fallen back to ad-hoc. The user deleted the certificate and its key pair and recreated it.
- ✔ second try → `1) DF0E1E281C6A4C1E962E292C76DF83B8996D7C98 "AgentMeter Signing" (CSSMERR_TP_NOT_TRUSTED)`

Runbook correction: the original steps said "accept the other defaults" and did not name the key size, the key usage, or the Subject Alternative Name page, which is checked by default. Item 3 now spells these out, and item 2 warns that the name must match exactly.

### Step 4 of 9: Build with the self-signed certificate and check permissions survive (US3)

**Why this step:** This is the fix for the inbox item `stable-signing-identity`: a certificate-based designated requirement lets macOS keep the notification permission and start at login across rebuilds.

**Needs:** Step 3.

**Run:**

```
make app && codesign -d -r- build/AgentMeter.app 2>&1 | grep designated
```

**What you should see:** `signing: self-signed (AgentMeter Signing)` and no ad-hoc warning; the designated requirement mentions `certificate root` or `certificate leaf` and contains no `cdhash`. macOS may ask once to allow codesign to use the key; choose "Always Allow".

**If you see something else:** `signing: ad-hoc` means the certificate name does not match; `SIGN_IDENTITY_NAME` overrides it.

**Result:** passed (run by the agent). Output: 8 lines, saved to `specs/005-macos-distribution/.walkthrough/step-4.log`. Incremental build (no recompile), so no compiler warnings this time.

- ✔ `signing: self-signed (AgentMeter Signing)` → line 5: `signing: self-signed (AgentMeter Signing)`
- ✔ no ad-hoc warning → no `warning:` line in the output
- ✔ requirement is certificate-based, no `cdhash` → line 8: `designated => identifier "dev.rhuss.agentmeter" and certificate leaf = H"df0e1e281c6a4c1e962e292c76df83b8996d7c98"` (the leaf hash is the certificate's SHA-1 from Step 3)

Rerun after rebasing the branch onto `main` (see Step 5): `make test` 375 tests passed, `make test-release` 155 passed, and `make app` again printed `version: 0.0.0-dev (build 78)`, `signing: self-signed (AgentMeter Signing)` and the same `certificate leaf` requirement (`.walkthrough/step-4-rebased.log`).

### Step 5 of 9: See the version in Settings and the permission persistence (US3)

**Why this step:** The app shows its stamped version, and with the stable signature a granted notification permission stays granted after a rebuild.

**Needs:** Step 4. Quit any other running AgentMeter first, so only this build runs.

**Do:**

1. Run `open build/AgentMeter.app`, open the dropdown, choose Settings..., General tab.
2. Allow notifications if macOS asks; enable start at login.
3. Quit AgentMeter, run `make app && open build/AgentMeter.app` again, and open Settings once more.

**What you should see:** The bottom of the General tab shows "AgentMeter <x.y.z>-dev (build <n>)". After the rebuild, no new notification permission prompt appears, and System Settings > Notifications still lists AgentMeter as allowed; start at login is still on.

**If you see something else:** A new permission prompt after the rebuild means the build fell back to ad-hoc (check the `signing:` line). A "Configuration error: Label ... is already used" banner with no accounts means the branch is behind `main` and the config was already migrated by a newer build; rebase onto `main` first and do not save settings in the older build.

**Result:** passed on the second try (run by the user, reported as "works").

- ✘ first try, branch based on `84af103`: the dropdown showed `Configuration error: Label "Claude" of account "Claude Code via Vertex" is already used by another account or group.` and "No accounts configured". Cause: the 005 branch predated the spec 004 commits on `main` (icon-only labels), and the shared `~/.config/llm-usage-menubar/config.json` had already been migrated by a `main` build (`config.json.bak-004`), so the older label check rejected it. Not a 005 defect. The branch was rebased onto `main` (one append-only conflict in `brainstorm/idea-inbox.md`, both sides kept), tests rerun green, app rebuilt (Step 4 note).
- ✔ second try: the user confirmed the General tab shows the stamped version, no new notification prompt appeared after the rebuild, and the notification permission and start at login stayed on.

### Step 6 of 9: Build the DMG and look at its window (US1)

**Why this step:** This is what users download: the drag-to-Applications window with the first-launch instructions for builds that are not notarized.

**Run:**

```
make dmg && open build/release/AgentMeter-*-dev.dmg
```

**What you should see:** Output ends with `dmg: build/release/AgentMeter-<x.y.z>-dev.dmg (self-signed, not notarized)` (or `ad-hoc` without the certificate), possibly with `warning:` lines from the preflight (untagged commit). Finder opens a window with the AgentMeter icon on the left, an Applications shortcut on the right, an arrow between them, and a panel with the first-launch steps for macOS 14, macOS 15 or later, and the `xattr` command. The mounted volume carries the AgentMeter icon (on the Desktop, in Get Info, and as the window's title proxy icon; the Finder sidebar draws a generic disk glyph for every volume since macOS 11).

**If you see something else:** A dmgbuild download error means no network for `uvx`; a cut-off instructions panel is a layout issue in `scripts/release/dmg-settings.py`.

**Result:** passed (built and opened by the agent, window checked by the user). Output: 10 lines, saved to `specs/005-macos-distribution/.walkthrough/step-6.log`.

- ✔ `dmg: ... (self-signed, not notarized)` → line 10: `dmg: build/release/AgentMeter-0.0.0-dev.dmg (self-signed, not notarized)`
- ✔ preflight `warning:` lines allowed → lines 1 and 2: `warning: working tree has uncommitted changes`, `warning: HEAD has no vX.Y.Z tag`
- ✔ DMG signed (extra check) → `codesign -dvvv`: `Authority=AgentMeter Signing`; `shasum -a 256 -c AgentMeter-0.0.0-dev.dmg.sha256` → `OK`
- ✔ window layout → user: app icon left, Applications right, arrow, first-launch panel complete
- ✔ volume icon → `/Volumes/AgentMeter/.VolumeIcon.icns` is identical to `Resources/icons/macos/AgentMeter.icns`, and the volume's `com.apple.FinderInfo` has the custom-icon flag (`04 00` at offset 8)

Runbook correction: the original expectation said the Finder sidebar shows the AgentMeter icon. The user saw a generic disk glyph there, which is how the sidebar renders every volume on current macOS (the MacMD Viewer volume next to it looks the same). The expectation now names the places where a custom volume icon appears.

### Step 7 of 9: Confirm a release refuses an untagged commit (US4)

**Why this step:** The preflight must stop before building or publishing anything when HEAD has no `vX.Y.Z` tag. The invalid repository names make sure nothing can be published even if a check were wrong.

**Run:**

```
GH_REPO=invalid/invalid TAP_REPO=/nonexistent make release; echo "exit status: $?"
```

**What you should see:** An `error:` line naming the problem (for example `HEAD has no vX.Y.Z tag`, or the dirty tree if you have local changes) and a non-zero exit status; no build output after the error.

**If you see something else:** Any `release:` line about creating a draft would be a serious bug; stop and report it.

**Result:** passed (run by the agent, stdin from `/dev/null`).

```
error: working tree has uncommitted changes
make: *** [release] Error 1
exit status: 2
```

- ✔ `error:` line naming the problem → `error: working tree has uncommitted changes` (the preflight stops at the first problem, so the missing tag was not reported)
- ✔ non-zero exit status → `exit status: 2`
- ✔ no build output after the error → none, and no `release:` line

### Step 8 of 9: Preview the Homebrew cask (US2)

**Why this step:** Shows exactly what `brew install --cask rhuss/tap/agentmeter` will install, including the caveats for a release that is not notarized.

**Run:**

```
bash -c 'source scripts/release/lib.sh && render_cask 0.2.0 0000000000000000000000000000000000000000000000000000000000000000 false' | tee /tmp/agentmeter-cask.rb && ruby -c /tmp/agentmeter-cask.rb
```

**What you should see:** A `cask "agentmeter"` definition with version `0.2.0`, the GitHub release URL, `depends_on arch: :arm64`, `depends_on macos: ">= :sonoma"`, `uninstall quit: "dev.rhuss.agentmeter"`, a `zap trash:` list with the config, log and preferences paths, and caveats with the first-launch steps plus the note that Homebrew quits and reopens AgentMeter on upgrade; then `Syntax OK`.

**If you see something else:** `missing cask template` means `packaging/homebrew/agentmeter.rb.tmpl` is not in the checkout.

**Result:** passed (run by the agent). The rendered cask is 33 lines followed by `Syntax OK`, exit status 0.

- ✔ `cask "agentmeter"`, `version "0.2.0"` → both present
- ✔ GitHub release URL → `url "https://github.com/rhuss/agentmeter/releases/download/v#{version}/AgentMeter-#{version}.dmg"`
- ✔ `depends_on arch: :arm64`, `depends_on macos: ">= :sonoma"` → both present
- ✔ `uninstall quit: "dev.rhuss.agentmeter"` → present
- ✔ `zap trash:` with config, log and preferences → `~/.config/llm-usage-menubar`, `~/Library/Logs/llm-usage-menubar`, `~/Library/Preferences/dev.rhuss.agentmeter.plist`
- ✔ caveats with first-launch steps and upgrade note → `AgentMeter is not notarized by Apple...`, the macOS 14 and macOS 15 lines, the `xattr` command, `Homebrew quits AgentMeter before an upgrade and opens it again afterwards.`
- ✔ `Syntax OK`

Cosmetic finding: the caveat continuation line `System Settings > Privacy & Security.` is indented to column 21 (matching the padded `macOS 14:` label), while the text after `macOS 15 or later:` starts at column 25, so the wrapped line sits 4 columns left of the text it continues.

### Step 9 of 9: Read the README installation and release sections (US5)

**Why this step:** Users and the maintainer need written instructions that match what the tooling does.

**Run:**

```
sed -n '/^## Installation/,/^## Build and run/p;/^## Releasing (maintainer)/,/^## Credits/p' README.md
```

**What you should see:** An Installation section with the download link, the `brew install --cask rhuss/tap/agentmeter` command, the first-launch steps for macOS 14 and 15+, the one-copy note and the upgrade behavior; and a Releasing section covering the certificate setup (3650 days, Always Trust, `.p12` export and import without passwords on the command line), the optional notarization profile `agentmeter-notary`, `make dmg`, `make release`, `make cask VERSION=...` and the variables.

**If you see something else:** Missing sections mean the docs commit is not on this branch.

**Result:** passed (run by the agent). Output: 97 lines, saved to `specs/005-macos-distribution/.walkthrough/step-9.log`.

- ✔ download link → line 5: `[latest release](https://github.com/rhuss/agentmeter/releases/latest)`
- ✔ brew command → line 10: `brew install --cask rhuss/tap/agentmeter`
- ✔ first-launch steps → lines 17 and 18 (macOS 14, macOS 15 or later)
- ✔ one-copy note and upgrade behavior → line 23: `Run only one copy of AgentMeter at a time. ... brew upgrade quits a running AgentMeter before the upgrade and opens it again afterwards`
- ✔ certificate setup → lines 34 (3650 days), 35 (Always Trust), 39 to 49 (`.p12` export, `security import` that asks for the password in a dialog)
- ✔ notarization profile → line 56: `xcrun notarytool store-credentials agentmeter-notary`
- ✔ `make dmg`, `make release`, `make cask VERSION=X.Y.Z` → lines 65, 67, 75
- ✔ variables → lines 84 to 91

Finding: line 34 says "keep the other defaults", which in Step 3 left the key size, the key usage and the Subject Alternative Name page (checked by default, empty) open, and the README does not warn that the name must match `AgentMeter Signing` exactly. The same gap Step 3 hit.

## Not covered here

- Publishing a real GitHub release, the cask commit to `rhuss/homebrew-tap`, and `brew install`, `brew upgrade`, `brew uninstall --zap` on a clean account: these publish artifacts, so they are the maintainer's first release after merge (quickstart.md sections 7 to 9).
- Developer ID signing and notarization: no Developer ID certificate exists yet; only the stubbed tests in Step 1 cover that path.
- Installing from the DMG on a second account or Mac with the quarantine attribute (quickstart.md section 5): needs a second machine or user account.

## Coverage

- US1 (install from DMG): Step 6 (window and instructions); the quarantined install on another account is not covered here.
- US2 (Homebrew): Step 8 (rendered cask); real install, upgrade and zap need a published release.
- US3 (permissions survive rebuilds): Steps 2 to 5.
- US4 (one-command release): Steps 1 and 7; a real release is not covered here.
- US5 (README): Step 9.

## Results

All 9 steps passed (6 run by the agent, Step 3 and Step 5 by the user, Step 6 together); none failed or were skipped. Two steps needed a second try, neither because of a defect in this feature:

- Step 3: the certificate was first created as "Agent Meter Signing"; the build matches the name exactly and would have fallen back to ad-hoc. Recreated with the right name.
- Step 5: the branch predated the spec 004 commits on `main`, and the older code rejected a config already migrated by a `main` build. The branch was rebased onto `main` (tests: 375 Swift, 155 release, all green) before the step passed.

What a reader now knows: the build picks the self-signed tier, stamps the version and icon, and produces a certificate-based designated requirement, so notification permission and start at login survive a rebuild (confirmed by hand). `make dmg` produces a signed DMG with a verified checksum, the drag-to-Applications layout, the first-launch panel and a custom volume icon. `make release` refuses a dirty tree before building or publishing anything. The rendered cask has the expected dependencies, uninstall, zap and caveats and is valid Ruby. The README covers installation and the release workflow.

Runbook corrections made during the session: Step 3 now names the key and extension settings and warns about the exact name; Step 6 no longer expects the volume icon in the Finder sidebar, which draws a generic glyph for every volume.

Follow-ups found: the README certificate steps (line 34) have the same gaps as the old Step 3, and the cask caveat's wrapped macOS 15 line is misaligned by 4 columns.
