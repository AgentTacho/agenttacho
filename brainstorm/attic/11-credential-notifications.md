# Brainstorm: Credential Notifications

**Date:** 2026-10-16
**Status:** active

## Problem Framing

When a sign-in stops working, AgentTacho fails silently. The bar shows `--` or a stale `~` value, and the dropdown shows a colored note, but nothing reaches a user who isn't looking at the menu bar. A Claude Code login that is rejected (HTTP 401/403), a credential that was removed, or a Codex sign-in that the server rejects all need the user to act, usually by running the agent to sign in again. A notification turns that silent failure into a prompt to act.

Today the only notifications are threshold crossings (`ThresholdTracker` plus `NotificationPresenter`). Claude separates `notSignedIn` and `credentialsExpired`, but a 401/403 becomes a generic stale state. Brainstorm 09 (keep-last-good-values) adds a shared error classifier (transport, auth, rate limit, service changed) and a dropdown action note for rejected sign-ins, and leaves notifications out of scope. This brainstorm builds on it.

Seeded from the inbox item `reset-and-credential-notifications` (credential part only; reset notifications stay in the inbox).

## Approaches Considered

### A: Separate credential tracker, built after 09 (chosen)
- Pros: a small pure struct in UsageCore, easy to test; reuses 09's classifier so the notification and the dropdown use the same wording; reuses the existing presenter (permission handling, queueing, bundle check).
- Cons: waits for spec 09.

### B: Extend ThresholdTracker
- Pros: one tracker, one queue.
- Cons: mixes percent thresholds with health changes; the baseline and reset-on-window-change rules don't fit credential states.

### C: Separate tracker, shipped before 09
- Pros: faster to ship.
- Cons: needs its own Claude 401/403 detection, which duplicates 09's classifier and has to be merged later.

## Decision

Approach A. A separate credential alert tracker in UsageCore. It reads the credential health of each account from the classifier introduced by brainstorm 09 and sends through the existing `NotificationPresenter`. Spec 09 comes first.

## Key Requirements

- Scope: Claude subscription accounts and Codex plan accounts. API-key accounts have no sign-in and never notify.
- Trigger: only the change from a working sign-in to a failing one. An account that is already failing when the app launches (or on the first refresh after a relaunch) stays silent; the dropdown already explains it. The first observed state is the baseline, as with thresholds.
- Failure kinds:
  - Rejected (HTTP 401/403, Claude and Codex) and removed (the credential disappears): notify on the first refresh that sees it.
  - Expired (token past `expiresAt`, which running the agent usually fixes on its own): notify only if the expiry lasts longer than a delay. The delay counts from `expiresAt`, so a relaunch does not restart it.
- Transport errors, rate limits and service changes never trigger a credential notification.
- One notification per failure episode. A recovery re-arms the account so the next failure notifies again.
- Recovery: no new notification. The delivered failure notification for that account is removed from Notification Center.
- Text names the account and the fix, matching the dropdown note from 09, for example "Claude (Work): sign-in rejected. Run claude to sign in again." It never contains token material (see FR-011a and the README's "Security and privacy" section).
- Clicking the notification opens the dropdown.
- Setting: one global switch in Settings ("Notify when a sign-in stops working"), on by default. No per-account control.
- AgentTacho still only reads credentials; no new network requests.

## Open Questions

- Length of the expiry delay (for example 24 hours) and whether it is configurable or fixed
- Whether an account that changes from expired to rejected within one episode notifies again or counts as the same episode
- Whether a config reload that changes an account's credential directory resets that account's baseline
- Config key name for the global switch and where it sits in Settings (General tab or next to thresholds)
- Whether clicking the notification can open the dropdown from a status item app, or falls back to activating the app
- How the presenter's permission queue treats a credential alert whose account recovered before permission was granted (drop it)
