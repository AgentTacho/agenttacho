# Contract: Settings Layout (spec 020)

## Settings > About

Top to bottom, centered:

1. Icon, "AgentMeter", tagline.
2. Release grid: Version, Commit, Built (each only when stamped). No Signing row (FR-002).
3. `Check for Updates…` button, disabled while an install runs (FR-003, FR-006).
4. Status line: the state's settings text and its actions, body size, secondary color, links in link style, centered, wrapping (FR-003, FR-004).
5. Optional second status line: a known update next to a failed manual check, with its actions (FR-005).
6. "What's new in X.Y.Z", release notes link, link row, footer (unchanged).

No "Updates" heading and no toggle (FR-001, FR-007).

```text
        Version  0.4.1 (build 114)
         Commit  e92b5f0
          Built  16. October 2026 at 12:47

           [ Check for Updates… ]
         Up to date (checked 14:02)
```

## Settings > General

Sections in order: Refresh, Weekly window, Launch, **Updates**, Notifications, then the directory lists. "Updates" holds one toggle, "Check for updates automatically", bound to the Settings draft (`checksForUpdates`), without a caption (FR-008, FR-009).
