---
runbook_version: 1
feature: 013-auto-update
status: passed
mode: full
steps_total: 14
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 96503df
drafted_fingerprint: 52bf223a4d5ec0b99cd7089169fcbd5c5945a789bfcdbf7ad0d4a62592f70a0d
tested_at: b2486d2
tested_fingerprint: 8b7eeb051f23f4b490f7355507243e3ab04421294f2c7ce1aa92f9f67a52e56b
updated: 2026-10-16
---

# Try it: Auto-Update

<!-- runbook-status -->
> **Status:** passed · 14 of 14 steps (14 passed) · Mode: full · Tested at b2486d2 · 2026-10-16
<!-- /runbook-status -->















## What you're testing

AgentMeter now checks GitHub for a newer release, shows a quiet line at the bottom of the dropdown, and installs a verified update with one click. The journey runs in this order:

1. The automated suites (release evaluation, policy, verification, Homebrew detection, the update-test build guards).
2. A development build, which must never check (US5).
3. A scratch GitHub repository with a notarized test release 0.9.0, and an update-test build that reads from it.
4. The update line and Release notes (US1), then a one-click install with relaunch (US2).
5. Turning the automatic check off (US4), and a tampered release that must be refused (US2 scenario 2).
6. Cleanup of the scratch repository, tags and temporary apps.

All commands run from the worktree root `.claude/worktrees/013-auto-update`. Your installed AgentMeter (Homebrew 0.2.1) must be quit while the test builds run, because AgentMeter runs only once.

## Test environment

Filled in when the walkthrough runs. Expected fixtures:

- **Scratch repository** `rhuss/agentmeter-update-test` on GitHub (remote, public so unauthenticated downloads work). Teardown: `gh repo delete rhuss/agentmeter-update-test --yes`.
- **Notarized test DMGs** built locally (slow local: a release build plus Apple notarization, several minutes each). Teardown: `rm -rf build/release`.
- **Local tags** `v0.9.0` and `v0.9.1` (never pushed). Teardown: `git tag -d v0.9.0 v0.9.1`.

## Steps

### Step 1 of 14: Run the unit tests (US1, US2, US3, US4, US5)

**Why this step:** All update decisions (version compare, release evaluation, install policy, verification order, Homebrew detection, schedule, state texts) live in UsageCore and are covered here, including every tampered-input case of SC-003.

**Needs:** nothing

**Run:**

```
make test 2>&1 | tail -5
```

**What you should see:** A final line like `Test run with 909 tests in 94 suites passed`, with no failures.

**If you see something else:** A failing `Update*` suite points at the update logic; other failures are unrelated regressions.

**Result:** passed (agent). `Test run with 909 tests in 94 suites passed`.

### Step 2 of 14: Run the release script tests (US5)

**Why this step:** Proves the update-test flag can never reach a published release: `make release` and `make dmg` refuse `UPDATE_TEST`, and `make app` strips it (FR-025).

**Needs:** nothing

**Run:**

```
make test-release 2>&1 | tail -5
```

**What you should see:** A summary with 180 passed and 0 failed.

**If you see something else:** A failing `test_build_scripts` or `test_makefile` case means a guard is missing.

**Result:** passed (agent). `180 passed, 0 failed`.

### Step 3 of 14: Development build never checks (US5)

**Why this step:** A build from a checkout without a release tag must not contact GitHub (FR-008, SC-007).

**Needs:** your installed AgentMeter quit (menu bar gear, Quit AgentMeter)

**Run:**

```
make app && open build/AgentMeter.app
```

**What you should see:** The build ends with a `signed` log line, and AgentMeter appears in the menu bar with no update line in the dropdown.

**If you see something else:** A single-instance prompt means another AgentMeter is still running; quit it and open the build again.

**Result:** passed (agent and user). Built and signed `developer-id`; the app ran from `build/AgentMeter.app`; the user saw no update line.

### Step 4 of 14: Ask the development build for updates (US5)

**Why this step:** "Check for Updates…" must say why nothing is checked instead of failing silently.

**Needs:** Step 3

**Do:**

1. Open the dropdown and click the gear button.
2. Choose "Check for Updates…".
3. Open Settings > About and look at the status under "Check for Updates…".

**What you should see:** The dropdown line reads "Development build: updates are not checked" until the dropdown closes; Settings shows the same status (a check started from Settings shows its result in Settings only).

**If you see something else:** "Checking for updates…" or an available version means the build was treated as a release build (check that HEAD has no `vX.Y.Z` tag).

**Result:** passed (user). The line read "Development build: updates are not checked"; Settings showed the same status with the toggle on.

### Step 5 of 14: Confirm no request was made (US5)

**Why this step:** The log is the evidence that nothing went to GitHub (SC-007).

**Needs:** Step 4

**Run:**

```
rg -n "update" ~/Library/Logs/agentmeter/usage.log | tail -5
```

**What you should see:** At most lines saying the build is a development build; no line with `api.github.com` or a check result.

**If you see something else:** A check line from this run means FR-008 is broken.

**Result:** passed (agent). Only `[update] updates are not checked: build=development ...` and `manual (dropdown) check skipped, development build`; no request to GitHub.

### Step 6 of 14: Create the scratch repository

**Why this step:** The update-test build reads releases from a repository you control, so the real `rhuss/agentmeter` stays untouched (FR-025).

**Needs:** `gh` logged in; quit the development build

**Run:**

```
gh repo create rhuss/agentmeter-update-test --public --description "AgentMeter update test releases (temporary)" && gh api -X PUT repos/rhuss/agentmeter-update-test/contents/README.md -f message="Initial commit" -f content="$(printf 'Temporary AgentMeter update test releases.\n' | base64)" -q .commit.sha && gh repo view rhuss/agentmeter-update-test --json visibility -q .visibility
```

**What you should see:** The commit hash of the initial README commit (a release needs a commit to tag), then `PUBLIC`.

**If you see something else:** "Name already exists" means a previous run left it; reuse it or delete it first.

**Result:** passed (agent), runbook corrected. Repo created `PUBLIC`. Step 8 then failed with `HTTP 422 Repository is empty`: a release needs a commit to tag, so the initial README commit was added to this step (FR-026).

### Step 7 of 14: Build and notarize test release 0.9.0

**Why this step:** One-click install only accepts a notarized Developer ID disk image whose checksum matches its release information, so the test release must be real.

**Needs:** Developer ID certificate and the `agentmeter-notary` profile; a clean work tree

**Run:**

```
git tag v0.9.0 && make dmg && bash scripts/release/notarize.sh build/release/AgentMeter-0.9.0.dmg && (cd build/release && shasum -a 256 AgentMeter-0.9.0.dmg > AgentMeter-0.9.0.dmg.sha256) && jq -n --arg v 0.9.0 --arg s "$(awk '{print $1}' build/release/AgentMeter-0.9.0.dmg.sha256)" '{version:$v, dmg:"AgentMeter-\($v).dmg", sha256:$s, tier:"developer-id", notarized:true}' > build/release/release-info.json && cat build/release/release-info.json
```

**What you should see:** notarytool reports `Accepted`, the stapler reports `The validate action worked!`, and the JSON shows version `0.9.0`, the DMG name, a 64 character checksum, `developer-id` and `notarized: true`.

**If you see something else:** A notarization error usually means the notary profile is missing or expired (README, Releasing).

**Result:** passed (agent). `version: 0.9.0 (build 117)`, `The staple and validate action worked!`, release-info.json with `developer-id`, `notarized: true` and the final checksum.

### Step 8 of 14: Publish 0.9.0 to the scratch repository

**Why this step:** The app finds releases through the GitHub API, exactly as it will for `rhuss/agentmeter`.

**Needs:** Steps 6 and 7

**Run:**

```
gh release create v0.9.0 -R rhuss/agentmeter-update-test --title "Test 0.9.0" --notes "Update test" build/release/AgentMeter-0.9.0.dmg build/release/AgentMeter-0.9.0.dmg.sha256 build/release/release-info.json && git tag -d v0.9.0
```

**What you should see:** The release URL `https://github.com/rhuss/agentmeter-update-test/releases/tag/v0.9.0`, then `Deleted tag 'v0.9.0'`.

**If you see something else:** An upload error leaves a draft; delete it with `gh release delete v0.9.0 -R rhuss/agentmeter-update-test --yes` and retry.

**Result:** passed (agent) after one fix (see Step 6). Published `releases/tag/v0.9.0`, local tag deleted.

### Step 9 of 14: Build and install the update-test app

**Why this step:** Only an update-test build may read another release source; it goes to a folder you can write to so one-click install is allowed.

**Needs:** Step 8 (tag deleted, so this is a development version below 0.9.0)

**Run:**

```
make app-update-test UPDATE_SOURCE=rhuss/agentmeter-update-test && mkdir -p ~/Applications && rm -rf ~/Applications/AgentMeter.app && ditto build/AgentMeter.app ~/Applications/AgentMeter.app && open ~/Applications/AgentMeter.app
```

**What you should see:** The build log says `update-test build, release source rhuss/agentmeter-update-test`, and AgentMeter starts from `~/Applications`.

**If you see something else:** "UPDATE_SOURCE is required" means the variable was not passed.

**Result:** passed (agent). `update-test build, release source rhuss/agentmeter-update-test`, version 0.3.1-dev, running from `~/Applications`.

### Step 10 of 14: See the update line and the release notes (US1)

**Why this step:** This is the notice users get within a day of a release (FR-009, FR-011).

**Needs:** Step 9

**Do:**

1. Open the dropdown, click the gear button, choose "Check for Updates…".
2. Click "Release notes".
3. Open Settings > About.

**What you should see:** The line "AgentMeter 0.9.0 available" with "Install" and "Release notes" above the footer; Release notes opens the scratch release page in the browser; Settings shows the same version with Install.

**If you see something else:** "Download" with a reason names the failing eligibility condition (for example "This build cannot verify updates" if the build is not Developer ID signed).

**Result:** passed (user and agent). "AgentMeter 0.9.0 available" with Install and Release notes; the release page opened; log: `available 0.9.0 (running 0.3.1), action install`, `release page of 0.9.0 opened`.

### Step 11 of 14: Install with one click (US2)

**Why this step:** The core promise: download, verify, replace, relaunch, with permissions kept (FR-014 to FR-020, SC-002, SC-004).

**Needs:** Step 10

**Do:**

1. Note the time, then click "Install".
2. Watch the line: Downloading with a percentage, Verifying, Installing.
3. When AgentMeter is back, open Settings > About.
4. Check the Trash for the previous AgentMeter.app.
5. Confirm that macOS showed no "prevented from modifying apps" prompt.

**What you should see:** The new version starts by itself from `~/Applications` within a minute; About shows version 0.9.0; the old app is in the Trash; no permission prompt appeared; threshold notifications and start at login still work.

**If you see something else:** A reason on the line ("checksum mismatch", "not notarized", "not signed by the same developer", "Gatekeeper could not confirm…") tells which verification step refused; `rg update ~/Library/Logs/agentmeter/usage.log` shows every step.

**Result:** passed (user and agent). Installed app reports 0.9.0, team EC5BHUKA6K, old copy at `~/.Trash/AgentMeter.app`, no App Management prompt. Log: `verified 0.9.0: checksum, notarized disk image, contents, signature and team, notarized app, staged copy`, `replaced ...`, `relaunching as 0.9.0`, `updated from 0.3.1 to 0.9.0`, all within 06:49:23 to 06:49:24 (SC-002). After relaunch: `notifications authorization granted`, `start at login: configured true, system status 1` (SC-004). Observation: the login item (one per bundle identifier) had moved to the `~/Applications` test copy when that copy first launched in Step 9; a test-setup effect, restored in Step 14.

### Step 12 of 14: Turn the automatic check off (US4)

**Why this step:** Users must be able to stop the request to GitHub (FR-002, SC-005).

**Needs:** Step 11 (any running build works)

**Do:**

1. Settings > General: turn off "Check for updates automatically".
2. Quit and reopen AgentMeter, wait more than 5 minutes.
3. Run `rg -n "update" ~/Library/Logs/agentmeter/usage.log | tail -5`.
4. Check that `~/.config/agentmeter/config.json` contains `"checksForUpdates" : false`.

**What you should see:** No new automatic check line after the restart; the key is false in the configuration; "Check for Updates…" still works on demand.

**If you see something else:** A check line 5 minutes after launch means the toggle is not honored.

**Result:** passed (user and agent), with a finding. `checksForUpdates: false` in config.json; no automatic check from 06:52:24 to 06:58:35 (SC-005). Finding: at launch the updater logs `automatic check on` about 10 s before the configuration is applied (`automatic check off`); no request goes out in that window because the first check is 5 minutes after launch, but the updater should read the setting before it starts.

### Step 13 of 14: A tampered release is refused (US2)

**Why this step:** A release whose checksum does not match must never replace the app (FR-015, SC-003).

**Needs:** Steps 6 and 9; reinstall the update-test build from Step 9 so the running version is below 0.9.1

**Run:**

```
git tag v0.9.1 && make dmg && bash scripts/release/notarize.sh build/release/AgentMeter-0.9.1.dmg && jq -n '{version:"0.9.1", dmg:"AgentMeter-0.9.1.dmg", sha256:"0000000000000000000000000000000000000000000000000000000000000000", tier:"developer-id", notarized:true}' > build/release/release-info.json && gh release create v0.9.1 -R rhuss/agentmeter-update-test --title "Test 0.9.1 (bad checksum)" --notes "Tampered" build/release/AgentMeter-0.9.1.dmg build/release/release-info.json && git tag -d v0.9.1
```

**What you should see:** The release is created. Then in the app: "Check for Updates…" shows "AgentMeter 0.9.1 available" with Install; clicking Install ends with "The download could not be verified (checksum mismatch)" and the installed app is unchanged.

**If you see something else:** Any replacement of the app here is a blocker.

**Result:** passed (user and agent). App stayed 0.3.1. Log: `downloaded 6432469 bytes (release lists 6432469)`, `verification failed at checksum`, `install of 0.9.1 failed, nothing replaced: The download could not be verified (checksum mismatch)`.

### Step 14 of 14: Clean up

**Why this step:** Removes the scratch repository, the local test files and the test app, and brings back your normal AgentMeter.

**Needs:** all earlier steps done or skipped

**Run:**

```
gh repo delete rhuss/agentmeter-update-test --yes; git tag -d v0.9.0 v0.9.1 2>/dev/null; rm -rf build/release ~/Applications/AgentMeter.app; open -a /Applications/AgentMeter.app
```

**What you should see:** `Deleted repository rhuss/agentmeter-update-test`, and your Homebrew AgentMeter 0.2.1 running again.

**If you see something else:** `gh repo delete` needs the `delete_repo` scope: `gh auth refresh -s delete_repo`.

**Result:** passed (agent and user). Tags, `build/release` and the test app removed; Homebrew AgentMeter running again from `/Applications` with `start at login: configured true, system status 1`; the user deleted the scratch repo (the gh token lacked `delete_repo`) and confirmed Login Items points to `/Applications`.

## Not covered here

- **Homebrew action end to end (US3):** needs a cask-installed release that already contains the updater (the installed 0.2.1 has none). Covered by `HomebrewDetectorTests` and `UpdateStateTests` (command copied text); try it by hand after the first release with this feature, against the following release.
- **Running from the mounted disk image or a translocated path (US5 scenario 2):** needs a quarantined download from a published release; covered by `InstallLocationTests` and `UpdatePolicyTests`.
- **The 24-hour schedule and wake behavior:** time based; covered by `UpdateScheduleTests`.

## Coverage

- US1: Steps 1, 10.
- US2: Steps 1, 11, 13.
- US3: Step 1 only (unit tests); see Not covered here.
- US4: Steps 1, 12.
- US5: Steps 1 to 5.

## Results

14 steps: 14 passed, 0 failed, 0 skipped (one runbook correction in Step 6).

The one-click update works end to end: a notarized release from a GitHub repository is found, verified (checksum, notarized disk image, contents, same Developer ID team, notarized app, staged copy), swapped in place and relaunched in about one second, with notifications and start at login intact. A release with a wrong checksum is refused with nothing replaced, a development build never contacts GitHub, and turning the automatic check off stops all automatic requests. Not tried by hand: the Homebrew action and running from a mounted disk image (see Not covered here). One finding to fix: the updater starts before it applies the saved setting, so the launch log briefly says the automatic check is on.
