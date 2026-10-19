# Brainstorm: Headline Window Switch

**Date:** 2026-10-19
**Status:** active

## Problem Framing

Each subscription plan has one fixed headline window: the 7-day window for a Claude subscription (spec 001 FR-005) and the longest effective window for a Codex plan (spec 007 FR-012). That window drives the bold percent in the dropdown header, the menu bar value, the bar's color level (spec 012) and the `↗` / `↑` markers (spec 011 FR-012, spec 017 FR-008). During heavy work another window is the one about to bite, usually the 5-hour window or a model limit such as Fable, and the user wants that number in the menu bar instead.

Threshold notifications are not affected: they already check every window separately. Budgets and member shares have a single window and are out of scope. This came from the spec 025 walkthrough (idea inbox `headline-percent-switch`).

## Approaches Considered

### A: Click a window row (chosen)
- Clicking any limit-window row in the dropdown makes it the account's headline window; a ● marks the chosen row.
- Pros: direct (you click the number you want to watch), all windows visible while choosing, no new control.
- Cons: rows become interactive, which needs a quiet affordance.

### B: Click the header percent to cycle
- Each click moves to the next window.
- Pros: one target.
- Cons: you cycle blind until you hit the window you want.

### C: Automatic "most pressing" with manual override
- The headline shows the highest or soonest-running-out window; a click pins one.
- Pros: no interaction in the common case.
- Cons: the menu bar value changes meaning on its own; the user asked for a manual switch.

## Decision

Approach A. When a window other than the default is chosen, the menu bar shows a small window tag next to the value (for example "✳ 5h 58%") so the number is never mistaken for the default window's; with the default window the bar looks as today. The choice is stored per account, survives a restart, and lasts until the user clicks the default row again.

```
✳ Claude Max                   5h 58%
● 5-hour  58%            resets in 1h 57m
████████████████░░░│░░░░░░░░░░░░░
  7-day   70%            resets in 3d 11h
████████████│████████░░░░░░░░░░
```

## Key Requirements

- In a Claude or Codex subscription section, clicking a limit-window row (5-hour, 7-day, model limits, each Codex window) makes it the account's headline window; the chosen row shows a ● marker.
- The headline window drives the section's bold header percent, the menu bar value, the bar's color level and the `↗` / `↑` markers.
- With a non-default window chosen, the menu bar shows a short window tag before the value; with the default window, the bar entry is unchanged.
- The choice is stored per account in the configuration, survives a restart, and returns to the default when the user clicks the default row.
- When the chosen window no longer exists (a model limit dropped, a Codex plan changed its windows), the account falls back to its default window.
- Threshold notifications, budgets, member shares and the window order in the dropdown are unchanged.
- The choice, the fallback, the tag text and the resulting bar value are decided by tested UsageCore logic (constitution II).
- Constitution V: the menu bar and dropdown shots change; the screenshot round follows this spec (idea inbox `minimal-dropdown-screenshots`).

## Open Questions

- How does a row show it can be clicked without a tooltip (pointer change, hover highlight, the ● slot)?
- Tag format in the menu bar for each window: "5h", "7d", model names such as "Fable", Codex windows ("wk", "30d")? Does the tag count toward the bar's width rules (spec 008)?
- Should Settings (account detail or the Menu Bar tab) also show and change the choice, for discoverability?
- VoiceOver: the row's action name ("Show in menu bar") and how the chosen state is announced.
- Does the Menu Bar tab's live preview show the tag?
- Interaction with brainstorm 25 (dropdown layout polish): order of the two specs and shared screenshot round.
