# Contract: Release, cask and site deploy

Spec FR-013 to FR-019. Extends `specs/005-macos-distribution/contracts/` and `specs/013-auto-update/contracts/`.

## Names produced by `make release` for version X.Y.Z

| Artifact | Name |
|---|---|
| App bundle | `build/AgentTacho.app` (bundle identifier `dev.rhuss.agenttacho`) |
| DMG | `build/release/AgentTacho-X.Y.Z.dmg`, volume name `AgentTacho` |
| Checksum | `AgentTacho-X.Y.Z.dmg.sha256` |
| `release-info.json` | `"dmg": "AgentTacho-X.Y.Z.dmg"`, other fields unchanged |
| GitHub release | title `AgentTacho X.Y.Z` in `AgentTacho/agenttacho` |
| Release notes | say AgentTacho; install line `brew install --cask rhuss/tap/agenttacho` |

## Defaults (`lib.sh release_defaults`)

| Variable | Default |
|---|---|
| `GH_REPO` | `AgentTacho/agenttacho` |
| `TAP_REPO` | `git@github.com:rhuss/homebrew-tap.git` (unchanged) |
| `SITE_REPO` (new) | `AgentTacho/agenttacho.github.io` |
| `NOTARY_PROFILE` | `agenttacho-notary` (missing in a Developer ID release: stop, unless `ALLOW_UNNOTARIZED=1`) |
| `SIGN_IDENTITY_NAME` | `AgentTacho Signing` |
| `APP_ICON` | `Resources/icons/macos/AgentTacho.icns` |

## Step order after the upload

1. Publish the release (unchanged).
2. **New**: if the release is marked latest and `GH_REPO` equals the default, run `gh workflow run deploy.yml -R "$SITE_REPO"`. Success: `release: started site deploy in <SITE_REPO>`. Failure: `release: warning: could not start the site deploy (<reason>); start it with: gh workflow run deploy.yml -R <SITE_REPO>`, and continue. Not latest or overridden `GH_REPO`: no call, no output.
3. Cask update (`update-cask.sh`), unchanged in its checks.

The exit status is decided only by the existing steps; step 2 never fails the release.

## Tap commit (`update-cask.sh`)

In the fresh tap clone:

1. Render `packaging/homebrew/agenttacho.rb.tmpl` to `Casks/agenttacho.rb`.
2. If `Casks/agentmeter.rb` exists: `git rm` it.
3. If `cask_renames.json` lacks `"agentmeter": "agenttacho"`: write it, keeping other entries (`jq '. + {"agentmeter": "agenttacho"}'`, starting from `{}` when the file is missing).
4. One commit `agenttacho X.Y.Z` (plus ` (renamed from agentmeter)` when step 2 or 3 changed something); push.

A second run for the same version finds nothing to change and logs `already up to date (agenttacho X.Y.Z)`.

## Cask template

```ruby
cask "agenttacho" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/AgentTacho/agenttacho/releases/download/v#{version}/AgentTacho-#{version}.dmg"
  name "AgentTacho"
  desc "Menu bar meter for coding-agent usage limits and budgets"
  homepage "https://github.com/AgentTacho/agenttacho"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "AgentTacho.app"

  uninstall quit: "dev.rhuss.agenttacho"

  zap trash: [
    "~/.config/agenttacho",
    "~/Library/Application Support/agenttacho",
    "~/Library/Logs/agenttacho",
    "~/Library/Preferences/dev.rhuss.agenttacho.plist",
  ]

  caveats <<~EOS
@CAVEATS@
  EOS
end
```

## Tests (`make test-release`, stubbed `gh` and a local bare tap repository)

- Built names: app, DMG, checksum, `release-info.json`, release title.
- Site deploy: started once for a latest release before the cask step; not started for an older tag or an overridden `GH_REPO`; a failing `gh workflow run` prints the warning, the cask is still updated, exit status 0.
- Tap: first run removes `Casks/agentmeter.rb`, adds the rename entry, writes `Casks/agenttacho.rb`; an existing `cask_renames.json` with other entries keeps them; a second run is a no-op.
- Defaults: `GH_REPO`, `SITE_REPO`, `NOTARY_PROFILE`, `SIGN_IDENTITY_NAME`, `APP_ICON`.
