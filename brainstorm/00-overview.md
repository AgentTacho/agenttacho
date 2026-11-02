# Brainstorm Overview

Last updated: 2026-11-02

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 17 | 2026-10-16 | account-budget-subtitle | active | - | - |
| 18 | 2026-10-16 | landing-page | approved | - | - |
| 19 | 2026-10-16 | pace-line-names-plan | active | - | - |
| 20 | 2026-10-16 | about-tab-update-layout | active | - | - |
| 21 | 2026-10-16 | recover-stuck-offline | active | - | - |
| 23 | 2026-10-18 | minimal-dropdown | spec-created | 025 | - |
| 24 | 2026-10-18 | readable-dialog-shots | spec-created | 029 | - |
| 25 | 2026-10-19 | dropdown-layout-polish | active | - | - |
| 26 | 2026-10-19 | headline-window-switch | active | - | - |
| 27 | 2026-10-19 | section-bands | spec-created | 028 | - |
| 28 | 2026-10-19 | default-window-setting | rejected | - | - |
| 29 | 2026-10-20 | threshold-levels-direction | active | - | - |
| 30 | 2026-10-20 | site-reframe-screenshots | spec-created | 031 | - |
| 31 | 2026-10-21 | dropdown-theme | spec-created | 032 | - |
| 32 | 2026-10-21 | free-reset-tickets | spec-created | 033 | - |
| 33 | 2026-10-22 | settings-sidebar-directories | spec-created | 034 | - |
| 34 | 2026-10-22 | additional-session-directories | spec-created | 035 | - |
| 35 | 2026-10-23 | translucent-dropdown | parked | 036 (branch) | - |
| 36 | 2026-10-23 | nsmenu-dropdown | active | - | - |
| 37 | 2026-10-27 | profile-account-matching | spec-created | 037 | - |
| 38 | 2026-10-27 | match-rule-operators (revisited 2026-10-28) | active | 038 (branch) | - |
| 39 | 2026-10-28 | faster-session-scan | active | - | - |
| 40 | 2026-11-02 | dynamic-plan-windows | active | - | - |

## Open Threads
- Exact text for an account in a missing group ("no group" or the dangling id) (from #17)
- Whether the group's icon renders as the same glyph in a subtitle's caption font as in the picker, and what to show for a group without an icon (from #17)
- Whether VoiceOver should read the icon name or skip it in the subtitle (from #17)
- Whether the reason names OpenCode too, since its activity counts for both plans (from #19)
- Plan names in the pace line: "Claude"/"Codex" or the platform names (from #19)
- Whether the dropdown's accessibility text changes with the pace line (from #19)
- Whether About's status says so when automatic update checks are off (from #20)
- Whether docs or comments that mention the signing tier in About need updating (from #20)
- Exact URL error codes that count as transport errors (reuse spec 010's classification) (from #21)
- Whether a manual click merges with a pending quick retry after a transport error (from #21)
- Whether the dropdown says "Retrying…" while a manual retry runs (from #21)
- Whether "Show accounts" remembers its state across openings (from #25)
- What Σ shows for a period without usage, and its style (from #25)
- The pinned footer at the height cap and with many error lines (from #25)
- VoiceOver order with a pinned footer (from #25)
- Whether a long "Last refreshed" text fits beside the refresh icon at 360 pt (from #25)
- How a clickable window row shows its affordance without a tooltip (from #26)
- Menu bar tag format per window and its effect on bar width (from #26)
- Whether Settings also shows and changes the headline window (from #26)
- VoiceOver action name and announcement for the chosen window (from #26)
- Whether the Menu Bar tab's live preview shows the tag (from #26)
- Order of specs 25 and 26 and the shared screenshot round (from #26)
- Tint strengths in light and dark mode and whether they survive WebP compression (from #27)
- Section bands under "Increase Contrast" (from #27)
- Bands under the scroll edge at the height cap (from #27)
- Whether the Settings panes' dividers follow later (from #27)
- Threshold editor wording in remaining mode and help text for both levels (from #29)
- Which threshold is critical when a configuration holds more than two (from #29)
- Upper threshold equal to or below the lower one (from #29)
- Dollar wording for budgets in remaining mode (from #29)
- Rounding of remaining percent near 100% used (from #29)
- Notification wording for budgets over 100% in remaining mode (from #29)
- Website shot or copy-only mention of remaining mode (from #29)
- Whether the Settings bar preview shows both directions (from #29)
- Theme picker label and placement in General (from #31)
- Light shades for orange, red and secondary text at 4.5:1 (from #31)
- Light panel background color and band tint on it (from #31)
- Whether a theme change applies while the dropdown is open (from #31)
- Demo coverage check for the light panel's warning and error lines (from #31)
- Whether the demo app needs a theme override for captures (from #31)
- Whether the free-reset expiry notification toggle is on by default (from #32)
- Tooltip and notification wording for free reset tickets (from #32)
- Notification state across restarts so a ticket does not notify twice (from #32)
- Diagnostic logging of ticket-fetch failures (from #32)
- VoiceOver reading for the gift glyphs (from #32)
- Claude Team and Enterprise behavior of the unverified `cedar_ember` block (from #32)
- Header width at 360 pt with three glyphs plus `+N` (from #32)
- Codex ticket request cadence: every refresh or slower (from #32)
- Sidebar entry icons and descriptions in General (from #33)
- Placement of the directory field for token-based accounts (from #33)
- Same directory on two accounts, and a directory equal to the default (from #33)
- Load note text for dropped global directory entries (from #33)
- Directory validation (exists, projects folder) (from #33)
- Settings window size with the General sidebar (from #33)
- Wildcard limits (`*` only or `**`, match cap) for additional session directories (from #34)
- Handling of deleted or moved sandbox folders (from #34)
- Showing the current match count of a wildcard entry in Settings (from #34)
- Configuration key for per-account additional session directories (from #34)
- Recommended folder layout for session deliverers such as cc-deck (from #34)
- Sending the sandbox export idea to cc-deck's idea inbox (from #34)
- Native form of each footer part in the NSMenu (status row, update line, source error lines) (from #36)
- Headline switch rows and Details inside the menu's tracking loop (from #36)
- Content row height changes while the menu is open, and the height cap against the menu's maximum (from #36)
- Orange and red text on the system's glass over light desktops (from #36)
- Which spec 036 parts carry over, and the opaque option's configuration key (from #36)
- Theme mismatch in the spec 036 walkthrough (light configured, dark shown) (from #36)
- Capturing and cropping the menu in the demo build and capture script (from #36)
- MenuBarOpener and MenuBarExtra mentions in docs and comments (from #36)
- Whether the memory path in `api-request-shape` lines also appears with auto-memory off or outside cc-deck (from #37)
- Cause of the two sessions mixing request id styles while naming one profile (from #37)
- Cost of reading the shape lines and caching the profile in the log index (from #37)
- Wording and placement of the overlap warnings in Settings (from #37)
- Whether the Unassigned popover explains why records stayed unassigned (from #37)
- Regex flavor, options and a length limit or timeout for the Anywhere field (from #38)
- Whether the condition row fits the editor pane at its minimum width (from #38)
- Name of the regex operator in the pop-up (from #38)
- Whether a screenshot stem shows the Session matching section (from #38)
- Whether a regex rule needs a "Test" affordance (from #38)
- Whether "no Anthropic request id" reliably marks gateway records, including Bedrock and proxies (from #38 revisit)
- Overlap warning wording for two accounts of the same session kind without a condition (from #38 revisit)
- A "Provider" field for OpenCode "Other provider" conditions (from #38 revisit)
- Whether the Unassigned hint explains sessions of no kind (from #38 revisit)
- Worker count and QoS for the parallel parse, and whether the first scan after a start differs from a refresh (from #39)
- Tail-window size for the type key and the fallback on very long lines (from #39)
- Whether files above a size threshold are read in chunks (from #39)
- How much of the cold start is disk I/O; the baseline's cold run answers it (from #39)
- Where the bench command lives and how a cold cache is produced reliably (from #39)
- Whether the sequential attribution phase (spec 038 regex rules per record) needs its own measurement (from #39)
- The maintainer script for the real-corpus differential test (from #39)
- Which ISO 8601 forms the fast date parser accepts and which fall back to Foundation (from #39)
- The byte-level parser API for the index, and whether `parse(line: String)` stays for tests (from #39)
- Whether `parse-off-cooperative-pool` and `shared-codex-rollout-scan` fold into the spec (from #39)
- What `is_active` means in the Claude `limits` entries and whether it affects the headline or row style (from #40)
- Whether `severity` feeds the threshold level or stays ignored (from #40)
- The stable configuration key for a Claude window (headline choice, threshold state) (from #40)
- Whether Claude's weekly window is named "weekly" to match Codex or keeps "7-day" (from #40)
- Which `group` values map to lengths besides `weekly`, and the bar tag for an unknown group (from #40)
- Whether a window with `scope.surface` is shown like a model limit or ignored (from #40)
- Which screenshots and website data files change with the 5-hour row gone (from #40)

## Parked Ideas
- Translucent dropdown (#35)
  Reason: a custom MenuBarExtra window cannot get the system's menu glass; waits for the dropdown in a real NSMenu (#36), where an opt-in "Opaque background" is planned to replace its toggle. Spec 036 and its walkthrough results are on branch `036-translucent-dropdown`.

Brainstorm 28 (default window setting) is rejected: spec 027's saved dropdown choice already serves as a per-account default, and hiding the marker and tag removed information; see its Rejection section.

Spec 022 (`022-move-repo-org`, an earlier draft for the repository location) is abandoned; the repository location was part of #22 (name the app AgentTacho, now in `attic/`).

Archived sessions 01 to 16 and 22 are in `attic/`; each has its spec in `specs/`. New ideas wait in `idea-inbox.md`.
