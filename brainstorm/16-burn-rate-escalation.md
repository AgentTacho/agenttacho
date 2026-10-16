# Brainstorm: Burn Rate Escalation

**Date:** 2026-10-16
**Status:** active

## Problem Framing

The pace forecast (spec 011) puts `↗` after a bar value when the average rate since the window start projects a run-out before the reset. The marker is binary: an entry that will run out on the last day of the week looks the same as one that will hit its limit within the hour. Users want the bar to tell them when a limit is coming quickly, so they can slow down or switch agents before work stops.

Two things make an entry "fast": the average pace over the whole window may already be far above what the remaining time allows, or a burst right now (a long agent run this afternoon after a quiet week) may burn much faster than the average shows. The average-since-start model of spec 011 reacts slowly to such a burst, and its 10% hold back hides it entirely early in a window.

The idea: measure the velocity (burn rate) and switch the bar marker from `↗` to `↑` when it crosses a threshold.

## Approaches Considered

### A: Bar escalation with in-memory samples (chosen)

Each provider keeps a short list of observed values (about the last hour) in memory. The bar shows `↑` instead of `↗` when either the average rate or the recent rate is at least k times the sustainable rate. The dropdown pace meter's tooltip and accessibility text name the fast burn and its run-out.

- Pros: no new requests, no stored files, security statement unchanged; reacts to bursts; one rule for every window length.
- Cons: the recent-rate side starts empty after each launch and needs about 15 minutes of samples; whole-percent steps on subscription windows limit precision.

### B: A plus a notification

Same as A, plus a one-time notification when an entry first switches to `↑`.

- Pros: most noticeable; reaches users who don't glance at the bar.
- Cons: reverses spec 011's "no notifications from pace"; can be noisy on 5-hour windows; overlaps with threshold notifications.

### C: A with persisted samples

The sample history survives restarts in a small local file.

- Pros: the recent rate is available right after launch.
- Cons: a new stored file and a change to the README's "Security and privacy" section for a small gain.

### Choices made along the way

- **Signal**: either one. `↑` when the average-pace projection or the recent burst crosses the threshold. Using only the existing run-out projection (no bursts) or only the recent rate (no steady overspending) were ruled out.
- **Threshold**: a rate multiple. `↑` when the rate is at least k times the sustainable rate, the remaining percent spread over the time left until the reset (k = 2 means "you would run out in half the remaining time or less"). An absolute horizon (for example 1 hour for every window) and per-kind horizons (30 minutes, 24 hours, 3 days) were ruled out: the first fits no window length well, the second adds numbers to explain.
- **Lookback**: the recent rate is the change between the oldest sample within the last 60 minutes and the newest. 30 minutes (whole-percent steps trip `↑` from a single step) and a share of the window (too slow for weekly and monthly windows) were ruled out.

## Decision

Approach A. `↗` keeps its meaning (projected to run out before the reset). It escalates to `↑` when the burn rate is at least k times the sustainable rate, measured either as the average since the window start or as the recent rate over the last 60 minutes. Samples live in memory only, the existing toggle covers both arrows, and pace still triggers no notifications.

## Key Requirements

- Sustainable rate at the observation time: (100 minus actual percent) divided by the time left until the reset.
- Average rate: actual percent divided by the elapsed time since the window start (the model of spec 011).
- Recent rate: change in percent between the oldest sample of the same window within the last 60 minutes and the newest sample, divided by the time between them. It counts only when the samples span at least about 15 minutes. A reset between samples (a changed reset time or a drop in percent) discards the older samples.
- `↑` replaces `↗` when the average rate or the recent rate is at least k times the sustainable rate (k = 2 as the working value). `↑` can appear from a recent burst even when the average pace is behind or still inside spec 011's 10% hold back.
- Same suppression as `↗`: no arrow while `⚠` or `‼` shows, on stale entries, on group member shares, or when the toggle is off. Same entry-to-window mapping as spec 011 FR-012 (7-day for Claude, longest effective window for Codex, the budget itself).
- Samples are kept per window in memory, from the values each refresh already produces (subscription fetch time, Codex observation time, snapshot time for budgets). No new requests, no stored files; the README's "Security and privacy" section stays true unchanged.
- Dropdown: the pace meter's tooltip and accessibility text say when an entry is burning fast and give the run-out at that rate; the bar's accessibility description says the entry will reach its limit soon.
- Works with adaptive refresh (brainstorm 15): endpoint calls stay at the base interval while an agent is active, which is when bursts happen, so samples stay dense when they matter.
- Rate, sample and threshold logic lives in `UsageCore` with unit tests (average and recent triggers, sample span minimum, reset between samples, whole-percent steps, suppression rules); the SwiftUI layer only renders the glyph and text.
- Out of scope: notifications from pace, persisted samples, burndown charts, a configurable k in Settings.

## Open Questions

- Final value of k (2, or 3 for fewer false alarms) and whether the 5-hour window needs a different value
- Minimum sample span for the recent rate (15 minutes or more) and whether a single whole-percent step can ever trigger `↑` on its own
- Whether the recent rate also escalates entries that are not yet ahead of even use, or only when the projected run-out also falls before the reset
- Whether `↑` from a recent burst may show inside spec 011's 10% early-window hold back
- Glyph choice (`↑` or a bolder variant) and how it sits next to colored bar levels (brainstorm 12)
- Toggle wording, now that one toggle covers both `↗` and `↑`
- Tooltip and accessibility wording for "burning fast" and the run-out at the recent rate
- Hysteresis so an entry near the threshold does not flip between `↗` and `↑` on every refresh
