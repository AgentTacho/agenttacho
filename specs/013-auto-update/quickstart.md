# Quickstart: Auto-Update Validation

## 1. Unit tests

```bash
make test           # UpdateTests suites: version, evaluator, policy, schedule, host policy, disk image, verdict, Homebrew, config
make test-release   # release script guards, including UPDATE_TEST refusal
```

Expected: all pass. The tampered-input cases of SC-003 are covered by `UpdateVerification` and `DiskImageCheck` tests.

## 2. End to end with a scratch repository (FR-025)

Prerequisites: Developer ID certificate and notary profile (README "Releasing"), `gh` logged in, a scratch repository such as `rhuss/agenttacho-update-test`.

1. Build a newer release DMG locally: create an unpushed tag `v0.9.0` on a clean checkout of this branch and run `make dmg` (a dry run, which does not notarize). Then, in `build/release/`:
   - notarize and staple it: `bash scripts/release/notarize.sh build/release/AgentTacho-0.9.0.dmg` (stapling changes the file);
   - recompute the checksum: `(cd build/release && shasum -a 256 AgentTacho-0.9.0.dmg > AgentTacho-0.9.0.dmg.sha256)`;
   - regenerate the release information with the final checksum and `notarized: true`: `jq -n --arg v 0.9.0 --arg s "$(awk '{print $1}' build/release/AgentTacho-0.9.0.dmg.sha256)" '{version:$v, dmg:"AgentTacho-\($v).dmg", sha256:$s, tier:"developer-id", notarized:true}' > build/release/release-info.json`.
2. Publish it to the scratch repository: `gh release create v0.9.0 -R rhuss/agenttacho-update-test build/release/AgentTacho-0.9.0.dmg build/release/AgentTacho-0.9.0.dmg.sha256 build/release/release-info.json`.
3. Delete the local tag, then `make app-update-test UPDATE_SOURCE=rhuss/agenttacho-update-test` and copy `build/AgentTacho.app` to `~/Applications` (a folder you can write to). Quit any other AgentTacho and start this copy.
4. Choose "Check for Updates…": the line reads "AgentTacho 0.9.0 available" with Install and Release notes.
5. Click Install and time it: progress, then the app quits and 0.9.0 starts from `~/Applications` in under one minute (SC-002); the old copy is in the Trash; notification permission and start at login still work (SC-004); macOS shows no "prevented from modifying apps" prompt. Repeat once with the update-test build started as a login item (log out and in) to confirm the relauncher still opens the new version.
6. Negative runs (each with a fresh update-test build): upload a DMG whose `release-info.json` has a wrong `sha256` (expect "checksum" reason, nothing replaced); start the app from a mounted DMG (expect Download with "Move AgentTacho to Applications…"); `chmod a-w ~/Applications` (expect "cannot replace itself").

## 3. Homebrew

With AgentTacho installed by `brew install --cask rhuss/tap/agenttacho` at an older version: the line shows "Upgrade with Homebrew"; clicking it copies the command and shows the hint; no file in `/Applications/AgentTacho.app` changes (SC-006).

## 4. Toggle and development build

- Turn off "Check for updates automatically", restart, watch `~/Library/Logs/agenttacho/usage.log`: no `update` check lines except after "Check for Updates…" (SC-005).
- `make app` and run: "Check for Updates…" says "Development build: updates are not checked" and the log shows no request (SC-007).
