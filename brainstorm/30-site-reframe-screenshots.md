# Brainstorm: Site Reframe Screenshots

**Date:** 2026-10-20
**Status:** tracking (follow-up to the site messaging reframe)

## Problem Framing

The landing site (`agentmeter-site`) is being reframed from a feature catalogue
to a focused positioning page. The design lives in that repo at
`docs/superpowers/specs/2026-10-20-messaging-reframe-design.md`. The site drops
its nine-card grid for a six-card (2 x 3) grid and demotes several features to a
one-line strip with no screenshots.

That restructure changes which captures the site needs. The site PR ships first
with nearest-existing shots as placeholders; this brainstorm tracks the capture
work on the app side so the page can reach its finished visual state. The
capture tooling is `scripts/screenshots/capture.sh` (current `STEMS`:
`menubar plan-limits pace budget groups details alert prices menubar-settings
harnesses dropdown`).

## What the site needs

### New or recomposed captures

1. **Usage at a glance** — a single dropdown capture that shows plan limits and
   pace together with one account's details expanded, so one image carries what
   used to be three cards (`plan-limits`, `pace`, `details`). Likely a recompose
   of the `dropdown` scenario with a details section expanded, or a new stem.
2. **Same provider, more than once** — two Claude Max subscriptions side by side,
   configured via separate directories. No existing capture resembles this; it
   is a new scenario and a new stem (working name `same-provider`).

### Fill requirement

Both captures must fill the card's image area more or less fully, with only a
small margin to the border. Crop to roughly the card image aspect rather than
leaving large empty padding, so the cards do not look sparse. The site side
adjusts its card image region to match; the capture crop must meet it halfway.

### Captures the site no longer uses

Once the two above land, these stems are no longer referenced by the site and
can be dropped from the asset set and from `capture.sh` `STEMS`:

- `plan-limits`, `pace`, `details` — folded into "Usage at a glance."
- `groups` — "Shared budgets" becomes a one-line mention, no screenshot.
- `alert` — "Notifications" becomes a one-line mention, no screenshot.

Kept and still used by the site: `menubar`, `budget`, `harnesses`, `prices`,
`menubar-settings`, and `dropdown` (the phase-1 placeholder for "Usage at a
glance," retired if the recompose gets its own stem).

## Decision

Treat this as a phase-2 follow-up to the site reframe. Produce the two captures
(light + dark `.webp` pairs), satisfy the fill requirement, remove the obsolete
stems, then hand the new pairs to the site repo to replace the placeholders and
update any screenshot-stem assertions in its `tests/page.test.ts`.

## Open Questions

- Does "Usage at a glance" reuse the `dropdown` stem (recomposed) or get a new
  stem? Affects whether `dropdown` is retired.
- Exact demo scenario for two Claude Max accounts (account names, which windows
  shown) so the capture is realistic and reads clearly at card size.
- Final card image aspect from the site, to crop both captures to fill it.
