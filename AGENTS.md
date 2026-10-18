# AGENTS.md

Guidance for coding agents, and the people driving them, working on AgentTacho. The constitution (`.specify/memory/constitution.md`) states the rules; this file says how to follow them day to day.

## Contributions

Contributions are welcome. Every change goes through spec-driven development (SDD): first a specification that says what changes and why, then a plan and tasks, then the implementation, reviewed against the spec. A pull request without its spec in `specs/` will be asked to add one.

## Tools

- [Spec Kit](https://github.com/github/spec-kit): the SDD toolkit, with the `specify` CLI and the `/speckit-*` commands.
- [cc-spex](https://github.com/rhuss/cc-spex): Spec Kit extensions for brainstorming, quality gates, worktrees, multi-agent code review and the pull request workflow. Every feature in this repository was built with it.

Setup in Claude Code:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```

```text
/plugin marketplace add rhuss/cc-rhuss-marketplace
/plugin install spex@cc-rhuss-marketplace
/spex:init
```

For Codex, OpenCode and other harnesses, the cc-spex README describes the workflow-based setup (`specify workflow run spex/setup.yml`).

## Workflow

- Start an idea with `/speckit-spex-brainstorm`, then `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks` and `/speckit-implement`. `/speckit-spex-ship` runs the whole pipeline with review gates.
- Specs live in `specs/NNN-name/` (spec, plan, tasks, review notes, runbook), brainstorms in `brainstorm/`. The existing specs show the expected depth.
- `/speckit-spex-walkthrough` tries the feature by hand, `/speckit-spex-submit` opens the pull request (title `<Feature> [Spec + Impl]`, or a `[Spec]` pull request first for larger changes).
- Start each SDD session in a fresh agent session; long sessions tend to skip steps.

## Project conventions

The constitution (`.specify/memory/constitution.md`) has the rules and their reasons. In short:

- Build and test only through the Makefile (`make test`, `make test-release`, `make app`, `make app-demo`); never `swift build` or `xcodebuild` directly (constitution IV).
- Logic in `UsageCore` or `DemoMode`, test first; `Sources/AgentTacho` stays a thin SwiftUI layer. Doc comments cite the spec requirement they implement, for example `spec 008 FR-004` (II).
- AgentTacho only reads the agents' files and never writes to them. A change touching credentials or network requests updates the README's "Security and privacy" section and the website's privacy section in the same pull request (III).
- No em dash or en dash anywhere, Conventional Commits, never commit `.mcp.json`.
- Publishing is the maintainer's call for each run: never `make release`, the site's `SITE_LIVE` variable, `deploy.yml` or a push to the site's `main` without being told to. Everything else (tests, builds, pull requests) runs without asking.

## Screenshots and website

The landing page `https://agenttacho.github.io` is generated from this repository: eleven screenshots from the demo build, nine feature cards and five "small things" from data files, the download button from the latest release. `docs/website.md` has the file map, the commands, the deploy and the pitfalls; this section is the rule and the order of work.

**Rule (constitution V).** A feature that changes what a user sees (menu bar item, dropdown, tooltips, Settings, notifications, wording or layout) ships with current screenshots and current website copy. Screenshots come only from the demo build, never from a real AgentTacho with real accounts (constitution III).

| You might think | Do this instead |
|---|---|
| "The change is a few pixels, the old shot still looks right" | A shot is current only when it comes from the current sources. The capture is one command and about five minutes. |
| "There is no site checkout on this machine, so skip the site part" | Clone it: `gh repo clone AgentTacho/agenttacho.github.io <site checkout>`. The app pull request is not finished until the site pull request is linked from it. |
| "A crop of the real app is quicker than the demo build" | Real shots carry real account names and locale formats. Only the demo build is allowed. |
| "I will recapture everything before the release" | Each pull request gets its own review of the shots; a batch at release time hides which change caused which difference. |

**Order of work** for a feature with a visible change:

1. **Plan.** Fill the "Screenshots and website" section of `plan.md` (template below). Done when every row has a value, or the section says "No visible UI change" with the reason.
2. **Scenario.** Make `Resources/demo/default.json` show the new or changed UI, and extend the coverage test in `Tests/DemoModeTests` for any new visual state a shot relies on. Done when `make test` passes with the new check.
3. **Shot list.** For a new feature that earns a landing page card, add a stem to `STEMS` in `scripts/screenshots/capture.sh` with its capture step, and a stub test in `scripts/release/tests/test_screenshots.sh`. Done when `make test-release` passes. A change to existing UI needs no new stem.
4. **Capture.** Ask the maintainer first: the capture quits AgentTacho, switches the system appearance twice and moves the mouse, so the Mac is unusable for the run. Then `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho` (it runs `make app-demo` itself). Done when it prints the 22 files with their sizes and exits 0. On a failure it names the stems it could not capture and leaves the target untouched; fix the cause and run again.
5. **Review the images.** Open every changed shot in both appearances. Reject one that shows a real name, a German number or date format, or clipped UI, and fix the scenario or the capture step rather than editing the image. A real 2x shot is tens to hundreds of kilobytes; a 2 to 8 KB file is a placeholder from the site's `scripts/make-placeholders.sh`, which means the capture never landed there.
6. **README image.** When the dropdown changed, replace `docs/images/agenttacho-dropdown.png` with the demo dropdown (`magick dropdown-light.webp docs/images/agenttacho-dropdown.png`) and update the alt text, which quotes the values shown.
7. **Website copy.** In the site checkout edit the data files for the cards, the comparison and the privacy section (file map in `docs/website.md`), and regenerate the social card when the menu bar shot changed. Then run the site's check, build and tests (`npm test` needs the build). Fix and rerun until all pass, at most three rounds; after that stop and report what still fails.
8. **Pull requests.** Open the site pull request, link it from the app pull request, and merge both before the release that ships the feature. Never push to the site's `main` directly.

After a release: set the site's fallback release to the new version (`docs/website.md`, Deploy). `make release` already starts the site deploy.

**Plan section template** (`plan.md`):

```markdown
## Screenshots and website

| | |
|---|---|
| Shots that change | plan-limits, dropdown |
| New shots | none |
| Demo scenario | add a Fable model limit at 44% (coverage test: model limit shown) |
| Website copy | features.ts "Plan limits": mention per-model limits |
| README image | replace (dropdown changed) |
```

Or one line: `No visible UI change: <why>`, for example for a refactor of the refresh timers.

**Examples.**
- A new Settings tab "Accounts" that earns a card: new stem `accounts` (steps 3 and 4), a new card in `features.ts`, and the page test that counts nine cards changes with it, on purpose.
- The dropdown says "resets at 14:00" instead of "resets in 2 h": no new stem, one capture run (it always writes all 22 files), README image replaced, no copy change.
- A refactor of the refresh timers with identical output: "No visible UI change", nothing else.

**Scope in the site repository.** Touch only the files listed under "Scope" in `docs/website.md`: the screenshots, the data files and the social card. Leave the AstroWind plumbing, the workflow and the page tests alone unless the task is about the site itself. Never commit a screenshot of the real app.
