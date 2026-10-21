# Contributing to AgentTacho

Thank you for wanting to help. AgentTacho is a small, personal project, built with AI agents from the first line, and contributions made the same way are very welcome. There is one firm rule: open an issue first, and start on the code only after the issue was accepted.

## Issues first

Every contribution starts as an issue in the [issue tracker](https://github.com/AgentTacho/agenttacho/issues), whether it is a bug, an idea or a change you would like to make yourself. Describe what you want to change and why. Once I have accepted the issue, open the pull request that implements it.

This order saves both of us time. AgentTacho deliberately stays small, with few dependencies and little new UI, so not every good idea fits. Agreeing on the issue first means you never build something that will not be merged, and it keeps the process around the pull request light: no spec, no ceremony, just the code rules below.

A pull request without an accepted issue will be closed with a pointer back to this section.

## AI-assisted contributions

AI first: contributions written with Claude Code, Codex, OpenCode or any other agent are welcome and expected. The [Vibe Coding Manifesto](https://vibe-coding-manifesto.com/) describes the mindset behind this. What I ask for is diligence:

- **Attribute the AI.** Say which agent helped, for example with an `Assisted-By:` trailer in each commit message that names the agent. Hiding AI help is not okay here.
- **Review before you open the pull request.** Ideally the change has already been through review agents, for example with [cc-review](https://github.com/rhuss/cc-review), which runs several review agents over your branch and fixes what they find. Mention in the pull request what the review found and what you did about it.
- **Stand behind the change.** You do not need to have typed every line, but you should understand what the change does and be able to answer questions about it.

## Spec-driven development: welcome, not required

Most of AgentTacho was built with spec-driven development (SDD): a specification in `specs/NNN-name/` that says what changes and why, then a plan and a task list, then the implementation, reviewed against the spec. The existing specs show how that looks.

For your contribution it is optional. If you bring a spec, review gets easier, because it checks the code against what you meant to build. If you do not, that is fine too.

If you want to try it, the smoothest path is the toolchain the project was built with:

- [Spec Kit](https://github.com/github/spec-kit): the SDD toolkit, with the `specify` CLI and the `/speckit-*` commands.
- [cc-spex](https://github.com/rhuss/cc-spex): Spec Kit extensions for brainstorming, quality gates, worktrees, multi-agent code review and the pull request workflow. Its **collab workflow** works in Claude Code and in Codex and turns your spec and code into review-ready pull requests with a generated reviewer guide.

Set it up in Claude Code:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```

```text
/plugin marketplace add rhuss/cc-rhuss-marketplace
/plugin install spex@cc-rhuss-marketplace
/spex:init
```

Then enable the collab extension:

```text
/speckit-spex-extensions
```

For Codex, OpenCode and other harnesses, the cc-spex README describes the workflow-based setup (`specify workflow run spex/setup.yml`).

The workflow in short:

1. `/speckit-spex-brainstorm` turns the accepted issue into something specifiable.
2. `/speckit-specify`, then `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks` and `/speckit-implement`. `/speckit-spex-ship` runs the whole pipeline with review gates.
3. `/speckit-spex-walkthrough` tries the feature by hand.
4. `/speckit-spex-submit` opens the pull request with the title `<Feature> [Spec + Impl]`.

Start each phase in a fresh agent session; long sessions tend to skip steps.

## What a change must respect

The [constitution](.specify/memory/constitution.md) holds the rules and their reasons, and [AGENTS.md](AGENTS.md) is the day-to-day guide for working with them. Point your agent at AGENTS.md before it starts. In short:

- **Build only through the Makefile** (`make test`, `make test-release`, `make app`, `make app-demo`), never `swift build` or `xcodebuild` directly.
- **Logic lives in `UsageCore`** (or `DemoMode`), tested before it is written. `Sources/AgentTacho` stays a thin SwiftUI layer. Doc comments cite the requirement they implement, for example `spec 008 FR-004`, or the issue number when there is no spec.
- **Read-only and private.** AgentTacho only reads the agents' files and never writes to them. A change that touches credentials or network requests keeps the README's "Security and privacy" section true and updates the website's privacy section in the same pull request.
- **Visible UI changes ship with current screenshots and website copy.** If your change alters what a user sees, the demo scenario shows it, and the recaptured shots land on the site in a linked pull request. See [AGENTS.md](AGENTS.md) and [docs/website.md](docs/website.md) for the order of work. If that is more than you want to take on, say so in the issue and I will handle the screenshots.
- **No em dash or en dash** anywhere, [Conventional Commits](https://www.conventionalcommits.org), and never commit `.mcp.json`.

Releases and the website deploy are the maintainer's job, so leave `make release`, the site's `SITE_LIVE` variable and the deploy alone.
