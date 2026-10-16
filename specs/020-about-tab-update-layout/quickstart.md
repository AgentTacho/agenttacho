# Quickstart: About Tab Update Layout

1. `make test`: all tests pass (SC-004).
2. `make app`, launch the app, open Settings > About: Version, Commit, Built, no Signing row; a centered "Check for Updates…" button with the status line below it in secondary text; no "Updates" heading, no toggle ([contract](contracts/settings-ui.md)).
3. Press "Check for Updates…": the status shows "Checking for updates…", then the result (a development build shows "Development build: updates are not checked").
4. Open Settings > General: "Updates" follows "Launch" with "Check for updates automatically". Switch it off, apply, quit, relaunch: still off, and the configuration file has `"checksForUpdates": false`. Switch it back on.
5. `rg -n "Settings > About" README.md specs/013-auto-update/spec.md specs/013-auto-update/contracts/update-ui.md specs/013-auto-update/RUNBOOK.md`: no passage places the toggle or the signing tier in About (FR-011, FR-012). The research and tasks files of spec 013 are historical records and stay as they are.

SC-003 holds by construction: the status line reuses `UpdateStatusText` and `UpdateButtons` and the same `UpdateState` texts unchanged, so states other than those of steps 2 and 3 (available, downloading, known update next to a failed check) need no extra step. To see them anyway, use the update-test build from spec 013 (`make app-update-test`, FR-025).
