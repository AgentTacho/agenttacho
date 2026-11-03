# Implementation Plan: Unified Token Accounts

**Branch**: `043-unified-token-accounts` | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/043-unified-token-accounts/spec.md`

## Summary

The user sees one kind of token account: an own budget whose amount is optional, or a group. Internally `TokenMembership.noLimit` stays and now means "own budget without an amount"; it gains the thresholds and shown-in-bar setting so they survive while the amount is empty (research R1). The configuration writes such an account as `budget` without `budgetUSD` and still reads spec 041's `noLimit` form (R2). Every budget path keeps its non-optional amount, so the menu bar, thresholds, pace and burn rate exclude amount-less accounts as they do today.

A new per-account `show` setting (`DropdownShow`: Automatic, Percent, Tokens, Money) picks the dropdown headline through one pure resolver (R3). The No limit snapshot entry becomes priced, so an account without an amount can show real spend and cost Details (R4); Value as now values only unpriced models (R5). A new `HeadlineText` produces every headline string, tooltip and accessibility text for both the budget section and the amount-less section (R6). Settings drops "No limit" from the budget picker and binds the own budget editor to a core `OwnBudgetForm` whose amount flips the membership case (R7).

## Technical Context

**Language/Version**: Swift 5.10 tools, Swift 6 compiler, macOS 14+

**Primary Dependencies**: Foundation (`Decimal`, `FormatStyle`), SwiftUI (grouped `Form`, `Picker`, `.help`, `.disabled`)

**Storage**: `~/.config/agenttacho/config.json` (`budget` without `budgetUSD`, new account key `show`; `noLimit` read only)

**Testing**: Swift Testing through `make test`; `make test-release` for the scripts

**Target Platform**: macOS menu bar app

**Project Type**: desktop app (UsageCore library + thin SwiftUI layer + DemoMode)

**Performance Goals**: no measurable change; the priced breakdown is the one own budgets already build

**Constraints**: read-only towards agent files (constitution III); no new reads or network; a Value as amount never counts as spend; a Money headline never shows "≈"

**Scale/Scope**: about 9 UsageCore files, 3 SwiftUI files, the demo scenario and its tests, two docs

## Global Constraints

Every task inherits these (spec, constitution, AGENTS.md):

- macOS 14+, Swift 6 compiler; build and test only through `make test`, `make test-release`, `make app`, `make app-demo`.
- Logic in UsageCore (or DemoMode), test first; `Sources/AgentTacho` only lays out. Doc comments cite `spec 043 FR-0xx` or research `Rn`.
- Invented examples only in tests, demo and docs (`gateway-a/`, `open-model-7b`, `proj-alpha`); real Claude model ids from the built-in price table are fine.
- Exact UI strings from [contracts/ui-strings.md](contracts/ui-strings.md); configuration per [contracts/config.md](contracts/config.md).
- No em dash or en dash in any file (the typographic minus U+2212 of "−$12" is allowed, as "−15%" today).
- An account without an amount is never a budget owner: `budgetOwners`, `budgetOwner(forAccount:)` and `accountBudgets` stay free of it (FR-008).
- A group's budget keeps requiring `budgetUSD` (FR-002).

## Constitution Check

| Principle | Status |
|---|---|
| I. Issue first, specs recommended | Spec-driven (brainstorm 43, spec 043); maintainer's own request |
| II. Test-first, logic in UsageCore | Decoding and encoding, `OwnBudgetForm`, `DropdownShow.resolve`, priced No limit entry, reference value on unpriced models, `HeadlineText`, `NoLimitPresentation`, Menu Bar tab rules and demo coverage live in UsageCore or DemoMode with failing tests first; views only lay out (FR-016) |
| III. Read-only, private by default | No new reads, no network, no credentials. README "Security and privacy" and the site's privacy section are unchanged |
| IV. One build entry point | `make test`, `make test-release`, `make app`, `make app-demo` only |
| V. Screenshots and website follow the UI | See "Screenshots and website" |

Re-check after design: no violation.

## Screenshots and website

| | |
|---|---|
| Shots that change | none in content: `no-limit` keeps cropping `acc-free` (first account without an amount, unchanged look: Tokens headline and value line); `glance`, `same-provider`, `budget`, `tickets` frame sections before it; `menubar` is unchanged (neither amount-less account is in the bar); `menubar-settings` shows the preview and level settings without the entry list. The new `acc-api` section goes after `acc-free` and before Unassigned, so no framed section moves. Recapture once (one run, 18 files) per AGENTS.md step 4, after asking the maintainer, and review that the crops are unchanged |
| New shots | none; no new card (the feature reshapes spec 041's card "Free models, valued at a real price", whose content stays true) |
| Demo scenario | `acc-free` written in the new form (`budget` without `budgetUSD`, `valueAs` kept); new `acc-api` ("API key", `solid:key`, Claude Code, Other provider, `~/.claude-api`, monthly, no amount) with records of a built-in priced Claude model this month, arranged after `acc-free`; coverage: `ScenarioCoverage` reports each amount-less section's resolved measure; `DefaultScenarioTests` checks `acc-free` Tokens headline plus value line, `acc-api` Money headline, `barValues.count` unchanged, `shotNoLimitAccountId == "acc-free"`, band list grows by one stripe, `tokenBasedAccountsUseSessionKinds` lists `acc-api` |
| Website copy | `src/data/features.ts` budget card: one clause that the amount is optional, so an account can track real spend or tokens without a limit (site pull request linked from the app pull request) |
| README image | unchanged |

## Project Structure

### Documentation (this feature)

```text
specs/043-unified-token-accounts/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1 to R9
├── data-model.md        # Phase 1: types, resolver table, transitions
├── quickstart.md        # Phase 1: validation scenarios
├── contracts/
│   ├── config.md        # configuration form, legacy form, show key
│   └── ui-strings.md    # headline texts, second line, Settings strings
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   ├── Configuration.swift          # NoLimitSettings thresholds/shownInBar, TokenBasedSettings.show,
│   │                                # decode/encode (budget without budgetUSD, legacy noLimit, show),
│   │                                # dataRelevant masks show, remove movingAccountToNoLimit (R1, R2, R3)
│   ├── DropdownShow.swift           # NEW: DropdownShow, HeadlineMeasure, resolve (R3)
│   ├── OwnBudgetForm.swift          # NEW: Settings draft, amount flips the case (R7)
│   └── Arrangement.swift            # Menu Bar tab: disabled checkbox rule stays (R8)
├── Snapshot/
│   ├── Aggregator.swift             # priced breakdown for No limit entries (R4)
│   └── UsageSnapshot.swift          # NoLimitEntry spentUSD, hasPricedUsage, unpricedModels
├── Pricing/ReferenceValue.swift     # unpriced models only (R5)
├── Dropdown/
│   ├── HeadlineText.swift           # NEW: headline, tooltip, accessibility per measure (R6)
│   └── NoLimitPresentation.swift    # measure, Money line, notes, cost Details flag, value tooltip (R5, R6)
Sources/DemoMode/ScenarioCoverage.swift   # resolved measure per amount-less section
Sources/AgentTacho/
├── DropdownView.swift               # BudgetSection header via HeadlineText; NoLimitSection Details with cost
├── AccountSettingsView.swift        # picker without No limit, OwnBudgetForm editor, Dropdown shows pop-up
└── MenuBarSettingsTab.swift         # disabled checkbox with help
Resources/demo/default.json          # acc-free new form, acc-api
Tests/UsageCoreTests/, Tests/DemoModeTests/
docs/configuration.md, docs/accounts-and-budgets.md
```

**Structure Decision**: the existing three-target layout (UsageCore, DemoMode, AgentTacho). Three new UsageCore files keep the resolver, the editor draft and the headline texts testable on their own.

## Complexity Tracking

No violations.
