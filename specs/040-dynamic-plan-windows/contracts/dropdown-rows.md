# Contract: Claude section rows and bar entry

Deltas to spec 025 `contracts/dropdown-ui.md` and spec 027 `contracts/bar-and-dropdown.md`.

## Rows

One row per `SubscriptionStatus.windows` entry, in that order (spec FR-006). Today's answer gives:

```
✳ Claude Max ..................... 11%
  ● 7-day        11%   resets Fri 08:00
    [bar]
  ○ Fable        15%   resets Fri 08:00
    [bar]
```

No "5-hour" row unless the answer has a window of a 5-hour group. A window of an unknown group (`daily`) shows its row with percent, bar and reset text and no pace note. With no window at all: no rows, state line "No limits reported".

## Bar entry

| Headline | Drawn | Accessibility |
|---|---|---|
| default (`sevenDay`) | `✳ 11%` | as today |
| `model:Fable` | `✳ Fable 15%` | `Claude Max Fable weekly limit 15%` |
| `fiveHour` (present) | `✳ 5h 58%` | `Claude Max 5-hour window 58%` |
| `fiveHour` (absent) | `✳ 11%` (default, no tag) | as today; replaces `✳ 5h --` |
| `limit:daily_all` | `✳ daily 40%` (no `↗` / `↑`) | `Claude Max daily window 40%` |
| no plan window | `✳ --` | as today |
