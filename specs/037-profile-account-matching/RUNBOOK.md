---
runbook_version: 1
feature: 037-profile-account-matching
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: d603b92
drafted_fingerprint: 8d2c84a85ae5cde22907d3c202f58e7f6346451f99f46041654650c60dd26dc9
tested_at: 0064ff0
tested_fingerprint: 8d2c84a85ae5cde22907d3c202f58e7f6346451f99f46041654650c60dd26dc9
updated: 2026-10-27
---

# Try it: Account Matching by Profile and Match Rules

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (9 passed) · Mode: light · Tested at 0064ff0 · 2026-10-27
<!-- /runbook-status -->










## What you're testing

A build of this branch runs with your real configuration and your real Claude Code sessions. The journey: back up the configuration, build and start the app, check in the diagnostic log that your token-based accounts were migrated and that session files name their profile, see in the dropdown that each profile's usage lands on its own account, give the gateway account a custom rule in Settings, provoke and clear the overlap warning, check the saved configuration, and optionally restore the backup.

Your configuration and usage stay on this Mac. Nothing in this runbook writes to the agents' files.

## Test environment

No fixtures. The journey uses the installed app's configuration (`~/.config/agenttacho/config.json`), a backup of it in this spec's `.walkthrough` folder, and a local build of the app (`make app`).

## Steps

### Step 1 of 9: Back up the configuration (US4)

**Why this step:** the new build migrates token-based accounts and writes the new form on the next save; the backup lets you go back to the installed release.

**Run:**

```
mkdir -p specs/037-profile-account-matching/.walkthrough && cp ~/.config/agenttacho/config.json specs/037-profile-account-matching/.walkthrough/config-before.json && ls -l specs/037-profile-account-matching/.walkthrough/config-before.json
```

**What you should see:** one line listing `config-before.json` with the same size as your configuration file.

**If you see something else:** "No such file" means the configuration lives elsewhere or does not exist yet; stop here.

**Result:** passed (agent). `config-before.json` 3.4K, same as `~/.config/agenttacho/config.json` 3.4K.

### Step 2 of 9: Build the app from this branch (US1)

**Why this step:** the walkthrough needs the new attribution and Settings code.

**Needs:** Step 1.

**Run:**

```
make app && ls -d build/AgentTacho.app
```

**What you should see:** the build finishes without errors and prints `build/AgentTacho.app`.

**If you see something else:** a compiler error means the branch does not build on this machine; record it and stop.

**Result:** passed (agent). `make app` exit 0, `Built build/AgentTacho.app`, 0 errors; log in `.walkthrough/step-2.log`.

### Step 3 of 9: Start the new build instead of the installed app (US1)

**Why this step:** only one AgentTacho may run at a time.

**Needs:** Step 2.

**Run:**

```
osascript -e 'quit app "AgentTacho"' ; sleep 2 ; open build/AgentTacho.app
```

**What you should see:** the installed app's menu bar item disappears and the new build's item appears after a few seconds.

**If you see something else:** if the old item stays, quit it from its dropdown and run `open build/AgentTacho.app` again.

**Result:** passed (agent). Installed app quit; process now runs from `build/AgentTacho.app/Contents/MacOS/AgentTacho`.

### Step 4 of 9: Check the migration in the diagnostic log (US4)

**Why this step:** every token-based account from before this feature is migrated once per load, and the log says so.

**Needs:** Step 3.

**Run:**

```
rg -n "migrated from provider" ~/Library/Logs/agenttacho/usage.log | tail -5
```

**What you should see:** one line per token-based account of the last launch, for example `account "Claude Code via Vertex" migrated from provider vertex to harness Claude Code`.

**If you see something else:** no lines means the configuration was already in the new form or the log path differs; check `ls ~/Library/Logs/agenttacho/`.

**Result:** passed (agent). Two lines: `account "Claude Code via Vertex" migrated from provider vertex to harness Claude Code` and the same for the gateway account.

### Step 5 of 9: Check that session files name their profile (US1)

**Why this step:** the profile step only works when the request shape lines name a configured Claude Code directory; the refresh log counts them.

**Needs:** Step 3, one refresh (wait about a minute or click refresh in the dropdown).

**Run:**

```
rg -n "profile named" ~/Library/Logs/agenttacho/usage.log | tail -1
```

**What you should see:** a Claude Code refresh line ending in `profile named N, none M, ...` with N greater than 0 (on the first refresh after launch, N covers the recent session files read).

**If you see something else:** `profile named 0` for every refresh means no configured directory appears in the shape lines; compare the accounts' Claude Code directories with the paths your profiles use.

**Result:** passed (agent). `[sessionLogs] directories read 3, files seen 11043, re-read 2156 (...), profile named 186, none 1970, 12.744 s`. The first search ran before the launch refresh finished and found nothing; rerun after it.

### Step 6 of 9: See each profile's usage on its own account (US1)

**Why this step:** this is the reported problem: Vertex usage of one profile and the gateway profile's usage used to land in Unassigned.

**Needs:** Step 5.

**Do:**

1. Open the dropdown.
2. Look at the Vertex section, the gateway account's section and the Unassigned section.

**What you should see:** the Vertex section shows spend again (not 0 of its budget), the gateway account's section shows its usage (it may say "incomplete, unpriced" for models without a price, which is expected), and Unassigned is gone or much smaller than before.

**If you see something else:** usage still in Unassigned may come from sessions older than the profile signal; Step 7 gives the gateway account a rule for those.

**Result:** passed (user). Vertex shows spend again, the gateway account shows its usage, Unassigned gone or small.

### Step 7 of 9: Give the gateway account a custom rule (US2)

**Why this step:** older sessions and sessions without a profile signal find their account through the rule.

**Needs:** Step 6.

**Do:**

1. Open Settings > Accounts and select the gateway account.
2. Check that "Harness" shows Claude Code and that "Session matching" shows the rule pop-up with "Vertex" (the migrated value), "Custom" and "None (profile only)".
3. Choose "Custom", set "Field" to "Model" and enter the model prefix your gateway uses. Settings saves about 0.6 s after each change; there is no Apply button.

**What you should see:** the Session matching section shows the field pop-up and text field, no "Not applied" line appears, and after the next refresh the gateway account's section includes the older gateway sessions too.

**If you see something else:** a "Not applied" line saying the rule needs a text means the field is blank.

**Result:** passed (user). Harness Claude Code, rule pop-up with Vertex, Custom and None (profile only); custom rule Model / the gateway's model prefix set. Correction (FR-026): Settings has no Apply button; it saves about 0.6 s after each change.

### Step 8 of 9: Provoke and clear the overlap warning (US3)

**Why this step:** two token-based accounts that neither the profile nor the rule can separate used to drop to Unassigned silently; Settings now warns.

**Needs:** Step 7.

**Do:**

1. In the gateway account, set the rule back to "Vertex" and its Claude Code directory to the Vertex account's directory (both are needed; Settings saves each change).
2. Read the Session matching section.
3. Restore the directory and the custom rule by hand.

**What you should see:** after step 1, a caption with a warning symbol says that records matching both this account and the Vertex account stay Unassigned; after step 3 the warning is gone.

**If you see something else:** no warning in step 1 means the directories still differ (an empty field counts as `~/.claude`).

**Result:** passed (user, second try). With the gateway account on the Vertex account's directory and the Vertex rule, the caption "Records that match both this account and \"Claude Code via Vertex\" stay Unassigned. Give one of them another rule or, for Claude Code, another directory." shows with a warning symbol; after restoring directory and rule it is gone. The first try showed no warning because the agent's paraphrase left out the shared directory (the two accounts use different profile directories, so they never overlap). Correction (FR-026): there is no "do not apply"; every change saves, so the restore must be done by hand.

### Step 9 of 9: Check the saved configuration (US4)

**Why this step:** after Step 7's apply, the file holds the new form: `harness` and `matchRule`, and neither `provider` nor a token-based `customMarker`.

**Needs:** Step 7.

**Run:**

```
jq '.accounts[] | select(.type == "tokenBased") | {displayName, harness, matchRule, provider, customMarker}' ~/.config/agenttacho/config.json
```

**What you should see:** after Step 8's restore, every token-based account has `harness` and `matchRule`; `provider` and `customMarker` are `null`. The gateway account shows `{"type": "custom", "field": "model", "text": ...}`.

**If you see something else:** a `provider` key means the file was not saved by the new build yet; apply any Settings change and run the step again.

**Result:** passed (agent, after the restore was redone). Both token-based accounts have `harness` and `matchRule`, `provider` and `customMarker` null; the gateway account has `{"field": "model", "text": "[gateway prefix]", "type": "custom"}`. The first read still showed the overlap state from Step 8, since the restore had not been made yet.

## Not covered here

- **Budget group across harnesses (US5):** needs Vertex usage from OpenCode on this Mac; the aggregator test covers it.
- **Going back to the installed release:** optional after the walkthrough. Quit the new build, then `cp specs/037-profile-account-matching/.walkthrough/config-before.json ~/.config/agenttacho/config.json` and start the installed app. The installed release reads the new form only partly (a token-based account without `provider` counts as Vertex), so restore the backup before switching back.

## Coverage

- US1: Steps 2, 3, 5, 6.
- US2: Step 7.
- US3: Step 8.
- US4: Steps 1, 4, 9.
- US5: not covered (see above).

## Results

9 steps: 9 passed, 0 failed, 0 skipped. Migration, profile attribution (186 files named a configured directory), the custom rule and the overlap warning all work with the real configuration. The two first-try misses (Step 5 timing, Step 8 missing shared directory) were runbook or agent errors, not defects; Steps 7 and 8 were corrected for the auto-saving Settings window. The backup `config-before.json` is in `.walkthrough` for going back to the installed release.
