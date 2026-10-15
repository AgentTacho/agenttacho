# Quickstart: Validating macOS Distribution (005)

Validation scenarios that prove the feature end to end. Commands run from the repository root on an Apple Silicon Mac with macOS 14 or newer. Contracts: [make-targets](contracts/make-targets.md), [release-info](contracts/release-info.md), [cask](contracts/cask.md).

## Prerequisites

- Xcode Command Line Tools, `gh` authenticated (`gh auth status`), `uv` installed (`uvx` on `PATH`), SSH access to `github.com:rhuss/homebrew-tap`.
- Optional for the stable tier: a code-signing certificate named "AgentMeter Signing" in the login keychain (README, Maintainer section).

## 1. Script tests (no signing, no network)

```bash
make test-release
make test
```
Expected: both report all tests passing.

## 2. Development build, ad-hoc tier (US3 scenario 4)

```bash
make app SIGN_IDENTITY=-
codesign -d -r- build/AgentMeter.app 2>&1 | grep designated
```
Expected: output has `signing: ad-hoc` and the ad-hoc warning; the requirement contains `cdhash`. `plutil -p build/AgentMeter.app/Contents/Info.plist` shows `CFBundleIconFile => AgentMeter`, a numeric `CFBundleShortVersionString`, and `AgentMeterVersionDisplay` ending in `-dev`.

## 3. Development build, self-signed tier (US3 scenarios 1 to 3)

```bash
make app
codesign -d -r- build/AgentMeter.app 2>&1 | grep designated
make run
```
Expected: `signing: self-signed (AgentMeter Signing)`; the requirement contains a certificate clause (`certificate root = H"…"` or `certificate leaf = H"…"`) and no `cdhash`. Settings, General tab shows "AgentMeter <version>-dev (build <n>)". Grant notifications, enable start at login, then `make run` twice more: no new permission prompt, a threshold notification still arrives (SC-003), and the login item stays enabled.

## 4. Dry run DMG (US1, FR-019)

```bash
make dmg
open build/release/AgentMeter-*-dev.dmg
```
Expected: a Finder window with the AgentMeter icon on the left, the Applications shortcut on the right, the drag arrow, and (self-signed tier) the first-launch instructions for macOS 14 and 15+ plus the `xattr` command. The mounted volume shows the AgentMeter icon. Drag to a scratch folder, not `/Applications`, if the development copy should stay.

## 5. Install from the DMG as a new user (US1 scenario 4, SC-001)

Copy the DMG to a second user account or Mac (for example with AirDrop, so it gets the quarantine attribute). Open it, drag to Applications, follow the on-screen first-launch step. Expected: AgentMeter appears in the menu bar within 3 minutes of opening the DMG.

## 6. Preflight refusals (SC-005)

```bash
make release                       # on an untagged commit
git tag v0.0.99 && make release    # tag not pushed
```
Expected: both stop with `error:` naming the problem; `gh release list` shows no new release; the tap has no new commit. Clean up with `git tag -d v0.0.99`.

## 7. First real release (US4, US2)

```bash
git tag v0.2.0 && git push origin v0.2.0
make release
```
Expected: `release:` lines for draft creation, three uploads and publishing; `cask:` line with the tap commit. The release page lists `AgentMeter-0.2.0.dmg`, `AgentMeter-0.2.0.dmg.sha256`, `release-info.json`, and notes stating "self-signed, not notarized" with the first-launch steps.

Then on a clean account:

```bash
brew install --cask rhuss/tap/agentmeter
```
Expected: installs into `/Applications`, prints the caveats. After the first-launch step the app runs.

## 8. Upgrade and zap (US2 scenarios 3 and 4)

After a second release `v0.2.1`:

```bash
brew upgrade --cask agentmeter
brew uninstall --zap --cask agentmeter
```
Expected: the upgrade quits the running app and installs 0.2.1 (notifications still allowed because the tier did not change); zap removes the app, `~/.config/agentmeter`, `~/Library/Logs/agentmeter` and `~/Library/Preferences/dev.rhuss.agentmeter.plist`.

## 9. Cask-only recovery (FR-021a)

```bash
make cask VERSION=0.2.0
```
Expected: `cask: already up to date` for the current cask, or a new tap commit when the cask was stale.

## Not verifiable yet

Developer ID signing, notarization and the notarized background (FR-005, FR-014, FR-014a, SC-006) need a Developer ID certificate; only the stubbed tests in step 1 cover them.
