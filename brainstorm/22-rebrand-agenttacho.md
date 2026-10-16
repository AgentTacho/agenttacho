# Brainstorm: Rebrand AgentMeter to AgentTacho

**Date:** 2026-10-16
**Status:** active

## Problem Framing

The name AgentMeter is taken by a product in the same field: [agentmeter.app](https://agentmeter.app) by Hensonism LLC tracks token usage of Claude Code, Cursor and Codex sessions ("Know what your AI agents actually did"), with a paid tier and the GitHub organization `github.com/AgentMeter`. Same audience, same word. Renaming before the landing page launches and before the app repository moves is the cheapest moment; the repository has 0 stars and 0 forks, and every release (0.2.2 to 0.4.1) is from 2026-10-15 and 2026-10-16, so the installed base is essentially the maintainer.

The new name is **AgentTacho** (one word, camel case). It keeps "Agent" up front, and "Tacho" (the German everyday word for a speedometer, close to the American "tach") matches the existing gauge mascot, so the imagery stays. The user created the GitHub organization `AgentTacho` and renamed the site repository to `AgentTacho/agenttacho.github.io`.

### Name research (2026-10-16)

- `AgentTacho`: free on GitHub (user, org, `-dev`, `-app`), no repositories, not on npm, PyPI, crates.io, Homebrew or the App Store; domains `.com`, `.app`, `.dev`, `.io`, `.ai`, `.de`, `.net`, `.org` all unregistered; no trademark found in a web pass (no USPTO, EUIPO or DPMA search yet).
- Neighbours: [Tacho Agent Ltd](https://www.tachoagent.com/) is a UK tachograph analysis consultancy (same words reversed, different field). [tacho.app](https://tacho.app) is a cycling fitness tracker, which is why the bare word "Tacho" was ruled out.
- Associations to know: in British English "tacho" means tachograph (fleet driving-time compliance, many "Tacho..." software products); in Latin American Spanish "tacho" means a bin. Neither is a product conflict.
- Rejected on the way: AgentMonitor, AgentEye, AgentGlimpse (all used by tools in this niche), QuotaWren and AgentWren (PolyAI filed WREN in classes 9 and 42 on 2026-07-28 for virtual agents and conversational AI monitoring software; WrenAI has a bird logo mark), Budgeto (two budgeting products), AgentBaro (one letter from several AgentBar usage apps). AgentBlick was the runner-up: equally free, with the "at a glance" story, but less direct than a name that matches the gauge.

### What the update path allows

Installed 0.4.x copies accept a one-click update only when the release's `release-info.json` names `AgentMeter-<version>.dmg` (`ReleaseEvaluator.downloadTarget`) and the downloaded app has the running app's bundle identifier and team (`Updater`, designated requirement). An AgentTacho release with a new DMG name therefore shows up in 0.4.x as "AgentMeter 0.5.0 available" with a link to its release page, without the one-click install (`infoProblem` = `releaseInfoIncomplete`). That is a graceful enough path for an installed base of about one: the old copy points to the new release, and the user installs AgentTacho once by hand.

## Approaches Considered

### Continuity of installed copies

- **Clean break (chosen):** new bundle identifier and data folders, one-time copy of the old configuration; 0.4.x copies only see the new release as a link. Simplest and leaves no old name inside the code.
- Keep the bundle identifier: renames everything visible but keeps `dev.rhuss.agentmeter` underneath, so notification and login-item settings carry over; the 0.4.x updater still fails on the DMG name, so it buys little.
- Bridge release: a last AgentMeter 0.4.2 that knows the new name, so 0.4.x copies update into AgentTacho with one click. Most work for an installed base of about one.

### How to cut the work

- **A: one spec for the app repository, the site as a follow-up (chosen).** One SDD spec covers the app, the release tooling, the cask, the docs and the repository transfer; the site rename follows as a small task list in the site repository, as brainstorm 18 set up for site work.
- B: everything in one go, app, site, transfer and local folder rename in a single push. Mixes two repositories in one spec and makes the site depend on unreleased app work.
- C: visible names first, internals later. Leaves two names inside the code, which a clean break is meant to avoid.

## Decision

Rename to AgentTacho with a clean break, cut as approach A. Spec 022 (move the repository to `agentmeter-dev`) is abandoned: the transfer goes to `AgentTacho/agenttacho` as part of the rebrand spec. Order: the in-flight `021-recover-stuck-offline` branch lands first (the rename touches the same files), then the rebrand spec, then the first AgentTacho release (0.5.0), then the site rename, then Stream B (demo mode) and the site launch.

## Key Requirements

### App (rebrand spec)

- Display name, bundle name and executable `AgentTacho`; every user-facing string says AgentTacho (menu, dropdown, Settings, About, notifications, update states and block reasons, alerts). The update request's `User-Agent` becomes `AgentTacho/<version>`.
- Bundle identifier `dev.rhuss.agenttacho`; names derived from it follow (the update temporary folder, the cask's `uninstall quit` and `zap` entries, `RunningInstance` and `SingleInstance` checks, test fixtures).
- Data folders `~/.config/agenttacho/` (`config.json`, `imported-prices.json`), `~/Library/Logs/agenttacho/` and `~/Library/Application Support/agenttacho/` (`last-good.json`). On first launch, when the new configuration folder does not exist and the old one does, AgentTacho copies `config.json`, `imported-prices.json` and `last-good.json` from the old folders once, and never writes to or deletes the old folders (they are AgentMeter's, and AgentTacho only reads them). Logs are not copied.
- The executable target and its source folder become `AgentTacho`; `UsageCore` keeps its name. Asset catalog names (`AgentMeterMonochrome`, `AgentMeterSolid`, `AgentMeterOutline`, `AgentMeterBadge`) and icon master file names follow the new name; the images themselves stay.
- Doc comments and log text that name the app say AgentTacho; comments citing historical specs keep their spec numbers.
- `AppLinks` point to `https://github.com/AgentTacho/agenttacho` (repository, new issue, security statement); the sponsor link `github.com/sponsors/rhuss` stays.
- `UpdateSource.official` is `AgentTacho/agenttacho`; `HomebrewDetector` looks for the cask `agenttacho` and `AgentTacho.app`; the expected DMG name is `AgentTacho-<version>.dmg`; the Homebrew command shown is `brew upgrade --cask agenttacho`.

### Release and distribution (rebrand spec)

- DMG `AgentTacho-<version>.dmg`, volume name and DMG backgrounds re-rendered with `AgentTacho.app`; release notes, `release-info.json`, the release title "AgentTacho <version>".
- `GH_REPO` default `AgentTacho/agenttacho`; the tap stays `rhuss/homebrew-tap`, with a new cask `agenttacho` and the old cask `agentmeter` renamed through the tap's cask rename mechanism, so `brew upgrade` moves existing installs over; the install command becomes `brew install --cask rhuss/tap/agenttacho`.
- `make release` starts the site deploy (`deploy.yml` in `AgentTacho/agenttacho.github.io`) after publishing a release marked latest, as spec 022 planned; a failed start only warns.
- First release under the new name: **0.5.0** (numbering continues; the repository keeps its tags and releases through the transfer).

### Repository and docs (rebrand spec)

- Transfer `rhuss/agentmeter` to the `AgentTacho` org and rename it `agenttacho`, with the maintainer's explicit approval; GitHub redirects the old web, API, download and git URLs, so 0.4.x copies still find the new release. Verify the redirect with requests before the first release from the new place (as spec 022 FR-011 planned). Set the repository homepage to the site.
- README and AGENTS.md say AgentTacho; the README's first lines say "formerly AgentMeter" once, so old links and searches still lead somewhere. The "Security and privacy" section names the new folders and the new request URL. `docs/images` keeps its pictures but not the old name in file names; screenshots showing the old name are replaced by Stream B's demo shots later.
- `.github/FUNDING.yml` stays `github: rhuss`. Historical specs and brainstorms keep the old name.

### Site (follow-up task list in the site repository)

- Copy, page title, meta description, footer and README say AgentTacho; links point to `AgentTacho/agenttacho`; the build reads releases from `AgentTacho/agenttacho`; the fallback release names `AgentTacho-<version>.dmg`; the Homebrew line is `brew install --cask rhuss/tap/agenttacho`; the OG card is regenerated with `scripts/make-og.sh`.
- Local remote updated to `git@github.com:AgentTacho/agenttacho.github.io.git`; page tests that assert the old name are updated, and a test forbids "AgentMeter" in the built page except the one "formerly" line if the page keeps one.

### Local environment (maintainer, outside the specs)

- Rename `~/Work/projects/agentmeter` and `~/Work/projects/agentmeter-site` after the open worktrees (`021`, `022`) are merged or removed. Claude Code keys its project memory and handoffs by path, so the memory folder moves with it.
- The notarization keychain profile `agentmeter-notary` may keep its name (local only) or be renamed together with `NOTARY_PROFILE`'s default.

## Open Questions

- Should AgentTacho also show a one-line notice ("AgentMeter is now AgentTacho, you can delete AgentMeter.app") on first launch when it copied an old configuration, or is the README enough?
- Should the old folders be named in the README so users can delete them, or stay unmentioned since AgentTacho never touches them?
- Buy `agenttacho.app` (or `.dev`) for the site now, or launch on `agenttacho.github.io` first?
- Run a proper trademark search (USPTO, EUIPO, DPMA) for AgentTacho before 0.5.0?
- Does the README keep the "formerly AgentMeter" line permanently, or drop it after a few releases?
