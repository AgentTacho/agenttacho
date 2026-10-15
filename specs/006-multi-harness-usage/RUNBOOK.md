---
runbook_version: 1
feature: 006-multi-harness-usage
status: passed
mode: light
steps_total: 10
step_results: passed,passed,passed,passed,passed,passed,passed,passed,skipped,passed
drafted_at: 126ab71
drafted_fingerprint: e32333a7511b5b362f4cca4502a5edda2c9b235c736a15881b997517d9d45c80
tested_at: ac6ad3b
tested_fingerprint: 7eb44a5b36989e79857ce5a6fb6c3d0cb8ebbae13f8aeb0e643477ee420cdbc3
updated: 2026-10-14
---

# Try it: Multi-Harness Usage (Codex and OpenCode)

<!-- runbook-status -->
> **Status:** passed · 10 of 10 steps (9 passed, 1 skipped) · Mode: light · Tested at ac6ad3b · 2026-10-14
<!-- /runbook-status -->











## What you're testing

AgentMeter now reads usage from Codex and OpenCode as well as Claude Code. Each record goes to the account that pays for it:

- OpenCode on Vertex counts toward your Vertex account.
- Codex API-key sessions count toward an OpenAI account.
- Codex ChatGPT-plan sessions count toward a Codex subscription account, which shows tokens only for now.

The journey goes like this:
1. Build and test with your configuration backed up.
2. Check that the diagnostic log lists the new harnesses.
3. Find this week's Codex usage under Unassigned, with a per-harness split.
4. Add an OpenAI account and watch the Codex usage move there.
5. Add a Codex subscription account.
6. Optionally, run one OpenCode prompt on Vertex and see it in the Vertex budget.
7. Restore your configuration.

## Test environment

No fixtures. The journey reads your real `~/.codex/sessions` and `~/.local/share/opencode/opencode.db` read-only. Your Codex sessions from the last 7 days are mostly `codex exec` review runs without a plan marker, so they count as API-key usage. Your last OpenCode message is from July 12, so OpenCode shows no usage in the current window unless you run step 9.

## Steps

### Step 1 of 10: Run the test suite (US1, US2, US3, US4)

**Why this step:** It proves the Codex and OpenCode parsing rules, attribution and stale handling before you touch the app.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 460 tests in 50 suites passed`, or a slightly higher count.

**If you see something else:** A failing suite name points at the area: `CodexSessionParserTests`, `OpenCodeSourceTests` or `AttributionTests`.

**Result:** passed (agent). Expected vs actual: ✔ "460 or slightly higher, passed" → `✔ Test run with 461 tests in 50 suites passed after 0.450 seconds.`

### Step 2 of 10: Back up your configuration (US4)

**Why this step:** Steps 5 and 7 add accounts, so you need a copy to restore.

**Run:**

```
cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-006 && jq -c '[.accounts[] | {displayName, type, provider}]' ~/.config/agentmeter/config.json
```

**What you should see:** Your current accounts: Claude Max (subscription) and Claude Code via Vertex (tokenBased, vertex). There are no OpenAI or Codex accounts yet.

**If you see something else:** If the file is missing, launch the app once first.

**Result:** passed (agent). Expected vs actual: ✔ `[{"displayName":"Claude Max","type":"subscription","provider":null},{"displayName":"Claude Code via Vertex","type":"tokenBased","provider":"vertex"}]`, no OpenAI or Codex accounts; backup written to `config.json.bak-006`.

### Step 3 of 10: Build and launch this version (US1, US4)

**Why this step:** The new sources run on the first refresh after launch.

**Needs:** Step 2

**Run:**

```
pkill -x AgentMeter; make run 2>&1 | tail -1 && sleep 8 && pgrep -lx AgentMeter
```

**What you should see:** `open "build/AgentMeter.app"` followed by a process line for `AgentMeter`. The bar shows your entries as before.

**If you see something else:** No process line means the app crashed at launch. Check `~/Library/Logs/agentmeter/usage.log`.

**Result:** passed (agent). Expected vs actual: ✔ `open "build/AgentMeter.app"`; ✔ `20468 AgentMeter` running after 8 s.

### Step 4 of 10: Check the diagnostic log for the new harnesses (US4)

**Why this step:** The log records which harnesses and locations were read, and how much each contributed (FR-022).

**Needs:** Step 3

**Run:**

```
rg "\[(codex|opencode)\]" ~/Library/Logs/agentmeter/usage.log | tail -4
```

**What you should see:**
- A `[codex]` line: `/Users/.../.codex: N record(s) in window, M file(s) read`, with N greater than 0.
- An `[opencode]` line for `.../opencode.db` with `0 record(s) in window`, because your last OpenCode use was in July.
- No error lines.

**If you see something else:** A line with an error names the location that failed. Other sources still refresh (FR-006).

**Result:** passed (agent), with a runbook correction. Actual lines:
- `[codex] /Users/rhuss/.codex: 0 record(s) in window, 63 file(s) read`
- `[codex] 63 session(s), 0 record(s) since collection start, 63 file(s) parsed, 0.045 s`
- `[opencode] ok: 0 record(s) since 2026-09-30T22:00:00Z`

Expected vs actual:
- ✔ Both harnesses are read and logged per location, with no errors.
- ✘ The expectation of "N greater than 0" for Codex was wrong. An independent read-only check found that all 35 `token_count` events since 2026-09-30 carry `info: null`: these are `codex exec` review runs rejected on the usage limit, so they used no tokens. The last real Codex usage was 2026-09-17, before the window. 0 is the correct value (FR-026 correction).

### Step 5 of 10: See Codex usage under Unassigned (US2, US1)

**Why this step:** Without an OpenAI account, Codex API-key usage has no billing account, so it goes to Unassigned instead of disappearing.

**Needs:** Step 3

**Do:**

1. Open the dropdown and choose Refresh now.
2. Find the Unassigned entry and expand Details.
3. Switch the details view to Harnesses.

**What you should see:** Unassigned lists tokens. The Harnesses view shows a Codex row (and Claude Code, if any Claude Code usage was unassigned). The Models view shows the Codex model, for example `gpt-5.6-terra`.

**If you see something else:** If there is no Codex row, the Codex sessions were not read or were attributed elsewhere. Check step 4's record count.

**Result:** passed (user, after a fresh Codex query), with a runbook correction. The window had no Codex usage (step 4), so the user signed Codex in with their ChatGPT Plus account and ran one query. The new session records `plan_type: "plus"`, 116,780 tokens, and model `gpt-5.6-terra` (checked read-only). Because no Codex subscription account exists yet, this plan usage lands in Unassigned (US3 scenario 3). It is not API-key usage, as this step first assumed (FR-026 correction).

Expected vs actual:
- ✔ The log shows `[codex] 67 session(s), 8 record(s) since collection start`.
- ✔ The user confirmed Unassigned shows 143.1K tokens, a Codex row under Harnesses, and `gpt-5.6-terra` under Models.

Note: the model table shows token counts in whole millions (`<1` for small values). That is the existing display convention from main (`2673c40`), not part of this feature.

### Step 6 of 10: Add an OpenAI account (US2)

**Why this step:** Codex API-key usage should count toward an OpenAI account and be priced from the price table.

**Needs:** Step 5

**Do:**

1. Open Settings, then Accounts. Add a token-based account with Provider **OpenAI**, choose **Own budget**, set it to Weekly, 20, and save.
2. Choose Refresh now in the dropdown and look at the new OpenAI entry.

**What you should see:**
- The new entry has the OpenAI icon and shows the Codex tokens that were under Unassigned in step 5.
- Unassigned no longer has a Codex row.
- If `gpt-5.6-terra` has no price yet, the entry says "incomplete, unpriced" and the spend excludes those tokens. That is expected until OpenAI prices are imported (Prices tab, LiteLLM import for OpenAI).

**If you see something else:** If the Codex tokens stay in Unassigned, attribution of `apikey` sessions to OpenAI accounts failed (FR-012).

**Result:** passed after a fix and retry (user), with a runbook correction.
- **First run:** Add → Token-based account opened a "New subscription account" sheet with no Provider picker. `.sheet(isPresented:)` captured the account type chosen previously. This bug predates the feature (main has the same pattern), and a third account type exposed it.
- **Fix:** commit "fix(settings): open the new-account sheet for the chosen account type", which switches to `.sheet(item:)`.
- **Retry:** the user confirmed the Provider picker, created "OpenAI API" (OpenAI, own budget, weekly $20), and saw it at $0.
- **Correction (FR-026):** the user's Codex usage is ChatGPT Plus plan usage, not API-key usage, so it correctly stays under Unassigned instead of moving to the OpenAI account.

### Step 7 of 10: Add a Codex subscription account (US3)

**Why this step:** ChatGPT-plan sessions should go to a tokens-only Codex subscription account with no bar entry.

**Needs:** Step 6

**Do:**

1. In Settings, Accounts, choose Add → **Subscription account**, set Platform to **ChatGPT (Codex)**, keep the Codex home `~/.codex` and save. (During the walkthrough this was still a separate "Codex subscription" menu entry; the menu was merged afterwards, see Results.)
2. Check the editor: there is no shown-in-bar toggle and there are no thresholds.
3. Choose Refresh now and look at the new entry in the dropdown.

**What you should see:** The Codex subscription entry appears with the OpenAI icon, tokens for the week, and no percent. It does not appear in the bar. It may show 0 tokens, because your plan-marked Codex sessions are from September. The OpenAI account keeps the API-key sessions.

**If you see something else:** If the entry shows a percent or appears in the bar, the tokens-only rules are broken (FR-017).

**Result:** passed (user). The user created "ChatGPT Plus" (Codex subscription, home `~/.codex`) and confirmed:
- the editor has no shown-in-bar toggle and no thresholds;
- the entry shows the Plus-plan Codex tokens with no percent and no bar entry;
- Codex usage is gone from Unassigned (FR-014, FR-015, FR-017).

Unlike this step's original expectation of 0 tokens, the fresh Plus query from step 5 made the plan usage visible.

### Step 8 of 10: Check the saved accounts (US2, US3)

**Why this step:** It confirms the new provider and the new account type are stored as the contract says.

**Needs:** Step 7

**Run:**

```
jq -c '[.accounts[] | select(.provider == "openai" or .type == "codexSubscription") | {type, provider, codexHome, icon}]' ~/.config/agentmeter/config.json
```

**What you should see:** Two entries:
- `{"type":"tokenBased","provider":"openai",...,"icon":"brands:openai"}`
- `{"type":"codexSubscription",...,"codexHome":"~/.codex","icon":"brands:openai"}`

**If you see something else:** A missing `codexHome` is fine (the default applies). An unknown type means the writer is out of date.

**Result:** passed (agent). Expected vs actual: ✔ `[{"type":"tokenBased","provider":"openai","codexHome":null,"icon":"brands:openai"},{"type":"codexSubscription","provider":null,"codexHome":"~/.codex","icon":"brands:openai"}]`.

### Step 9 of 10: Optional: OpenCode on Vertex counts toward the Vertex budget (US1)

**Why this step:** This is the main promise of the feature, but it needs fresh OpenCode usage in the window. It costs a few cents on Vertex.

**Needs:** Step 3

**Do:**

1. In a terminal, run one short OpenCode prompt with your Vertex model, for example `opencode run "Reply with OK"` in any directory.
2. Choose Refresh now in AgentMeter.
3. Expand Details on your Vertex budget entry and switch to Harnesses.

**What you should see:** The Vertex spend increases by the cost of that prompt. The Harnesses view lists Claude Code and OpenCode, and the `[opencode]` log line now shows at least 1 record in window.

**If you see something else:** If the OpenCode row appears under Unassigned instead, the message's provider was not `google-vertex`. Check which provider OpenCode used.

**Result:** skipped (user choice). This optional step costs Vertex usage. OpenCode attribution to Vertex is covered by `OpenCodeSourceTests` (`vertexProviderIsAttributedToTheVertexAccount`) and by the read-only real-data probe (403 OpenCode records, 400 on `google-vertex`, which matched a direct database query). There is no OpenCode usage in the current window.

### Step 10 of 10: Restore your configuration (US4)

**Why this step:** It removes the test accounts.

**Needs:** Step 2

**Run:**

```
cp ~/.config/agentmeter/config.json.bak-006 ~/.config/agentmeter/config.json && jq -c '[.accounts[].displayName]' ~/.config/agentmeter/config.json
```

**What you should see:** Your original account names. After the next refresh, Codex usage is back under Unassigned.

**If you see something else:** The backup is still at `~/.config/agentmeter/config.json.bak-006`.

**Result:** passed (agent ran, user checked), using a variant the user chose. Instead of restoring the backup, only the test OpenAI account was removed, with `jq 'del(.accounts[] | select(.type == "tokenBased" and .provider == "openai"))'`. The Codex subscription account was kept for real use, and the backup stays at `config.json.bak-006`.

Expected vs actual:
- ✔ The accounts are now Claude Max, Claude Code via Vertex, and Codex subscription.
- ✔ The user confirmed no configuration error after refresh, with the Codex subscription still showing the Plus tokens.

## Not covered here

- **A busy or locked OpenCode database (FR-005):** hard to provoke by hand. Covered by `OpenCodeSourceTests` (lock and WAL cases) in step 1.
- **Late plan markers, subagent inheritance and the fork copy rule (FR-014):** they depend on specific session histories. Covered by `CodexSessionParserTests` and `CodexSessionSourceTests` in step 1.
- **Extra Codex or OpenCode locations (US4 scenario 1):** you have no second Codex home. Covered by the source tests in step 1.

## Coverage

- **US1 (OpenCode into budgets):** steps 1, 3, 5 and 9 (step 9 is optional).
- **US2 (Codex API key priced):** steps 1, 5, 6 and 8.
- **US3 (Codex plan visible):** steps 1, 7 and 8.
- **US4 (locations and visibility):** steps 1, 2, 4 and 10.

## Results

9 of 10 steps passed and 1 was skipped (2026-10-14, on the branch rebased onto main `d100553`).

What passed:
- **Tests:** the full suite passed (461 tests; 466 after the rebase).
- **Diagnostic log:** it reports both new harnesses per location.
- **Codex usage, end to end:** after the user signed Codex in with ChatGPT Plus and ran one query, the session (`plan_type: "plus"`, 116,780 tokens, `gpt-5.6-terra`) appeared under Unassigned with a Codex harness row. It then moved to a new Codex subscription account, which shows tokens only, with no bar entry and no thresholds.
- **OpenAI provider:** it saves and shows correctly.
- **Stored config:** both new account types are stored as the contract specifies.

Corrections and findings:
- **Runbook expectations corrected (FR-026):** recent Codex `exec` runs carried no usage (rejected on the old plan's limit), and Plus usage is plan usage rather than API-key usage.
- **Bug found and fixed:** the Add menu opened the new-account sheet for the previously chosen type (`.sheet(isPresented:)` captured stale state). This bug predates the feature; it is fixed with `.sheet(item:)`.
- **Display convention:** the model table shows token counts in whole millions (`<1` for small values). That convention comes from main.

Follow-up from the walkthrough: the Add menu listed "Subscription account", "Token-based account" and "Codex subscription" asymmetrically. It now has two entries, and the subscription dialog has a Platform picker (Claude or ChatGPT), mirroring the token-based Provider picker.

Skipped: step 9, OpenCode on Vertex in the current window. It is optional and costs Vertex usage. Unit tests and the earlier real-data probe cover it.
