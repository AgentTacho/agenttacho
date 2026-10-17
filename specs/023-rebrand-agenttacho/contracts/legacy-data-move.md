# Contract: One-time move of AgentMeter's settings

Spec FR-008 to FR-012, FR-027. Data shapes in [data-model.md](../data-model.md).

## When it runs

Once per launch, in `AppModel.init(paths:)`, after the diagnostic log exists and before any store reads its file. `SingleInstance.ensure()` has run before (it runs in `AgentTachoApp.init()`), so a running AgentMeter was either stopped or AgentTacho has quit.

## Decision table

| New config folder | Legacy files present | Outcome | Files written |
|---|---|---|---|
| exists (even empty) | any | `.skipped` | none |
| missing | none | `.nothingToMove` | none (folders are created later by the stores as today) |
| missing | some or all | `.moved(copied, failed)` | each present legacy file, under its own name in the new folder |

## Guarantees

1. No file or folder under `~/.config/agentmeter/`, `~/Library/Logs/agentmeter/` or `~/Library/Application Support/agentmeter/` is created, changed, renamed or deleted (checked by tests that compare the legacy tree before and after).
2. A destination file is either absent or a complete copy of its source. A destination file that already exists (possible only when the configuration folder was deleted by hand while another new folder stayed) is replaced as a whole with `FileManager.replaceItemAt`.
3. A legacy name that is a symbolic link is followed and the bytes of its target are copied; a legacy name that is not a regular file (a folder, a FIFO, a dangling link) is a failure `not a regular file`, read without blocking (RegularFile, shared with LastGoodStore); files larger than 16 MB are a failure `larger than 16 MB`. A destination folder that resolves into one of AgentMeter's three folders, also through a linked parent of a folder that does not exist yet, is a failure `the destination is one of AgentMeter's folders`. Copies are written with mode 0600; the Application Support folder is created with 0700, and an existing one only loses permissions (added in code review).
4. A failure of one file does not stop the others; each failure is reported with the file name and the error's description.
5. Content is not parsed; validation stays with the stores (spec 001 for the configuration, spec 002 for imported prices, spec 010 for last good values).
6. No UI: no alert, notification or dropdown line (FR-027). Only the log lines in data-model.md.
7. After any `.moved` outcome the new configuration folder exists (it is created for `config.json`, or for the first copied file in that folder; if only `last-good.json` was present, the configuration folder is created empty), so the move never runs again.

## Tests (UsageCoreTests, temporary home directories)

- All three legacy files present, new folder missing: three copies, identical bytes, legacy tree unchanged.
- Only `config.json` present: one copy, others absent in the new folders.
- Only `last-good.json` present: one copy, and the new configuration folder exists afterwards.
- New configuration folder exists and is empty: `.skipped`, nothing copied.
- No legacy files: `.nothingToMove`, no new folder created.
- Destination not writable (read-only parent): `.moved` with a failure, no file at the destination name, no temporary file left behind.
