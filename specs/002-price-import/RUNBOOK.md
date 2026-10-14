---
runbook_version: 1
feature: 002-price-import
status: in_progress
mode: light
steps_total: 15
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,pending,pending,pending,pending,pending,pending
drafted_at: 987ae67
drafted_fingerprint: efcaef3bf365454930fd17318502cec27e7bec40cce2365d7b2291e0fc53f9d9
tested_at: 1777675
tested_fingerprint: c50048ee1583a394932aa8d241cb2189ed6d60ee9c1f08a065d98c650fad6b8a
updated: 2026-10-13
---

# Try it: Price Import

<!-- runbook-status -->
> **Status:** in_progress · 9 of 15 steps (9 passed) · Mode: light · Tested at 1777675 · 2026-10-13
<!-- /runbook-status -->










## What you're testing

AgentMeter can now import model prices instead of relying only on its built-in table and your manual overrides. Provider prices come from LiteLLM's public price list (Anthropic, OpenAI direct plus Vertex, Google Gemini) or from a CSV file. Every import shows a preview of what would change before it applies, applying re-prices your session logs without calling Anthropic's rate-limited usage endpoint, and each import can be removed again.

The journey: back up your real configuration, run the tests, start the branch build, import Anthropic prices and check the preview, the stored file and the log, see a manual override win over an import, import OpenAI prices with the collapsed list of unused models, import a CSV with a bad row, look at sources and the filter, export and re-import, remove the CSV import, try an import offline, simulate a damaged file, and finally restore your configuration.

All steps run from the repository root: `/Users/rhuss/Work/projects/llm-usage-menubar` (main, with the feature merged).

## Test environment

No fixtures. The journey uses the real app build from this branch and your real configuration directory `~/.config/llm-usage-menubar`, which step 1 backs up and the last step restores. Provider imports make one request each to raw.githubusercontent.com.

## Steps

### Step 1 of 15: Back up your configuration (setup)

**Why this step:** Imports write `imported-prices.json` and later steps damage it on purpose. A backup lets you return to exactly where you started.

**Needs:** nothing

**Run:**

```
rm -rf ~/.config/llm-usage-menubar.walkthrough-backup && cp -Rp ~/.config/llm-usage-menubar ~/.config/llm-usage-menubar.walkthrough-backup && ls ~/.config/llm-usage-menubar.walkthrough-backup
```

**What you should see:** `config.json` listed, and no `imported-prices.json` (it does not exist before this feature).

**If you see something else:** "No such file or directory" means the app never created a configuration; start the app once and repeat. An existing `imported-prices.json` means an earlier test run left one; it is part of the backup and will be restored.

**Result:**

Passed (agent ran it). Expected vs actual: `config.json` listed → `config.json  1.2K`; no `imported-prices.json` → none present.

### Step 2 of 15: Run the test suite (setup)

**Why this step:** Confirms the branch builds and all core logic (LiteLLM mapping, CSV parsing, diff, storage, reprice path) passes before you try the UI.

**Needs:** Step 1

**Run:**

```
make test 2>&1 | tail -3
```

**What you should see:** a line reporting 230 tests in 21 suites passed, and no failures.

**If you see something else:** "catalog not found" failures mean a stale test bundle; run `rm -rf .build/out/Products/Debug/UsageCoreTests.xctest` and repeat. Other failures are real regressions.

**Result:**

Passed (agent ran it). Output: 544 lines, saved to specs/002-price-import/.walkthrough/step-2.log. Expected vs actual: 230 tests in 21 suites pass → "Test run with 230 tests in 21 suites passed after 0.094 seconds."

### Step 3 of 15: Start the branch build of the app (setup)

**Why this step:** The menu bar app from main may still be running; it has to be replaced by this branch's build.

**Needs:** Step 2

**Run:**

```
pkill -x LLMUsageMenuBar; make app && open build/AgentMeter.app && sleep 3 && ps -o pid=,lstart=,command= -p $(pgrep -x LLMUsageMenuBar | paste -sd, -)
```

**What you should see:** "Built build/AgentMeter.app", then one process whose path is `/Users/rhuss/Work/projects/llm-usage-menubar/build/AgentMeter.app/Contents/MacOS/LLMUsageMenuBar`, with a start time of just now.

**If you see something else:** Two processes mean the old instance survived; quit it from its menu and repeat.

**Result:**

Passed (agent ran it). Expected vs actual: "Built build/AgentMeter.app" → present; one process from the main checkout started just now → `12877 Tue Oct 13 20:47:07 2026 /Users/rhuss/Work/projects/llm-usage-menubar/build/AgentMeter.app/Contents/MacOS/LLMUsageMenuBar` (single process).

### Step 4 of 15: Import Anthropic prices and read the preview (US1)

**Why this step:** The core promise: one action brings a provider's prices up to date, and you see every change before it applies.

**Needs:** Step 3

**Do:**

1. Open the AgentMeter menu and choose Settings. While here, check the settings window from the earlier session: it comes to the front, the title names the pane, and the panes have even margins. Then open the Prices pane.
2. Click the Import menu and choose "Anthropic prices (LiteLLM)".
3. Read the preview, then click Apply.

**What you should see:** A short loading indicator, then a summary like "5 new, 1 changed, 11 unchanged". Under Changed, `claude-sonnet-5-5` with cache read 0.2 → 0.1. New models you have not used are collapsed behind "N more new models". After Apply the sheet closes, Anthropic rows show "LiteLLM" with today's date in the Source column, and a status line reads "Anthropic prices from LiteLLM, imported today".

**If you see something else:** An error naming the network or HTTP status means the download failed; check connectivity. Different counts are fine if LiteLLM changed its list since 2026-10-13; the Sonnet 5.5 cache read change should still be there unless they fixed it.

**Result:**

Passed (user ran it in the app). The user confirmed the preview and the applied result match the expectation ("looks good"), including the settings window behavior from the earlier session.

### Step 5 of 15: Check the stored file and the log, and that no endpoint call happened (US1)

**Why this step:** Imports must live in their own file, log only counts, and re-price without calling the usage endpoint (FR-023a).

**Needs:** Step 4

**Run:**

```
jq -c '.batches[] | {kind, origin, importedAt, models: (.entries | length)}' ~/.config/llm-usage-menubar/imported-prices.json; tail -n 30 ~/Library/Logs/llm-usage-menubar/usage.log | grep -E '\[prices\]|reprice'
```

**What you should see:** One batch with `kind` "anthropic", the LiteLLM URL as origin, and about 17 models. In the log, one `[prices] imported 17 Anthropic prices from https://raw.githubusercontent.com/...` line with changed and new counts, then a subscription line starting with "reused for reprice" and a refresh line ending in "reprice (network sources reused)".

**If you see something else:** A subscription line without "reused for reprice" right after the `[prices]` line means the reprice path called the endpoint; that is a bug against FR-023a.

**Result:**

Passed (agent ran it). Expected vs actual (account id and usage percentages redacted):

- one `anthropic` batch with the LiteLLM origin and about 17 models → `{"kind":"anthropic",...,"importedAt":"2026-10-13T18:54:53Z","models":17}`
- `[prices] imported 17 Anthropic prices ...` → `[prices] imported 17 Anthropic prices from https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json (5 new, 1 changed, 0 removed)`
- subscription line starts with "reused for reprice" → `[subscription] reused for reprice, ok: 1 account(s) [redacted]=ok([redacted])`
- refresh line ends with "reprice (network sources reused)" → `[refresh] done in 0.357 s, 0 source error(s), window ... (aligned), reprice (network sources reused)`

All three log lines carry the same timestamp, so no endpoint call happened between apply and recomputation.

### Step 6 of 15: A manual override wins over an import (US1)

**Why this step:** Imports must never replace your own prices silently.

**Needs:** Step 4

**Do:**

1. In the Prices pane, click Override on `claude-opus-5-5` and change its input price to 9.
2. Wait a moment for the change to apply, then choose Import, "Anthropic prices (LiteLLM)" again.
3. Read the preview, then click Cancel.
4. Remove the override on `claude-opus-5-5` again (Remove button on its row).

**What you should see:** In the preview, `claude-opus-5-5` appears under Shadowed with "your override stays in effect", not under Changed. The summary has no changed Anthropic models other than ones LiteLLM changed since step 4 (usually none). After Cancel nothing changes; after Remove the row shows the LiteLLM source again.

**If you see something else:** `claude-opus-5-5` listed under Changed means the override would be ignored; that is a bug against FR-004.

**Result:**

Passed (user ran it in the app). The user confirmed `claude-opus-5-5` was listed under Shadowed with "your override stays in effect" and returned to the LiteLLM source after removing the override.

### Step 7 of 15: Import OpenAI prices (US1)

**Why this step:** OpenAI models (direct and on Vertex) have no built-in prices; the import should add them while keeping the preview readable.

**Needs:** Step 3

**Do:**

1. Choose Import, "OpenAI prices (LiteLLM, direct and Vertex)".
2. Look at the New section, expand "N more new models" once, then click Apply.
3. Switch the filter above the table to All and scroll for `openai/gpt-oss-120b-maas`.

**What you should see:** A summary with well over 100 new models. Models you used in this window (likely none) are listed directly; the rest sit behind "N more new models". After Apply, `openai/gpt-oss-120b-maas` and `gpt-6-sol` appear with Source "LiteLLM" under the All filter.

**If you see something else:** An error "no usable entries" would mean the OpenAI selection broke on a LiteLLM schema change.

**Result:**

Passed (user ran it in the app). The user confirmed the collapsed list of new models and that `openai/gpt-oss-120b-maas` and `gpt-6-sol` show Source "LiteLLM" after Apply.

### Step 8 of 15: Prepare a CSV file with one bad row (US2)

**Why this step:** The next step needs a CSV in German spreadsheet style (semicolons, decimal comma) with a deliberate error.

**Needs:** nothing

**Run:**

```
printf 'model;input;output\nclaude-test-model;2,50;10\n;1;1\n' > "$TMPDIR/agentmeter-prices.csv" && cat "$TMPDIR/agentmeter-prices.csv" && echo "$TMPDIR/agentmeter-prices.csv"
```

**What you should see:** The three lines of the file, then its full path (copy it for the open panel; in the panel press Cmd-Shift-G and paste).

**If you see something else:** An empty `$TMPDIR` would write to `/agentmeter-prices.csv`; use `/tmp/agentmeter-prices.csv` instead.

**Result:**

Passed (agent ran it). Expected vs actual: three file lines and the path → `model;input;output`, `claude-test-model;2,50;10`, `;1;1`, then `/var/folders/.../T//agentmeter-prices.csv`.

### Step 9 of 15: Import the CSV (US2)

**Why this step:** CSV prices fill gaps in the public list; bad rows must be reported, not silently dropped, and missing cache prices derived.

**Needs:** Step 8

**Do:**

1. Choose Import, "From CSV file…", and pick the file from step 8.
2. Read the preview, then click Apply.

**What you should see:** `claude-test-model` under New with input 2.5, output 10, and cache prices 3.125 (5 min), 5 (1 h) and 0.25 (read), each marked "derived". A Skipped rows section lists line 3 with "missing model". After Apply the row's Source reads "CSV agentmeter-prices.csv".

**If you see something else:** Input shown as 250 or an error on line 2 means the decimal comma was not recognized.

**Result:**

Passed (user ran it in the app; agent verified the stored result). The user's screenshot of the preview showed "1 new, 1 skipped", `claude-test-model` with input 2,5 (German locale for 2.5), output 10 and cache prices 3,125 / 5 / 0,25 each marked "derived", and "Line 3: missing model" under Skipped rows. After Apply: `imported-prices.json` holds a `csv` batch with origin `agentmeter-prices.csv` and exactly those prices; the log shows `[prices] imported 1 CSV prices from agentmeter-prices.csv (1 new, 0 changed, 0 removed)`. Observations for later fixes: the only new model was collapsed behind "1 more new models" with nothing listed above it (wording and grammar), and the bad row's "error" was at first read as a problem rather than the step's deliberate test case.

### Step 10 of 15: Sources, filter and status line (US3)

**Why this step:** With layered prices you need to see where each price comes from, and the table should stay short by default.

**Needs:** Steps 4, 7 and 9

**Do:**

1. Look at the Source column for a built-in-only model (for example `claude-sonnet-4-6` if LiteLLM lacks it), an Anthropic model, an OpenAI model and `claude-test-model`.
2. Switch the filter to "Used in this window", note the rows, then back to All.
3. Set the filter to "Used in this window", quit AgentMeter from its menu, run `open build/AgentMeter.app`, and reopen the Prices pane.

**What you should see:** Sources read "Built-in", "LiteLLM <date>", "CSV agentmeter-prices.csv" or "Manual" as appropriate. "Used in this window" shows only models from your current usage plus manual overrides. Below the table, one status line per import (Anthropic, OpenAI, CSV) with its age. After the relaunch the filter is still "Used in this window".

**If you see something else:** The filter back on All after relaunch means the choice is not remembered (FR-030).

**Result:**

### Step 11 of 15: Export and re-import unchanged (US5)

**Why this step:** Export must round-trip: re-importing an unedited export changes nothing.

**Needs:** Step 9

**Do:**

1. Choose Import, "Export current prices as CSV…", save as `agentmeter-export.csv` in the folder from step 8.
2. Choose Import, "From CSV file…", and pick that export.
3. Read the summary, then click Cancel (applying would move every model into the CSV layer).

**What you should see:** A summary starting with "no new, changed or removed models", with only unchanged and possibly shadowed counts, and no skipped rows. Apply is disabled or the summary confirms nothing would change.

**If you see something else:** Any changed rows point at a precision or formatting problem in export (SC-005).

**Result:**

### Step 12 of 15: Remove the CSV import (US4)

**Why this step:** Every import can be undone, but removal asks first because a CSV cannot be restored without its file.

**Needs:** Step 9

**Do:**

1. Open the Import menu and choose "Remove CSV prices (imported <date>)".
2. Read the confirmation, then click Remove.

**What you should see:** A dialog "Remove CSV prices?" saying 1 model falls back to another price or becomes unpriced. After Remove, `claude-test-model` disappears from the All list (it had no other price), and the CSV status line is gone.

**If you see something else:** No dialog, or a count of 0, contradicts FR-023.

**Result:**

### Step 13 of 15: Try a provider import offline (US1)

**Why this step:** Without network, imports must fail cleanly and leave every price as it was.

**Needs:** Step 4

**Do:**

1. Turn Wi-Fi off (and unplug any wired network).
2. Choose Import, "Google Gemini prices (LiteLLM)".
3. Close the sheet, then turn Wi-Fi back on.

**What you should see:** An error in the sheet naming the network problem, a Close button, and no Apply. The table and status lines are unchanged.

**If you see something else:** A hanging spinner for more than 30 seconds would violate the timeout in FR-012.

**Result:**

### Step 14 of 15: Simulate a damaged imported-prices file

**Why this step:** A broken file must never break the app: it falls back to manual plus built-in prices and tells you.

**Needs:** Step 1 (backup exists)

**Run:**

```
pkill -x LLMUsageMenuBar; printf '{' > ~/.config/llm-usage-menubar/imported-prices.json && open build/AgentMeter.app && sleep 3 && grep -i 'imported' ~/Library/Logs/llm-usage-menubar/usage.log | tail -n 2
```

**What you should see:** A log line `[prices] imported prices ignored, using manual and built-in prices: ...`. In Settings, Prices pane: a red notice about the unreadable file, all Source values "Built-in" or "Manual", and no import status lines.

**If you see something else:** A crash or missing notice is a bug against FR-027.

**Result:**

### Step 15 of 15: Restore your configuration (cleanup)

**Why this step:** Returns your configuration to the state before the walkthrough and removes the temporary CSV files.

**Needs:** Step 1

**Run:**

```
pkill -x LLMUsageMenuBar; rm -rf ~/.config/llm-usage-menubar && mv ~/.config/llm-usage-menubar.walkthrough-backup ~/.config/llm-usage-menubar && rm -f "$TMPDIR/agentmeter-prices.csv" "$TMPDIR/agentmeter-export.csv" && ls ~/.config/llm-usage-menubar
```

**What you should see:** The directory listing from step 1 (`config.json`, no `imported-prices.json`). Start whichever build you want to keep using afterwards.

**If you see something else:** "No such file or directory" for the backup means step 1 did not run; your configuration is then in its post-walkthrough state.

**Result:**

## Not covered here

- **SC-006 with real Vertex OpenAI sessions:** pricing a real session that used an OpenAI model on Vertex needs such a session in your logs. Step 7 checks the price exists; whether log ids match `openai/gpt-oss-120b-maas` can only be confirmed once you have such a session.
- **SC-001 timing:** measured informally in step 4; the parse and diff part was measured at about 0.03 s during implementation.

## Coverage

- US1 (provider import): steps 4, 5, 6, 7, 13.
- US2 (CSV import): steps 8, 9.
- US3 (sources, filter, status line): step 10, plus the notice in step 14.
- US4 (removal): step 12.
- US5 (export): step 11.

All five user stories are covered.

## Results
