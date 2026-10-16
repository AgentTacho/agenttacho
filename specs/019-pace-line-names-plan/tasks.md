# Tasks: Pace Line Names the Plan

**Input**: Design documents from `specs/019-pace-line-names-plan/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Required (AGENTS.md, test first). `make test` only.

## Conventions for every task

- Doc comments cite the spec requirements (for example `spec 019 FR-001`).
- No em dash or en dash characters anywhere.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.

## Interfaces (binding)

```swift
// Sources/UsageCore/Snapshot/AdaptivePace.swift
extension PacedEndpoint {
    public var planName: String   // "Claude", "Codex"
    public var agentName: String  // Harness.claudeCode.displayName, Harness.codex.displayName
}

// Sources/UsageCore/Snapshot/RefreshPaceStatus.swift
public struct RefreshPaceStatus: Equatable, Sendable {
    public let reason: PaceReason
    public let nextAt: Date
    public let kind: Kind
    public let plans: [PacedEndpoint]   // spec 019: slowed plans, Claude then Codex; [] for timer reasons
    public init(reason: PaceReason, nextAt: Date, kind: Kind, plans: [PacedEndpoint] = [])
}
```

---

## Phase 1: User Story 1 - The pace line says which plan is slowed (Priority: P1)

- [X] T001 Run `make test` once to confirm the baseline. Then write failing tests, using the file's `calendar` (Gregorian, UTC) and `locale` (`en_GB`) helpers and `at(_:_:)`; add `spec 019 FR-001 to FR-006` to the `RefreshPaceStatusTests.swift` header comment:
  - in `Tests/UsageCoreTests/RefreshPaceStatusTests.swift`, update `l2NoAgentActivity`: `RefreshPaceStatus(reason: .noAgentActivity, nextAt: at(14, 35), kind: .planLimits, plans: [.claude])` and text "Claude limits next checked at 14:35 (no Claude Code activity)";
  - add a helper `stretched(_ quiet: PacedEndpoint)` mirroring `stretchedClaude()` (the quiet endpoint stretched, the other in use at the base); Codex quiet gives `plans == [.codex]`, `nextAt == at(14, 35)` and "Codex limits next checked at 14:35 (no Codex activity)";
  - both stretched with Codex due first: base 300, scheduled ticks at 14:00, 14:05, 14:10, 14:15 and 14:20; Codex quiet throughout (due 14:35); Claude sees activity at 14:04 and is quiet afterwards (calls at 14:05, 14:10, 14:20). Expect `dueAt(.claude) == at(14, 40)`, `dueAt(.codex) == at(14, 35)`, and `status(now: at(14, 21))` with `plans == [.claude, .codex]`, `nextAt == at(14, 35)` and "Claude and Codex limits next checked at 14:35 (no agent activity)";
  - plan not in use: `AdaptivePace(base: 300, inUse: [.claude])` with `.codex` stretched through quiet scheduled `recordCall`s; with Claude at the base `status` is nil; with Claude also stretched `plans == [.claude]`;
  - timer reasons: `plans == []` and today's texts (L3 and the other timer tests stay unchanged);
  - another day: both plans with `nextAt` on the next day give "Claude and Codex limits next checked at Fri 09:05 (no agent activity)" (weekday as the existing other-day test);
  - 12 hour (`Locale(identifier: "en_US")`): the both-plans text equals "Claude and Codex limits next checked at Fri 9:05\u{202F}AM (no agent activity)" (macOS puts a narrow no-break space before AM);
  - `PacedEndpoint.claude.planName == "Claude"`, `.agentName == "Claude Code"`; `.codex.planName == "Codex"`, `.agentName == "Codex"`;
  - in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`, `paceStatusNamesTheNextPlanLimitCheck` (near line 2518) expects `plans: [.claude]`.
- [X] T002 Implement per the Interfaces block: `planName` and `agentName` on `PacedEndpoint`; `plans` on `RefreshPaceStatus` and the new wording in `text(now:calendar:locale:)`; `AdaptivePace.status(now:)` passes `PacedEndpoint.allCases.filter { stretched.contains($0) }` for "no agent activity". Update the doc comments, including the example line in `RefreshPaceStatus.swift` (around line 24) that still quotes "Plan limits next checked at 14:35 (no agent activity)" (spec 019 FR-001 to FR-006). Run `make test`.
- [X] T003 In `Sources/AgentMeter/DropdownView.swift`, replace `.lineLimit(1)` on the pace line with `.fixedSize(horizontal: false, vertical: true)` and update its comment (spec 019 FR-007). In `specs/016-adaptive-refresh/contracts/refresh-pace.md`, change row L2 to "Claude limits next checked at 14:35 (no Claude Code activity)" and add "(wording changed by spec 019)"; add the same pointer after spec 016 FR-016 in `specs/016-adaptive-refresh/spec.md`. Scan the changed files for em and en dash characters (U+2014, U+2013). Run `make test` and `make app`.

**Checkpoint**: commit `fix(refresh): name the slowed plan in the pace line`.

## Dependencies

T001, T002, T003 in order.
