# Brainstorm: Auto-Update

**Date:** 2026-10-16
**Status:** active

## Problem Framing

AgentMeter ships as a notarized Developer ID DMG on GitHub releases and as a cask in `rhuss/homebrew-tap`. Homebrew users get new versions through `brew upgrade`, but DMG users only learn about a release by checking GitHub themselves, so they stay on old builds (idea inbox item `auto-update`, from the CodexBar comparison).

The goal is that an installed AgentMeter notices a newer release and makes installing it a single click for DMG installs, while Homebrew installs keep Homebrew as their update channel. AgentMeter values few dependencies and a small trust surface, and its README promises that it contacts no server besides the usage endpoints and the optional price import, so the update check is a new outbound request that has to be documented and can be turned off.

## Approaches Considered

### A: Own small updater
Ask GitHub for the latest release, download the DMG, check its SHA-256 against the published value, accept it only if it is notarized and signed by the same Developer ID team as the running app, replace the app and relaunch.
- Pros: no dependency and no new signing key (reuses the existing Developer ID and notarization trust); the UI is AgentMeter's own dropdown line; the security statement grows by one GitHub request.
- Cons: the installer code is ours to get right (atomic replacement, unwritable install location, running from the DMG or a translocated path); those cases fall back to the release link.

### B: Sparkle 2 with a custom user driver
The standard Mac updater with an EdDSA-signed appcast, its UI replaced by a custom user driver that feeds the dropdown line.
- Pros: tested installer with authorization for admin-owned `/Applications`, rollback and edge cases handled.
- Cons: first third-party dependency with bundled XPC services; a new EdDSA private key and appcast publishing in the release script; embedding and signing the framework in the custom bundle script; replacing Sparkle's UI is real work.

### C: Notice plus guided download
Same check as A, but "Install" downloads and verifies the DMG and opens it for the user to drag over.
- Pros: almost no installer code.
- Cons: not one click.

### Choices made along the way
- **How far to go**: one-click install for DMG installs, plus a release-page link for people who prefer to install by hand. Notify-only and silent install were ruled out.
- **Homebrew installs**: show the same notice, but the action is `brew upgrade --cask agentmeter` instead of replacing the app (no fight with the cask). Staying silent was ruled out.
- **Trigger**: automatic background check about once a day, on by default, with a Settings toggle and a "Check for Updates…" item. Asking on first launch and manual-only were ruled out.
- **Surface**: a quiet line in the dropdown and the same in Settings. No macOS notification, no update window, no change to the menu bar.

## Decision

Approach A: an own small updater without new dependencies, trusting a release only when its DMG matches the published SHA-256 and the app inside is notarized and signed by the same Developer ID team as the running app. DMG installs get a one-click install with relaunch; Homebrew installs get a `brew upgrade` action; both see the same dropdown line.

## Key Requirements

- **Check**: about once a day in the background against the latest published (non-draft, non-prerelease) GitHub release of `rhuss/agentmeter`, plus "Check for Updates…" on demand. On by default; a Settings toggle turns the automatic check off. No credentials, no cookies, no data about the user's usage in the request.
- **Version comparison**: a release counts as newer only when its version is higher than `CFBundleShortVersionString` of the running app.
- **Dropdown line**: "AgentMeter X.Y.Z available" with an install action and a "Release notes" link, at the bottom of the dropdown; the same information in Settings. No line when up to date; nothing in the menu bar itself.
- **DMG install, one click**: download the DMG, verify the SHA-256 published with the release, verify that the app inside has a valid signature from the same Developer ID team as the running app and is notarized, replace the installed app, relaunch. Notification permission and start at login carry over (same certificate).
- **Safe fallback**: when the app runs from the DMG, from a translocated path, from a location it cannot write to, or any verification fails, it does not install and offers the release page instead, with a short reason.
- **Homebrew install**: detected automatically; the action runs or copies `brew upgrade --cask agentmeter` instead of replacing the app.
- **Development builds**: builds made with `make app` from source do not offer to replace themselves with a release.
- **No new dependency**: no Sparkle, no new signing key; the release process stays as it is apart from what the check needs from the release.
- **Security statement**: the README's "Security and privacy" section names the new request (host, what is sent, how often, how to turn it off) and how a downloaded update is verified, in the same pull request.
- **Logic in UsageCore**: version comparison, release parsing, install-kind detection and the verification decisions live in `UsageCore` with tests; the app target only wires the UI and the file operations.

## Out of Scope

- Pre-release or beta channels
- Delta updates
- Silent or unattended installs
- macOS notifications or an update window
- "Skip this version"

## Open Questions

- Source of the check: the GitHub REST API (`/repos/rhuss/agentmeter/releases/latest`, unauthenticated rate limit of 60 requests per hour per IP) or a fixed asset URL such as `releases/latest/download/release-info.json`, and which fields `release-info.json` must carry (version, DMG name, SHA-256, minimum macOS)
- How the SHA-256 is trusted: from `release-info.json` / the `.sha256` asset over HTTPS only, or whether the code signature and notarization check alone is the real trust anchor
- How Homebrew installs are detected (Caskroom entry for `agentmeter`, receipt, install path) and whether the action runs `brew` directly or copies the command into the clipboard
- How the replacement and relaunch work while the app is running (helper script after quit, move old bundle to the Trash, keep a backup until the new one starts)
- What happens when `/Applications/AgentMeter.app` is owned by another user or root: fall back to the release link, or ask for admin rights
- Exact check interval, jitter, and behavior when offline or rate limited (silent retry next day, a note in the diagnostic log)
- How development builds are recognized (signing tier, version suffix, bundle location)
- Wording and placement of the dropdown line and the Settings section, and where the toggle sits
