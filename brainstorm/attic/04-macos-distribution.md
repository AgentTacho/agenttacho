# Brainstorm: macOS Distribution (Signed DMG and Homebrew Cask)

**Date:** 2026-10-14
**Status:** active

## Problem Framing

AgentTacho is built from source with `make app` and signed ad-hoc. There is no way for other people to install it without a Swift toolchain, and no versioned releases exist. The ad-hoc signature also changes with every build, so macOS treats each build as a new app: the notification permission and the start-at-login registration are lost after a rebuild (idea inbox item `stable-signing-identity`, folded into this session). The same would happen to users on every update.

The goal is a distributable, signed drag-to-Applications DMG published as a GitHub release, plus installation through Homebrew, without requiring the paid Apple Developer Program today while being ready for it.

## Approaches Considered

### A: Tiered signing in one release path
Release and development builds use the best identity available: Developer ID with notarization and stapling when the certificate and notary credentials are present; otherwise a stable self-signed code-signing certificate; ad-hoc only as the last fallback.
- Pros: one code path, upgraded later just by installing a certificate; a stable identity keeps notification permission and start at login across rebuilds and across updates for users, even without Apple's program.
- Cons: self-signed DMGs still trigger the "unverified developer" warning on first open, so the DMG, the cask and the README must explain a one-time step.

### B: Developer ID or nothing
No public releases until a Developer ID exists; development builds use the self-signed identity.
- Pros: users never see a Gatekeeper warning.
- Cons: nothing ships until the membership is paid.

### C: Ad-hoc releases now, signing later
- Pros: least work.
- Cons: every update loses notification permission and start at login (the inbox problem stays).

### Installer format (decided along the way)
Drag-to-Applications DMG chosen over a `.pkg` installer: AgentTacho is a single app with no system-wide setup, start at login is an in-app setting, and a `.pkg` would need admin rights and a separate Developer ID Installer certificate.

### Homebrew channel (decided along the way)
A cask (not a formula: a formula is for command-line tools, a cask installs a `.app`) in the existing `rhuss/homebrew-tap` repository. The official `homebrew/cask` repository was ruled out for now (notability requirement, Gatekeeper requirement for unsigned apps, a PR per release).

### Release location (decided along the way)
Local first (`make release`), kept scriptable so a GitHub Actions workflow can call the same steps later. Signing material stays in the local keychain.

## Decision

Approach A. One release path with tiered signing (Developer ID plus notarization, else stable self-signed, else ad-hoc), producing a drag-to-Applications DMG uploaded to a GitHub release, and a cask in `rhuss/homebrew-tap` updated by the release. Development builds (`make app`, `make run`) use the same identity selection, which resolves the `stable-signing-identity` inbox item.

## Key Requirements

- **Signing tiers**: the build selects the identity in this order: Developer ID Application (then notarize and staple the DMG), a stable self-signed code-signing certificate, ad-hoc. The chosen tier is printed and recorded in the release notes. A certificate-based designated requirement must be verifiable (`codesign -d -r-` shows the certificate, not a cdhash) for the first two tiers.
- **Persistence across updates**: with the first two tiers, notification permission and start at login survive a rebuild and an upgrade to a newer release.
- **DMG layout**: a window with `AgentTacho.app` and a link to `/Applications`, a background image, and the app icon.
- **One-time step in the DMG background**: when the build is not notarized, the background shows short instructions for the first launch: on macOS 14, Control-click AgentTacho in Applications and choose Open; on macOS 15 and later, open it once, then choose "Open Anyway" in System Settings, Privacy & Security; alternatively `xattr -dr com.apple.quarantine /Applications/AgentTacho.app`. A notarized DMG uses a background without these instructions.
- **App icon**: the provided icon set is stored in the repository under `Resources/icons/` (macOS `.icns` and iconset, 1024 px PNG, masters, web favicons). `Resources/icons/macos/AgentTacho.icns` goes into the bundle (`CFBundleIconFile` = `AgentTacho`) and serves as the DMG volume icon.
- **Versioning**: the release version comes from a git tag `vX.Y.Z` and is stamped into `CFBundleShortVersionString`; `CFBundleVersion` increases monotonically. The DMG is named `AgentTacho-X.Y.Z.dmg`.
- **GitHub release**: `make release` creates the tag's GitHub release on `rhuss/agenttacho` and uploads the DMG with its SHA-256.
- **Homebrew cask**: `Casks/agenttacho.rb` in `rhuss/homebrew-tap`, installable with `brew install --cask rhuss/tap/agenttacho`; the release updates its version and checksum. For non-notarized builds the cask shows caveats with the one-time step. The cask's `zap` removes the configuration (`~/.config/agenttacho`) and the log directory.
- **Platform**: Apple Silicon (arm64), macOS 14 or newer, as today.
- **README**: installation section (DMG, Homebrew, first-launch step) and the app icon at the top.
- **CI-ready**: all release steps run non-interactively from one script so a later GitHub Actions workflow can call it; no CI in this feature.

## Open Questions

- Name of the self-signed certificate and how it is created (documented manual steps in Keychain Access versus a script using `security` and `openssl`), and how a second machine or a future CI job gets the same identity.
- Whether the cask should clear the quarantine attribute itself in a `postflight` step for non-notarized builds, or only print caveats (convenience versus bypassing Gatekeeper on the user's behalf).
- Notarization credentials: `notarytool` keychain profile name and how `make release` detects that notarization is possible.
- Whether the DMG background is a static image per tier or rendered at build time with the version number.
- Behavior when the tag already has a release, or the tap has uncommitted changes (refuse, or overwrite with a flag).
- Whether a universal (arm64 plus x86_64) build is worth adding later.
