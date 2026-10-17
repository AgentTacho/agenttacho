# Brainstorm: Name the app AgentTacho

**Date:** 2026-10-16
**Status:** active

## Problem Framing

The app needs a name that is free in its field, works as a GitHub organization and a domain, and fits the gauge mascot. The cheapest moment to settle it everywhere is now, before the landing page launches: every release so far (0.2.2 to 0.4.1) is from 2026-10-15 and 2026-10-16, and the installed base is essentially the maintainer.

The name is **AgentTacho** (one word, camel case). It keeps "Agent" up front, and "Tacho" (the German everyday word for a speedometer, close to the American "tach") matches the existing gauge mascot, so the imagery stays. The user created the GitHub organization `AgentTacho`, which holds the site repository `AgentTacho/agenttacho.github.io`.

### Name research (2026-10-16)

- `AgentTacho`: free on GitHub (user, org, `-dev`, `-app`), no repositories, not on npm, PyPI, crates.io, Homebrew or the App Store; domains `.com`, `.app`, `.dev`, `.io`, `.ai`, `.de`, `.net`, `.org` all unregistered; no trademark found in a web pass (no USPTO, EUIPO or DPMA search yet).
- Neighbours: [Tacho Agent Ltd](https://www.tachoagent.com/) is a UK tachograph analysis consultancy (same words reversed, different field). [tacho.app](https://tacho.app) is a cycling fitness tracker, which is why the bare word "Tacho" was ruled out.
- Associations to know: in British English "tacho" means tachograph (fleet driving-time compliance, many "Tacho..." software products); in Latin American Spanish "tacho" means a bin. Neither is a product conflict.
- Rejected on the way: AgentMonitor, AgentEye, AgentGlimpse (all used by tools in this niche), QuotaWren and AgentWren (PolyAI filed WREN in classes 9 and 42 on 2026-07-28 for virtual agents and conversational AI monitoring software; WrenAI has a bird logo mark), Budgeto (two budgeting products), AgentBaro (one letter from several AgentBar usage apps). AgentBlick was the runner-up: equally free, with the "at a glance" story, but less direct than a name that matches the gauge.

## Approaches Considered

### How far the name reaches

- **Everywhere (chosen):** display name, bundle identifier, data folders, release artifacts, cask and repository all say AgentTacho. One name in the code and in what the user sees.
- Visible names only: the app says AgentTacho, while identifiers and folders keep generic or mixed names. Saves little and leaves two vocabularies in the code.

### How to cut the work

- **A: one spec for the app repository, the site as a follow-up (chosen).** One SDD spec covers the app, the release tooling, the cask, the docs and the repository settings; the site follows as a small task list in the site repository, as brainstorm 18 set up for site work.
- B: everything in one go, app, site and local folders in a single push. Mixes two repositories in one spec and makes the site depend on unreleased app work.
- C: visible names first, identifiers and folders later. Leaves the code inconsistent for a while.

## Decision

Name the app AgentTacho everywhere, cut as approach A. Spec 022 (an earlier draft for the repository location) is abandoned; the repository location is part of this spec. Order: the in-flight `021-recover-stuck-offline` branch lands first (this work touches the same files), then the AgentTacho spec, then the first AgentTacho release (0.5.0), then the site, then Stream B (demo mode) and the site launch.

## Key Requirements

### App (AgentTacho spec)

- Display name, bundle name and executable `AgentTacho`; every user-facing string says AgentTacho (menu, dropdown, Settings, About, notifications, update states and block reasons, alerts). The update request's `User-Agent` is `AgentTacho/<version>`.
- Bundle identifier `dev.rhuss.agenttacho`; names derived from it follow (the update temporary folder, the cask's `uninstall quit` and `zap` entries, the `RunningInstance` and `SingleInstance` checks, test fixtures).
- Data folders `~/.config/agenttacho/` (`config.json`, `imported-prices.json`), `~/Library/Logs/agenttacho/` and `~/Library/Application Support/agenttacho/` (`last-good.json`).
- The executable target and its source folder are `AgentTacho`; `UsageCore` keeps its name. Asset catalog names (`AgentTachoMonochrome`, `AgentTachoSolid`, `AgentTachoOutline`, `AgentTachoBadge`) and icon master file names carry the name; the images themselves stay.
- Doc comments and log text that name the app say AgentTacho; comments citing other specs keep their spec numbers.
- `AppLinks` point to `https://github.com/AgentTacho/agenttacho` (repository, new issue, security statement); the sponsor link is `github.com/sponsors/rhuss`.
- `UpdateSource.official` is `AgentTacho/agenttacho`; `HomebrewDetector` looks for the cask `agenttacho` and `AgentTacho.app`; the expected DMG name is `AgentTacho-<version>.dmg`; the Homebrew command shown is `brew upgrade --cask agenttacho`.

### Release and distribution (AgentTacho spec)

- DMG `AgentTacho-<version>.dmg`, volume name and DMG backgrounds rendered with `AgentTacho.app`; release notes, `release-info.json`, the release title "AgentTacho <version>".
- `GH_REPO` default `AgentTacho/agenttacho`; the tap is `rhuss/homebrew-tap` with the cask `agenttacho`; the install command is `brew install --cask rhuss/tap/agenttacho`.
- `make release` starts the site deploy (`deploy.yml` in `AgentTacho/agenttacho.github.io`) after publishing a release marked latest; a failed start only warns.
- The notarization keychain profile is `agenttacho-notary`, the default of `NOTARY_PROFILE`.
- First release under the name AgentTacho: **0.5.0** (numbering continues; the repository keeps its tags and releases).

### Repository and docs (AgentTacho spec)

- The repository lives at `AgentTacho/agenttacho` in the `AgentTacho` organization, with the site `https://agenttacho.github.io` as its homepage.
- README and AGENTS.md say AgentTacho. The "Security and privacy" section names the data folders and the update request URL. `docs/images` file names carry the name; the screenshots are replaced by Stream B's demo shots later.
- `.github/FUNDING.yml` stays `github: rhuss`.

### Site (follow-up task list in the site repository)

- Copy, page title, meta description, footer and README say AgentTacho; links point to `AgentTacho/agenttacho`; the build reads releases from `AgentTacho/agenttacho`; the fallback release names `AgentTacho-<version>.dmg`; the Homebrew line is `brew install --cask rhuss/tap/agenttacho`; the OG card is generated with `scripts/make-og.sh`.
- Local remote `git@github.com:AgentTacho/agenttacho.github.io.git`; page tests check the name in the built page.

### Local environment (maintainer, outside the specs)

- The local checkouts are named `agenttacho` and `agenttacho-site` once the open worktrees (`021`, `022`) are merged or removed. Claude Code keys its project memory and handoffs by path, so the memory folder follows the checkout.

## Open Questions

- Buy `agenttacho.app` (or `.dev`) for the site now, or launch on `agenttacho.github.io` first?
- Run a proper trademark search (USPTO, EUIPO, DPMA) for AgentTacho before 0.5.0?
