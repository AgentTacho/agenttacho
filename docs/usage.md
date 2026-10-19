# Reading the bar

Each entry in the bar is an icon and a percentage. Click it for the details. This page explains the markers, the colors, the alerts and how to arrange what you see.

## Details on click

Usage per model, project or agent tool, with a daily trend. Every account, group and Unassigned entry can show its usage per model, per project or per harness.

## Alerts, colors and markers

A notification fires when usage crosses your thresholds (80% and 100% by default). In the bar, a value turns orange when it is close to the limit and red when it is over it. In the Menu Bar tab of Settings you can show levels as a pill instead, add the `⚠` and `‼` symbols, or turn the colors off.

The markers:

- `~` means the value may be out of date.
- `↗` means the entry will run out before it resets if you keep this pace.
- `↑` takes the place of `↗` when the entry burns at least twice as fast as the remaining time allows, either on average or over the last hour, so it will run out in half the time left or sooner.

In the dropdown, every limit and budget row has a bar filled to its percent, with a tick where even use would be now, so a fill past the tick means you are ahead of pace. When a row will run out before it resets, or burns fast, its bar turns orange and a short note says so, for example "15% ahead · runs out in 2d 13h" or "15% ahead · burning fast · runs out in 3h 10m". Rows on pace or behind show no note, and nothing needs hovering. Reset and run-out times read relative ("resets in 2h 26m") or, per account or group, absolute ("resets 17:20"); hovering a time shows the other form.

## Your layout

Pick which entries show in the bar and in which order. See [Configuration](configuration.md) for the Menu Bar tab that controls this.
