# Quickstart: Adaptive Refresh

## Automated

```bash
make test
```

Covers the contract tables in [contracts/refresh-pace.md](contracts/refresh-pace.md): `AdaptivePaceTests` (P, T, D and L rows as pure values), the new `RefreshCoordinatorTests` cases (P1, P2, P6, P8, D3, U2, U3 with stub sources and a fake clock), `EndpointPolicyTests` (the new triggers are spaced and never touch `retryUsed`), `CodexLimitsSourceTests` (`codexPaceDue` and the new triggers), and `ConfigurationTests` (`adaptiveRefresh` decoding and its load note).

## By hand (built app)

```bash
make app && open build/AgentMeter.app
tail -f ~/Library/Logs/agentmeter/usage.log
```

1. **Dropdown open**: wait 2 minutes after a refresh, then open the dropdown. The log shows `trigger dropdownOpen, endpoint fetched`. Close it and reopen at once: the refresh, if any, logs `endpoint reused (last fetch ... s ago)`.
2. **No agent activity**: leave Claude Code and Codex idle for 40 minutes. The scans log every 5 minutes, and the log shows `pace: claude interval 600 s (no agent activity)`, then 1200 and 1800, with `endpoint reused (adaptive pace ...)` in between (for Codex: `pace: codex interval ...` and `pace: codex reused (adaptive pace, next call ...)`). The dropdown shows `Plan limits next checked at ... (no agent activity)`.
3. **Activity returns**: run one Claude Code prompt. The next scheduled refresh logs `endpoint fetched` and `pace: claude interval back to base (activity)`.
4. **Low Power Mode**: turn it on in System Settings > Battery. The log shows `pace: timer 600 s (Low Power Mode)`, and the dropdown line names Low Power Mode.
5. **Idle**: lock the screen for a few minutes and unlock it. The log shows the idle timer, then an `idleReturn` refresh within a minute of unlocking.
6. **Toggle off**: in Settings > General, turn off "Adapt refresh". Refreshes and endpoint calls return to every 5 minutes, the dropdown line disappears, and opening the dropdown starts no refresh.
