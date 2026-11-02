# Implementation Plan: Accounts without a Limit

**Branch**: `041-no-limit-accounts` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/041-no-limit-accounts/spec.md`

## Summary

`TokenMembership` gets a third case, `.noLimit(NoLimitSettings)`, next to `.group` and `.ownBudget`. A No limit account stores `"noLimit": {"period": ...}` in the configuration and, at account level like `timeFormat`, an optional `"valueAs": "<model id>"` that survives a switch to a budget. The aggregator counts a No limit account over its period's window into a new snapshot map `noLimitAccounts`; it never becomes a budget owner, so the bar, thresholds, notifications, pace and burn rate leave it out without changes of their own. The arrangement keeps it as an entry, so its dropdown section appears in order; the Menu Bar tab shows it without a "Show in bar" checkbox.

The value line is computed at presentation time: a core function prices the section's per-model breakdown at the Value as model's rates from the effective price table (built-in, imported, overrides), the same table the Prices tab shows. This keeps the refresh pipeline free of price state and lets the value follow a price change at once. Settings gets "No limit" in the account editor's budget picker and in the new account sheet, with the period, a "Value as" pop-up and the "Times" picker; switching between No limit, an own budget and a group goes through new and widened `Configuration` helpers.

## Technical Context

**Language/Version**: Swift 5.10 tools, Swift 6 compiler, macOS 14+

**Primary Dependencies**: Foundation (`Decimal`, `FormatStyle`), SwiftUI (grouped `Form`, `Picker` with a `Menu` submenu for "More")

**Storage**: `~/.config/agenttacho/config.json` (new account keys `noLimit` and `valueAs`)

**Testing**: Swift Testing through `make test`; `make test-release` for the scripts

**Target Platform**: macOS menu bar app

**Project Type**: desktop app (UsageCore library + thin SwiftUI layer + DemoMode)

**Performance Goals**: no measurable change; the value is one pass over a section's per-model breakdown (a handful of models) when the dropdown draws

**Constraints**: read-only towards agent files (constitution III); no new reads or network; the value never counts as spend anywhere

**Scale/Scope**: about 10 UsageCore files, 3 SwiftUI files, the demo scenario and its tests, two docs

## Global Constraints

Every task inherits these (spec, constitution, AGENTS.md):

- macOS 14+, Swift 6 compiler; build and test only through `make test`, `make test-release`, `make app`, `make app-demo`.
- Logic in UsageCore (or DemoMode), test first; `Sources/AgentTacho` only lays out. Doc comments cite `spec 041 FR-0xx` or research `Rn`.
- Invented examples only in tests, demo and docs (`gateway-a/`, `open-model-7b`, `proj-alpha`); never real gateway prefixes, account names or paths. Real Claude model ids from the built-in price table are fine as Value as models.
- Exact UI strings from [contracts/ui-strings.md](contracts/ui-strings.md); no "spent" or "of" in the value line (FR-012).
- No em dash or en dash in any file.
- A No limit account is never a budget owner: `budgetOwners`, `budgetOwner(forAccount:)` and `accountBudgets` stay free of it (FR-009).

## Constitution Check

| Principle | Status |
|---|---|
| I. Issue first, specs recommended | Spec-driven (brainstorm 41, spec 041); maintainer's own request |
| II. Test-first, logic in UsageCore | Membership case, decoding and validation, switches, aggregation, value, presentation texts, Value as options, subtitle and demo coverage live in UsageCore or DemoMode with failing tests first; the new `NoLimitSection` view and editor fields only lay out (FR-015a) |
| III. Read-only, private by default | No new reads, no network, no credentials. README "Security and privacy" and the site's privacy section are unchanged |
| IV. One build entry point | `make test`, `make test-release`, `make app`, `make app-demo` only |
| V. Screenshots and website follow the UI | See "Screenshots and website": the demo gains a No limit section after the existing entries, no captured crop changes, a card candidate entry goes to the site |

Re-check after design: no violation.

## Screenshots and website

| | |
|---|---|
| Shots that change | none: `harnesses` is cropped from the shot budget's Details and `prices` from the import sheet's Changed section, and neither shows No limit usage (FR-005: it counts for no budget). The other crops of `scripts/screenshots/capture.sh` frame the Claude sections (`same-provider`, `glance`), the budget section (`budget`), the Harnesses tab, the bar (`menubar`, unchanged since a No limit account has no bar entry) and the Menu Bar tab's preview and level settings without the entry list (`menubar-settings`). The new demo section goes after the existing entries and before Unassigned, so every framed section keeps its position and band. Recapture once (one run, 14 files) per AGENTS.md step 4, after asking the maintainer |
| New shots | none in this pull request; card candidate "Free models, valued at a real price" added to the site's `docs/card-candidates.md` (shot idea: the No limit section with its value line; copy draft: "Track free gateway models without a made-up limit, and see what they would have cost at a real model's price.") |
| Demo scenario | add account `acc-free` ("Free models", Claude Code, session kind Other provider, condition "Model starts with `gateway-a/`", `noLimit` monthly, `valueAs` a built-in Claude model) with usage of `gateway-a/open-model-7b` this month, arranged after the existing entries; coverage: `ScenarioCoverage` reports No limit sections (headline, value line present, no bar value); `DefaultScenarioTests` checks `acc-free` shows a token headline and a value line, `barValues.count` stays 4, the band list grows to six stripes, and `tokenBasedAccountsUseSessionKinds` lists `acc-free` |
| Website copy | `src/data/features.ts` "Budgets" card: one clause that an account can also have no limit and show what its tokens would have cost (site pull request linked from the app pull request) |
| README image | unchanged (the README image is the menu bar shot, which does not change) |

## Project Structure

### Documentation (this feature)

```text
specs/041-no-limit-accounts/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1 to R9
├── data-model.md        # Phase 1: types, keys, validation, transitions
├── quickstart.md        # Phase 1: validation scenarios
├── contracts/
│   ├── config.md        # configuration keys and validation
│   └── ui-strings.md    # exact texts for dropdown, Settings, subtitle
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   ├── Configuration.swift          # TokenMembership.noLimit, NoLimitSettings, valueAs, decode/encode,
│   │                                # validate, dataRelevant, moving helpers (R1, R2, R5)
│   ├── Arrangement.swift            # isEntry, isShownInBar, settingShownInBar (R6)
│   └── AccountBudgetDescription.swift  # Kind.noLimit(period:) subtitle (FR-020)
├── Windows/WindowResolver.swift     # collectionWindow widens for a monthly No limit account (R3)
├── Snapshot/
│   ├── Aggregator.swift             # noLimitAccounts entries over the account's period window (R3)
│   ├── UsageSnapshot.swift          # NoLimitEntry, UsageSnapshot.noLimitAccounts
│   └── RefreshCoordinator.swift     # carry-over of noLimitAccounts on failure, log line
├── Pricing/
│   ├── ReferenceValue.swift         # NEW: value of a breakdown at a reference model's rates (R4)
│   └── ValueAsOptions.swift         # NEW: pop-up entries (None, primary, More, missing)
├── Dropdown/
│   ├── CompactFormat.swift          # tokens(_:) core formatter (R7)
│   ├── NoLimitPresentation.swift    # NEW: headline, period line, value line, tooltip, note, accessibility
│   └── SectionNote.swift            # valueAsMissing(model:) neutral note
Sources/DemoMode/ScenarioCoverage.swift   # No limit sections in CoverageReport
Sources/AgentTacho/
├── DropdownView.swift               # NoLimitSection, dispatch for .tokenBased with .noLimit
├── AccountSettingsView.swift        # "No limit" in TokenBasedEditor and NewAccountSheet, NoLimitFields
└── MenuBarSettingsTab.swift         # caption "No limit", no checkbox
Resources/demo/default.json          # acc-free
Tests/UsageCoreTests/                # new and extended suites per research R10
Tests/DemoModeTests/DefaultScenarioTests.swift
docs/configuration.md, docs/accounts-and-budgets.md
```

**Structure Decision**: the existing three-target layout (UsageCore, DemoMode, AgentTacho). Three new UsageCore files keep the value computation, the section texts and the pop-up entries testable on their own.

## Complexity Tracking

No violations.
