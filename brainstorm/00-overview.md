# Brainstorm Overview

Last updated: 2026-10-14

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 01 | 2026-10-13 | llm-usage-menubar | active | - | - |
| 02 | 2026-10-14 | monthly-budget-period | active | - | - |

## Open Threads
- Which session log markers reliably distinguish Vertex from direct Anthropic traffic, and what happens when none match (from #01)
- Which Anthropic endpoint exposes subscription 5-hour/7-day utilization, how it authenticates with local Claude Code OAuth credentials, and its polling limits (from #01)
- Session log discovery across several Claude Code config directories: automatic, configured, or both (from #01)
- Budget group reset handling when the aligned subscription has no reset timestamp yet (from #01)
- Whether the price table needs per-provider variants for cache-token categories on Vertex (from #01)
- Which window (7-day, 5-hour, or the higher) drives the bar percent for a subscription (from #01)
- Notification semantics: once per threshold per window, or re-notify after a quiet period (from #01)
- Threshold notification state when a group's period is switched mid-window: reset immediately or baseline like a rollover (from #02)
- Session-log coverage for a full monthly window (up to 31 days back, first launch mid-month) (from #02)
- Dropdown phrasing of a monthly group's reset date (from #02)
- Whether the configuration writer emits the new budgetUSD key on load or only on the next edit (from #02)

## Parked Ideas
- None
