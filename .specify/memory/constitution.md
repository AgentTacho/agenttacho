<!--
Sync Impact Report
- Version change: 1.1.0 -> 2.0.0
- Modified principles:
  - I. Spec-Driven Development -> I. Issue First, AI Welcome, Specs Recommended: redefined.
    Spec-driven development is no longer mandatory for any change, only recommended. Outside
    contributions start with an issue and open a pull request only after it was accepted.
    AI-assisted contributions carry a diligent AI attribution and are ideally self-reviewed by
    review agents (cc-review).
  - II. Test-First, Logic in UsageCore: doc comments cite the issue when a change has no spec.
  - V. Screenshots and Website Follow the UI: without a spec, the pull request description
    takes the plan's screenshot section.
- Modified sections: Development Workflow and Quality Gates (every change needs tests and a
  code review; the SDD pipeline is one way, not the only one), Governance (deviations are
  justified in the plan or, without a spec, the pull request description)
- Added sections: none
- Removed sections: none
- Dependent files: AGENTS.md (Contributions section), CONTRIBUTING.md (rewritten for the new
  contribution rules)
- Deferred TODOs: none
-->

# AgentTacho Constitution

## Core Principles

### I. Issue First, AI Welcome, Specs Recommended

Outside contributions MUST start with an issue. An implementation pull request MUST be opened
only after the maintainer accepted that issue. AI-assisted contributions are welcome. They MUST
carry a diligent AI attribution (for example an `Assisted-By:` commit trailer naming the agent)
and SHOULD be self-reviewed with review agents, such as cc-review, before the pull request is
opened.

Spec-driven development is recommended but not required: a specification in
`specs/NNN-name/` that says what changes and why, then a plan and tasks, then the
implementation, reviewed against the spec. The cc-spex collab workflow supports it in Claude
Code and Codex. Larger changes MAY land as a `[Spec]` pull request first.

Rationale: agreeing on the issue first keeps contributors from building something that will
not be merged, which lets the bar for the contribution itself stay low. Where there is a spec,
it is the reviewable record of intent, and code review checks the code against it.

### II. Test-First, Logic in UsageCore

Logic MUST live in `UsageCore` (or another library target such as `DemoMode`) and MUST be
covered by tests written before the implementation. `Sources/AgentTacho` MUST stay a thin
SwiftUI layer that wires models to views. Doc comments MUST cite the spec requirements they
implement (for example `spec 008 FR-004`), or the issue when the change has no spec.

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

- The plan (or, for a change without a spec, the pull request description) MUST say which
  shots change, which are new and which website copy changes, or that there is no visible UI
  change and why.
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

- Every change passes `make test` and `make test-release` before merge, plus a code review
  (the deep review gate or review agents such as cc-review). A change with a spec also passes
  the spec compliance review. A site change passes `npm run check`, `npm run build` and
  `npm test` in the site repository.
- For a UI change, the recaptured shots are looked at in both appearances before merge.
- With spec-driven development, an idea starts with `/speckit-spex-brainstorm`, then
  `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks` and
  `/speckit-implement`; `/speckit-spex-ship` runs the pipeline with review gates,
  `/speckit-spex-walkthrough` tries the feature by hand, and `/speckit-spex-submit` opens the
  pull request with the title `<Feature> [Spec + Impl]`. Each SDD session starts in a fresh
  agent session.
- Without a spec, a change goes from its accepted issue (for an outside contribution) or the
  maintainer's decision straight to a pull request.
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
- Every code review, and every spec review where there is a spec, checks compliance with these
  principles. A deviation MUST be justified (in the plan's complexity tracking, or in the pull
  request description when there is no spec) or fixed before merge.

**Version**: 2.0.0 | **Ratified**: 2026-10-18 | **Last Amended**: 2026-10-21
