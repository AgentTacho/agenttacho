# Feature Specification: Pace Line Names the Plan

**Feature Branch**: `019-pace-line-names-plan`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Pace line names the plan (from brainstorm/19-pace-line-names-plan.md, for 0.4.2). The dropdown's adaptive-refresh pace line reads 'Plan limits next checked at 13:57 (no agent activity)' while Claude Code is clearly running, because only the Codex endpoint is slowed. Name the slowed plan or plans and the agent: 'Codex limits next checked at 13:57 (no Codex activity)'; both: 'Claude and Codex limits next checked at 13:45 (no agent activity)'; timer reasons keep today's wording."

This feature changes the wording of the pace line defined in `specs/016-adaptive-refresh/spec.md` FR-016. With adaptive refresh on, each **plan** (the Claude usage endpoint, used by Claude subscription accounts, and the Codex usage endpoint, used by Codex subscription accounts with live limits) has its own pace (spec 016 FR-003a, FR-004). A plan is **slowed for lack of activity** when it is in use (spec 016 FR-003a) and its interval is above the base because none of the agents whose sessions count for it was active (spec 016 FR-004: Claude Code and OpenCode for Claude, Codex and OpenCode for Codex). A **timer reason** (away, Low Power Mode, high temperature) slows the whole refresh and with it every plan (spec 016 FR-008, FR-009). When the line is shown, which reason wins, and which time it shows stay as spec 016 FR-016 defines them; only the words change.

## Clarifications

### Session 2026-10-16

- Q: Does the reason mention OpenCode, whose activity counts for both plans? → A: No. A plan slowed for lack of activity had neither its main agent nor OpenCode active, so "no Codex activity" or "no Claude Code activity" is true; naming the main agent keeps the line short.
- Q: Which plan names does the line use? → A: "Claude" and "Codex", not account names (user-chosen, possibly several per plan) nor platform names.
- Q: Does the dropdown's accessibility text change with the line? → A: Yes; it is the same string (FR-005).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The pace line says which plan is slowed (Priority: P1)

A user works with Claude Code while Codex has been idle for an hour. The dropdown says "Codex limits next checked at 13:57 (no Codex activity)", which matches what they see: their Claude rows keep updating every few minutes, and only the Codex limits wait. When both agents have been quiet, the line says "Claude and Codex limits next checked at 13:45 (no agent activity)". When the Mac is idle or in Low Power Mode, the line keeps today's wording, because then every plan waits.

**Why this priority**: The current line reads as wrong whenever only one plan is slowed, which is the common case for a user who mainly works with one agent.

**Independent Test**: Build a pace state where only Codex is slowed, only Claude is slowed, both are slowed, and a timer reason applies, and read the line for each.

**Acceptance Scenarios**:

1. **Given** adaptive refresh is on, only the Codex plan is slowed for lack of activity, and its next check is at 13:57, **When** the dropdown is shown, **Then** the line reads "Codex limits next checked at 13:57 (no Codex activity)".
2. **Given** only the Claude plan is slowed for lack of activity, next check at 13:45, **When** the dropdown is shown, **Then** the line reads "Claude limits next checked at 13:45 (no Claude Code activity)".
3. **Given** both plans are slowed for lack of activity, Claude due at 13:45 and Codex at 13:57, **When** the dropdown is shown, **Then** the line reads "Claude and Codex limits next checked at 13:45 (no agent activity)".
4. **Given** the Mac is idle (or in Low Power Mode, or under thermal pressure) and at least one plan is in use, **When** the dropdown is shown, **Then** the line reads as today, for example "Plan limits next checked at 13:57 (away)".
5. **Given** a timer reason applies and no plan is in use, **When** the dropdown is shown, **Then** the line reads as today, for example "Next refresh at 14:20 (Low Power Mode)".
6. **Given** every pace equals the base, **When** the dropdown is shown, **Then** no pace line is shown (unchanged).
7. **Given** the next check is on another day, **When** the line is shown, **Then** the time carries the abbreviated weekday as today ("Fri 09:05").

---

### Edge Cases

- Only one plan is in use (for example no Codex subscription account): only that plan can be slowed, so the line names it alone.
- A plan in use but at the base interval while the other is slowed: only the slowed plan is named.
- OpenCode activity counts for both plans; a plan slowed for lack of activity therefore had neither its main agent nor OpenCode active, and the line names the main agent only ("no Codex activity"), which is still true.
- The 12 or 24 hour time format and the weekday follow the user's settings as today.
- The line reflects activity as of each plan's last call: after new activity it keeps the old wording until the next refresh that sees it (at the latest one timer interval; opening the dropdown also refreshes when the last try is 60 s or more old, spec 016 FR-012).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When the pace line's reason is lack of agent activity and exactly one plan is slowed, the line MUST read "<Plan> limits next checked at <time> (no <Agent> activity)", where <Plan> is "Claude" or "Codex" and <Agent> is "Claude Code" for Claude and "Codex" for Codex.
- **FR-002**: When the reason is lack of agent activity and both plans are slowed, the line MUST read "Claude and Codex limits next checked at <time> (no agent activity)", with <time> the earlier of the two next checks (as spec 016 FR-016). The order is always Claude, then Codex, whichever is due first.
- **FR-003**: When a timer reason applies, the line MUST keep today's wording: "Plan limits next checked at <time> (<reason>)" when at least one plan is in use, "Next refresh at <time> (<reason>)" otherwise.
- **FR-004**: When the line is shown, which reason wins, and which time it shows MUST stay as spec 016 FR-016 defines them.
- **FR-005**: The line text MUST be produced by testable logic outside the user interface; the dropdown only renders it, and its accessibility text is the same string.
- **FR-006**: Time formatting (12 or 24 hours, weekday on another day) MUST stay as today.
- **FR-007**: The pace line MUST stay fully readable in every case FR-001 to FR-006 allow and MUST NOT be truncated. Since spec 025 (FR-025) it is the tooltip and accessibility value of the "Last refreshed" line instead of a line of its own, so its length no longer depends on the dropdown's width.

### Key Entities

- **Pace status**: the reason, the time and, new, which plans the line is about (the slowed plans for lack of activity; none named for a timer reason).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In tests covering one slowed plan (each of the two), both slowed, and each timer reason with and without a plan in use, the line text matches the scenarios in 100% of cases.
- **SC-002**: With Claude Code active and Codex idle, after the next scheduled refresh following new Claude Code activity the dropdown names only Codex as slowed, never "no agent activity" for both.

## Assumptions

- "Claude" and "Codex" are the plan names because account names are user-chosen and a plan can have several accounts; the agent names follow `Harness.displayName`.
- No change to the pace itself, the diagnostic log (which already names the endpoint) or configuration. No README change: README.md does not quote the line.
- This spec replaces the "no agent activity" wording of spec 016 FR-016 and row L2 of `specs/016-adaptive-refresh/contracts/refresh-pace.md`; the L2 test and the pace status equality checks change with it.
- Ships as 0.4.2 through the existing release process.
