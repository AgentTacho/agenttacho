# Brainstorm Overview

Last updated: 2026-10-16

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 01 | 2026-10-13 | agentmeter | active | - | - |
| 02 | 2026-10-14 | monthly-budget-period | active | - | - |
| 03 | 2026-10-14 | icon-labels-standalone-budgets | active | - | - |
| 04 | 2026-10-14 | macos-distribution | active | - | - |
| 05 | 2026-10-14 | multi-harness-usage | active | - | - |
| 06 | 2026-10-14 | codex-plan-limits | active | - | - |
| 07 | 2026-10-15 | menu-bar-arrangement | active | - | - |
| 08 | 2026-10-15 | explicit-group-management | active | - | - |
| 09 | 2026-10-15 | keep-last-good-values | active | - | - |
| 10 | 2026-10-15 | pace-forecast | active | - | - |
| 11 | 2026-10-16 | credential-notifications | active | - | - |
| 12 | 2026-10-16 | colored-bar-levels | active | - | - |

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
- Whether the bar should visually separate duplicate icons or rely on ordering plus the dropdown (from #03)
- Config format for an account's own budget: nested budget object or flat fields (from #03)
- Threshold state when an account moves between its own budget and a group (from #03)
- Whether the Unassigned entry needs an icon now that labels are icon-only (from #03)
- Self-signed certificate name, creation steps, and sharing it with a second machine or CI (from #04)
- Whether the cask clears the quarantine attribute in postflight or only prints caveats (from #04)
- notarytool keychain profile and how the release detects that notarization is possible (from #04)
- Static DMG background per signing tier or rendered at build time with the version (from #04)
- Release behavior when the tag already has a release or the tap has uncommitted changes (from #04)
- Whether a universal (arm64 plus x86_64) build is worth adding later (from #04)
- How to tell a Codex session's auth mode (ChatGPT login vs API key) from the log alone (from #05)
- Mapping of OpenCode providerID values to AgentMeter providers, and handling of custom providers (from #05)
- Mapping and pricing of Codex cached input and reasoning tokens (from #05)
- Safe reading of OpenCode's SQLite database while OpenCode writes to it (from #05)
- Whether the per-account harness field stays, becomes a list, or goes away (from #05)
- Part B: stability of the Codex usage endpoint and how it combines with log rate_limits snapshots (from #05)
- Which Codex usage endpoint path to use (/wham/usage vs /api/codex/usage) and which headers it needs (from #06)
- Detecting and logging a changed or failing endpoint response without blocking the snapshot fallback (from #06)
- Whether the newest observation or the endpoint wins when both sources have values (from #06)
- Handling of the premium bucket (limit_id other than codex) if it ever carries windows (from #06)
- Refresh cadence for the Codex usage endpoint (from #06)
- Whether a reached limit gets its own visual state beyond 100% (from #06)
- Settling review finding M-11 (planAccounts naming) in the part B spec (from #06)
- Initial order for existing configurations: current bar order or Settings list order (from #07)
- Where an account lands when it gets its own budget or leaves a group (from #07)
- Whether the "Show in bar" toggles stay in the account and group editors or move to the new tab only (from #07)
- Config format for the order: separate ordered id list or array order plus a position field (from #07)
- Whether the Accounts and Groups lists in Settings should also follow the new order (from #07)
- Name of the tab ("Menu Bar", "Layout", "Arrangement") (from #07)
- Default budget amount for a group added from the Groups tab (from #08)
- Whether the remove dialog offers only groups with the same period as destination (from #08)
- Wording of the empty-group note and the remove dialog (from #08)
- Migration note for older versions that reject empty groups (from #08)
- Exact transport retry delay and how it combines with a pending rate-limit retry (from #09)
- Location of the last-good file and handling of an unreadable or older-format file (from #09)
- Maximum age for persisted values without a known reset time (from #09)
- Whether HTTP 5xx and refused redirects count as transport or service errors (from #09)
- Whether Codex live values are persisted or its session-file fallback suffices (from #09)
- Whether Claude's "credentials expired" state also gets the sign-in action note (from #09)
- Size of the "on pace" tolerance band: fixed percentage points or relative to the expected value (from #10)
- Minimum elapsed share before the run-out date and bar hint appear, and a separate minimum for the 5-hour window (from #10)
- Glyph for the bar hint and how it sits next to icon labels, ⚠, ‼ and colored-bar-levels (from #10)
- Run-out phrasing: day only, day and time, or "in 2 days" (from #10)
- Whether stale entries show pace at their last good time or hide it (from #10)
- Whether the pace line for the 5-hour window is useful or mostly noise (from #10)
- Accessibility text for the bar hint (from #10)
- Length of the expiry delay (for example 24 hours) and whether it is configurable or fixed (from #11)
- Whether an account that changes from expired to rejected within one episode notifies again or counts as the same episode (from #11)
- Whether a config reload that changes an account's credential directory resets that account's baseline (from #11)
- Config key name for the global switch and where it sits in Settings (General tab or next to thresholds) (from #11)
- Whether clicking the notification can open the dropdown from a status item app, or falls back to activating the app (from #11)
- How the presenter's permission queue treats a credential alert whose account recovered before permission was granted (drop it) (from #11)
- Settings tab and wording for "Level color" and "Also show ⚠ / ‼ symbols", and the note shown when levels are hidden from the bar (from #12)
- Pill geometry (corner radius, padding, gap between pills) and the text color on orange and red pills in light and dark menu bars (from #12)
- How neutral parts get the menu bar's text color in a non-template image (appearance changes, inactive display, highlighted state); spike first (from #12)
- Whether a stale entry at a level keeps full color or a dimmed color (from #12)
- Whether the pill style needs increased-contrast variants (from #12)
- How the pace-forecast bar hint sits next to colored values and pills (from #12)

## Parked Ideas
- None
