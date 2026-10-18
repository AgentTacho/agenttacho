# Contributing to AgentTacho

Thank you for wanting to help. AgentTacho is a small, personal project, and contributions are welcome within one firm rule: every change goes through spec-driven development. If you open a pull request, it carries its specification with it.

## Spec-driven development, always

Every change to AgentTacho starts as a specification in `specs/NNN-name/` that says what changes and why, then a plan and a task list, then the implementation, reviewed against the spec. This is the first principle of the [project constitution](.specify/memory/constitution.md), and it is not optional: a pull request without its spec will be asked to add one before it merges. For a larger change, open a `[Spec]` pull request first so the intent is agreed before any code is written.

The reason is simple. The spec is the reviewable record of what you meant to build. Review then checks the code against that record instead of guessing at it.

## The recommended way: Spec Kit and cc-spex

You can write the spec by hand, but the smooth path is the toolchain the whole project was built with:

- [Spec Kit](https://github.com/github/spec-kit): the SDD toolkit, with the `specify` CLI and the `/speckit-*` commands.
- [cc-spex](https://github.com/rhuss/cc-spex): Spec Kit extensions for brainstorming, quality gates, worktrees, multi-agent code review and the pull request workflow.

Set it up in Claude Code:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```

```text
/plugin marketplace add rhuss/cc-rhuss-marketplace
/plugin install spex@cc-rhuss-marketplace
/spex:init
```

Enable the **collab extension** so your spec and code land as review-ready pull requests with a generated reviewer guide, which is how changes are reviewed here:

```text
/speckit-spex-extensions
```

For Codex, OpenCode and other harnesses, the cc-spex README describes the workflow-based setup (`specify workflow run spex/setup.yml`).

## The workflow

1. `/speckit-spex-brainstorm` to turn a rough idea into something specifiable.
2. `/speckit-specify`, then `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks` and `/speckit-implement`. `/speckit-spex-ship` runs the whole pipeline with review gates.
3. `/speckit-spex-walkthrough` tries the feature by hand.
4. `/speckit-spex-submit` opens the pull request. Use the title `<Feature> [Spec + Impl]`, or open a `[Spec]` pull request first for a larger change.

Start each session in a fresh agent session; long sessions tend to skip steps.

## What a change must respect

The [constitution](.specify/memory/constitution.md) holds the rules and their reasons, and [AGENTS.md](AGENTS.md) is the day-to-day guide for working with them. In short:

- **Build only through the Makefile** (`make test`, `make test-release`, `make app`, `make app-demo`), never `swift build` or `xcodebuild` directly.
- **Logic lives in `UsageCore`** (or `DemoMode`), tested before it is written. `Sources/AgentTacho` stays a thin SwiftUI layer. Doc comments cite the spec requirement they implement, for example `spec 008 FR-004`.
- **Read-only and private.** AgentTacho only reads the agents' files and never writes to them. A change that touches credentials or network requests keeps the README's "Security and privacy" section true and updates the website's privacy section in the same pull request.
- **Visible UI changes ship with current screenshots and website copy.** If your change alters what a user sees, the plan says which shots change, the demo scenario shows it, and the recaptured shots land on the site in a linked pull request. See [AGENTS.md](AGENTS.md) and [docs/website.md](docs/website.md) for the order of work.
- **No em dash or en dash** anywhere, [Conventional Commits](https://www.conventionalcommits.org), and never commit `.mcp.json`.

Publishing a release and taking the website live are the maintainer's call for each run, so leave `make release`, the site's `SITE_LIVE` variable and the deploy alone unless you are asked.

## Reporting issues

Bug reports and ideas are welcome in the [issue tracker](https://github.com/AgentTacho/agenttacho/issues). An idea that grows into a change still goes through the spec-driven flow above, so a short issue first is a good place to agree it is worth doing.
