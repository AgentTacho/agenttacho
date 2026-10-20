# Research: Site Reframe Screenshots

## R1: Aspect rule instead of a fixed 16:10

- **Decision**: uniform margin from the window plus an aspect range of 3:4 to 4:3 (FR-012).
- **Rationale**: today's site images (2x) measure plan limits 696x308, details 673x496, dropdown 720x1232. A Claude section with expanded details is about 0.9:1 and two stacked sections about 1.1:1 at the dropdown's fixed 360 pt width. A 16:10 frame would need well over 4% padding; synthesized padding also cannot match the dropdown's material and tinted bands.
- **Alternatives**: fixed 16:10 (rejected, sparse), fixed 1:1 per shot (rejected, would force padding on one of the two), tight crop without bounds (rejected, a long details table could produce a strip).

## R2: Markers for the first and second Claude Max sections

- **Decision**: `BarLayout.shotClaudeAccountIds` picks the first two Claude subscription accounts in arrangement order; the view attaches `agenttacho.claudeSection`, `agenttacho.claudeSection2` and `agenttacho.claudeDetails`. `same-provider` is the union of the two section frames.
- **Rationale**: the existing `agenttacho.claudePlan` and `agenttacho.paceRow` are attached to every Claude section, so with two accounts `uihelper frame` would find two elements. A container spanning two adjacent `ForEach` entries does not exist in the view tree; the union of two frames is the same region, since FR-005 keeps the sections adjacent. Choosing the accounts in UsageCore keeps the rule testable (constitution II), like `shotBudgetOwner`.
- **Alternatives**: one container around both (rejected, needs restructuring the section loop); markers on every Claude section with an index from the view (rejected, logic in the view).

## R3: Capture order and the shared details state

- **Decision**: `same-provider` first, then `glance` (expand, Models, capture, collapse), then `budget`, then `harnesses`.
- **Rationale**: the view picker is pressed by its title (`Models`, `Harnesses`); with two expanded details the title would be ambiguous. The details mode is one stored choice (`detailsMode`), so selecting Models for `glance` also prepares the budget's details; `harnesses` switches it and the script restores Models at the end, as today.

## R4: Scrolling before every dropdown crop

- **Decision**: `scrollto` the region and take a fresh window capture before each dropdown crop, including `budget`.
- **Rationale**: with five sections the dropdown can reach its height cap (spec 026 FR-010); the budget row was cut from the first window image without scrolling, which only worked while everything fit.

## R5: Removing the notification setup

- **Decision**: remove `check_notifications`, the permission part of `preflight`, `first_run` and `--first-run`.
- **Rationale**: they existed only for the `alert` stem (spec 024). The demo may still post its crossing notification; window captures never include it. The scenario keeps its timed frame, because the capture waits for "demo: last frame applied".

## R6: Names of the two accounts

- **Decision**: "Claude Max · Work" (`~/.claude`) and "Claude Max · Personal" (`~/.claude-personal`).
- **Rationale**: both read as Claude Max at card size, the suffix tells them apart, and the pair matches the site's story of a company account plus one's own. Invented, so `demoFilesUseInventedNamesOnly` holds. Unit tests that use "Claude Max" build their own fixtures and are unaffected; `variants.json` keeps its own names.
