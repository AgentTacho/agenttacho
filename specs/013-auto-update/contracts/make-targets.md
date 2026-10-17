# Contract: Update-Test Build (FR-025)

## `make app-update-test`

```bash
make app-update-test UPDATE_SOURCE=<owner>/<repo>
```

- Runs `scripts/release/build-app.sh` with `UPDATE_TEST=1` and `UPDATE_SOURCE`.
- Fails when `UPDATE_SOURCE` is empty or not `owner/repo` (`^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$`).
- Compiles with `-Xswiftc -DAGENTTACHO_UPDATE_TEST`, stamps `AgentTachoUpdateSource` into Info.plist, signs like `make app`, and prints "update-test build, release source <owner>/<repo>".
- Output: `build/AgentTacho.app` (same place as `make app`).

## Guards

- `scripts/release/release.sh` (also `make dmg` and `make release`) dies with "UPDATE_TEST is set; release builds never carry the update-test flag" when `UPDATE_TEST` is non-empty.
- `make app` exports no `UPDATE_TEST`; build-app.sh compiles the flag only when `UPDATE_TEST=1`.
- A build without the flag never reads `AgentTachoUpdateSource`.

Covered by `make test-release` (scripts/release/tests).
