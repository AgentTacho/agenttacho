# Quickstart: LLM Usage Menu Bar

## Prerequisites

- macOS 14 or newer on Apple Silicon, Xcode command line tools with Swift 5.10+ (`swift --version`).
- Claude Code installed and signed in with a subscription (for User Story 1), and some session logs under `~/.claude/projects` (for User Story 2).

## Build and test

```bash
swift build                 # builds UsageCore and the executable
swift test                  # runs UsageCoreTests (parsing, pricing, windows, attribution, thresholds)
make app                    # assembles build/LLM Usage.app with Info.plist (LSUIElement) and ad-hoc signature
make run                    # launches the bundle; first keychain read shows a macOS consent dialog, click Always Allow
```

## Validation scenarios

### S1: Subscription percent appears without configuration (US1, SC-001)
1. Remove any existing config: `rm -f ~/.config/llm-usage-menubar/config.json`.
2. `make run`. Within 60 seconds the bar shows `M <n>%`.
3. Click the item. Expect the 5-hour and 7-day rows with percent and local reset time. Compare with `/usage` inside Claude Code: within 1 point (SC-002).
4. Disconnect the network and click "Refresh now". Expect the same values marked stale and an error line with the last successful time.

### S2: Vertex spend against a weekly budget (US2, SC-003)
1. Open Settings from the dropdown, add a token-based account (label `VC`, provider Vertex) in a new group "Vertex" (label `V`, budget 60; labels are unique across accounts and groups). Save.
2. Click "Refresh now". The dropdown shows `$x.xx of $60.00 (n%)` and the window end.
3. Cross-check: run the fixture script `scripts/sum-vertex.sh` (planned test helper) or a manual `jq` sum over `req_vrtx_` records inside the window with the built-in prices; results agree within 1 cent.
4. Add a price override for one model in Settings and refresh; the spend changes accordingly.

### S3: Configuration round trip (US3)
1. In Settings set refresh interval to 30 seconds. Expect a validation message naming the 60-second minimum.
2. Enter a 4-character label. Expect rejection.
3. Edit `config.json` by hand to make it invalid JSON. Click "Refresh now". The dropdown shows a configuration error and the previous values remain.

### S4: Threshold notifications (US4, SC-006)
1. Set a threshold on the Vertex group just above the current percent.
2. Append a synthetic assistant record with `req_vrtx_` to a test JSONL file inside `~/.claude/projects/<any>/` with enough output tokens to cross it. Refresh. One notification appears.
3. Refresh again. No second notification.

### S5: Breakdown and trend (US5)
1. Expand the Vertex group in the dropdown. Expect one row per model with token categories and cost summing to the group total, and one entry per day of the window with zeros for idle days.

## Results recorded during implementation (2026-10-13)

### S1
- Launched from the bundle with no config file. The default configuration with one subscription account `M` was created, and the first refresh logged `5h 24%, 7d 55%`. Verified through `~/Library/Logs/llm-usage-menubar/usage.log` and `config.json`, not by looking at the bar (no human at the screen during the implement stage).
- Keychain consent: every rebuild changes the ad-hoc code signature, so macOS shows the consent dialog again on the next launch. While the dialog is open the subscription fetch blocks (the refresh does not finish until it is answered). A developer certificate would make the signature stable.

### S2
- With account `VC` (Vertex) in group `V` (budget 60) the app logged `group V: [amount] of 60 USD ([n]%)` for the fallback window `2026-10-11T22:00:00Z` to `2026-10-18T22:00:00Z`.
- `scripts/sum-vertex.sh 2026-10-11T22:00:00Z 2026-10-18T22:00:00Z ~/.claude` returned `totalUSD: [amount]` over 1308 deduplicated records (all `claude-opus-4-8`): identical to the cent (SC-003).
- The first full scan over 9,684 files read 126 changed files (190 MB) in 7.3 s (SC-004 target 10 s).
- Steps 1 and 4 (settings window) are covered by Phase 5; this run configured the account by editing `config.json` by hand, and the subscription account was removed for the run so the keychain dialog could not block it.

### S3
- Steps 1 and 2 (settings validation) need a human at the settings window and were not exercised during the implement stage; the validator behind the Save button is the same `Configuration.validate()` covered by `ConfigurationTests` (interval below 60 s and labels longer than 3 characters are rejected with a message).
- Step 3 verified from the bundle: with `config.json` overwritten by invalid JSON the next refresh logged `config error: Configuration file could not be decoded: The given data was not valid JSON.` while the group line still showed the previous values (`group V: [amount] of 60 USD ([n]%)`).

### S4
- Group `V` at [n]% with a threshold just above it. A synthetic `req_vrtx_` record (100,000 output tokens of `claude-opus-4-8`, 2.50 USD) was written into an extra configured log directory. The next refresh logged `group V: [amount] of 60 USD ([n]%)`, `crossing: Vertex weekly weekly [threshold]% (now [n]%)` and `sent: ...`. The refresh after that logged no further crossing (SC-006 at the app level). Whether macOS displayed the banner was not observed (the notification permission prompt needs a click).

### S5
- Not observed in the UI. `AggregatorTests` pin the per-model rows summing to the group total and the zero-filled per-day trend (7 entries for a window on day boundaries, 8 when it starts mid-day, 7 across the DST change).

### Performance (T058, SC-004 and SC-008)
- Setup: 9 accounts (1 Vertex plus 8 token-based accounts with non-matching custom markers) in 9 groups, refresh interval 60 s, `~/.claude` plus one extra log directory, 9,693 to 9,709 session files on disk, subscription account removed so the keychain dialog could not block refreshes.
- Full refresh at launch (135 changed files, 200 MB read, 3,590 records in the window): 3.7 s after parallelizing file parsing (10.8 s before). Target 10 s.
- Incremental refresh (2 changed files): 0.26 to 0.32 s; over 59 timed refreshes in the hour the median was 0.29 s and the maximum 1.86 s. Target 1 s.
- One hour of `top -l 2` samples every 60 s with a refresh every minute: average CPU 0.23%, resident memory 43 to 76 MB (average 61 MB). Targets 1% and 100 MB.

### SC-005 (add an account from the settings window in under 2 minutes)
- Not measured: needs a human driving the settings window.

### Automated coverage
`swift test` must cover: JSONL parsing with a truncated last line, dedupe by message id, provider detection by request id prefix, custom marker, price normalization (`-YYYYMMDD` and `@YYYYMMDD` suffixes, prefix fallback, unpriced), window alignment and weekday fallback including rollover, group aggregation across members, per-day zero filling, threshold crossing semantics including the launch baseline and window reset, and config validation rules.
