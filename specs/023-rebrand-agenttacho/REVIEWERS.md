# Review Guide: Name the app AgentTacho

**Generated**: 2026-10-16 | **Spec**: [spec.md](spec.md)

## Why This Change

The app needs one name that is free in its field and carried the same way everywhere: in the app, its identifiers and folders, the release artifacts, the Homebrew cask, the repository and the docs. AgentTacho was researched for collisions (brainstorm 22) and matches the gauge mascot, so the imagery stays.

## What Changes

The app, its bundle identifier (`dev.rhuss.agenttacho`), data folders, release artifacts, Homebrew cask, GitHub repository and docs all say AgentTacho. The release starts the site deploy after a latest release, and a Developer ID release stops when the notarization profile is missing.

## How It Works

- **Names**: `git mv` of the executable target (`Sources/AgentTacho`), icons, the cask template and an image; Info.plist and its custom keys (`AgentTacho*`); user-facing strings; update logic names (official source `AgentTacho/agenttacho`, expected DMG `AgentTacho-<v>.dmg`, cask `agenttacho`, User-Agent).
- **Data folders**: `Paths` points to `~/.config/agenttacho/`, `~/Library/Logs/agenttacho/` and `~/Library/Application Support/agenttacho/` (FR-007).
- **Release tooling**: defaults (`GH_REPO`, `SITE_REPO`, `agenttacho-notary`, `AgentTacho Signing`), DMG and notes names; `release.sh` starts the site's `deploy.yml` after publishing a latest release and before the cask step, warning only on failure; `update-cask.sh` writes `Casks/agenttacho.rb` and nothing else.
- **DMG artwork**: the notarized background had the title painted in; it becomes a title-less base, and `render-dmg-backgrounds.swift` draws the title from text for both backgrounds.
- **Operations** (maintainer approval): repository settings for `AgentTacho/agenttacho` (homepage `https://agenttacho.github.io`), then the 0.5.0 release.

## When It Applies

**Applies when**:
- Building, running or releasing the app from this repository (every build is AgentTacho).
- Installing AgentTacho from the DMG or with `brew install --cask rhuss/tap/agenttacho`.

**Does not apply when**:
- Working on the landing page repository (`AgentTacho/agenttacho.github.io`): a separate task list in that repository (brainstorm 22).
- The maintainer's local folders, the domain, and a formal trademark search: outside the spec.

## Key Decisions

1. **One name everywhere**, in the code as well as in what the user sees, including the bundle identifier and the data folders.
2. **The site deploy is part of the release**, so a latest release is on the landing page without a manual step; a failed start only warns.
3. **No un-notarized release by accident**: a Developer ID release without the `agenttacho-notary` profile stops, unless `ALLOW_UNNOTARIZED=1` (added in code review).
4. **First release 0.5.0, numbering continues**; the repository keeps its tags and history.

## Areas Needing Attention

- **DMG background patch** (research R3): filling the title band of the committed artwork must look seamless at 1x and 2x; the fallback is regenerating the artwork without text.
- **Sequencing**: implementation waits for `021-recover-stuck-offline` to land; the change touches the same files.
- **Scope of the naming change**: about 90 files; review by commit (each phase is a separate commit) rather than as one diff.

## Open Questions

- When to run a formal trademark search (USPTO, EUIPO, DPMA) for AgentTacho, before 0.5.0 or before the site launch? (brainstorm 22)

## Review Checklist

- [ ] Key decisions are justified
- [ ] Scope matches the stated boundaries (site and local folders excluded)
- [ ] Success criteria are achievable
- [ ] No unstated assumptions
- [ ] README "Security and privacy" matches the data folders and update URL (AGENTS.md)

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
