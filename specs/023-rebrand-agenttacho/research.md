# Research: Name the app AgentTacho

## R1: The Homebrew cask

- **Decision**: The tap update writes `Casks/agenttacho.rb` in `AgentTacho/homebrew-tap` and nothing else, in one commit. A second run for the same version finds nothing to change (spec FR-016).
- **Rationale**: One cask per app keeps the tap simple. The cask has no `auto_updates true`, so `brew upgrade` upgrades it without `--greedy`.

## R3: The DMG backgrounds

- **Decision**: The unnotarized background is rendered by `scripts/release/render-dmg-backgrounds.swift`, and `make backgrounds` regenerates it. The notarized background was committed artwork with its title painted in. It is split once into a title-less base (`Resources/dmg/background-notarized-base.png` and `@2x`), made by filling the title band with background pixels sampled from the same rows outside the text, and the render script draws "Drag AgentTacho to Applications" on the base in a rounded bold system font (closer to the painted weight than semibold, chosen during implementation) in the teal of the original (sampled from the artwork). `make backgrounds` then produces both backgrounds.
- **Rationale**: The title sits on a calm cream area (about y 70 to 110 at 1x, x 190 to 640) with no mascot or arrow behind it, so filling the band is straightforward and checkable by eye. Rendering the title from text keeps it in sync with the app name, without image editing.
- **Fallback**: If the filled band shows visible seams in either scale, the maintainer regenerates the artwork without text using the original prompt; the render script then works unchanged on the new base.
- **Alternatives considered**: Editing the PNG by hand (no repeatable process); dropping the title (the drag hint helps first-time users).

## R6: Names of targets, files and identifiers

- **Decision**: The executable target and product are `AgentTacho` in `Sources/AgentTacho`, the package is `agenttacho`, the app struct is `AgentTachoApp`. Icon files (`AgentTacho.icns`, `AgentTacho.png`, `AgentTacho-mono.png`, `AgentTacho.iconset`, `AgentTachoMonochrome.xcassets` and its image sets, master PNGs), the cask template `packaging/homebrew/agenttacho.rb.tmpl` and `docs/images/agenttacho-dropdown.png` carry the name; files are moved with `git mv` so history follows. The Info.plist keys use the `AgentTacho` prefix in `build-app.sh`, `AppVersionInfo` and `InstallEnvironment` together (FR-004). `ConfigurationLoadNotes`' identifier is `agenttacho.configurationLoadNotes`. `UpdateOutcome.folderName` is `dev.rhuss.agenttacho-update`.
- **Rationale**: One name everywhere, in the code and in what the user sees.

## R7: Signing and notarization names

- **Decision**: `NOTARY_PROFILE` default `agenttacho-notary` (FR-015) and `SIGN_IDENTITY_NAME` default `AgentTacho Signing` (the self-signed fallback identity, used only without a Developer ID). The README's release section shows how to store the notary profile (`xcrun notarytool store-credentials agenttacho-notary ...`) and how to create the self-signed identity. A Developer ID release without the profile stops before building, unless `ALLOW_UNNOTARIZED=1` (added in code review).
- **Rationale**: Both are local keychain names that match the app. The Developer ID itself (team `EC5BHUKA6K`) is not tied to the app name.

## R8: Starting the site deploy

- **Decision**: In `release.sh`, after `published` and before `bash "$UPDATE_CASK_SH"`, when `latest_flag` is `--latest` and `GH_REPO` equals the official default, run `gh workflow run deploy.yml -R "$SITE_REPO"` (default `AgentTacho/agenttacho.github.io`, overridable for testing). On failure, `log release "warning: ..."` with the command to run by hand, and continue (FR-018).

## R9: Order of operations

- **Decision**: (1) `021-recover-stuck-offline` lands on `main`. (2) This branch rebases on it and implements the names. (3) With the maintainer's approval, the repository settings: `origin` set to `git@github.com:AgentTacho/agenttacho.git` and the homepage `https://agenttacho.github.io` (FR-020). (4) Merge to `main`, push. (5) The maintainer stores the `agenttacho-notary` profile. (6) Tag `v0.5.0`, `make release`. (7) Post-release checks Q3 to Q5.
- **Rationale**: The code does not need the repository settings to build or test, so implementation can start before them.
