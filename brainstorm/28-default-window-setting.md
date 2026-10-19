# Brainstorm: Default Window Setting

**Date:** 2026-10-19
**Status:** active

## Problem Framing

Spec 027 fixed each subscription account's default window: the 7-day window for a Claude subscription and the longest window for a Codex plan (spec 027 FR-005). A click on another row in the dropdown makes that row the headline window. The ● marks the headline row in every case, including the default, so the dropdown always carries a marker even when nothing was changed.

Users work differently: one watches the 5-hour window all day, another a model limit such as Fable. They want to set the default per account, and keep the dropdown click for a temporary switch. The ● should then mean "temporarily switched", and appear only then.

This brainstorm follows brainstorm 27 (section bands) and is implemented after it.

## Approaches Considered

### A: Settings picker with fixed and observed windows (chosen)
- A "Default window" picker in each Claude and Codex subscription account's settings. Claude: 5-hour and 7-day always, plus every model limit in the latest data. Codex: the windows the plan currently reports. A saved default not currently reported stays listed as "(not reported)".
- Pros: covers the model limit case, discoverable, no hidden gestures.
- Cons: the list depends on observed data; an account that has not refreshed yet offers only the fixed windows.

### B: Fixed windows only
- Claude: 5-hour or 7-day; Codex: shortest or longest.
- Pros: a static list, nothing to observe.
- Cons: a model limit can never be the default, which is one of the cases asked for.

### C: Set from the dropdown
- A secondary gesture on a row (right-click or option-click, "Make default").
- Pros: no Settings change.
- Cons: hidden gesture, hard to discover, and a menu bar extra has little room for context menus.

## Decision

Approach A, with these marker and tag rules:

- While the account's default window is the headline, no row shows ●, and the menu bar shows no tag.
- Hovering a non-headline row still shows ○ as the click hint (spec 027).
- A click on a non-default row makes it the temporary headline: that row gets ●, and the menu bar shows its tag (spec 027 FR-008, FR-009).
- A click on the default row ends the temporary choice: ● and tag disappear.
- The temporary choice lasts until clicked back, as today: saved per account, survives a restart, ends only on a click on the default row or when the window disappears.

## Key Requirements

- Each Claude and Codex subscription account has a "Default window" setting, stored as a new configuration key next to `headlineWindow`. An account without the key keeps the built-in default of spec 027 FR-005.
- The picker lists the fixed windows plus the observed ones (Approach A); a saved default not in the latest data shows as "(not reported)".
- `headlineWindow` keeps its meaning as the temporary choice; existing configuration files stay valid.
- "Default" in spec 027 (marker, tag, fallback) now means the configured default window.
- ● appears only on a temporary non-default headline row; the default headline row has no marker.
- The menu bar tag appears only for a temporary non-default headline, whatever the configured default is (a 5-hour default shows no tag).
- When the configured default window is not reported (a model limit dropped, a Codex plan changed), the account falls back to the built-in default.
- Changing the default in Settings clears a temporary choice (assumption, to confirm in the spec).
- Resolution of default, temporary choice and fallback, the marker rule and the tag rule are tested UsageCore logic (constitution II).
- Threshold notifications, budgets, member shares and the window order are unchanged.
- Constitution V: the Settings account pane and the dropdown shots change; the screenshot round follows this spec.

## Open Questions

- During a fallback (configured default not reported), does the built-in default get a tag in the menu bar, or does it count as the default?
- Does the Menu Bar tab's live preview reflect the configured default?
- VoiceOver: how the dropdown announces the default row now that it has no visible marker.
- Picker labels for Codex windows ("5-hour", "weekly") and model limits (the model name as reported).
- Whether a temporary choice equal to a newly configured default is cleared silently (it becomes the default) or kept.
