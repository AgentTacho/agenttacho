# Review Guide: Rebrand AgentMeter to AgentTacho

**Generated**: 2026-10-16 | **Spec**: [spec.md](spec.md)

## Why This Change

The name AgentMeter belongs to another product in the same field: agentmeter.app tracks token usage of Claude Code, Cursor and Codex sessions and owns `github.com/AgentMeter`. Sharing a name with a competitor confuses search, links and word of mouth, and the cheapest moment to rename is now, before the landing page launches and while the installed base is about one person. The new name AgentTacho was researched for collisions (brainstorm 22) and matches the existing gauge mascot, so the imagery stays.

## What Changes

The app, its bundle identifier, data folders, release artifacts, Homebrew cask, GitHub repository and docs move from AgentMeter to AgentTacho as a clean break: macOS treats AgentTacho as a new app (`dev.rhuss.agenttacho`). Users moving over keep their setup through a one-time, read-only copy of AgentMeter's configuration, imported prices and last good values, and AgentTacho offers to stop a still running AgentMeter. `brew upgrade` moves existing Homebrew installs to the new cask. **Breaking for existing installs**: AgentMeter 0.4.x cannot one-click update to AgentTacho; it shows 0.5.0 as available and links to the release page, and the user installs AgentTacho once by hand. Notification permission and launch at login start over, because macOS keeps them per app.

## How It Works

- **Rename**: `git mv` of the executable target (`Sources/AgentMeter` to `Sources/AgentTacho`), icons, the cask template and an image; Info.plist and its custom keys (`AgentTacho*`); user-facing strings; update logic names (official source `AgentTacho/agenttacho`, expected DMG `AgentTacho-<v>.dmg`, cask `agenttacho`, User-Agent).
- **One-time move** (`UsageCore/Config/LegacyDataMove.swift`): runs in `AppModel.init(paths:)` after the log exists and before any store reads, only when `~/.config/agenttacho/` does not exist; copies each present file to a temporary file in the destination folder and moves it into place; never writes under the old folders; returns an outcome that `AppModel` logs. No UI.
- **Running AgentMeter**: `RunningInstance` accepts a set of bundle identifiers and knows each app's name; `SingleInstance.ensure()` (which already runs before `AppModel`) queries both identifiers and shows the existing alert.
- **Release tooling**: new defaults (`GH_REPO`, `SITE_REPO`, `agenttacho-notary`, `AgentTacho Signing`), DMG and notes names; `release.sh` starts the site's `deploy.yml` after publishing a latest release and before the cask step, warning only on failure; `update-cask.sh` writes `Casks/agenttacho.rb`, removes `Casks/agentmeter.rb` and adds `cask_renames.json` once.
- **DMG artwork**: the notarized background had the title painted in; it becomes a title-less base, and `render-dmg-backgrounds.swift` draws the title from text for both backgrounds.
- **Guard rail**: `scripts/release/tests/test_names.sh` fails `make test-release` on any "AgentMeter" outside an allowlist with a requirement per line.
- **Operations** (maintainer approval): transfer `rhuss/agentmeter` to `AgentTacho` and rename it `agenttacho`, verify GitHub's redirects with `curl` before releasing 0.5.0.

## When It Applies

**Applies when**:
- Building, running or releasing the app from this repository (every build is AgentTacho).
- A user starts AgentTacho for the first time on a Mac where AgentMeter was used (one-time copy, running-copy alert).
- An AgentMeter 0.4.x install checks for updates or runs `brew upgrade` after 0.5.0 (redirect, cask rename).

**Does not apply when**:
- The landing page repository (`AgentTacho/agenttacho.github.io`) is renamed: a separate task list in that repository (brainstorm 22).
- Local folder renames on the maintainer's Mac, the domain, and a formal trademark search: outside the spec.
- Historical specs, brainstorms and `docs/superpowers/`: keep the old name by design.

## Key Decisions

1. **Clean break instead of continuity.** Alternatives: keep the old bundle identifier under a new display name, or ship a bridge release 0.4.2 that updates into AgentTacho. Rejected because the installed base is about one person and both would keep the old name inside the code; 0.4.x still points to the new release through GitHub's redirect.
2. **Copy, never move, AgentMeter's files.** Moving would write to AgentMeter's folders; the copy leaves AgentMeter fully working and matches the project's read-only stance toward other apps' files.
3. **Copy only when the new configuration folder is missing, no retry.** Keeps AgentTacho from ever overwriting its own setup; a failed copy is logged and the README explains the manual path.
4. **No in-app rename notice** (clarification 2026-10-16). The README carries the moving instructions; the single-instance alert covers the one risky moment.
5. **Rename the cask inside the tap** with `cask_renames.json` rather than deprecating the old cask, so `brew upgrade` moves users without manual steps.
6. **First release 0.5.0, numbering continues**; the transferred repository keeps tags and history.
7. **Name check as a test**, so the old name cannot creep back in later features.

## Areas Needing Attention

- **Homebrew behavior** (research R1): the docs confirm the rename mapping but not that `brew upgrade` removes the old `AgentMeter.app`; quickstart Q6 verifies it, and the README covers the manual fallback.
- **DMG background patch** (research R3): filling the title band of the committed artwork must look seamless at 1x and 2x; the fallback is regenerating the artwork without text.
- **GitHub redirects** depend on nobody creating `rhuss/agentmeter` again; the README warns about it and the checks run before 0.5.0.
- **Sequencing**: implementation waits for `021-recover-stuck-offline` to land; the rename touches the same files.
- **Scope of the mechanical rename**: about 90 files; review by commit (each phase is a separate commit) rather than as one diff.

## Open Questions

- Should the README's "formerly AgentMeter" line stay permanently or be dropped after a few releases? (brainstorm 22)
- When to run a formal trademark search (USPTO, EUIPO, DPMA) for AgentTacho, before 0.5.0 or before the site launch? (brainstorm 22)

## Review Checklist

- [ ] Key decisions are justified
- [ ] Breaking changes are documented with migration guidance (README "Moving from AgentMeter")
- [ ] Scope matches the stated boundaries (site and local renames excluded)
- [ ] Success criteria are achievable
- [ ] No unstated assumptions
- [ ] AgentMeter's folders are never written (FR-009, tests compare the legacy tree before and after)
- [ ] README "Security and privacy" matches the new folders and update URL (AGENTS.md)

---

<!-- Code phase sections are appended below this line by the phase-manager command -->
<!-- Each phase section follows the template below -->

<!--
## Phase N: [Phase Name] (YYYY-MM-DD)

### What Changed

[Summary of files and functionality added/modified]

### Spec Compliance

[Which requirements this phase addresses, compliance score]

### Focus Areas for Review

[Where the reviewer should concentrate]

### AI Assumptions

[Decisions made during implementation that were not in the spec]
-->
