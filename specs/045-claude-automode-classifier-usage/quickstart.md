# Quickstart: validating classifier usage

## Automated

```bash
make test           # parser, probe, index, attribution and end-to-end tests (SC-001 to SC-005)
make test-release   # release-path checks, unchanged by this feature
```

Key tests:

- `SessionLogSourceClassifierTests`: the probe fixture (three main records, two classifier rows) gives 149,792 tokens on the session's account (SC-001); ten unchanged refreshes give identical totals, N appended rows add exactly N (SC-002); no decision log gives the same totals as before (SC-003); overlapping sessions on two accounts leave the row unassigned (SC-005).
- `ClassifierLogIndexTests`: the 50-directory steady-state timing under 50 ms (SC-004), partial last line, replaced and deleted file.
- `DecisionLogProbeTests`: a probe that never returns yields `.timedOut`, then `.busy` on the next refresh, and never a second concurrent check.

## By hand

1. Enable the log for one Claude Code profile: `aprofile features claude/<name>` with the decision-log feature, then `aprofile sync`; or add `"AUTOMODE_DECISION_LOG": "1"` to the `env` block of that profile's `settings.json`.
2. Start a Claude Code session in Auto mode in a scratch directory and let it run two or three tool calls.
3. Check that `<scratch>/.automode_decisions.jsonl` exists and has rows with token counters.
4. Open AgentTacho and refresh. In `~/Library/Logs/agenttacho/usage.log` (the diagnostic log), the `sessionLogs` line reports `decision logs read 1` with the row counts.
5. The account's token total grows by the sum of the rows' counters, in the same model row as the session (no separate `[1m]` model).
6. Delete the decision log and refresh: the total drops back by the same amount.
