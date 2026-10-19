# Reading the bar

Each entry in the bar is an icon and a percentage. Click it for the details. This page explains the markers, the colors, the alerts and how to arrange what you see.

## Details on click

Usage per model, project or agent tool, with a daily trend. Every account, group and Unassigned entry can show its usage per model, per project or per harness. The day row below the table has one column per day and ends with a `Σ` column holding the sum of all shown days: the week's tokens for a subscription, the period's spend for a budget. Point at a day or at `Σ` for the exact value.

When the dropdown is taller than the screen allows, only the sections scroll. The footer stays at the bottom: any source errors (at most three lines, the rest behind "+N more"), the update line, and the status row with the refresh icon, "Last refreshed" right beside it, and the Settings and Quit icons on the right. While AgentTacho refreshes less often than usual, pointing at "Last refreshed" says why.

## Which window the bar shows

A Claude subscription shows its 7-day window in the bar, a Codex plan its longest window. To watch another one, click its row in the dropdown: the 5-hour window, a model limit such as Fable, or another plan window. A `●` marks the row the bar follows (dimmed while it is the default window), and the bar and the section header put a short tag before the value, for example `✳ 5h 58%` (`wk` for a weekly plan window, the model name for a model limit). The color and the `↗` and `↑` markers follow that window; a full 7-day window still shows red. Click the default row to go back. Each account keeps its choice across restarts. When the provider stops reporting a chosen model limit or plan window, the bar shows the default window until it comes back. Notifications still check every window.

## Alerts, colors and markers

A notification fires when usage crosses your thresholds (80% and 100% by default). In the bar, a value turns orange when it is close to the limit and red when it is over it. In the Menu Bar tab of Settings you can show levels as a pill instead, add the `⚠` and `‼` symbols, or turn the colors off.

The markers:

- `~` means the value may be out of date.
- `↗` means the entry will run out before it resets if you keep this pace.
- `↑` takes the place of `↗` when the entry burns at least twice as fast as the remaining time allows, either on average or over the last hour, so it will run out in half the time left or sooner.

In the dropdown, every limit and budget row has a bar filled to its percent, with a tick where even use would be now, so a fill past the tick means you are ahead of pace. When a row will run out before it resets, or burns fast, its bar turns orange and a short note says so, for example "15% ahead · runs out in 2d 13h" or "15% ahead · burning fast · runs out in 3h 10m". Rows on pace or behind show no note, and nothing needs hovering. Reset and run-out times read relative ("resets in 2h 26m") or, per account or group, absolute ("resets 17:20"); hovering a time shows the other form.

## Your layout

Pick which entries show in the bar and in which order. See [Configuration](configuration.md) for the Menu Bar tab that controls this.
