---
runbook_version: 1
feature: 034-settings-sidebar-directories
status: passed
mode: light
steps_total: 8
step_results: passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 0052d67
drafted_fingerprint: a78d358e28a253f7a68739d082e2845629b52212e0c3d6706bab200e40cfe53a
tested_at: 0048a73
tested_fingerprint: 1426926c2782382ea7cc6f18d862d9ecf8aba1bad25970f89e77a0d378b21bf6
updated: 2026-10-22
---

# Try it: Settings Sidebar and Per-Account Directories

<!-- runbook-status -->
> **Status:** passed · 8 of 8 steps (8 passed) · Mode: light · Tested at 0048a73 · 2026-10-22
<!-- /runbook-status -->









## What you're testing

The General tab of Settings gets a sidebar with six pages (Refresh, Appearance, Weekly window, Notifications, Sources, Startup). Agent directories move to the accounts: Claude accounts (subscription and Vertex) have a "Claude Code directory", Codex accounts (subscription and OpenAI) a "Codex home". The old global "Additional Claude Code directories" and "Additional Codex homes" lists are gone; entries left in an older configuration are no longer read and each leaves a note in the diagnostic log. OpenCode data directories stay global on the Sources page.

The journey: run the tests, open the demo build and click through the sidebar, check the account editors, then run the real app with your own configuration (which still holds old global entries) and read the upgrade notes.

## Test environment

No fixtures. Step 6 backs up your real configuration before the new build rewrites it without the old keys.

## Steps

### Step 1 of 8: Run the test suite (US1, US2, US3)

**Why this step:** the directory rules, the upgrade notes, the page model and the texts are tested in UsageCore; a green run is the baseline.

**Needs:** nothing

**Run:**

```
make test 2>&1 | grep "Test run with"
```

**What you should see:** two "✔ Test run with" lines, about 1954 UsageCore tests and 70 DemoMode tests, both passed.

**If you see something else:** a "✘" line names the failing test.

**Result:** passed (agent). `✔ Test run with 1954 tests in 203 suites passed` and `✔ Test run with 70 tests in 7 suites passed` (1964 after the walkthrough fixes).

### Step 2 of 8: Build and open the demo app (US1)

**Why this step:** the demo build has invented accounts, so the new Settings can be explored without touching your configuration.

**Needs:** Step 1. Quit a running "AgentTacho Demo" first.

**Run:**

```
make app-demo && open "build/AgentTacho Demo.app"
```

**What you should see:** the build ends with "Built build/AgentTacho Demo.app" and the demo's menu bar item appears.

**If you see something else:** a build error points at the app target.

**Result:** passed (agent). `Built build/AgentTacho Demo.app`, demo running.

### Step 3 of 8: Walk the General sidebar (US1)

**Why this step:** this is the new layout; every old General option must be on exactly one page.

**Needs:** Step 2

**Do:**

1. Open the demo's Settings and select General.
2. Click each sidebar entry in turn.

**What you should see:** a narrow sidebar with Refresh, Appearance, Weekly window, Notifications, Sources, Startup, each with a grey (monochrome) icon and uncolored text; the selected page has the row highlight. Refresh: interval and Adapt refresh. Appearance: Show usage as and Dropdown theme. Weekly window: alignment account, fallback weekday and hour. Notifications: the two notification switches. Sources: the OpenCode data directories and the caption "Claude Code directories and Codex homes are set per account in Accounts. An account without one uses ~/.claude or ~/.codex." Startup: Start at login and Check for updates. Nothing is clipped in light or dark appearance.

**If you see something else:** a missing option or a page with clipped controls.

**Result:** passed (maintainer, after two fixes). First run: sidebar icons were blue. Fixed with monochrome icons (`8b2bfca`, tint moved per row in `0048a73`) and a single Weekly window caption naming what the week counts for. The Sources caption changed with the new read rule (`748f740`: only the accounts' directories are read). Confirmed: grey icons, uncolored text, row highlight, captions as expected, nothing clipped.

### Step 4 of 8: Page memory and undo (US1)

**Why this step:** the selected page is remembered like the selected tab, and edits still apply and undo.

**Needs:** Step 3

**Do:**

1. Select Startup, switch to the Accounts tab and back to General.
2. Close Settings and open it again.
3. On Appearance, change "Show usage as", then press Cmd-Z.

**What you should see:** General reopens on Startup both times; the change applies and Cmd-Z undoes it.

**If you see something else:** General falling back to Refresh, or an edit that does not undo.

**Result:** passed (maintainer). Startup remembered across tab switch and reopen; Appearance change applied and undone with Cmd-Z.

### Step 5 of 8: Directories on the accounts (US2)

**Why this step:** agent directories now live on the account, with the same field for subscription and token-based accounts.

**Needs:** Step 2

**Do:**

1. In Settings > Accounts, select a Claude subscription account.
2. Select a Vertex account, then an OpenAI account if the demo has one.
3. Look through General for "Additional Claude Code directories" or "Additional Codex homes".

**What you should see:** the Claude subscription field reads "Claude Code directory" with a caption saying sessions and the login come from it (invented example path, no real tool path). The Vertex account has a "Usage source" section with an empty "Claude Code directory" whose caption says an empty field uses ~/.claude; an OpenAI account has a "Codex home" there (empty uses ~/.codex). The old global lists exist nowhere.

**If you see something else:** the old "Credential directory" label, a real local path in a caption, or a leftover global list.

**Result:** passed (maintainer). Claude Code directory label and captions, Vertex "Usage source" section, OpenAI Codex home; no Credential directory label, no real local paths.

### Step 6 of 8: Back up your configuration and run the real app (US3)

**Why this step:** your configuration still holds `logDirectories` and `codexHomes` entries; the new build stops reading them and writes the file without them on the next save, so keep a copy first.

**Needs:** Step 1. Quit the demo app and your running AgentTacho first.

**Run:**

```
cp ~/.config/agenttacho/config.json ~/.config/agenttacho/config.json.before-034 && make app && open build/AgentTacho.app
```

**What you should see:** the copy succeeds, the build ends with "Built build/AgentTacho.app", and AgentTacho starts with your accounts.

**If you see something else:** an empty account list means the configuration failed to load (check Step 7's log for the reason).

**Result:** passed (agent). Config backed up to `config.json.before-034`; `Built build/AgentTacho.app`; log: Claude sessions read, Codex `282 session(s)`, subscription `ok`.

### Step 7 of 8: Read the upgrade notes (US3)

**Why this step:** each old global entry must be named in the log with what to do about it.

**Needs:** Step 6 (wait for the first refresh)

**Run:**

```
grep -E "(logDirectories|codexHomes) entry" ~/Library/Logs/agenttacho/usage.log | tail -10
```

**What you should see:** one line per old entry, ending in "it is already covered by account ..." (also for `~/.claude` or `~/.codex` when an account's directory, or an empty field, resolves to it) or "set it as the Claude Code directory of an account in Settings > Accounts" (or the Codex home variant).

**If you see something else:** no lines although the backup holds entries means the notes are missing.

**Result:** passed (agent; expectation corrected). The maintainer's old `logDirectories` and `codexHomes` lists were empty, so no note is the right result: 0 matching lines, refresh `0 source error(s)`.

### Step 8 of 8: Move an entry to its account and compare usage (US2)

**Why this step:** usage from a directory that was only in the old list must come back once it is set on the account.

**Needs:** Step 7

**Do:**

1. For each note that says "set it as ...", open Settings > Accounts, select the account that runs from that directory and enter it as its Claude Code directory or Codex home.
2. Open the dropdown after the next refresh and compare the usage with your previous version.

**What you should see:** the same usage figures as before the upgrade; no note asks for that entry after a relaunch.

**If you see something else:** lower token counts mean a directory is still not read.

**Result:** passed (maintainer and agent). The walkthrough found that the Vertex profile and the codex-private profile were not read by any account (also not before this branch). The maintainer set the Vertex account to the work profile directory and added a second Codex subscription account for the profile home (its sessions are on the Plus plan). Log: `[codex] 284 session(s), 2801 record(s)`, refresh `0 source error(s)`. Several session locations per account are the follow-up of brainstorm 34.

## Not covered here

- **Screenshots:** no shot shows the General or Accounts tab, so none was recaptured.
- **OpenCode with several data directories:** unchanged behavior, covered by tests.

## Coverage

- US1 (sidebar): Steps 1 to 4.
- US2 (per-account directories): Steps 1, 5, 8.
- US3 (upgrade notes): Steps 1, 6, 7.

## Results

8 steps: 8 passed, 0 failed, 0 skipped.

The General tab has its six-page sidebar with monochrome icons, page memory and unchanged apply and undo. Accounts carry their own Claude Code directory or Codex home, and AgentTacho now reads exactly the accounts' directories (an empty field meaning the default), a rule changed during this walkthrough. Three more changes came out of it: grey sidebar icons, one Weekly window caption, and the read rule. On the maintainer's setup, mapping the profiles to accounts brought the work Vertex sessions and the profile's Codex sessions into the count. Several session locations per account (local profiles, OpenShell sandboxes) are brainstorm 34.
