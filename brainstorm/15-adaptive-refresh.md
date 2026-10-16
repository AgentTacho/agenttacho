# Brainstorm: Adaptive Refresh

**Date:** 2026-10-16
**Status:** active

## Problem Framing

AgentMeter refreshes on one fixed timer (`refreshIntervalSeconds`, default 300 s, minimum 60 s). Each scheduled refresh scans the local session logs and calls the undocumented, rate-limited usage endpoints of Anthropic and ChatGPT. Launch, wake, the manual refresh, settings edits and the rate-limit and quick retries add further refreshes; opening the dropdown does not, so what the user sees can be up to one interval old.

The fixed interval is a compromise that fits neither case: it is too slow when the user looks at the dropdown, and wasteful when nobody looks, no agent is running, or the Mac is saving power. The goal is both: current numbers when the user looks, fewer endpoint calls and less battery use when they don't (idea inbox item `adaptive-refresh`, from the CodexBar comparison; CodexBar's default refresh mode ranges from 2 to 30 minutes based on similar signals).

## Approaches Considered

### A: One adaptive timer
All signals drive one interval for the whole refresh (local scan and endpoint calls), from the base interval up to 30 minutes.
- Pros: simplest; saves the most battery.
- Cons: when an agent starts again after a quiet period, its spend, budget bars and threshold notifications can appear up to 30 minutes late (unless the user opens the dropdown); the activity signal itself is only sampled at the stretched pace.

### B: Split cadence
The local scan keeps the base interval (no network, incremental). Only the usage endpoint calls stretch while no agent is active. Low Power Mode, thermal pressure and user idle stretch the whole timer.
- Pros: local spend and threshold notifications stay prompt; the activity signal stays accurate because the scan keeps running; fits into `EndpointPolicy` as one more reason to reuse the last network result.
- Cons: two notions of pace (timer and endpoint) to explain and test.

### C: Event-driven
Watch the log directories with FSEvents and refresh soon after agents write, plus a slow heartbeat up to 30 minutes.
- Pros: the fastest response to agent activity.
- Cons: a new mechanism; OpenCode's SQLite WAL churn and Codex/Claude append patterns need debouncing; more to test and get wrong.

### Choices made along the way
- **Purpose**: balanced, fresher when looking and fewer calls when not. Neither goal alone.
- **Relation to the interval setting**: the configured interval stays as the base (fastest regular pace); an "Adapt refresh" toggle, on by default, restores today's fixed timer. A Fixed/Adaptive mode picker with hidden interval, and an always-adaptive design without a toggle, were ruled out.
- **Signals**: all four are in scope: dropdown open, agent activity, power state (Low Power Mode, thermal pressure), user idle.
- **Upper bound**: 30 minutes, regardless of the base interval. A multiple of the base and 15 minutes were ruled out.
- **Battery power alone** is not a signal; only Low Power Mode is.

## Decision

Approach B, split cadence: the local scan runs at the base interval; usage endpoint calls stretch up to 30 minutes while the scans find no new agent records; Low Power Mode, serious or critical thermal pressure and user idle stretch the whole timer up to 30 minutes; opening the dropdown or returning from idle refreshes when the values are older than about a minute.

## Key Requirements

- **Toggle**: "Adapt refresh" in the General tab next to the refresh interval, on by default. Off means exactly today's behavior (fixed timer, endpoint call on every scheduled refresh).
- **Base and bound**: the configured interval is the fastest regular pace; no adaptive pace is ever slower than 30 minutes. A base interval above 30 minutes is never shortened by adaptation.
- **Agent activity (endpoint pace)**: while consecutive scans find no new local usage records from any harness, the time between endpoint calls grows step by step up to 30 minutes. One new record returns the endpoint pace to the base interval at that refresh.
- **Power and idle (whole timer)**: Low Power Mode, thermal state serious or critical, and user idle (no keyboard or mouse input for a while, or screen locked) stretch the whole refresh timer up to 30 minutes. When the condition ends, the base pace returns.
- **Dropdown open**: opening the dropdown triggers a refresh when the last endpoint result is older than about 60 s, within the existing `EndpointPolicy` minimum spacing. It never bypasses a rate-limit block.
- **Return from idle**: one refresh when the user returns, like wake today.
- **No change to retries**: rate-limit backoff, `Retry-After`, the single rate-limit retry, the 30 s quick retry (spec 010) and the wake refresh keep their timing. Adaptation only ever adds waiting, never shortens a backoff.
- **Visibility**: one quiet line in the dropdown with the current pace and its reason when it differs from the base (for example "Next refresh in 25 min (idle)"); no indicator in the menu bar. The diagnostic log records each pace change with its reason.
- **Notifications**: threshold notifications follow the refreshes that run; no extra refreshes for them.
- **Docs**: the README's Configuration section and the "Security and privacy" statement ("a single read-only request per refresh (every 5 minutes by default)") describe the adaptive pace and its 30-minute bound, in the same pull request.
- **Logic in UsageCore**: the pace decision (signals in, next scheduled time and endpoint fetch-or-reuse out) is a pure, tested value type like `EndpointPolicy`; the app target only reads the system signals and runs the timer.

## Out of Scope

- File system watching (FSEvents) of the log directories
- Per-account or per-provider intervals
- A pace indicator in the menu bar
- Settings beyond the single toggle (no configurable upper bound or idle threshold)
- Stretching on battery power without Low Power Mode

## Open Questions

- Growth of the endpoint interval while no agent is active: doubling per quiet refresh, fixed steps, or a jump after a quiet period (for example after 15 minutes without records)
- Idle detection: idle threshold (for example 5 minutes without input), whether the screen lock and screensaver count, and how detection works without new permissions
- Whether the Codex usage endpoint and the Claude usage endpoint share one adaptive endpoint pace or each follows its own harness's activity (Claude activity says nothing about Codex limits)
- Whether usage on other devices (claude.ai chat, another Mac, Codex cloud) needs any mitigation beyond the 30-minute bound and the dropdown-open refresh
- How the dropdown-open refresh interacts with a pending scheduled tick (reset the timer or keep it) and with the MenuBarExtra window resizing on new data
- Wording and placement of the dropdown pace line, and whether it also shows at the base pace
- Config key name for the toggle and how older versions treat the unknown key
- How the "next refresh" time is presented while a rate-limit block is longer than the adaptive pace
