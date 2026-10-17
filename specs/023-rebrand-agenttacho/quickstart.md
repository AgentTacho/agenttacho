# Quickstart: Validating the name AgentTacho

Contract: [release-and-tap.md](contracts/release-and-tap.md). Order of operations: [research.md](research.md) R9.

## Q0: Tests (before merge)

```bash
make test           # includes the Paths, update name and Info.plist key tests
make test-release   # includes the release names and site deploy tests
```

Expected: all pass.

Result (2026-10-17, branch `023-rebrand-agenttacho`): `make test` and `make test-release` passed.

## Q1: The app under its name (development build)

```bash
make app && open build/AgentTacho.app
```

Expected: menu bar item, dropdown, every Settings tab, About and the update line say AgentTacho; About's links open `github.com/AgentTacho/agenttacho`; the sponsor link opens `github.com/sponsors/rhuss`.

Result (2026-10-17): `make app` builds `build/AgentTacho.app` with bundle identifier `dev.rhuss.agenttacho`, `AgentTacho.icns`, `AgentTacho-mono.png` and `agenttacho_UsageCore.bundle`.

## Q2: DMG backgrounds

```bash
make backgrounds && make dmg
```

Expected: both backgrounds read "Drag AgentTacho to Applications"; the notarized one shows no seam where the painted title was, at 1x and 2x (open both PNGs at full size). The DMG is `build/release/AgentTacho-<version>.dmg` with volume name AgentTacho.

Result (2026-10-17): both backgrounds read "Drag AgentTacho to Applications". The notarized title is drawn in the rounded bold system font (closer to the painted weight than semibold) at the painted title's position. The title-less bases show no seam at 1x or 2x, also with the contrast around the background color raised twelvefold. `make dmg` built `build/release/AgentTacho-0.4.1-dev.dmg` (developer-id, not notarized); mounted, its volume name is AgentTacho and it holds `AgentTacho.app` and the Applications link; `release-info.json` names `AgentTacho-0.4.1-dev.dmg`.

## Q3: The 0.5.0 release (after merge)

Store the notary profile once: `xcrun notarytool store-credentials agenttacho-notary --apple-id <id> --team-id EC5BHUKA6K`. Tag `v0.5.0` on `main`, push the tag, run `make release`.

Expected: release "AgentTacho 0.5.0" in `AgentTacho/agenttacho` with the three assets; the output says the site deploy was started; the tap has `Casks/agenttacho.rb` for 0.5.0 and no other change; a run of `deploy.yml` appears in `AgentTacho/agenttacho.github.io` (it skips the deploy while `SITE_LIVE` is not `true`).

Result (2026-10-17): passed. `make release` built 0.5.0 (build 136), signed it with Developer ID, notarized and stapled `AgentTacho-0.5.0.dmg` (submission edc4abe6-2876-4c17-b0b2-1a2d00aad35b), and published [AgentTacho 0.5.0](https://github.com/AgentTacho/agenttacho/releases/tag/v0.5.0) as the latest release with `AgentTacho-0.5.0.dmg`, `AgentTacho-0.5.0.dmg.sha256` and `release-info.json` (`notarized: true`). It printed `release: started site deploy in AgentTacho/agenttacho.github.io`; that run passed check and build (deploy skipped, `SITE_LIVE` unset). `AgentTacho/homebrew-tap` has `Casks/agenttacho.rb` for 0.5.0 with the same checksum.

## Q4: Homebrew install (after Q3)

On a test Mac or user account:

```bash
brew update && brew install --cask agenttacho/tap/agenttacho
brew list --cask | rg agenttacho
ls /Applications | rg AgentTacho
```

Expected: `agenttacho` listed; `/Applications/AgentTacho.app` present and it opens.

## Q5: The update check of an installed AgentTacho (after Q4)

In the installed AgentTacho 0.5.0, choose "Check for Updates…".

Expected: "AgentTacho is up to date"; the request goes to `https://api.github.com/repos/AgentTacho/agenttacho/releases/latest`. For this Homebrew install, a later release is offered with `brew upgrade --cask agenttacho` instead of the one-click install (FR-017).
