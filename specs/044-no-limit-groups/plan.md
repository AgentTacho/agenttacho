# Implementation Plan: Budget Groups Without an Amount

**Branch**: `044-no-limit-groups` | **Date**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/044-no-limit-groups/spec.md`

## Summary

A budget group's amount becomes optional. As spec 043 did for accounts, a group without an amount is never a budget owner, so the menu bar, thresholds, pace, burn rate and run-out skip it and its member shares without new checks downstream (research R1). Its members still count in the group's period (R2). The aggregator builds one `NoLimitEntry` per such group from the members' combined records (R3), and spec 043's generic `NoLimitPresentation` renders it through a new group wrapper (R4). Groups gain `valueAs` and `show`; with an amount, `show` only changes the headline. Member lines move from the SwiftUI view into a tested `MemberLineText` (R5). Settings get a core `GroupBudgetForm` mirroring `OwnBudgetForm`, plus Groups tab, Menu Bar tab and member toggle rules (R6). Lifecycle transitions give members an own budget without an amount (R7). The configuration accepts an absent or `null` group amount and the two new keys (R8), the log gets a group line (R9), and the demo gains an "Open models" group (R10).

## Technical Context

**Language/Version**: Swift 5.10 tools, Swift 6 compiler, macOS 14+

**Primary Dependencies**: Foundation (`Decimal`, `FormatStyle`), SwiftUI (grouped `Form`, `Picker`, `.help`, `.disabled`)

**Storage**: `~/.config/agenttacho/config.json` (group `budgetUSD` optional, new group keys `valueAs`, `show`)

**Testing**: Swift Testing through `make test`; `make test-release` for the scripts

**Target Platform**: macOS menu bar app

**Project Type**: desktop app (UsageCore library + thin SwiftUI layer + DemoMode)

**Performance Goals**: no measurable change; one more `splitByPrice` pass per group without an amount

**Constraints**: read-only towards agent files (constitution III); no new reads or network; a Price tokens as value never counts as spend; member lines and Money headlines never show "≈"

**Scale/Scope**: about 10 UsageCore files, 3 SwiftUI files, the demo scenario and its tests, three docs

## Global Constraints

Every task inherits these (spec, constitution, AGENTS.md):

- macOS 14+, Swift 6 compiler; build and test only through `make test`, `make test-release`, `make app`, `make app-demo`.
- Logic in UsageCore (or DemoMode), test first; `Sources/AgentTacho` only lays out. Doc comments cite `spec 044 FR-0xx` or research `Rn`.
- Reuse spec 043's types and strings (`NoLimitEntry`, `NoLimitPresentation`, `HeadlineText`, `ReferenceValue`, `DropdownShow`, `OwnBudgetForm` strings); do not copy their rules (FR-015).
- Invented examples only in tests, demo and docs (`gateway-a/`, `gateway-b/`, `open-model-12b`); real Claude model ids from the built-in price table are fine.
- Exact UI strings from [contracts/ui-strings.md](contracts/ui-strings.md); configuration per [contracts/config.md](contracts/config.md).
- No em dash or en dash in any file (the typographic minus U+2212 stays allowed).
- A group without an amount is never a budget owner: `budgetOwners`, `budgetOwner(forAccount:)`, `GroupEntry` and `snapshot.groups` stay free of it (FR-003).
- A group with an amount behaves exactly as today except for its headline under a stored Show setting (review-spec decision).

## Constitution Check

| Principle | Status |
|---|---|
| I. Issue first, specs recommended | Spec-driven (brainstorm 44, spec 044); maintainer's own request |
| II. Test-first, logic in UsageCore | Config decoding and encoding, owners and counting periods, aggregation, `NoLimitPresentation.make(group:)`, `MemberLineText`, `GroupBudgetForm`, `GroupListSubtitle`, `Arrangement` rules, `BarLayout` gating, lifecycle, log line and demo coverage live in UsageCore or DemoMode with failing tests first; views only lay out (FR-015) |
| III. Read-only, private by default | No new reads, no network, no credentials. README "Security and privacy" and the site's privacy section are unchanged |
| IV. One build entry point | `make test`, `make test-release`, `make app`, `make app-demo` only |
| V. Screenshots and website follow the UI | See "Screenshots and website" |

Re-check after design: no violation.

## Screenshots and website

| | |
|---|---|
| Shots that change | none in content: the new "Open models" section goes after `acc-api` and before Unassigned, so every framed section of `glance`, `same-provider`, `budget`, `tickets` and `no-limit` stays in place; `menubar` is unchanged (the group has no bar entry). Recapture once (one run, 18 files) per AGENTS.md step 4, after asking the maintainer, and check that the crops are unchanged |
| New shots | none; no new card. The feature extends the budget card's statement; a card candidate entry is not warranted |
| Demo scenario | new group `grp-open` "Open models" (`solid:gift`, monthly, no amount) with `acc-open-claude` (Claude Code, Other provider, `~/.claude-open`, model starts with `gateway-b/`) and `acc-open-codex` (Codex, API key, `~/.codex-open`, same condition), records of `gateway-b/open-model-12b` this month priced by a demo override; coverage: `ScenarioCoverage.noLimitGroupSections` (measure, headline, member lines); `DefaultScenarioTests` checks the Money headline, two member lines without "%", `barValues.count` unchanged, one more band stripe |
| Website copy | `src/data/features.ts` budget card: groups can share a budget or just add up spend without a limit (site pull request linked from the app pull request) |
| README image | unchanged |

## Project Structure

### Documentation (this feature)

```text
specs/044-no-limit-groups/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1 to R10
├── data-model.md        # Phase 1: fields, accessors, transitions
├── quickstart.md        # Phase 1: validation scenarios
├── contracts/
│   ├── config.md        # group keys budgetUSD (optional), valueAs, show
│   └── ui-strings.md    # member lines, Settings strings, log line
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   ├── Configuration.swift          # BudgetGroup optional amount, valueAs, show; decode/encode/validate;
│   │                                # budgetOwners, noLimitGroups, countingPeriod, movingAccountToOwnBudget,
│   │                                # dataRelevant masks (R1, R2, R7, R8)
│   ├── DropdownShow.swift           # doc comment widened to groups
│   ├── GroupBudgetForm.swift        # NEW: group editor draft (R6)
│   ├── GroupLifecycle.swift         # removingGroup(.ownBudgets) without amount (R7)
│   ├── AccountBudgetDescription.swift # GroupListSubtitle no limit + VoiceOver, member subtitle (R6)
│   ├── (Configuration.swift)        # memberShareToggle(forAccount:) for the account editor (R6)
│   └── Arrangement.swift            # offersShownInBar, shownInBarHelp, budgetCaption for groups (R6)
├── Snapshot/
│   ├── Aggregator.swift             # NoLimitEntry per group without amount (R3)
│   ├── UsageSnapshot.swift          # noLimitGroups
│   └── RefreshCoordinator.swift     # no limit group log line (R9)
├── Bar/BarLayout.swift              # skip groups without amount and their members (R6)
├── Dropdown/
│   ├── NoLimitPresentation.swift    # make(group:) wrapper (R4)
│   └── MemberLineText.swift         # NEW: member line text, tooltip, accessibility (R5)
Sources/DemoMode/ScenarioCoverage.swift   # noLimitGroupSections
Sources/AgentTacho/
├── DropdownView.swift               # group no-limit section, member lines via MemberLineText, show on budget headline
├── AccountSettingsView.swift        # GroupEditor via GroupBudgetForm, member toggle disabled, remove sheet note
└── MenuBarSettingsTab.swift         # unchanged layout, new core rules
Resources/demo/default.json          # grp-open, acc-open-claude, acc-open-codex, price override, records
Tests/UsageCoreTests/, Tests/DemoModeTests/
docs/configuration.md, docs/accounts-and-budgets.md, README.md
```

**Structure Decision**: the existing three-target layout. Two new UsageCore files (`GroupBudgetForm`, `MemberLineText`) keep the editor draft and member line rules testable on their own; everything else extends spec 043's types.

## Complexity Tracking

No violations.
