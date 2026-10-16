# Quickstart: Fix-Soon Review Batch

## Automated checks

```bash
make test          # Swift Testing: threshold reset, period mismatch, scan set, OpenCode hardening, Claude timeout
make test-release  # release scripts: tier guard and draft-first replacement
```

Expected: both pass. The new tests are named after the spec requirements (`FR-001` ... `FR-017`).

## Manual checks

1. **Window reset notification**: with an 80% threshold on a 5-hour window close to 80%, sleep the Mac across the 5-hour reset while using Claude elsewhere until the new window is above 80%; on wake, one notification for 80% appears. The diagnostic log (Settings > Log) shows the crossing.
2. **Period switch with a failing source**: make every Claude Code log directory unreadable (for example `chmod 000 ~/.claude` on a test account, or point the configuration at directories that do not exist and rename the default), so the session log source reports "no log directory could be scanned"; switch a weekly group to monthly; the bar shows `…` for the group and the dropdown shows the group without amount, percent or period line until the directories are readable again. (An unreadable OpenCode database does not trigger this path; it is reported as a record batch issue.)
3. **Credential directory scan**: with a second Claude subscription account whose credential directory is `~/.claude-work`, remove it from the extra Claude Code directories; its sessions still count (compare the dropdown before and after).
4. **Release guard (no keychain change needed)**: `bash scripts/release/tests/run.sh` covers the expired and revoked cases with a stubbed `security` tool; see [contracts/release-command.md](contracts/release-command.md) for the expected messages.
