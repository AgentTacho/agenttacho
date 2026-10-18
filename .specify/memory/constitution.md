<!--
Sync Impact Report
- Version change: 1.0.0 -> 1.1.0
- Modified principles:
  - III. Read-Only, Private by Default: the website's privacy section mirrors the README
  - V. Screenshots and Website Follow the UI: states what must be true at merge (plan
    section, scenario, shot and card, recapture with linked site pull request, no
    placeholders live, fallback release after each release); the how moved to AGENTS.md
    and docs/website.md
- Added sections: none
- Removed sections: none
- Dependent files: AGENTS.md (order of work, plan section template, scope in the site
  repository), docs/website.md (new: file map, commands, deploy, pitfalls)
- Deferred TODOs: none
-->

# AgentTacho Constitution

## Core Principles

### I. Spec-Driven Development

Every change MUST go through spec-driven development: a specification in `specs/NNN-name/`
that says what changes and why, then a plan and tasks, then the implementation, reviewed
against the spec. A pull request without its spec MUST add one before merge. Larger changes
MAY land as a `[Spec]` pull request first.

Rationale: the spec is the reviewable record of intent; code review checks code against it.

### II. Test-First, Logic in UsageCore

Logic MUST live in `UsageCore` (or another library target such as `DemoMode`) and MUST be
covered by tests written before the implementation. `Sources/AgentTacho` MUST stay a thin
SwiftUI layer that wires models to views. Doc comments MUST cite the spec requirements they
implement (for example `spec 008 FR-004`).

Rationale: the SwiftUI layer is hard to test; keeping it thin keeps behavior testable.

### III. Read-Only, Private by Default

AgentTacho MUST only read the agents' files (`~/.claude`, `~/.codex`, OpenCode's data) and
MUST never write to them. A change that touches credentials, keychain access or network
requests MUST keep the README's "Security and privacy" section true and MUST update it in the
same pull request. The website's privacy section MUST say the same as that README section; a
change to one MUST change the other. Images and text published from this repository (README,
website) MUST NOT show real account names, email addresses, employers or usage data.

Rationale: users trust a menu bar app with their agents' credentials only if it never
surprises them, and the website is where they read the promise first.

### IV. One Build Entry Point

Building and testing MUST go through the Makefile: `make test`, `make test-release`,
`make app`, `make app-demo`, `make dmg`, `make release`. Scripts and documentation MUST NOT
describe a second way to build that bypasses it.

Rationale: the Makefile sets the SDK, plugin paths, signing and the demo switch; a side path
drifts and breaks releases.

### V. Screenshots and Website Follow the UI

The website (`AgentTacho/agenttacho.github.io`) is generated from the app: the screenshots from
the demo build, the download button from the latest release, the text from data files. A
feature that changes what a user sees (menu bar item, dropdown, tooltips, Settings,
notifications, wording or layout) MUST keep both current. When its pull request merges:

- The plan MUST say which shots change, which are new and which website copy changes, or
  that there is no visible UI change and why.
- The demo scenario MUST show the new or changed UI, and the coverage test MUST check any new
  visual state a shot relies on.
- A new feature that merits a landing page card MUST have its own shot, in light and dark,
  and its card on the site.
- Changed and new shots MUST be recaptured with `scripts/screenshots/capture.sh` from the demo
  build, reviewed in both appearances, and land on the site together with the copy change.
  The site pull request MUST be linked from the app pull request, and both MUST merge before
  the release that ships the feature.
- Screenshots MUST come only from the demo build, never from a real AgentTacho. The site MUST
  NOT go live with placeholder images.
- After each release, the site's fallback release MUST name that release.

AGENTS.md holds the order of work; `docs/website.md` the file map, commands and pitfalls.

Rationale: the landing page is the first thing a user sees; stale images promise a UI that no
longer exists. The demo build makes recapturing cheap, so it happens with every UI change.

## Additional Constraints

- No em dash or en dash characters in code, comments, docs, specs or commit messages; the
  website's page tests reject them too.
- Commit messages follow Conventional Commits.
- `.mcp.json` and other files with credentials MUST never be committed.
- The demo build MUST stay out of regular builds: `make app`, `make dmg` and `make release`
  never link `DemoMode`, and a release refuses to run while `DEMO` is set.
- Published images use English text and US formats (`-AppleLanguages (en) -AppleLocale
  en_US`).

## Development Workflow and Quality Gates

- Start an idea with `/speckit-spex-brainstorm`, then `/speckit-specify`, `/speckit-clarify`,
  `/speckit-plan`, `/speckit-tasks` and `/speckit-implement`; `/speckit-spex-ship` runs the
  pipeline with review gates.
- Each feature passes `make test` and `make test-release` before merge, plus the spec
  compliance review and the deep review gate. A site change passes `npm run check`,
  `npm run build` and `npm test` in the site repository.
- `/speckit-spex-walkthrough` tries the feature by hand; for a UI change the walkthrough
  includes looking at the recaptured shots in both appearances.
- `/speckit-spex-submit` opens the pull request with the title `<Feature> [Spec + Impl]`.
- Each SDD session starts in a fresh agent session.
- Publishing actions (`make release`, the site's `SITE_LIVE` variable, starting `deploy.yml`,
  pushes to the site's `main`) happen only on the maintainer's explicit go for that run.

## Governance

This constitution supersedes other project practices. AGENTS.md is the runtime guidance file
for agents, `docs/website.md` its reference for the website; both MUST stay consistent with
this document.

- Amendments are made with `/speckit-constitution`, reviewed in a pull request, and record a
  Sync Impact Report at the top of this file.
- Versioning follows semantic versioning: MAJOR for removing or redefining a principle, MINOR
  for a new principle or materially expanded guidance, PATCH for wording and clarifications.
- Every spec review and code review checks compliance with these principles. A deviation MUST
  be justified in the plan's complexity tracking or fixed before merge.

**Version**: 1.1.0 | **Ratified**: 2026-10-18 | **Last Amended**: 2026-10-18
