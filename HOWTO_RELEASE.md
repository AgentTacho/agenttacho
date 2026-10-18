# Releasing (maintainer)

## Signing certificate (once)

Releases and local builds are signed with a self-signed code-signing certificate named "AgentTacho Signing", so macOS recognizes each new build as the same app. Create it once in Keychain Access:

1. Choose Keychain Access > Certificate Assistant > Create a Certificate.
2. Enter the name `AgentTacho Signing` exactly (no space; the build matches the name exactly and otherwise falls back to ad-hoc signing), choose Identity Type "Self Signed Root" and Certificate Type "Code Signing", and select "Let me override defaults".
3. Set the validity period to 3650 days (10 years). Keep the key pair at RSA, 2048 bits. Under Key Usage, check only "Signature"; under Extended Key Usage, keep "Code Signing". Leave Basic Constraints unchecked, uncheck Subject Alternative Name (checked by default, but code signing does not use it), and store the certificate in the login keychain.
4. Open the new certificate in the login keychain, expand Trust and set "Code Signing" to "Always Trust".

`make app` then prints `signing: self-signed (AgentTacho Signing)`. To look up a certificate with another name, pass `SIGN_IDENTITY_NAME="Other name"`. The tier `self-signed` stands for any certificate that is not a Developer ID Application certificate, so a build signed with, for example, an "Apple Development" certificate through `SIGN_IDENTITY` is also reported, released and described in the notes as `self-signed`.

To sign on a second Mac or a CI runner, export the certificate together with its private key as a `.p12` file (select both in Keychain Access, then File > Export Items, and set an export password) and import it there. Both commands ask for their password, so no password ends up on the command line or in the shell history:

```bash
security import AgentTacho-Signing.p12 -k ~/Library/Keychains/login.keychain-db \
  -T /usr/bin/codesign                  # asks for the .p12 export password in a dialog
security set-key-partition-list -S apple-tool:,apple: -s \
  ~/Library/Keychains/login.keychain-db # asks for the login keychain password in the terminal
rm AgentTacho-Signing.p12               # the private key is in the keychain now
```

The second command lets `codesign` use the key without a keychain prompt, which a release without a terminal needs. Delete the `.p12` file after the import (or keep it only in a password manager or vault): anyone with the file and its password can sign builds that macOS treats as AgentTacho. A CI runner has to pass both passwords non-interactively (`-P` and `-k`); take them from the runner's secret store, never from a value typed into a command.

## Notarization profile (once)

Releases with a Developer ID certificate are notarized with the `notarytool` keychain profile `agenttacho-notary`. Store it once. The command asks for an app-specific password for your Apple ID:

```bash
xcrun notarytool store-credentials agenttacho-notary --apple-id <apple-id> --team-id EC5BHUKA6K
```

Without the profile, `make release` stops before building and says how to store it; `ALLOW_UNNOTARIZED=1` releases without notarization on purpose. `make dmg` only warns.

## Publishing a release

```bash
make dmg                                     # dry run, works on any commit
git tag vX.Y.Z && git push origin vX.Y.Z
make release
```

`make dmg` builds `build/release/AgentTacho-<version>.dmg` and its checksum without publishing anything. Untagged or uncommitted builds get a development version such as `0.2.0-dev`, and preflight problems only print warnings.

Every build stamps its release data into `Info.plist`. `AgentTachoVersionDisplay`, `AgentTachoCommit` (full hash), `AgentTachoBuildDate` (ISO 8601, UTC) and `AgentTachoReleaseTag` (release builds only) are the release data for the About tab. `AgentTachoSigning` (`developer-id`, `self-signed` or `ad-hoc`) and `AgentTachoNotarized` (only when `make release` or `make dmg` builds with Developer ID and a working notarization profile; a dry run stamps it too but never submits) are read by the updater to choose how an update is installed, not shown on the About tab. It also bundles `Contents/Resources/changes.json`: the `feat`, `fix` and `perf` commit subjects since the previous `vX.Y.Z` tag (merges and other commit types are left out). The release notes get the same list as their "Changes" section, grouped into Features, Fixes and Performance, so write those subjects for users.

`make release` checks first and stops before building when the working tree has uncommitted changes, the repository is a shallow clone, HEAD has no `vX.Y.Z` tag, the tag is not on `origin` at the same commit, `gh` is not logged in, the GitHub release already exists, only an ad-hoc signature is available, a Developer ID certificate in the keychain is expired or revoked while no usable one exists (so the release would quietly drop to a lower signing tier), or the tap repository cannot be reached. To release on the lower tier anyway, set `ALLOW_TIER_DOWNGRADE=1`; the output then says that the downgrade was deliberate. `make app` and `make dmg` only warn about such a certificate. It then builds and signs the app, creates the DMG, notarizes it when possible, creates a draft GitHub release, uploads the DMG, its `.sha256` file and `release-info.json`, publishes the release, starts the website deploy (`deploy.yml` in `AgentTacho/agenttacho.github.io`) and updates the `agenttacho` cask in `AgentTacho/homebrew-tap`. It starts the deploy only for the latest release of `AgentTacho/agenttacho`. If starting it fails, `make release` prints a warning with the command to run by hand and carries on. Before the upload it checks that the checksum in `release-info.json` matches the final DMG. The cask moves only to the latest published release: replacing the assets of an older tag with `REPLACE=1` leaves it alone, and the GitHub release is marked as latest only when its tag is the highest one. Replacing the assets of a published release turns it back into a draft first and publishes it again once every upload succeeded, so users never see a release with a missing or mismatched DMG; while it is a draft, its downloads are unavailable. If an upload fails, the release stays a draft and the output shows how to retry (`make release REPLACE=1`) or delete it. If the cask update fails after publishing, finish it with the command below, which refuses releases that are still drafts:

```bash
make cask VERSION=X.Y.Z
```

`make cask` downloads the release's DMG and stops when its checksum differs from `release-info.json`.

The release targets read these variables:

| Variable | Default | Meaning |
|---|---|---|
| `SIGN_IDENTITY` | automatic | Identity name or SHA-1 to sign with; `-` forces ad-hoc |
| `SIGN_IDENTITY_NAME` | `AgentTacho Signing` | Name of the self-signed certificate |
| `NOTARY_PROFILE` | `agenttacho-notary` | `notarytool` keychain profile |
| `ALLOW_ADHOC` | unset | `1` allows publishing an ad-hoc signed release |
| `ALLOW_TIER_DOWNGRADE` | unset | `1` allows releasing on a lower tier when the Developer ID certificate is expired or revoked (ad-hoc still needs `ALLOW_ADHOC=1`) |
| `ALLOW_UNNOTARIZED` | unset | `1` allows a Developer ID release without the notarization profile |
| `REPLACE` | unset | `1` replaces the assets of an existing release |
| `TAP_REPO` | `git@github.com:AgentTacho/homebrew-tap.git` | Tap repository; override for testing only |
| `GH_REPO` | `AgentTacho/agenttacho` | GitHub repository of the app; override for testing only |
| `SITE_REPO` | `AgentTacho/agenttacho.github.io` | Website repository whose `deploy.yml` a latest release starts; override for testing only |
| `VERSION` | required for `make cask` | Version of an already published release |

`TAP_REPO`, `GH_REPO` and `SITE_REPO` exist so tests and trial runs can point at a scratch tap or repository. With another `GH_REPO`, `make release` does not start the website deploy.

To try one-click install end to end before a release contains it, `make app-update-test UPDATE_SOURCE=owner/repo` builds `build/AgentTacho.app` with an update-test flag that reads releases from that repository instead of `AgentTacho/agenttacho` (and checks although it is not a tagged release build). `make app` never sets the flag, and `make release` and `make dmg` refuse to run when `UPDATE_TEST` is set. The procedure is in `specs/013-auto-update/quickstart.md`. The cask's download URL and the `brew install` command in the release notes always name `AgentTacho/agenttacho` and `agenttacho/tap`, whatever these variables say.

The DMG backgrounds live in `Resources/dmg/` and are generated by `make backgrounds`: the notarized one (used by every Developer ID release) draws its title on the committed artwork `background-notarized-base.png`, and the unnotarized one, with the first-launch steps, is drawn entirely from code. The window size and icon positions for each are in `scripts/release/dmg-settings.py`.

## After a release

Set the website's fallback release to the new version (`src/data/release-fallback.json`, see [docs/website.md](docs/website.md) under Deploy). `make release` already starts the site deploy.
