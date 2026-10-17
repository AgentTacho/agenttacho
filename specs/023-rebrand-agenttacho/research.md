# Research: Rebrand AgentMeter to AgentTacho

## R1: Renaming the Homebrew cask inside the tap

- **Decision**: The first AgentTacho cask update writes `Casks/agenttacho.rb`, removes `Casks/agentmeter.rb` with `git rm`, and adds `"agentmeter": "agenttacho"` to `cask_renames.json` at the tap root (merged with `jq` into any existing object), all in one commit. The step is idempotent: when the old cask file is gone and the entry exists, later updates touch only `Casks/agenttacho.rb` (spec FR-016).
- **Rationale**: Homebrew's [rename guide](https://docs.brew.sh/Rename-A-Formula) defines `cask_renames.json` as an object mapping old token to new token, used "during updates and `brew migrate`", and requires the target to exist in the same tap. The cask has no `auto_updates true`, so `brew upgrade` upgrades it without `--greedy`.
- **Open risk**: The docs do not spell out that `brew upgrade` removes the old version's `AgentMeter.app`. Homebrew uninstalls an installed cask version from its stored caskfile, which lists `AgentMeter.app`, so removal is expected; the quickstart verifies it on a real install (scenario Q6). If it does not remove it, the README's moving instructions already say to delete `AgentMeter.app` by hand (FR-023).
- **Alternatives considered**: Keeping both casks with the old one marked `deprecate!` (users stay on AgentMeter until they read the message); `tap_migrations.json` (meant for moving between taps, not renames).

## R2: GitHub redirects after transfer and rename

- **Decision**: Transfer `rhuss/agentmeter` to the `AgentTacho` organization first (it keeps the name `agentmeter`), then rename it to `agenttacho`. Verify redirects with `curl -sIL` right after (quickstart Q1), before 0.5.0.
- **Rationale**: GitHub redirects web, git and API requests after both a transfer and a rename, as long as nobody creates a repository at the old path. Release asset downloads (`github.com/<owner>/<repo>/releases/download/...`) are web URLs and follow the same redirect, ending on `release-assets.githubusercontent.com` or `objects.githubusercontent.com`, both in `UpdateHostPolicy.allowedHosts`. The API answers a moved repository with a 301 to `api.github.com/repositories/<id>/...`, same host. Installed 0.4.x copies follow redirects within allowed hosts (spec 013).
- **Alternatives considered**: Creating a fresh `AgentTacho/agenttacho` and archiving the old repository (no redirect, loses issues and release history).

## R3: The DMG backgrounds

- **Decision**: The unnotarized background is rendered by `scripts/release/render-dmg-backgrounds.swift`; only its strings change, and `make backgrounds` regenerates it. The notarized background is committed artwork with "Drag AgentMeter to Applications" painted into it. Split it once into a title-less base (`Resources/dmg/background-notarized-base.png` and `@2x`), made by filling the title band with background pixels sampled from the same rows outside the text, and let the render script draw the title on the base in a rounded bold system font (closer to the painted weight than semibold, chosen during implementation) in the teal of the original (sampled from the artwork). `make backgrounds` then produces both backgrounds, so a future rename needs no image editing.
- **Rationale**: The title sits on a calm cream area (about y 70 to 110 at 1x, x 190 to 640) with no mascot or arrow behind it, so filling the band is straightforward and checkable by eye. Rendering the title from text keeps it in sync with the app name.
- **Fallback**: If the filled band shows visible seams in either scale, the maintainer regenerates the artwork without text using the original prompt; the render script then works unchanged on the new base.
- **Alternatives considered**: Editing the PNG by hand once (no repeatable process); dropping the title (the drag hint helps first-time users).

## R4: The one-time move of AgentMeter's settings

- **Decision**: A new `LegacyDataMove` in `UsageCore` (pure file operations, injectable `Paths` and `FileManager`) runs in `AppModel.init(paths:)` right after the `DiagnosticLog` is created and before `ConfigStore`, `ImportedPriceStore` and `LastGoodStore` read their files. It returns which files it copied and which failed; `AppModel` writes the log lines (FR-011). The trigger is "new configuration folder does not exist" (FR-008). Each copy goes to a temporary file in the destination folder and is then moved into place, so a carried-over name never holds a partial file (FR-010). The source is opened read-only and never modified (FR-009).
- **Rationale**: `SingleInstance.ensure()` already runs in `AgentTachoApp.init()` before `AppModel()` exists, so the running-copy check (FR-012) precedes the move by construction. The log folder is separate from the configuration folder, so creating the log first does not defeat the trigger.
- **Alternatives considered**: Running the move in `AgentTachoApp.init()` before `AppModel` (no log yet, results would have to be carried over); moving instead of copying (would write to AgentMeter's folders, forbidden by FR-009 and AGENTS.md's read-only rule in spirit).

## R5: Detecting a running AgentMeter

- **Decision**: `RunningInstance` gains the app name per bundle identifier (`dev.rhuss.agenttacho` gives "AgentTacho", `dev.rhuss.agentmeter` gives "AgentMeter") and `others(from:ownPID:bundleIdentifiers:)` accepts the own and the legacy identifier. `SingleInstance.ensure()` queries `NSRunningApplication` for both identifiers and shows the existing alert with the other app's name (FR-012).
- **Rationale**: Reuses the tested alert, stop and timeout logic; the only change is which identifiers count and which name the summary shows.
- **Alternatives considered**: A separate alert for AgentMeter (duplicates logic and copy).

## R6: Renaming targets, files and identifiers

- **Decision**: Rename with `git mv` so history follows: `Sources/AgentMeter` to `Sources/AgentTacho`, the executable target and product `AgentTacho`, the package name `agenttacho`, `AgentMeterApp` to `AgentTachoApp`, icon files (`AgentMeter.icns`, `AgentMeter.png`, `AgentMeter-mono.png`, `AgentMeter.iconset`, `AgentMeterMonochrome.xcassets` and its image sets, master PNGs), `packaging/homebrew/agentmeter.rb.tmpl` to `agenttacho.rb.tmpl`, `docs/images/agentmeter-dropdown.png` to `agenttacho-dropdown.png`. Info.plist keys `AgentMeter*` become `AgentTacho*` in `build-app.sh`, `AppVersionInfo` and `InstallEnvironment` together (FR-004). `ConfigurationLoadNotes`' identifier becomes `agenttacho.configurationLoadNotes`. `UpdateOutcome.folderName` becomes `dev.rhuss.agenttacho-update`.
- **Rationale**: Clean break (brainstorm 22): no old name inside the code except the legacy paths and identifier needed for FR-008 and FR-012.

## R7: Signing and notarization names

- **Decision**: `NOTARY_PROFILE` default `agenttacho-notary` (FR-015) and `SIGN_IDENTITY_NAME` default `AgentTacho Signing` (the self-signed fallback identity, used only without a Developer ID). The README's release section shows how to store the notary profile (`xcrun notarytool store-credentials agenttacho-notary ...`) and how to create the self-signed identity under the new name.
- **Rationale**: Both are local keychain names; keeping the old ones would leave "agentmeter" in the scripts and break the name check. The Developer ID itself (team `EC5BHUKA6K`) is not tied to the app name.

## R8: Starting the site deploy

- **Decision**: In `release.sh`, after `published` and before `bash "$UPDATE_CASK_SH"`, when `latest_flag` is `--latest` and `GH_REPO` equals the official default, run `gh workflow run deploy.yml -R "$SITE_REPO"` (default `AgentTacho/agenttacho.github.io`, overridable for testing). On failure, `log release "warning: ..."` with the command to run by hand, and continue (FR-018). Carried over from spec 022 FR-006 and FR-007.

## R9: Order of operations

- **Decision**: (1) `021-recover-stuck-offline` lands on `main`. (2) This branch rebases on it and implements the rename. (3) With the maintainer's approval, the transfer and rename on GitHub, followed at once by the redirect checks (quickstart Q1) and `git remote set-url`. (4) Merge to `main`, push. (5) The maintainer stores the `agenttacho-notary` profile. (6) Tag `v0.5.0`, `make release`. (7) Post-release checks Q5 to Q7.
- **Rationale**: FR-020 requires the transfer before the merge; the code does not need the transfer to build or test, so implementation can start before it.
