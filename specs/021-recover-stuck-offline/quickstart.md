# Quickstart: Recover From a Stuck Offline State

## Automated checks

```bash
make test   # NetworkFailureDetail, FailureCategory.isNoAnswer, EndpointPolicy, SubscriptionSource, CodexLimitsSource, RefreshCoordinator, client session tests
make app
```

## Manual checks

1. Start the build, turn Wi-Fi off, wait for a refresh: the dropdown shows the usual "unreachable" note; the log line ends with `[NSURLErrorDomain -1009; ...]`.
2. Turn Wi-Fi on and click "Refresh now" within a minute: the log shows a fetch for the no-answer accounts and fresh values appear.
3. Toggle the WireGuard VPN on and off while AgentMeter runs: the next request succeeds without a restart (SC-004 smoke test).
