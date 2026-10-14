# Contract: Make Targets and Release Scripts

All targets run non-interactively (FR-018). Failures print `error: <reason>` on stderr and exit with a non-zero status. Informational lines use the prefixes `signing:`, `version:`, `dmg:`, `notary:`, `release:`, `cask:`, `warning:`.

## Variables

| Variable | Default | Used by | Meaning |
|---|---|---|---|
| `SIGN_IDENTITY` | (unset: automatic selection) | app, dmg, release | Explicit identity (name or SHA-1); `-` forces ad-hoc |
| `SIGN_IDENTITY_NAME` | `AgentMeter Signing` | app, dmg, release | Name of the self-signed certificate looked up in tier 2 |
| `NOTARY_PROFILE` | `agentmeter-notary` | dmg, release | `notarytool` keychain profile |
| `ALLOW_ADHOC` | unset | release | `1` allows publishing an ad-hoc signed release |
| `REPLACE` | unset | release | `1` replaces assets of an existing release for the tag |
| `VERSION` | (required) | cask | Version `X.Y.Z` of an already published release |
| `TAP_REPO` | `git@github.com:rhuss/homebrew-tap.git` | release, cask | Tap repository URL; other values are meant for testing only |
| `GH_REPO` | `rhuss/agentmeter` | release, cask | GitHub repository of the app; other values are meant for testing only |

`TAP_REPO` and `GH_REPO` redirect where the scripts read and write, so tests and trial runs can use a scratch tap or repository. The published artifacts do not follow them: the cask's `url` and `homepage` and the `brew install` command in the release notes always name `rhuss/agentmeter` and `rhuss/tap`. All variables reach the scripts through the environment (the Makefile exports them), never as text pasted into a recipe.

## Targets

### `make app`
Builds `build/AgentMeter.app` (FR-001 to FR-008).
- Output includes `version: <display_version> (build <n>)` and `signing: <tier> (<identity name>)`.
- Ad-hoc adds `warning: ad-hoc signature, notification permission and start at login will not persist across rebuilds`.
- Fails when `Resources/icons/macos/AgentMeter.icns` is missing: `error: missing app icon: Resources/icons/macos/AgentMeter.icns`.
- Fails when a non-ad-hoc build has a `cdhash` designated requirement.
- A binary with SwiftPM's native resource accessor (it finds resources only on the build machine) prints `warning: SwiftPM's native resource accessor: ...` and still builds; with `DISTRIBUTION=1` (set by `make dmg` and `make release`) the build stops with `error:`.

### `make dmg` (dry run, FR-019)
Builds the app like `make app`, but with `DISTRIBUTION=1` (a native resource accessor stops the dry run), then creates `build/release/AgentMeter-<display_version>.dmg` and `.sha256`. Never writes to GitHub or the tap and never notarizes; it may read from them for the preflight checks. Preflight problems, including failed reads (offline, not authenticated), print as `warning:` lines. Output ends with `dmg: <path> (<tier>, not notarized|notarizable)`.

### `make release` (FR-015 to FR-017)
Steps in order, stopping at the first failure:
1. Preflight: clean tree; not a shallow clone (the build number would be wrong); HEAD exactly at `vX.Y.Z`; `git ls-remote origin refs/tags/vX.Y.Z refs/tags/vX.Y.Z^{}` resolves to `git rev-parse HEAD` (peeled `^{}` entry for annotated tags, plain entry for lightweight tags); `gh auth status` succeeds; no release for the tag unless `REPLACE=1`; tier is not ad-hoc unless `ALLOW_ADHOC=1`; `git ls-remote $TAP_REPO` succeeds.
2. For the `developer-id` tier, check the notarization profile: `missing` (no keychain item) prints a `warning:` and continues as "Developer ID, not notarized"; any other notarytool failure stops the release (a dry run only warns).
3. Build app (with `DISTRIBUTION=1`, which refuses SwiftPM's native resource accessor), create DMG, notarize when the profile works.
4. Write `build/release/release-notes.md` and `build/release/release-info.json`, then check that the `sha256` in `release-info.json` equals the SHA-256 of the final (stapled) DMG; a mismatch stops with `error: release-info.json has sha256 <x>, but <dmg> has <y>` before anything is written to GitHub (also in the dry run).
5. `gh release create vX.Y.Z --draft --verify-tag` (skipped with `REPLACE=1` when the release exists), upload DMG, `.sha256`, `release-info.json` (`--clobber` with `REPLACE=1`), then publish (`--draft=false`).
6. Run the cask update (same code as `make cask`, including the latest-release check, so `REPLACE=1` on an older tag leaves the cask unchanged).

Exit status 0 only when every step including the cask update succeeded. Messages on partial failure:
- after draft creation, before publishing: `error: …; draft release vX.Y.Z left in place, retry with: make release REPLACE=1, or delete with: gh release delete vX.Y.Z -R <GH_REPO> --yes`
- replacing assets of a published release (`REPLACE=1`) failed: `error: …; release vX.Y.Z is published, retry with: make release REPLACE=1`
- after publishing, cask failed: `error: cask update failed; finish with: make cask VERSION=X.Y.Z`

### `make cask VERSION=X.Y.Z` (FR-021a)
Fails when the release does not exist or is still a draft. Updates the cask only when `vX.Y.Z` is the latest published (non-draft) release of `GH_REPO` (`gh release list --exclude-drafts`, versions compared numerically per component); otherwise prints `cask: vX.Y.Z is not the latest release, cask left unchanged` and exits 0. Then downloads `release-info.json` and `AgentMeter-X.Y.Z.dmg` of the release and stops when the DMG's SHA-256 differs from the `sha256` in `release-info.json`. Renders the cask, clones the tap into a temporary directory, writes `Casks/agentmeter.rb`, commits `agentmeter X.Y.Z` (skips commit with `cask: already up to date` when unchanged), pushes. Error messages of failed `git` and `gh` calls end with the last line of the command's stderr in parentheses.

### `make test-release`
Runs `scripts/release/tests/run.sh`; prints one line per test and a summary `N passed, M failed`; exits non-zero on any failure.

### `make backgrounds`
Regenerates `Resources/dmg/*.png` from `scripts/release/render-dmg-backgrounds.swift`. Not part of `make release`; the images are committed.
