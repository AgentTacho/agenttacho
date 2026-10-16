# Quickstart: Pace Line Names the Plan

## Automated checks

```bash
make test   # RefreshPaceStatusTests: one plan (each), both, timer reasons, other day, 12 hour
make app
```

## Manual check

With adaptive refresh on, use Claude Code and leave Codex idle for longer than one stretch step (spec 016), then open the dropdown: the line reads "Codex limits next checked at <time> (no Codex activity)". The diagnostic log shows `pace: codex interval ... (no agent activity)` for the same moment.

Longest case (FR-007): with the Mac set to a 12 hour clock, both plans slowed and the next check on another day, the line wraps to two lines and the reason "(no agent activity)" stays fully visible.
