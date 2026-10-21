# Brainstorm: Free Reset Tickets

**Date:** 2026-10-21
**Status:** active

## Problem Framing

Claude and ChatGPT subscriptions sometimes grant free limit resets: tickets that reset a usage limit early when redeemed. Claude's own UI calls this "Reset for free" (Settings > Usage). The tickets expire, and nothing in AgentTacho tells the user they hold one, so a ticket can lapse unused while the user waits for a window to reset.

CodexBar (https://github.com/steipete/CodexBar, "Limit Reset Credits") already reads them for both providers, display only. Its sources, read at commit `ad0c567`:

- **Claude:** no new request. The usage request AgentTacho already makes (`GET https://api.anthropic.com/api/oauth/usage`) returns a `cedar_ember` block when the query flag `?cedar_ember=1` is added: `{ eligible: Bool, grants: [ { resets_left: Int, resets_total: Int?, starts_at: ISO8601?, ends_at: ISO8601?, paused: Bool } ] }`. A ticket counts when `eligible` is true and its grant is not paused, has started and has not ended; a null `ends_at` never expires. The key is undocumented and obfuscated, observed on personal Pro/Max accounts only (Team and Enterprise unverified). CodexBar retries once without the flag on HTTP 400 or a non-scope 403.
- **Codex:** one extra request per refresh, `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`, with the same token and headers as the `wham/usage` call. Shape: `{ available_count: Int, credits: [ { id, reset_type, status: "available"|"redeeming"|"redeemed"|"expired", granted_at, expires_at?, title?, description? } ] }`. A ticket counts when `status == "available"` and `expires_at` is in the future. The server drops consumed credits instead of marking them redeemed.
- CodexBar never redeems a ticket. It shows a "Limit Reset Credits" section with an expiry timeline and notifies 3 days before a Codex credit expires.

## Approaches Considered

### A: Gift glyphs in the account header
- Pros: no extra row in the minimal dropdown (spec 025), the information sits next to the account name where the user looks.
- Cons: limited room; only short facts fit, details live in tooltips.

### B: A separate "Free resets" row under the windows
- Pros: room for an expiry timeline like CodexBar's.
- Cons: adds height to every section that holds a ticket; works against the minimal dropdown.

### C: Header glyphs (A) plus expiry notifications
- Pros: the user learns about a ticket about to lapse without opening the dropdown, which is the actual loss this feature prevents.
- Cons: one more notification kind and one more General setting.

## Decision

Approach C: dimmed gift glyphs in each account's header, and two expiry notifications per ticket. Display only; AgentTacho never redeems a ticket (constitution III, read-only).

## Key Requirements

- **Detection.** Claude subscription accounts read tickets from the existing usage request with `?cedar_ember=1`; Codex subscription accounts read them from `wham/rate-limit-reset-credits`. Only usable tickets count: not paused, started, not expired, not redeemed. Paused or future tickets are not shown.
- **Always on, best effort.** Fetched with every live refresh, no setting. Accounts with "Live limits from the usage service" off fetch nothing and show no tickets. A failed, rejected or malformed ticket response hides the glyphs and never changes the usage figures, their error state or the account's credential health. For Claude, a rejected flag falls back to the plain request.
- **Glyph.** Font Awesome Free `solid:gift` from the bundled icon font, monochrome in the dropdown's secondary (dimmed) text color, like the other header glyphs; no colored emoji.
- **Placement and count.** In the account's dropdown header, next to the account name: one glyph per ticket, at most three, then a dimmed `+N` for the rest. Groups and budgets show nothing. The menu bar item does not change.
- **Tooltips.** Each glyph's tooltip says how long that ticket stays valid, for example "Free limit reset, expires in 2 days (Thu 14:00)", or "Free limit reset, no expiry". Glyphs are ordered soonest expiry first. The `+N` tooltip lists the remaining tickets' expiries.
- **Notifications.** Two per ticket: when it gets within 3 days of expiry, and when it gets within 24 hours. A ticket that arrives with less time left gets only the applicable one, once. Tickets without expiry never notify. A ticket that disappears (redeemed elsewhere) cancels nothing already posted but posts nothing further. A new General toggle next to "Notify when a sign-in stops working", for example "Notify before a free reset expires".
- **Privacy.** The README "Security and privacy" section and the website's privacy section name the added query flag and the Codex request in the same pull request (constitution III).
- **Demo and screenshots.** The demo scenario gives one Claude account tickets (one never expiring, one expiring soon, so the tooltip and `+N` paths are covered by the coverage test); the `glance` shot shows the glyphs; the website copy mentions free reset tickets (constitution V).

## Open Questions

- Whether the General toggle for expiry notifications is on by default.
- Exact tooltip and notification wording, including the relative time format reused from the reset texts.
- How notification state survives a restart so a ticket does not notify twice for the same lead time.
- Whether a ticket-fetch failure is logged to the diagnostic log, and how often.
- VoiceOver reading for the glyphs ("2 free limit resets").
- Behavior for Claude Team and Enterprise organizations, where the `cedar_ember` block is unverified.
- Header width at 360 pt with a long account name, the headline figure and three glyphs plus `+N`.
- Whether the Codex request should run every refresh or at a slower cadence, since tickets change rarely.
