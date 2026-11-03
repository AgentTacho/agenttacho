# Brainstorm: Pace Line Names the Plan

**Date:** 2026-10-16
**Status:** active

## Problem Framing

With adaptive refresh on (spec 016), the dropdown shows a pace line such as "Plan limits next checked at 13:57 (no agent activity)" when a usage endpoint is slowed. The pace is kept per endpoint: on 2026-10-16 only the Codex endpoint was stretched to 20 minutes, because no Codex session file had changed for over an hour, while the Claude endpoint stayed at the base interval because Claude Code was busy. The line does not say which plan it means, so a user watching Claude Code work reads it as plainly wrong. Planned as 0.4.2.

## Approaches Considered

### A: Name every slowed plan (chosen)
- Pros: always true, one line, short; tells the user which agent's quiet time caused it.
- Cons: the two-plan case falls back to a generic reason.

### B: Name only the plan whose check comes first
- Pros: shortest.
- Cons: hides that the other plan is slowed too.

### C: One line per slowed plan
- Pros: most precise.
- Cons: two lines in a footer that spec 016 kept to one; more visual weight.

## Decision

Approach A:

- One plan slowed for lack of activity: "Codex limits next checked at 13:57 (no Codex activity)" or "Claude limits next checked at 13:45 (no Claude Code activity)".
- Both plans slowed: "Claude and Codex limits next checked at <earliest of the two> (no agent activity)".
- Timer reasons (away, Low Power Mode, high temperature) slow every plan, so they keep today's wording: "Plan limits next checked at 13:57 (away)", or "Next refresh at 13:57 (Low Power Mode)" when no plan is in use.
- When the line appears, which reason wins and which time it shows stay as in spec 016 FR-016.

## Key Requirements

- The pace line names the slowed plan or plans when the reason is lack of agent activity.
- The reason names the agent whose activity counts for that plan (Codex for the Codex plan, Claude Code for the Claude plan).
- Wording is built and tested in `UsageCore` (`RefreshPaceStatus`), the app only renders it.
- The diagnostic log already names the endpoint (`pace: codex interval 1200 s`); no change there.

## Open Questions

- OpenCode activity counts for both plans (spec 016 FR-004): should the reason say "no Codex or OpenCode activity", or stay with the main agent's name?
- Plan names in the line: "Claude"/"Codex", or the platform names used elsewhere ("Claude subscription", "ChatGPT")?
- Should the dropdown's accessibility text change with it (it reads the same string today)?
