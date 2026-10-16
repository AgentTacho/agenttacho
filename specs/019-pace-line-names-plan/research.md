# Research: Pace Line Names the Plan

## R1: Where the plans come from (FR-001, FR-002, FR-004)

- **Decision**: `RefreshPaceStatus` gets `public let plans: [PacedEndpoint]` with an init default of `[]`. `AdaptivePace.status(now:)` passes `PacedEndpoint.allCases.filter { stretched.contains($0) }` for the "no agent activity" case (fixed order Claude, Codex) and `[]` for timer reasons. The time logic is untouched.
- **Rationale**: `status(now:)` already computes `stretched` (in use and above the base), so no new state; the default keeps every timer-reason test and call site unchanged.
- **Alternatives considered**: a new `PaceReason` case per plan (multiplies reasons and their ranking).

## R2: Wording (FR-001 to FR-003, FR-005, FR-006)

- **Decision**: `PacedEndpoint.planName` ("Claude", "Codex") and `PacedEndpoint.agentName` (`Harness.claudeCode.displayName`, `Harness.codex.displayName`). In `RefreshPaceStatus.text(now:calendar:locale:)`, for `.planLimits` with reason `.noAgentActivity` and non-empty `plans`: subject is the plan names joined with " and ", reason is "no \(agentName) activity" for one plan and "no agent activity" for two. Otherwise today's strings. The time formatting code is shared and unchanged.
- **Rationale**: one place builds every variant; the dropdown and its accessibility read the same `Text`.

## R3: Width (FR-007)

- **Decision**: in `DropdownView`, replace `.lineLimit(1)` on the pace line with `.fixedSize(horizontal: false, vertical: true)` so it wraps inside the 360 pt dropdown.
- **Rationale**: the longest case ("Claude and Codex limits next checked at Fri 9:05 AM (no agent activity)") measures about 346 pt at the caption font against 336 pt available; wrapping keeps the reason visible.
- **Alternatives considered**: shorter wording (loses "limits"), accepting truncation (loses the reason).
