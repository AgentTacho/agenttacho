---
runbook_version: 1
feature: 038-match-rule-operators
status: passed
mode: light
steps_total: 12
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 24954c5
drafted_fingerprint: 9f0a1810fb95a343b0fa5137519ff992ed7f3cc2bd3847b1aeebb884ebeda07b
tested_at: 35fdde1
tested_fingerprint: 2f779ef030c8c77bd3d98d9ef5a4cab2233b759edb30fa7b18139aa63214bf9f
updated: 2026-10-28
---

# Try it: Session Kinds and Match Conditions for Token-Based Accounts

<!-- runbook-status -->
> **Status:** passed · 12 of 12 steps (12 passed) · Mode: light · Tested at 35fdde1 · 2026-10-28
<!-- /runbook-status -->














## What you're testing

A build of this branch runs with your real configuration. Your token-based accounts are migrated from their old rules to a session kind with an optional condition, and Settings shows the new section "Which sessions count". The journey: check the backup, build and start the app, read the migration lines in the log, look at your existing token-based accounts, explore the new account sheet for each harness without adding anything, try the condition controls, an invalid pattern and undo on a test account, check the saved form, provoke the shared-directory warning, look at a subscription's marker section and the other appearance, and remove the test accounts.

Settings has no Apply button: it saves about 0.6 s after each change. Examples use invented texts (`intranet/`, `^gateway-(a|b)/`, `~/.claude-gateway`).

## Test environment

No fixtures. The journey uses the app's configuration (`~/.config/agenttacho/config.json`), the backup `config-before.json` in this spec's `.walkthrough` folder (taken before the first walkthrough of this branch), and a local build (`make app`).

## Steps

### Step 1 of 12: Check the backup (US5)

**Why this step:** the new build rewrites token-based accounts in the new form on the next save; the backup from before the first walkthrough lets you go back.

**Run:**

```
ls -l specs/038-match-rule-operators/.walkthrough/config-before.json && jq -r '.accounts[].displayName' specs/038-match-rule-operators/.walkthrough/config-before.json
```

**What you should see:** the file is listed, and its account names do not include "Walkthrough Test".

**If you see something else:** a missing file means no backup; copy the current configuration there first.

**Result:** passed (agent). Backup listed; it names the four configured accounts, no test account.

### Step 2 of 12: Build the app from this branch (US4)

**Why this step:** the walkthrough needs the reworked model and Settings section.

**Run:**

```
make app && ls -d build/AgentTacho.app
```

**What you should see:** the build ends with `Built build/AgentTacho.app`, and the path is printed.

**If you see something else:** a compiler error means the branch does not build here; record it and stop.

**Result:** passed (agent). `make app` built `build/AgentTacho.app` (rebuilt several times during the session for the fixes below).

### Step 3 of 12: Start the new build (US4)

**Why this step:** only one AgentTacho may run at a time.

**Run:**

```
osascript -e 'quit app "AgentTacho"' ; sleep 2 ; open build/AgentTacho.app ; sleep 3 ; ps -axo command | rg 'AgentTacho.app/Contents/MacOS/AgentTacho$'
```

**What you should see:** one process line whose path ends in this worktree's `build/AgentTacho.app/Contents/MacOS/AgentTacho`.

**If you see something else:** a path outside this worktree means the old app still runs; quit it from its dropdown and run the step again.

**Result:** passed (agent, after the user quit the old build by hand: an open sheet made it refuse the scripted quit).

### Step 4 of 12: Your accounts were migrated (US5)

**Why this step:** every earlier form must load as a kind and a condition, with one log line per migrated account (FR-011).

**Needs:** Step 3.

**Run:**

```
rg -n "\[config\]" ~/Library/Logs/agenttacho/usage.log | tail -8
```

**What you should see:** after the launch, one line per token-based account saying it was migrated to a session kind (the Vertex account to Vertex; accounts with an old custom rule to Other provider with their condition), and no "could not be read" line.

**If you see something else:** a "could not be read" line names an account whose old setting fell back to the default; record it.

**Result:** passed (agent). Three lines `account "…": match rule migrated to sessions …` (Vertex; two accounts to Other provider with a condition), no "could not be read".

### Step 5 of 12: Existing accounts in "Which sessions count" (US2, US4)

**Why this step:** the section must say in plain words which sessions count, without "profile", "Match rule" or "Custom" (FR-012, FR-013, FR-017).

**Needs:** Step 4.

**Do:**

1. Open Settings > Accounts and select your Vertex account; read the section "Which sessions count".
2. Select your gateway account (the one that had a custom rule) and read the section.
3. Look at the subtitles in the account list.

**What you should see:** the Vertex account shows Sessions "Vertex", the "Only when" checkbox unticked, and small dimmed notes inside the box: what Vertex counts and that sessions from this account's Claude Code directory always count. The gateway account shows Sessions "Other provider", "Only when" ticked and the Condition row with the condition from its old rule. The subtitles name the kind ("Vertex", "Other provider"). No text says "profile", "Match rule" or "Custom".

**If you see something else:** "Custom" or "Match rule" anywhere means the old section is still shown.

**Result:** passed (user). Kinds, checkbox, condition, caption notes and subtitles as expected. Fixed on the way: the directory note now names the field's value, the default and sharing accounts, and says which sessions the choices decide; the kind notes say what each kind adds beyond the directory.

### Step 6 of 12: The new account sheet per harness (US1, US4)

**Why this step:** each harness offers only real choices; Claude Code starts with Directory only and asks for its own directory (FR-001, FR-016).

**Needs:** Step 3.

**Do:**

1. Accounts > Add > Token-based account; harness Claude Code. Look at the Sessions pop-up order and the "Claude Code directory" field; leave the directory empty.
2. Type `~/.claude-gateway` into the directory field.
3. Switch the harness to Codex, then to OpenCode, and look at the section each time; on OpenCode choose "Other provider".
4. Click Cancel (add nothing).

**What you should see:** Claude Code offers "Directory only" (selected), "Vertex", "Other provider"; with the directory empty a warning names your Claude subscription account and asks for this account's own Claude Code directory; with `~/.claude-gateway` the warning is gone. Codex shows no Sessions pop-up, the sentence "Counts Codex sessions signed in with an API key." and the "Only when" checkbox. OpenCode offers "Vertex" (selected), "OpenAI", "Other provider"; with Other provider the Condition row is shown without a way to turn it off.

**If you see something else:** no directory field in the sheet, or "API key" as a pop-up item, means the sheet was not reworked.

**Result:** passed (user). Order, directory field, shared-directory warning, Codex sentence and OpenCode condition as expected. Added on the way: OpenCode kind Anthropic.

### Step 7 of 12: Add a test account and try the condition controls (US3, US4)

**Why this step:** the condition only narrows; its controls must stay put and keep the last condition when switched off and on (FR-014, FR-015).

**Needs:** Step 6.

**Do:**

1. Add > Token-based account: name `Walkthrough Two`, harness Claude Code, directory `~/.claude-gateway`, Sessions "Other provider", tick "Only when", Model, "matches regex", `^gateway-(a|b)/`; click Add.
2. In Settings, switch the field between Model, Request id and Anywhere, and the operator between its items.
3. Untick "Only when", then tick it again.

**What you should see:** the account is added. No pop-up changes width when the selection changes; Anywhere offers only "contains" and "matches regex", and switching to Anywhere from "starts with" gives "contains". After unticking, the Condition row disappears; after ticking again, it shows the last condition again.

**If you see something else:** controls that jump sideways, or an empty condition after re-ticking, are failures.

**Result:** passed (user). Fixed on the way: a layout loop that hung the app (measured one-line/two-line switch inside the self-sizing sheet), now one fixed line; bordered field and operator pop-ups as wide as their widest item; Condition label above the controls everywhere; the sheet has account, sessions and budget sections, sizes to its content, and offers existing groups or Own budget only.

### Step 8 of 12: An invalid pattern is not saved; undo works (US3)

**Why this step:** invalid patterns are refused by the automatic save, and undo covers kind, checkbox and condition (FR-008, FR-019).

**Needs:** Step 7.

**Do:**

1. On "Walkthrough Two" set Model, "matches regex" and type `^gateway-(a`; wait two seconds.
2. Finish it as `^gateway-(a|b)/` and wait two seconds.
3. Change Sessions to "Vertex", then press Cmd-Z.

**What you should see:** after step 1 a note inside the box says the regular expression is not valid and the "Not applied" line names the account. After step 2 the note is gone. After Cmd-Z, Sessions shows "Other provider" again.

**If you see something else:** no note in step 1, or a saved invalid pattern (Step 9 shows it), is a failure.

**Result:** passed (user). Invalid pattern refused with note and "Not applied", saved once finished, Cmd-Z restored the kind.

### Step 9 of 12: The saved form (US5)

**Why this step:** the file must hold the new form only: `sessionKind` and, when on, `condition` (FR-010).

**Needs:** Step 8.

**Run:**

```
jq '.accounts[] | select(.type == "tokenBased") | {displayName, sessionKind, condition, matchRule, provider, customMarker}' ~/.config/agenttacho/config.json
```

**What you should see:** every token-based account has `sessionKind`; accounts with a condition have `condition` with `field`, `operator` and `text`; `matchRule`, `provider` and `customMarker` are `null`. "Walkthrough Two" has `"sessionKind": "otherProvider"` and the regex condition.

**If you see something else:** a remaining `matchRule` means that account was not saved by this build yet; change any setting and run the step again.

**Result:** passed (agent). All token-based accounts carry `sessionKind`; conditions carry field, operator and text; `matchRule`, `provider` and `customMarker` are null.

### Step 10 of 12: Shared-directory warning (US1, US4)

**Why this step:** a Directory only account on another account's directory counts nothing, so Settings must warn, as a caption note with a warning symbol (FR-013).

**Needs:** Step 9.

**Do:**

1. On "Walkthrough Two" set Sessions to "Directory only" and clear the directory field (so it means `~/.claude`).
2. Read the notes.
3. Set the directory back to `~/.claude-gateway` and Sessions to "Other provider".

**What you should see:** after step 1 a warning with the warning symbol names your Claude subscription account and asks for this account's own Claude Code directory, in small dimmed text inside the box. After step 3 it is gone.

**If you see something else:** no warning in step 1 means the shared-directory check does not run in Settings.

**Result:** passed (user). Warning naming the subscription with an empty directory on Directory only; gone after restoring.

### Step 11 of 12: Subscription marker section and the other appearance (US4)

**Why this step:** subscription sections keep their marker with caption notes, and both appearances must read well (FR-017, FR-018, SC-006).

**Needs:** Step 10.

**Do:**

1. Select your Claude subscription account; read its directory caption and "Session matching (advanced)".
2. Switch macOS to the other appearance, look at this section and at "Walkthrough Two"'s section, then switch back.

**What you should see:** no "profile" in the directory caption; the marker row with its text field filling the row and two small dimmed notes inside the box. In both appearances the notes and warning symbols are readable and nothing is clipped.

**If you see something else:** "profile" in a caption is a failure of FR-017.

**Result:** passed (user). No "profile" in the subscription caption; marker notes inside the box; both appearances readable.

### Step 12 of 12: Remove the test accounts (US4)

**Why this step:** leaves your configuration with your own accounts only.

**Needs:** Step 11.

**Do:**

1. Remove "Walkthrough Two" and "Walkthrough Test" (Remove…, confirm).

Then run:

```
jq -r '.accounts[].displayName' ~/.config/agenttacho/config.json && jq -r '.accounts[].displayName' specs/038-match-rule-operators/.walkthrough/config-before.json
```

**What you should see:** both lists name the same accounts.

**If you see something else:** an extra name means a test account is left; remove it.

**Result:** passed (agent). Account lists of the configuration and the backup are equal.

## Not covered here

- **Codex attribution (US1 scenarios 1, 2):** no token-based Codex account is configured on this Mac; `CodexSessionSourceTests` cover plan sessions staying with the subscription.
- **The 50 ms limit and retries (FR-007):** needs a pathological pattern on real data; covered by `MatchRuntimeTests` and the source tests.
- **Migration of v0.8.0 files (US5 scenarios 1, 2):** covered by `ConfigurationTests`; this Mac's file is already in the spec 037 form.

## Coverage

- US1: Steps 6, 10 (Codex attribution by tests).
- US2: Step 5.
- US3: Steps 7, 8.
- US4: Steps 2, 3, 5, 6, 7, 10, 11, 12.
- US5: Steps 1, 4, 9.

## Results

12 steps: 12 passed, 0 failed, 0 skipped. Migration, the "Which sessions count" section, the new account sheet, conditions, refusal of invalid patterns, undo, the saved form and the warnings work with the real configuration. The walkthrough led to several fixes, all committed on the branch: a layout loop that hung the app, bordered condition pop-ups, a sectioned add sheet with one budget pop-up, field-aware directory and kind notes, and the OpenCode kind Anthropic.
