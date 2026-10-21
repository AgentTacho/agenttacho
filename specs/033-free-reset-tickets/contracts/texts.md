# Contract: Texts

`<rel>` is `TimeText.relative` and already includes "in" ("in 2d 3h"); `<abs>` is `TimeText.absolute` with `isReset: false` ("09:30" today, "Fri 09:30" within a week, the long form later). All texts are built in UsageCore and tested there with `en_US_POSIX` and a fixed time zone.

## Dropdown

| Element | Text |
|---|---|
| Glyph tooltip, with expiry | `Free limit reset, expires <rel> (<abs>)` + newline + `Click to open the usage page` |
| Glyph tooltip, no expiry | `Free limit reset, no expiry` + newline + `Click to open the usage page` |
| `+N` marker | `+N` |
| `+N` tooltip | one glyph line per hidden ticket (without the click line), then `Click to open the usage page` |
| VoiceOver label | `1 free limit reset, expires <rel>` / `N free limit resets, the next expires <rel>` / `1 free limit reset, no expiry` / `N free limit resets, no expiry` |
| VoiceOver action | `Open usage page` |

## Notifications

Identifier: `free-reset-<accountId>-<expiry epoch seconds>-<3d|24h>`.

| Step | Count | Title | Body |
|---|---|---|---|
| 3 days | 1 | `<account>: free limit reset expires within 3 days` | `1 free limit reset expires <abs>.` |
| 3 days | n | `<account>: free limit resets expire within 3 days` | `<n> free limit resets expire <abs>.` |
| 24 hours | 1 | `<account>: free limit reset expires within 24 hours` | `1 free limit reset expires <abs>.` |
| 24 hours | n | `<account>: free limit resets expire within 24 hours` | `<n> free limit resets expire <abs>.` |

No token, no service identifier, no credential data (FR-015).

## Diagnostic log

| Event | Source | Message |
|---|---|---|
| ticket read failed (first per kind per run) | `subscription` / `codex` | `<accountId>: free reset tickets not read (<kind>)` |
| flag dropped | `subscription` | `<accountId>: usage service refused the free reset flag (http-<code>), not sent again until relaunch` |
| flag suspended | `subscription` | `<accountId>: usage service refused the free reset flag (http-<code>) and the plain request failed too, flag sent again after the next successful request` |
| notification delivered | `notifications` | `free reset expiry <step> for <accountId>, expires <ISO 8601>` |
| notification suppressed | `notifications` | `free reset expiry <step> for <accountId> not sent (switch off), expires <ISO 8601>` |

## Settings

General > Notifications: `Toggle("Notify before a free limit reset expires")` below `Notify when a sign-in stops working`.
