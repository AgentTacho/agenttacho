# Brainstorm: Section Bands

**Date:** 2026-10-19
**Status:** active

## Problem Framing

The dropdown draws a `Divider()` between every pair of sections and one above the pinned footer (spec 025 FR-011, spec 026). With several accounts and groups the dropdown reads as a stack of horizontal lines, which works against the minimal look of specs 025 and 026. The sections still need a visible boundary, but a quieter one: very faint alternating background tints instead of lines.

This brainstorm is the first of two dropdown changes from the same session; brainstorm 28 (default window per account) follows it.

## Approaches Considered

### A: Full-width zebra bands (chosen)
- Every other section gets a very faint tint that runs edge to edge across the dropdown; no lines, no gaps.
- Pros: closest to the request, keeps the vertical rhythm, no extra height.
- Cons: the tint must be faint enough to stay calm yet survive screenshots; it must not swallow the row hover highlight of spec 027.

### B: Rounded cards
- Each section sits on its own faint rounded panel with a small gap between panels.
- Pros: every section is bounded, no alternation needed.
- Cons: more chrome than today, the gaps add height, and nested cards (group members) get busy.

### C: Spacing only
- No lines and no tints, a larger gap between sections.
- Pros: quietest.
- Cons: weak boundaries in a long list; adds height.

## Decision

Approach A. Sections alternate plain and tinted, starting plain. The pinned footer always gets its own band, a touch stronger than the zebra tint, so it never blends into the last section whichever stripe that is.

```
┌──────────────────────────────────┐
│ ✳ Claude Max              70%    │  plain
│   5-hour  58%    resets 1h 57m   │
│░◎ Codex Pro               41%   ░│  faint tint
│░  weekly  41%    resets 4d 2h   ░│
│ ▣ Team budget   $212 / $500      │  plain
│▒ ⟳ Last refreshed 16:54        ▒│  footer band
└──────────────────────────────────┘
```

## Key Requirements

- The dividers between sections and above the pinned footer are removed from the dropdown.
- Sections alternate plain and faintly tinted in arrangement order, the first section plain; Unassigned continues the alternation. A group with its members is one section.
- Each band spans the full dropdown width and includes the section's vertical padding, so text never touches a band edge.
- The pinned footer has its own band, slightly stronger than the zebra tint, regardless of the last section's stripe.
- The tints adapt to light and dark mode (system-adaptive colors, no fixed RGB) and stay subtle in both.
- The row hover highlight of spec 027 stays clearly visible on a tinted band.
- The configuration error and demo scenario error lines at the top are not sections and get no band.
- The stripe of each section is decided by tested logic (constitution II), for example a pure function from the arranged entries and Unassigned to plain or tinted.
- Constitution V: every dropdown screenshot changes; the README dropdown image is replaced.

## Open Questions

- Exact tint strengths in light and dark mode, and whether they still read after the site's WebP compression.
- Behavior under "Increase Contrast" (stronger tints, or the dividers come back).
- Whether the band changes under the scroll edge when sections scroll beneath the pinned footer at the height cap (spec 026 FR-010).
- Whether the Settings panes' dividers should follow later (out of scope here).
