# AGENTS.md

Guidance for coding agents, and the people driving them, working on AgentTacho.

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

- Build and test only through the Makefile: `make test` (Swift Testing; the Makefile sets the plugin path and SDK), `make test-release` (release script tests) and `make app`.
- Logic belongs in `UsageCore`, covered by tests; `Sources/AgentTacho` stays a thin SwiftUI layer. Write the test first.
- Doc comments cite the spec requirements they implement (for example `spec 008 FR-004`).
- No em dash or en dash characters in code, comments, docs or commit messages. Commit messages follow Conventional Commits.
- AgentTacho only reads the agents' files (`~/.claude`, `~/.codex`, OpenCode's data) and never writes to them. A change that touches credentials or network requests must keep the README's "Security and privacy" section true, and update it in the same pull request.
- The project constitution is `.specify/memory/constitution.md`; these conventions follow it.

## Screenshots and website

Every feature that changes what a user sees (menu bar item, dropdown, tooltips, Settings, notifications, wording or layout) keeps the screenshots and the website current (constitution, principle V):

- The plan has a "Screenshots and website" section: the shots that change, the new shots, and the website copy to update, or "no visible UI change".
- The demo scenario in `Resources/demo/` shows the new or changed UI, and the scenario coverage test checks any new visual state the shots rely on.
- A new feature worth a landing page card gets its own shot in `scripts/screenshots/capture.sh`, in light and dark.
- Recapture with `make app-demo` and `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho/` (the site is `AgentTacho/agenttacho.github.io`). Replace `docs/images/agenttacho-dropdown.png` when the dropdown changes. Look at every image in both appearances.
- Update the website copy (feature cards, small things, comparison) in a pull request to the site repository and link it from the app pull request. Both are merged before the release that ships the feature.
- Screenshots come only from the demo build, never from a real AgentTacho with real accounts.
- The capture takes over the Mac (it quits AgentTacho, switches the appearance and moves the mouse), so an agent asks before running it.
