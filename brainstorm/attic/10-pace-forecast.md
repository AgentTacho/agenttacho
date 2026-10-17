# Brainstorm: Pace Forecast

**Date:** 2026-10-15
**Status:** active

## Problem Framing

AgentTacho shows how much of a window or budget is used ("62%", "$145 of $300/month") and when it resets, but not whether that is a lot for this point in the window. 62% of a 7-day limit is fine on day six and alarming on day two. The question users actually ask is "will this last until the reset?": will the monthly Vertex budget last until the 1st, will the Claude 7-day limit hold until Thursday.

Every entry that has a percent already carries what a pace needs: the Claude 5-hour and 7-day windows and model-scoped weekly limits have a fixed length and `resetsAt`, Codex windows report their length in minutes and their reset, and budget entries carry their own `window` (weekly or calendar month). Pace can therefore be computed from the snapshot alone, without new requests, credentials or a history store.

Seeded from the idea inbox entry `pace-forecast` (CodexBar comparison, rated 5 stars on 2026-10-15). Budgets and subscription windows matter equally.

## Approaches Considered

### A: Delta plus run-out (chosen)

One short secondary line under each window and budget row: "on pace" inside a tolerance band, otherwise "12% ahead · runs out Wed" or "8% behind". The run-out appears only when it falls before the reset.

- Pros: answers both "how am I doing" and "will it last" in a few words; no new widgets; same treatment for every entry kind.
- Cons: one more line per row makes the dropdown slightly taller; the tolerance band needs a sensible value.

### B: Run-out only

Text only when the projection runs out before the reset ("runs out Wed 14:00"), nothing otherwise.

- Pros: quietest; no prediction shown when everything is fine.
- Cons: "comfortably behind" and "barely fine" look the same; users cannot tell how much room is left.

### C: Delta plus guide marker

Like A, plus a mini progress bar per row with an even-use tick (CodexBar style).

- Pros: most visual, burndown at a glance.
- Cons: new UI on every row, taller dropdown, works against AgentTacho's minimal setup.

### Forecast model alternatives

- Average since window start (chosen): rate = used so far / elapsed time. Works for every entry from the snapshot alone, stable, easy to explain; reacts slowly to a burst today.
- Recent rate for budgets from the per-day trend: reacts to bursts, but subscription windows would still use the average (AgentTacho only sees their current percent), so the two kinds would behave differently.
- Pace delta only, no run-out date: simplest, but drops the "will it last" answer.

## Decision

Approach A with the average-since-window-start model, shown in the dropdown, plus a small bar hint for entries projected to run out before their reset.

- Dropdown: a pace line per window and budget row ("on pace", "X% ahead · runs out <when>", "X% behind").
- Bar: a small marker next to an entry's value when the projection runs out before the reset. It follows the window the bar already shows (7-day for Claude subscriptions, the longest window for Codex plans, the budget itself), and it gives way to `⚠` and `‼` once a threshold or 100% is reached.
- Early in a window the average is noisy, so the pace delta shows from the start, but the run-out date and the bar hint wait until a minimum part of the window has passed.
- The bar hint is on by default, with one toggle in the Menu Bar tab.

## Key Requirements

- Pace is computed from the snapshot only: percent (or spend and budget), window start or length, and reset time. No new outbound requests, no stored history; the README's "Security and privacy" section stays true unchanged.
- Expected use at time t is the elapsed share of the window (elapsed / window length, as a percent). The pace delta is actual percent minus expected percent.
- Inside a tolerance band around the expected value the row says "on pace"; above it "X% ahead", below it "X% behind".
- Run-out time is a linear extrapolation of the average rate since window start. It is shown only when it falls before the reset, and only after the minimum elapsed share of the window.
- Applies to every row with a known window: Claude 5-hour, 7-day and model-scoped weekly limits, Codex plan windows, weekly and monthly budgets (groups and own budgets).
- No pace for: windows that have not started, empty groups, entries without data, and values at or above 100% (already reached, `‼` covers it).
- The pace uses the time the value was observed (the subscription fetch time, the Codex observation time, the snapshot time for budgets), not the moment the dropdown opens.
- Bar hint: one compact marker on bar entries projected to run out before their reset, suppressed while `⚠` or `‼` is shown, and turned off by a Menu Bar tab toggle (default on).
- Pace logic lives in `UsageCore` with unit tests (window kinds, early-window hold back, tolerance band, run-out before and after reset, observed time); the SwiftUI layer only renders the text and marker.
- Out of scope: notifications based on pace, burndown charts or history, recent-rate forecasting, progress bars in the dropdown.

## Open Questions

- Size of the "on pace" tolerance band: fixed percentage points (for example 5) or relative to the expected value
- Minimum elapsed share before the run-out date and bar hint appear (for example 10%), and whether the 5-hour window needs its own minimum in minutes
- Glyph for the bar hint and how it sits next to icon labels, `⚠` and `‼`, and the planned colored-bar-levels idea
- Run-out phrasing: day only, day and time, or "in 2 days"; reuse of the reset-time formatting rules
- Whether stale entries show pace computed at their last good time or hide it
- Whether the pace line for the 5-hour window is useful or mostly noise
- Accessibility text for the bar hint (VoiceOver label of the status item)
