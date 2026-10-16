# Data Model: Pace Line Names the Plan

## RefreshPaceStatus (changed)

| Field | Type | Meaning |
|---|---|---|
| `reason` | PaceReason | unchanged |
| `nextAt` | Date | unchanged |
| `kind` | Kind | unchanged |
| `plans` | [PacedEndpoint] | NEW: the slowed plans for `.noAgentActivity`, in the order Claude, Codex; empty for timer reasons |

## PacedEndpoint (added names)

| Case | `planName` | `agentName` |
|---|---|---|
| `.claude` | Claude | Claude Code |
| `.codex` | Codex | Codex |

## Line texts (en_GB, 24 hour)

| Case | Text |
|---|---|
| Codex slowed | Codex limits next checked at 13:57 (no Codex activity) |
| Claude slowed | Claude limits next checked at 13:45 (no Claude Code activity) |
| Both slowed | Claude and Codex limits next checked at 13:45 (no agent activity) |
| Timer reason, plan in use | Plan limits next checked at 13:57 (away) |
| Timer reason, no plan | Next refresh at 14:20 (Low Power Mode) |
