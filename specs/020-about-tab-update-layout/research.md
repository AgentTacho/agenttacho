# Research: About Tab Update Layout

## R1: Shape of the update block in About

- **Decision**: A centered `VStack` with the "Check for Updates…" button first, then the status `HStack` (`UpdateStatusText` plus `UpdateButtons`), then the optional known-update `HStack`. Each `UpdateStatusText` gets `.foregroundStyle(.secondary)` at body size; the style goes on the text, not the row, so `UpdateButtons` (`.buttonStyle(.link)`) keeps its link color without relying on how link buttons treat an inherited foreground style. `.multilineTextAlignment(.center)` and `.frame(maxWidth: 520)` stay, so long errors wrap centered (FR-003, FR-004, FR-005).
- **Rationale**: Reuses the existing `UpdateStatusText` and `UpdateButtons` unchanged, so every state keeps its text and actions (SC-003) and the dropdown line is untouched (FR-010).
- **Alternatives considered**: Caption-size status like the dropdown line (rejected in clarification: errors and links get hard to read); a new shared view for the block (no second user, YAGNI).

## R2: What happens to `AppVersionInfo.Signing.text`

- **Decision**: Keep `Signing.text`. Besides the About row it feeds `InstallContext.logSummary` (`signing=...` in the diagnostic log, spec 013 FR-021), which `Updater` writes on every check. Only the `AppVersionInfo` doc comment changes: the signing tier is read by the update policy and the diagnostic log, not shown on the About tab.
- **Rationale**: Removing it would break the `UsageCore` build or force a new log format, for no user benefit.
- **Alternatives considered**: Remove it and log a tier token instead (changes the log format, needs a new test; rejected).

## R3: Where the toggle goes in General

- **Decision**: `Section("Updates") { Toggle("Check for updates automatically", isOn: $draft.checksForUpdates) }` directly after `Section("Launch")`, before `Section("Notifications")`. `AboutSettingsTab` loses its `draft` binding; its call site in `SettingsView` passes only the updater.
- **Rationale**: The General tab already applies every change through the same `draft`, so apply, discard, undo and reload behave as for "Start at login" (FR-009) with no new code path.
- **Alternatives considered**: The toggle inside "Launch" (offered in the brainstorm, not chosen).
