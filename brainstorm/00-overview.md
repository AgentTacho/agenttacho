# Brainstorm Overview

Last updated: 2026-10-19

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

## Parked Ideas
- None

Spec 022 (`022-move-repo-org`, an earlier draft for the repository location) is abandoned; the repository location was part of #22 (name the app AgentTacho, now in `attic/`).

Archived sessions 01 to 16 and 22 are in `attic/`; each has its spec in `specs/`. New ideas wait in `idea-inbox.md`.
