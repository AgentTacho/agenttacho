<!--
Sync Impact Report
- Version change: template (unversioned) -> 1.0.0
- Modified principles: all template placeholders replaced
  - [PRINCIPLE_1_NAME] -> I. Spec-Driven Development
  - [PRINCIPLE_2_NAME] -> II. Test-First, Logic in UsageCore
  - [PRINCIPLE_3_NAME] -> III. Read-Only, Private by Default
  - [PRINCIPLE_4_NAME] -> IV. One Build Entry Point
  - [PRINCIPLE_5_NAME] -> V. Screenshots and Website Follow the UI
- Added sections: Additional Constraints, Development Workflow and Quality Gates
- Removed sections: none
- Dependent files: AGENTS.md updated with the screenshot and website rule (Principle V).
  Spec Kit templates read this file at runtime and are not changed here.
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
same pull request. Images and text published from this repository (README, website) MUST NOT
show real account names, email addresses, employers or usage data.

Rationale: users trust a menu bar app with their agents' credentials only if it never
surprises them.

### IV. One Build Entry Point

Building and testing MUST go through the Makefile: `make test`, `make test-release`,
`make app`, `make app-demo`, `make dmg`, `make release`. Scripts and documentation MUST NOT
describe a second way to build that bypasses it.

Rationale: the Makefile sets the SDK, plugin paths, signing and the demo switch; a side path
drifts and breaks releases.

### V. Screenshots and Website Follow the UI

A feature that changes what a user sees (menu bar item, dropdown, tooltips, Settings,
notifications, wording or layout) MUST keep the screenshots and the website current:

- The plan MUST contain a "Screenshots and website" section that lists the affected shots,
  the new shots, and the website copy to change, or states "no visible UI change".
- The demo scenario (`Resources/demo/`) MUST show the new or changed UI, and the scenario
  coverage test MUST check any new visual state the shots rely on.
- A new user-visible feature that merits a landing page card MUST add a shot to
  `scripts/screenshots/capture.sh` in light and dark.
- Changed and new shots MUST be recaptured with `scripts/screenshots/capture.sh` from the demo
  build into the site checkout (`AgentTacho/agenttacho.github.io`, `src/assets/agenttacho/`).
  The README image (`docs/images/`) MUST be replaced when the dropdown it shows changes.
- Website copy (feature cards, small things, comparison) MUST be updated in a pull request to
  the site repository, linked from the app pull request. Both MUST be merged before the next
  release that ships the feature.
- Screenshots MUST come only from the demo build, never from a real AgentTacho.

Rationale: the landing page is the first thing a user sees; stale images promise a UI that no
longer exists. The demo build makes recapturing cheap, so it happens with every UI change.

## Additional Constraints

- No em dash or en dash characters in code, comments, docs, specs or commit messages.
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
  compliance review and the deep review gate.
- `/speckit-spex-walkthrough` tries the feature by hand; for a UI change the walkthrough
  includes looking at the recaptured shots in both appearances.
- `/speckit-spex-submit` opens the pull request with the title `<Feature> [Spec + Impl]`.
- Each SDD session starts in a fresh agent session.

## Governance

This constitution supersedes other project practices. AGENTS.md is the runtime guidance file
for agents and MUST stay consistent with it.

- Amendments are made with `/speckit-constitution`, reviewed in a pull request, and record a
  Sync Impact Report at the top of this file.
- Versioning follows semantic versioning: MAJOR for removing or redefining a principle, MINOR
  for a new principle or materially expanded guidance, PATCH for wording and clarifications.
- Every spec review and code review checks compliance with these principles. A deviation MUST
  be justified in the plan's complexity tracking or fixed before merge.

**Version**: 1.0.0 | **Ratified**: 2026-10-18 | **Last Amended**: 2026-10-18
