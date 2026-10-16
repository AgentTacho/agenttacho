# Brainstorm: Fix-Soon Review Batch

**Date:** 2026-10-16
**Status:** active

## Problem Framing

The idea inbox's priority section (rated 2026-10-15) marks seven deep-review findings as "worth fixing soon (small, user-relevant)". Each one is too small for its own spec, yet several change visible behavior, security posture or what a release does, so they should not slip in as unreviewed cleanups. A check on 2026-10-16 confirmed all seven are still open in the code.

| Entry | Theme | Origin spec |
|---|---|---|
| threshold-baseline-after-reset | App correctness | 001 (FR-028) |
| scan-credential-directories | App correctness | 001 |
| stale-entry-period-mismatch | App correctness | 003 (FR-014) |
| sqlite-defensive-open | Security hardening | 006 |
| claude-client-resource-timeout | Security hardening | 007 (001 FR-011a) |
| release-signing-tier-guard | Release safety | 005 |
| replace-published-as-draft | Release safety | 005 |

The release items gained weight with v0.2.1, the first notarized Developer ID release: a silent fallback to self-signed now changes the designated requirement for every installed user.

## Approaches Considered

### A: One brainstorm, one spec, three themed user stories
- Pros: one review cycle and one pull request for a set of small changes; the three themes stay visible as separate stories; matches the inbox's "fix soon" grouping.
- Cons: mixes Swift app code and release shell scripts in one change, so the review touches two test suites (`make test`, `make test-release`).

### B: One brainstorm, two specs (app fixes, release fixes)
- Pros: each pull request touches one area and one test suite.
- Cons: two pipelines for seven small items; more overhead than the work.

### C: Subset now, rest later
- Pros: smallest change.
- Cons: leaves user-relevant findings in the inbox; the inbox rating already selected these seven.

## Decision

Approach A: one spec covering all seven entries, organized as three user stories (app correctness, security hardening, release safety).

Per-item decisions:

1. **threshold-baseline-after-reset**: a window reset while the app is running starts the new window from 0%. A first observation in the new window that is already at or above a threshold counts as a crossing and notifies (one notification per crossed threshold, as FR-028 already says for multi-crossings). The baseline rules stay unchanged for the first refresh after launch, period switches (spec 003 FR-017), group membership changes (spec 004 FR-015) and restored last-good values (spec 010 FR-019).
2. **stale-entry-period-mismatch**: a carried-over group entry whose stored period differs from the configured period drops its value and shows the group as pending (no number) with the new period's wording, until the record source recovers. A weekly number never appears under monthly wording.
3. **release-signing-tier-guard**: when a Developer ID certificate is present but unusable (expired or revoked), release preflight fails with a clear error instead of falling back to self-signed. An explicit opt-out variable allows a deliberate downgrade. Builders without any Developer ID certificate keep the self-signed path as today.
4. **scan-credential-directories**: credential directories of subscription accounts are added to the log scan set automatically, so the directory tie-breaker needs the path in one setting only.
5. **sqlite-defensive-open**: the OpenCode database is opened with `SQLITE_DBCONFIG_DEFENSIVE` and `trusted_schema=OFF`; no visible change.
6. **claude-client-resource-timeout**: the Claude usage client gets a resource timeout matching the Codex client (45 s).
7. **replace-published-as-draft**: `REPLACE=1` on a published release must not leave a public release without its DMG after a failed upload (exact mechanism is an open question below).

## Key Requirements

- Window resets during a running session notify for thresholds already exceeded at the first observation of the new window; all other re-baseline paths are unchanged. FR-028 gets an explicit note distinguishing launch baseline from window reset.
- A group entry whose period no longer matches its configuration is shown as pending with the configured period's wording, never with a value from the old period.
- A configured credential directory is scanned for session logs without being listed again under log directories.
- The OpenCode database is opened in defensive mode with untrusted schema disabled.
- The Claude usage client has a bounded total request time, like the Codex client.
- Release preflight refuses to sign with self-signed when a Developer ID certificate exists but is expired or revoked, unless an explicit downgrade variable is set; the existing tests that assert the silent fallback change accordingly.
- A failed asset upload during `REPLACE=1` on a published release leaves no public release without a DMG.
- Logic changes land in `UsageCore` with tests written first; release changes are covered by `make test-release`.
- The README "Security and privacy" section stays true (timeouts, SQLite handling) and is updated in the same pull request if affected.
- Out of scope: all other review findings in the inbox.

## Open Questions

- Mechanism for safe replacement of a published release: switch to draft, upload, republish (asset URLs and the cask 404 while it is a draft) versus uploading under a temporary asset name and swapping after success.
- Name of the explicit downgrade variable for the signing tier guard (for example `ALLOW_TIER_DOWNGRADE=1`) and whether it should be listed in the Makefile's release variables.
- Whether a reset-time notification should say the threshold was already exceeded when the window started, or use the normal crossing text.
- Whether "pending" for a period-mismatched group reuses the existing waiting-for-data presentation or needs its own note.
- Whether automatically scanned credential directories appear in the diagnostic log or Settings so the user can see they are scanned.
