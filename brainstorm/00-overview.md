# Brainstorm Overview

Last updated: 2026-10-20

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 17 | 2026-10-16 | account-budget-subtitle | active | - | - |
| 18 | 2026-10-16 | landing-page | approved | - | - |
| 19 | 2026-10-16 | pace-line-names-plan | active | - | - |
| 20 | 2026-10-16 | about-tab-update-layout | active | - | - |
| 21 | 2026-10-16 | recover-stuck-offline | active | - | - |
| 23 | 2026-10-18 | minimal-dropdown | spec-created | 025 | - |
| 24 | 2026-10-18 | readable-dialog-shots | active | - | - |
| 25 | 2026-10-19 | dropdown-layout-polish | active | - | - |
| 26 | 2026-10-19 | headline-window-switch | active | - | - |
| 27 | 2026-10-19 | section-bands | spec-created | 028 | - |
| 28 | 2026-10-19 | default-window-setting | rejected | - | - |
| 29 | 2026-10-20 | threshold-levels-direction | active | - | - |
| 30 | 2026-10-20 | site-reframe-screenshots | active | - | - |

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
- Whether the demo scenario fills the Groups, Menu Bar and Prices panes richly enough for a tight crop to read (from #24)
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
- Exact target aspect and margin for the card captures (from #30)
- Names, directories and levels of the two Claude Max demo accounts (from #30)
- Whether two Claude entries make the menubar shot too wide for the hero strip (from #30)
- Whether the glance shot stays readable with Details expanded at card size (from #30)
- Whether capture.sh drops its notification checks once the alert shot is gone (from #30)
- Whether the groups shot disappears entirely (from #30)

## Parked Ideas
- None

Brainstorm 28 (default window setting) is rejected: spec 027's saved dropdown choice already serves as a per-account default, and hiding the marker and tag removed information; see its Rejection section.

Spec 022 (`022-move-repo-org`, an earlier draft for the repository location) is abandoned; the repository location was part of #22 (name the app AgentTacho, now in `attic/`).

Archived sessions 01 to 16 and 22 are in `attic/`; each has its spec in `specs/`. New ideas wait in `idea-inbox.md`.
