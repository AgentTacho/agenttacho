# Brainstorm: Readable Dialog Screenshots

**Date:** 2026-10-18
**Status:** active

## Problem Framing

The landing page (brainstorm #18) shows nine feature cards, each with a screenshot in a fixed card frame (150 px tall, ~340 px wide). Three of the cards look wrong: the window is shrunk so small that nothing in it can be read.

All the landing-page screenshots come from `scripts/screenshots/capture.sh`, which writes the 22 WebP files straight into the site checkout's `src/assets/agenttacho/`. The site repo does not author these images, so any crop or CSS zoom done on the site side is overwritten by the next capture. The fix belongs in `capture.sh`.

`capture.sh` already produces two kinds of shots:

- **Cropped to one UI element** with the `crop` helper and `uihelper frame <pid> <identifier>`: `plan-limits`, `budget`, `pace`, `details`, `harnesses`. These are tight and read well.
- **Whole-window `screencapture`**: `groups`, `menubar-settings`, `prices`, and `dropdown`. The Settings window is a standard macOS TabView pane window at a fixed size with sparse demo content, so these come out around 1600×1000 with a lot of empty chrome and shrink to unreadable in the card.

The three that look wrong are exactly the three whole-window Settings shots: `groups` (Shared budgets), `menubar-settings` (Your bar, your way), and `prices` (Prices you control).

The screenshots exist to highlight the feature's message, not to document the whole window. So the fix is to make these three crop to the part that *is* the message, the way the strip shots already crop to their element.

## Approaches Considered

### A: Crop the three Settings shots to a content frame (chosen)
- Add an accessibility identifier to the content container of each of the three tabs on the Swift side. In `capture.sh`, change `settings_tab` (and the `prices` block) to `crop` the captured window image to that frame, reusing the existing `crop` helper and `uihelper frame`, instead of `screencapture` of the whole window.
- Pros: reuses the path the strip shots already use; no site-side change; each crop lands on the feature's message; nothing else about the capture run changes.
- Cons: needs one small Swift change per tab (an identifier); a tight crop only looks convincing if the demo scenario fills that region with believable content.

### B: Fix it on the site (CSS crop / object-position, or re-crop the WebP files by hand)
- Zoom or re-crop the three images in the site repo.
- Rejected: the capture overwrites `src/assets/agenttacho/` wholesale, so any site-side work is lost the next time anyone regenerates the screenshots. It also splits the source of truth for how a shot looks across two repos.

### C: Shrink or resize the Settings window for the capture
- Make the demo Settings window smaller so the whole pane reads at card size.
- Rejected: fights Apple's settings-window conventions, still shows chrome and empty space that is not the message, and the window is not freely resizable.

## Decision

Approach A. Crop the three whole-window Settings shots to the content that carries each card's message, in `capture.sh`, with an accessibility identifier added to each tab's content container on the Swift side. No change to the site repo, to the already-readable strip shots, or to the capture run's structure (preflight, appearance passes, move-into-target).

Focal point per shot (what the crop must contain):

- **`groups` (Shared budgets)** — the group editor for "Company budget", showing its members (Claude via Vertex, OpenAI API) rolling up into the one monthly budget. The "several accounts, one limit" idea, nothing else. This content lives in `GroupEditor`, which only renders when a group is selected, so the capture must select the group first (see Key Requirements).
- **`menubar-settings` (Your bar, your way)** — the live bar preview together with the entry list the user reorders. The "pick and arrange, see it live" idea.
- **`prices` (Prices you control)** — the import preview sheet, the "preview before it applies" moment, not the full price table behind it.

## Key Requirements

- `capture.sh` crops `groups`, `menubar-settings`, and `prices` to an accessibility-identified content frame, using the existing `crop` helper and `uihelper frame <pid> <identifier>`, rather than capturing the whole Settings window.
- Each of the three Settings tab content containers exposes an accessibility identifier for the croppable region, following the `shotContainer`/`shotIdentifier` pattern the dropdown already uses for its cropped elements (for example `agenttacho.budgetRow`, `agenttacho.details`). A natural naming is `agenttacho.settings.groups`, `agenttacho.settings.menubar`, `agenttacho.settings.prices`; the builder picks the exact ids and the exact subview they sit on so the crop frames the focal point above. (Source note: `GroupSettingsView` lives in `AccountSettingsView.swift`, and `PriceSettingsTab` lives in `SettingsView.swift`, not in files of their own.)
- **`groups` needs a selected group at capture time.** `GroupSettingsView` opens on the "Select a group or add one" placeholder (`selection` starts nil, not persisted), and `capture.sh` currently shoots the Groups tab immediately. The capture must first select the "Company budget" row, then crop to the `GroupEditor` region. This needs a small accessibility id on that group-list row so `uihelper` can select it, and a new select step in the `groups` capture before the crop. (Chosen over pre-selecting in the demo build, so the whole fix stays in `capture.sh` + Swift ids.)
- For `prices`, the crop frames the import preview sheet. The sheet is already reachable as its own window (it appears as a layer-0 window of its own; `largest_window` / the window list finds it), so the builder may capture it by its own id or crop from the Settings-window image. The result must show the preview, not the empty price table.
- The crop uses enough margin that the content does not look clipped at the edges. The builder may reuse the `crop` helper's current margins or widen them for these panes.
- The other eight shots are unchanged: the five strip shots keep their element crops, `menubar` and `alert` keep their current handling, and `dropdown` keeps its whole-window capture (it is already card-shaped).
- The three new identifiers exist in the demo build as well as the normal build, since the capture runs against "AgentTacho Demo.app".
- After the change, a capture run still prints the 22 files with their sizes and exits 0; `make test-release` (which includes `scripts/release/tests/test_screenshots.sh`) still passes.
- The stub-based test (`scripts/release/tests/test_screenshots.sh`) pins the old behavior: it asserts `prices-*` comes from a whole-Settings-window `screencapture`, and its `uihelper` stub returns a single fixed rect for any `frame` id against fixed `windows` fixtures. These expectations get rewritten to match the new crop flow, with fixtures for the new ids' frames (and, for `groups`, the group-row select step). Rewriting these expectations is in scope, not a reason to keep the old whole-window capture.

## What's Left to the Builder

- The exact accessibility identifier strings and which subview each sits on, chosen so the crop frames the focal point for that card.
- The exact crop margins for the Settings panes.
- For `prices`, whether to capture the import sheet by its own window id or crop it out of the Settings-window image.
- For `menubar-settings`, how tightly to frame. The focal pair (the live `preview` at the top and the reorder `List` at the bottom) brackets the level-settings picker and the run-out-marker toggle. A single container id over the whole tab content (preview + level settings + toggle + list, minus the window chrome) is acceptable for the card and reuses `crop` as-is; that is the default. Framing *only* preview + list would need a union-of-two-frames crop like the `pace` shot's `region` helper. The builder picks based on how the captured image reads.

## Open Questions

- Does the demo scenario (`Resources/demo/default.json`) fill these three panes with convincing content once cropped, or does a tight crop expose sparse or empty demo data? The group editor and import sheet are populated in the demo, so this is lower risk than it first looked, but the crop only lands if the content behind it reads. The builder confirms it when looking at the captured images (the capture already requires the maintainer to run and inspect every shot in both themes).
- Should `dropdown` also be reconsidered later? It is captured whole and is naturally card-shaped, so it is out of scope here, but worth a glance when the three are done.
