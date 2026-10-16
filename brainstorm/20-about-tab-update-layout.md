# Brainstorm: About Tab Update Layout

**Date:** 2026-10-16
**Status:** active

## Problem Framing

Settings > About stacks a lot of text under the release data. The update block (spec 013 FR-002, FR-011) has an "Updates" heading, a status line ("Up to date (checked 14:02)"), and a row with the "Check for Updates…" button next to the "Check for updates automatically" toggle. The heading adds nothing the button does not already say. The toggle is a preference, not information about this build, so it sits oddly in About when all other preferences live in General. The release grid also shows a Signing row ("Developer ID, notarized") that means little to an end user.

## Approaches Considered

### A: Button with the status below it (chosen)
- Centered "Check for Updates…" button, the status line under it in secondary text; an available update shows its actions (Install, Release notes) on that line.
- Pros: closest to the current code, keeps the update check as a small block of its own, room for action links without crowding.
- Cons: two lines instead of one.

### B: Status as a grid row
- An "Updates" row in the version grid ("Updates  Up to date (checked 14:02)"), the button underneath.
- Pros: reads as part of the release data.
- Cons: the grid widens when an update with action links appears.

### C: Status inline with the button
- Button and status side by side on one line.
- Pros: most compact.
- Cons: long line, wraps awkwardly with action links or an error text.

For the Signing row, keeping it only for non-notarized builds or moving it to a tooltip on the version were considered and dropped: release builds are notarized, and someone running a source build knows how they built it.

## Decision

Approach A. The toggle moves to a new "Updates" section in General, placed after "Launch". The Signing row is removed from About entirely.

## Key Requirements

- About no longer shows the "Updates" heading or the Signing row.
- About shows a centered "Check for Updates…" button with the status line below it in secondary text. The status uses the existing settings text ("Up to date (checked HH:MM)", "Not checked yet", "AgentMeter X.Y.Z available", errors).
- An available update shows its actions (Install / Upgrade with Homebrew / Download / Try again, Release notes) on the status line. A known update kept after a failed manual check (spec 013 FR-007a) appears as a second line.
- The button stays disabled while an install runs.
- General gets an "Updates" section after "Launch" with "Check for updates automatically", applied through the Settings draft like every other setting, persisted as today.
- The signing stamp stays in the bundle and in `AppVersionInfo`; the updater still uses it to choose the install action. Only its display in About goes.
- Spec 013 FR-002 and FR-011 are updated to say the toggle lives in Settings > General and About shows the button and status without the toggle.
- No change to update logic or the dropdown's update line.

## Open Questions

- When automatic checks are off, should About's status say so (for example "Not checked yet · automatic checks off")?
- Does the About doc comment and README text that mentions the signing tier in About need updating?
