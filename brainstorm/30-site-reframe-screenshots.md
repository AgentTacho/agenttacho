# Brainstorm: Site Reframe Screenshots

**Date:** 2026-10-20
**Status:** active

## Problem Framing

The landing site (`agentmeter-site`, repository `AgentTacho/agenttacho.github.io`)
is being reframed from a feature catalogue to a focused positioning page. The
design lives in that repo at
`docs/superpowers/specs/2026-10-20-messaging-reframe-design.md` (draft, not yet
committed). The site drops its nine-card grid for a six-card (2 x 3) grid and
demotes several features to a one-line strip with no screenshots.

That restructure changes which captures the site needs. The site PR (phase 1)
ships first with nearest-existing shots as placeholders; this brainstorm covers
the capture work on the app side (phase 2) so the page can reach its finished
visual state. The capture tooling is `scripts/screenshots/capture.sh` (current
`STEMS`: `menubar plan-limits pace budget groups details alert prices
menubar-settings harnesses dropdown`, 22 files per run).

## What the site needs

1. **Usage at a glance** (card 1): one image that carries what used to be three
   cards (`plan-limits`, `pace`, `details`): plan limits, pace and the Details
   breakdown expanded, in one view.
2. **Same provider, more than once** (card 3): two Claude Max subscriptions,
   configured with separate credential directories, tracked separately. No
   existing capture resembles this.

Both captures must fill the card's image area nearly fully, with only a small
margin to the border, so the cards do not look sparse.

The site no longer uses `plan-limits`, `pace`, `details` (folded into card 1),
`groups` ("Shared budgets" becomes a one-line mention) and `alert`
("Notifications" becomes a one-line mention). It keeps `menubar`, `budget`,
`harnesses`, `prices` and `menubar-settings`.

## Approaches Considered

### Where the second Claude Max account lives

- **A: Add it to `default.json`** (chosen). One scenario, one launch per
  appearance. The menubar and dropdown also show two Claude entries, which backs
  the hero's "several on the same provider" claim. Cost: every shot that shows
  the bar or the dropdown changes, and the dropdown gets taller.
- **B: Separate scenario file.** Existing shots stay as they are, but
  `capture.sh` needs a second launch per appearance and the demo loader has to
  pick a scenario.
- **C: Turn an existing account into the second Claude Max.** Single launch,
  but it weakens the harnesses and multi-provider story.

### Usage at a glance vs. the `dropdown` stem

- **A: New stem `glance`, retire `dropdown`** (chosen). The stem name says what
  the shot is, and a section crop stays readable at card size.
- **B: Recompose `dropdown`.** No stem rename on the site, but with two Claude
  accounts a full-window shot is too tall to read at card size.
- **C: Keep both.** One more pair per run that the site does not reference.

### What the same-provider shot shows

- **A: Both Claude Max sections from the dropdown, stacked** (chosen). Shows
  plainly that each account has its own windows and levels.
- **B: Two Claude entries in the rendered menu bar.** Small, and too close to
  the hero's menu-bar strip (the site design warns against saying the same thing
  twice).
- **C: The account list in Settings.** Shows the separate directories, but it
  is a configuration screen, not usage.

### How the fill requirement is pinned down

- **A: The app sets the aspect** (chosen). The spec fixes a target aspect and a
  maximum margin; the site sizes its card image area to match. Testable now.
- **B: Wait for site phase 1** and read the card aspect from it. Exact, but
  blocks the spec.
- **C: Tight crop, no aspect.** Simplest, but cards may differ in height.

## Decision

Phase-2 follow-up to the site reframe, built in the app repo:

- Add a second Claude Max subscription account to `Resources/demo/default.json`
  with its own credential directory, its own plan windows and its own usage.
- New stem `glance`: the first Claude Max section with plan limits, pace and its
  Details breakdown expanded, cropped to the target aspect.
- New stem `same-provider`: a crop of the dropdown showing both Claude Max
  sections stacked, cropped to the target aspect.
- Drop `plan-limits`, `pace`, `details`, `groups`, `alert` and `dropdown` from
  `STEMS`. The final set is `menubar budget harnesses prices menubar-settings
  glance same-provider` (7 stems, 14 files per run).
- Hand the new pairs to the site repo, which replaces its placeholders, deletes
  the retired pairs and updates `tests/page.test.ts`.

## Key Requirements

- Both new captures meet a fixed target aspect (proposal: 16:10) with a maximum
  margin per side (proposal: 4%). The site's card image area adopts the same
  aspect.
- Both new captures come from the demo build only, in light and dark, as
  lossless `.webp` pairs like the existing ones (constitution III and V).
- The two Claude Max accounts read as two distinct accounts at card size
  (distinct names, different usage levels).
- The coverage test in `Tests/DemoModeTests` checks the states the new shots
  rely on: two subscription accounts on the same harness with different
  credential directories, and an expanded Details breakdown on the first.
- `scripts/release/tests/test_screenshots.sh` covers the new stems and crops,
  and its file count goes from 22 to 14; the tests for retired stems (pace crop,
  alert banner, details scroll) are removed or adapted.
- Docs that name the stems or counts are updated: `AGENTS.md` (eleven
  screenshots, nine cards, five small things, 22 files) and
  `docs/website.md` (stem list, 22 files).
- No strict order between the two repos: `capture.sh` never deletes files from
  its target, so retired pairs stay in the site checkout until the site's
  phase-2 PR removes them, and its build stays green throughout.
- The existing shots that change because of the second account (`menubar`,
  `budget` if affected) are reviewed in both appearances as usual (AGENTS.md
  step 5).

## Open Questions

- Exact target aspect and margin (16:10 and 4% are proposals); confirm with the
  site's new card layout.
- Account names and credential directories for the two Claude Max accounts
  (for example "Claude Max · Work" with `~/.claude` and "Claude Max · Personal"
  with `~/.claude-personal`), and which windows and levels each shows.
- Whether the bar shows both Claude accounts, and whether that makes the
  `menubar` shot too wide for the hero strip.
- Whether `glance` fits plan limits, pace and the expanded Details in the
  target aspect without becoming unreadable at card size, or whether Details
  needs a shorter view (for example fewer model rows) in the demo.
- With `alert` gone, whether `capture.sh` drops its Notification Center and
  banner-style checks, and whether the demo still sends its crossing
  notification.
- Whether `groups` and the Groups Settings tab shot disappear entirely, or the
  docs still use them elsewhere.
