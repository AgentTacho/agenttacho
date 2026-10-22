---
runbook_version: 1
feature: 035-additional-session-directories
status: passed
mode: light
steps_total: 8
step_results: passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 4c143b4
drafted_fingerprint: da6c60a0a0e0f8708c818851d9e2bdf2894cb29df96de856016965599dae3028
tested_at: b0899a5
tested_fingerprint: 98505947085183ff3227a7131a12e05cc58d103390911bc2d7af39f39b7c706f
updated: 2026-10-22
---

# Try it: Additional Session Directories per Account

<!-- runbook-status -->
> **Status:** passed · 8 of 8 steps (8 passed) · Mode: light · Tested at b0899a5 · 2026-10-22
<!-- /runbook-status -->





## What you're testing

Every Claude and Codex account keeps its one main directory (login and sessions) and gains an optional list of additional session directories, read for sessions only. An entry may use `*` for one folder level, so one entry covers every sandbox folder a tool like cc-deck delivers, also folders created later. OpenCode's global list on General > Sources accepts the same entries. Unsafe entries (`**`, a bare `*` directly under home or `/`, relative paths) are refused.

The journey: run the tests, start the new build with your configuration, move your second Codex home from its own account into the Codex subscription's additional list, then try a wildcard entry with two invented sandbox folders and a refused entry.

## Test environment

No fixtures. Step 2 backs up your configuration; Step 5 creates two empty invented folders under `~/agent-sessions`, removed again in Step 8.

## Steps

### Step 1 of 8: Run the test suite (US1 to US4)

**Why this step:** the entry check, the wildcard expander, the resolver, the read-once rule and the tie-break are tested in UsageCore.

**Needs:** nothing

**Run:**

```
make test 2>&1 | grep "Test run with"
```

**What you should see:** two "✔ Test run with" lines, about 2067 UsageCore tests and 70 DemoMode tests, both passed.

**If you see something else:** a "✘" line names the failing test.

**Result:**

### Step 2 of 8: Back up your configuration and start the new build (US1)

**Why this step:** you will edit accounts in your real configuration.

**Needs:** Step 1. Quit your running AgentTacho first.

**Run:**

```
cp ~/.config/agenttacho/config.json ~/.config/agenttacho/config.json.before-035 && make app && open build/AgentTacho.app
```

**What you should see:** the copy succeeds, the build ends with "Built build/AgentTacho.app", AgentTacho starts with your accounts.

**If you see something else:** an empty account list means the configuration failed to load.

**Result:**

### Step 3 of 8: Move a second Codex home into the subscription's list (US1)

**Why this step:** one subscription used from two Codex homes no longer needs a second account.

**Needs:** Step 2

**Do:**

1. In Settings > Accounts, select your Codex subscription account whose Codex home is `~/.codex`.
2. Under "Additional session directories", click + and "Choose Folder…", and pick the Codex home of your second profile (the one you had given its own subscription account); the chooser shows hidden folders.
3. Select that second subscription account and remove it.

**What you should see:** the section sits below the Codex home, with a caption saying the entries are read for sessions only and `*` matches one folder level; the entry appears in the list, written with `~` for your home folder; no "Not applied" line.

**If you see something else:** a "Not applied" line names the reason the entry was refused.

**Result:**

### Step 4 of 8: Both homes are read for the one account (US1)

**Why this step:** the sessions of both homes must count, each once.

**Needs:** Step 3 (wait for the next refresh or open the dropdown)

**Run:**

```
grep -E "\[codex\] [0-9]+ session" ~/Library/Logs/agenttacho/usage.log | tail -1
```

**What you should see:** the same session count as with two accounts before (the sessions of `~/.codex` plus those of the second home), and the dropdown shows one Codex plan section instead of two.

**If you see something else:** a lower count means the additional home is not read; a higher one means a home is read twice.

**Result:**

### Step 5 of 8: Create two invented sandbox folders (US2)

**Why this step:** a wildcard entry must match every folder a deliverer creates.

**Needs:** nothing

**Run:**

```
mkdir -p ~/agent-sessions/openshell/box-a/codex/sessions ~/agent-sessions/openshell/box-b/codex/sessions && ls ~/agent-sessions/openshell
```

**What you should see:** `box-a` and `box-b`.

**If you see something else:** an error from mkdir.

**Result:**

### Step 6 of 8: Add a wildcard entry (US2)

**Why this step:** one entry covers all sandbox folders.

**Needs:** Step 5

**Do:**

1. In Settings > Accounts, select the Codex subscription account.
2. Click + and "Enter Path…", type `~/agent-sessions/openshell/*/codex` and click Add.
3. Open the dropdown to trigger a refresh.

**What you should see:** the entry is accepted (no "Not applied" line).

**If you see something else:** a "Not applied" line.

**Result:**

### Step 7 of 8: The wildcard matched both folders (US2)

**Why this step:** the log reports how many folders each wildcard entry matched.

**Needs:** Step 6

**Run:**

```
grep -E 'wildcard "~/agent-sessions/openshell/\*/codex"' ~/Library/Logs/agenttacho/usage.log | tail -1
```

**What you should see:** a line ending in `2 folder(s) matched, 0 record(s) in window, 0 file(s) read` (the folders are empty).

**If you see something else:** no line means the entry was not resolved; another count means the wildcard matched too much or too little.

**Result:**

### Step 8 of 8: A refused entry, then clean up (US3)

**Why this step:** unsafe entries are refused with a reason; the test folders and entries are removed again.

**Needs:** Step 6

**Do:**

1. Click + and "Enter Path…", add `~/*` to the Codex account's list, and read the bottom line of Settings.
2. Select `~/*` and the wildcard entry from Step 6 (Command-click for both) and click the minus button or press Delete; keep the second Codex home from Step 3.
3. In Terminal run `rm -r ~/agent-sessions/openshell/box-a ~/agent-sessions/openshell/box-b`.

**What you should see:** after step 1 a line starting `Not applied: Additional session directory "~/*" of account` with the reason; it disappears once the entry is removed.

**If you see something else:** `~/*` accepted means the home-level wildcard is not refused.

**Result:**

## Not covered here

- **OpenCode wildcards (US4):** same rules on General > Sources; covered by tests.
- **More than 100 matches:** covered by tests (the cap and its log line).
- **Real sandbox exports:** need a deliverer such as cc-deck to copy sessions out of a sandbox; not part of this feature.

## Coverage

- US1 (literal additional directories): Steps 1 to 4.
- US2 (wildcards): Steps 5 to 7.
- US3 (refused entries): Step 8.
- US4 (OpenCode): tests only, see above.

## Results
