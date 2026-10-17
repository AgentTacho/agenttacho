# Quickstart: Validating the rebrand

Contracts: [legacy-data-move.md](contracts/legacy-data-move.md), [release-and-tap.md](contracts/release-and-tap.md), [name-check.md](contracts/name-check.md). Order of operations: [research.md](research.md) R9.

## Q0: Tests and name check (before merge)

```bash
make test           # includes LegacyDataMove and RunningInstance tests
make test-release   # includes the release names, site deploy, tap rename and name check tests
```

Expected: all pass; `names: ok (<n> allowed matches)`.

Result (2026-10-17, branch `023-rebrand-agenttacho`): `make test` 1450 tests in 137 suites passed; `make test-release` 224 passed, 0 failed; the name check printed `names: ok (115 allowed matches)`.

## Q1: Redirects after the transfer (before 0.5.0, FR-021)

Right after the maintainer transferred `rhuss/agentmeter` to `AgentTacho` and renamed it `agenttacho`:

```bash
curl -sIL https://api.github.com/repos/rhuss/agentmeter/releases/latest | rg -i '^(HTTP|location)'
curl -sIL -o /dev/null -w '%{http_code} %{url_effective}\n' \
  https://github.com/rhuss/agentmeter/releases/download/v0.4.1/AgentMeter-0.4.1.dmg
curl -sIL -o /dev/null -w '%{http_code} %{url_effective}\n' \
  https://github.com/rhuss/agentmeter/releases/download/v0.4.1/release-info.json
```

Expected: the API request ends in `200` with the latest release of `AgentTacho/agenttacho` (tag `v0.4.1` until 0.5.0 exists); both downloads end in `200`; every `location` host is `api.github.com`, `github.com`, `objects.githubusercontent.com` or `release-assets.githubusercontent.com`. Record the output here. If any check fails, do not release 0.5.0.

Then: `git remote set-url origin git@github.com:AgentTacho/agenttacho.git` and `gh repo edit AgentTacho/agenttacho --homepage https://agenttacho.github.io`.

Result (2026-10-17, after the transfer with the maintainer's approval): passed. Signed query strings of the asset URLs are cut off below.

```text
API latest release:
HTTP/2 301  location: https://api.github.com/repositories/1417309418/releases/latest
HTTP/2 200  tag v0.4.1, html_url https://github.com/AgentTacho/agenttacho/releases/tag/v0.4.1

AgentMeter-0.4.1.dmg:
HTTP/2 301  location: https://github.com/AgentTacho/agenttacho/releases/download/v0.4.1/AgentMeter-0.4.1.dmg
HTTP/2 302  location: https://release-assets.githubusercontent.com/github-production-release-asset/1417309418/...
HTTP/2 200

release-info.json:
HTTP/2 301  location: https://github.com/AgentTacho/agenttacho/releases/download/v0.4.1/release-info.json
HTTP/2 302  location: https://release-assets.githubusercontent.com/github-production-release-asset/1417309418/...
HTTP/2 200
```

Every hop is on `api.github.com`, `github.com` or `release-assets.githubusercontent.com`. `origin` now points to `git@github.com:AgentTacho/agenttacho.git` (`git ls-remote origin main` answers), and the repository homepage is `https://agenttacho.github.io`.

## Q2: The app under its new name (development build)

```bash
make app && open build/AgentTacho.app
```

Expected: menu bar item, dropdown, every Settings tab, About and the update line say AgentTacho; About's links open `github.com/AgentTacho/agenttacho`; the sponsor link opens `github.com/sponsors/rhuss`.

Result (2026-10-17): `make app` builds `build/AgentTacho.app` with bundle identifier `dev.rhuss.agenttacho`, `AgentTacho.icns`, `AgentTacho-mono.png` and `agenttacho_UsageCore.bundle`. Not opened yet: AgentMeter 0.4.1 runs on the maintainer's Mac, so the first launch is the move of Q3, which waits for the maintainer's go-ahead.

## Q3: Moving from AgentMeter on the maintainer's Mac

Preconditions: AgentMeter 0.4.1 installed and running, `~/.config/agenttacho/` absent. Note the checksums first:

```bash
shasum ~/.config/agentmeter/* ~/Library/Application\ Support/agentmeter/*
```

Open `build/AgentTacho.app`. Expected: the running-copy alert names AgentMeter with its version and location; choose stop and continue. AgentTacho shows the same accounts, groups, budgets and bar arrangement at once. The log `~/Library/Logs/agenttacho/usage.log` has one `copied from AgentMeter` line. Re-run the `shasum` command: identical output. Quit and reopen AgentTacho: no second copy line.

## Q4: DMG backgrounds

```bash
make backgrounds && make dmg
```

Expected: both backgrounds read "Drag AgentTacho to Applications"; the notarized one shows no seam where the old title was, at 1x and 2x (open both PNGs at full size). The DMG is `build/release/AgentTacho-<version>.dmg` with volume name AgentTacho.

Result (2026-10-17): both backgrounds read "Drag AgentTacho to Applications". The notarized title is drawn in the rounded bold system font (closer to the painted weight than semibold) at the old title's position. The title-less bases show no seam at 1x or 2x, also with the contrast around the background color raised twelvefold. `make dmg` built `build/release/AgentTacho-0.4.1-dev.dmg` (developer-id, not notarized); mounted, its volume name is AgentTacho and it holds `AgentTacho.app` and the Applications link; `release-info.json` names `AgentTacho-0.4.1-dev.dmg`.

## Q5: The 0.5.0 release (after merge)

Store the notary profile once: `xcrun notarytool store-credentials agenttacho-notary --apple-id <id> --team-id EC5BHUKA6K`. Tag `v0.5.0` on `main`, push the tag, run `make release`.

Expected: release "AgentTacho 0.5.0" in `AgentTacho/agenttacho` with the three assets; the output says the site deploy was started; the tap has `Casks/agenttacho.rb`, no `Casks/agentmeter.rb`, and `cask_renames.json` with `"agentmeter": "agenttacho"`; a run of `deploy.yml` appears in `AgentTacho/agenttacho.github.io` (it skips the deploy while `SITE_LIVE` is not `true`).

## Q6: Homebrew moves an AgentMeter install (after Q5)

Precondition: before Q5, `brew install --cask rhuss/tap/agentmeter` (0.4.1) on a test Mac or user account.

```bash
brew update && brew upgrade
brew list --cask | rg 'agent(meter|tacho)'
ls /Applications | rg 'Agent(Meter|Tacho)'
```

Expected: `agenttacho` listed, `agentmeter` not; `/Applications/AgentTacho.app` present, `AgentMeter.app` gone. If `AgentMeter.app` stays, note it here; the README's moving instructions already tell users to delete it (research R1).

## Q7: An installed AgentMeter 0.4.1 sees 0.5.0

On a Mac still running AgentMeter 0.4.1, choose "Check for Updates…".

Expected: "AgentMeter 0.5.0 available" with a link that opens the 0.5.0 release page in `AgentTacho/agenttacho`; no one-click install (its DMG name does not match).
