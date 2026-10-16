# Contract: Refresh Pace Decisions

The behavior `AdaptivePace` and `RefreshCoordinator` must show. Each row maps to a test in `AdaptivePaceTests` or `RefreshCoordinatorTests`. Times are minutes after a start at t=0. The base is 5 minutes and the toggle is on unless stated otherwise.

## Endpoint pace (FR-004 to FR-007, FR-010a, FR-013)

| # | Situation | Expected |
|---|---|---|
| P1 | Scheduled Claude calls with no Claude Code or OpenCode records after each call | Calls at 0 (launch), 5, 15, 35, 65, 95; scans every 5 |
| P2 | As P1, then a Claude Code record at t=70 | The scheduled refresh at t=70 calls Claude (activity, at least 5 since 65), and the interval returns to 5 |
| P3 | Codex records only | The Codex interval stays 5; the Claude interval grows as in P1 |
| P4 | OpenCode record at t=12 | Counts for both endpoints |
| P5 | Re-read of records older than the last call (price change, window move, launch) | No activity |
| P6 | A scheduled Claude call ends in a transport failure (or HTTP 5xx) | Interval and last call unchanged; a record from before the failed call counts at the next call |
| P7 | A scheduled call is not made because of an expired or rejected sign-in | Interval and last call unchanged |
| P8 | Dropdown-open call at t=20 with no activity, interval 20 | The last call becomes 20, the interval stays 20 (no doubling) |
| P9 | Dropdown-open call at t=20 that sees activity | The interval returns to 5 |
| P10 | A tick fires 3 s before the due time | Counts as due |
| P11 | Base 40 min | The interval stays 40 forever; no stretching |
| P12 | Base 1 min, no activity | Intervals 1, 2, 4, 8, 16, 30 |
| P13 | Toggle off | Every scheduled refresh decides as before (EndpointPolicy only); no pace reuse, no pace log lines |

## Timer pace (FR-008 to FR-011)

| # | Situation | Expected |
|---|---|---|
| T1 | Idle | Next scheduled refresh = last refresh + 30, but no later than the earliest endpoint due time, where due = last call + max(interval, 30) |
| T2 | Low Power Mode | Timer 10; the endpoint due time uses max(interval, 10) |
| T3 | High temperature and Low Power Mode | Timer 10; the reason is Low Power Mode |
| T4 | Idle and Low Power Mode | Timer 30; the reason is idle |
| T5 | The condition ends at t=50, last refresh at t=35 | Next scheduled refresh = 40, or at once if 40 has passed |
| T6 | Base 40 and idle | Timer 40 |
| T7 | Return from idle | An `.idleReturn` refresh within 60 s, spaced 60 s per endpoint, never during a block; skipped when a wake refresh ran in the last 60 s |
| T8 | Base 7, Low Power Mode, Claude interval 30 | Ticks at 14, 28, then at the due time 30 (FR-010a); no call later than 30 after the previous one (SC-005) |
| T9 | Claude calls fail by transport (or are blocked, or make no request), so the last call stays at 0 | Next scheduled refresh = last refresh + timer interval; the past due time never makes the timer fire at once again |
| T10 | Endpoint in use with no call yet | Same as T9: the timer follows the last refresh |
| T11 | Clock moved back 1 hour after a call | `normalize(now:)` stores `now` as last call and last refresh; Claude is called within `max(interval, timerInterval)` of the jump |
| T12 | No refresh completed yet (launch refresh running) | `nextScheduledRefresh` = `now + timerInterval` |
| T13 | A `.local` reprice 3 s before a Claude due time | The due time still pulls the next tick (only scheduled refreshes hide a due time) |

## Dropdown open (FR-012)

| # | Situation | Expected |
|---|---|---|
| D1 | Last Claude call 4 min ago | `shouldRefreshOnOpen` is true; the refresh calls Claude |
| D2 | Last Claude call 30 s ago, Codex not in use | false |
| D3 | Claude 30 s ago, Codex 5 min ago | true; only Codex is called (the Claude spacing reuses) |
| D4 | Rate-limit block active | Refresh allowed (local scan) but no endpoint call |
| D5 | No endpoint in use, last refresh 2 min ago | true |
| D6 | Toggle off | false |
| D7 | A refresh is already running | `shouldRefreshOnOpen` is false: no second refresh starts and none is queued |

## Unchanged (FR-014, SC-004)

| # | Situation | Expected |
|---|---|---|
| U1 | Launch, wake, manual, settings, quick retry, rate-limit retry | Same decisions and timing as before; their calls count as last call without doubling |
| U2 | Rate-limit block until t=40 while the pace says due at t=35 | No call before 40; the scheduled retry at 40 is unchanged |
| U3 | Toggle off for one hour of ticks | The same sequence of refreshes and endpoint calls as the pre-feature code |
| U4 | Scheduled tick during a Claude rate-limit block, Codex not due by pace | Claude reused (block), Codex gets `codexPaceDue == false` and makes no request |
| U5 | Pace or reprice reuse of a stored Claude result whose entries carry `reachedService == true` | No call recorded: Claude's last call and interval unchanged |
| U6 | An account added by hand (new id or changed directory) while Claude is paced | The next scheduled refresh calls Claude (no pace reuse) |

## Pace line (FR-016)

| # | State | Line |
|---|---|---|
| L1 | All paces at base | none |
| L2 | Claude stretched, next Claude call 14:35 | `Plan limits next checked at 14:35 (no agent activity)` |
| L3 | Low Power Mode, Claude at base, next due 14:20 | `Plan limits next checked at 14:20 (Low Power Mode)` |
| L4 | Low Power Mode, no endpoint in use, next refresh 14:20 | `Next refresh at 14:20 (Low Power Mode)` |
| L5 | Next check tomorrow | weekday plus time, for example `Fri 09:05` |
| L6 | Claude past due (transport failures), next scheduled refresh 14:40 | the line shows 14:40, never a past time |
