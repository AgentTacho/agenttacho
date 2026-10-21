# Release runbook (maintainer)

This runbook publishes a new AgentTacho release: the signed, notarized DMG on GitHub, the website deploy and the Homebrew cask. Follow the steps in order. The one-time prerequisites are set up once per machine; the per-release steps run for every version.

- **Prerequisites** (once per machine): the signing certificate and the notarization profile.
- **Release a new version** (every release): preflight, dry run, tag, release, verify, site fallback.
- **Recovery** when a step fails.
- **Reference** for the variables, CI signing, the update test and the DMG backgrounds.

Build only through the Makefile (constitution IV). Publishing is the maintainer's call for each run: do not run `make release` or start a deploy without deciding to for that version.

---

## Prerequisites (once per machine)

### A. Signing certificate

Releases and local builds are signed with a self-signed code-signing certificate named "AgentTacho Signing", so macOS recognizes each new build as the same app. Create it once in Keychain Access:

1. Choose Keychain Access > Certificate Assistant > Create a Certificate.
2. Enter the name `AgentTacho Signing` exactly (no space; the build matches the name exactly and otherwise falls back to ad-hoc signing), choose Identity Type "Self Signed Root" and Certificate Type "Code Signing", and select "Let me override defaults".
3. Set the validity period to 3650 days (10 years). Keep the key pair at RSA, 2048 bits. Under Key Usage, check only "Signature"; under Extended Key Usage, keep "Code Signing". Leave Basic Constraints unchecked, uncheck Subject Alternative Name (checked by default, but code signing does not use it), and store the certificate in the login keychain.
4. Open the new certificate in the login keychain, expand Trust and set "Code Signing" to "Always Trust".

**Check:** `make app` prints `signing: self-signed (AgentTacho Signing)`.

To look up a certificate with another name, pass `SIGN_IDENTITY_NAME="Other name"`. The tier `self-signed` stands for any certificate that is not a Developer ID Application certificate, so a build signed with, for example, an "Apple Development" certificate through `SIGN_IDENTITY` is also reported, released and described in the notes as `self-signed`.

To sign on a second Mac or a CI runner, see [Signing on a second Mac or CI](#signing-on-a-second-mac-or-ci) in the reference.

### B. Notarization profile

Releases with a Developer ID certificate are notarized with the `notarytool` keychain profile `agenttacho-notary`. Store it once. The command asks for an app-specific password for your Apple ID:

```bash
xcrun notarytool store-credentials agenttacho-notary --apple-id <apple-id> --team-id EC5BHUKA6K
```

**Check:** `make release` no longer stops with a message about the missing profile.

Without the profile, `make release` stops before building and says how to store it; `ALLOW_UNNOTARIZED=1` releases without notarization on purpose. `make dmg` only warns.

---

## Release a new version

Pick the version `X.Y.Z` first. Write the commit subjects for users: the release notes are built from the `feat`, `fix` and `perf` commit subjects since the previous `vX.Y.Z` tag (merges and other commit types are left out), grouped into Features, Fixes and Performance.

### Step 1: Preflight

Make sure the working tree is clean and on the commit you want to release.

```bash
git status            # working tree is clean, no uncommitted changes
git log --oneline -5  # HEAD is the commit to release
```

`make release` also checks this for you and stops before building (see [Step 4](#step-4-publish-the-release)), but a clean tree now avoids a late failure.

### Step 2: Dry run

Build the DMG without publishing anything, on any commit.

```bash
make dmg
```

**Check:** `build/release/AgentTacho-<version>.dmg` and its `.sha256` checksum exist, and the command reports the signing tier. Untagged or uncommitted builds get a development version such as `0.2.0-dev`, and preflight problems only print warnings here, not errors.

Every build stamps its release data into `Info.plist`: `AgentTachoVersionDisplay`, `AgentTachoCommit` (full hash), `AgentTachoBuildDate` (ISO 8601, UTC) and `AgentTachoReleaseTag` (release builds only) feed the About tab; `AgentTachoSigning` (`developer-id`, `self-signed` or `ad-hoc`) and `AgentTachoNotarized` are read by the updater to choose how an update is installed. It also bundles `Contents/Resources/changes.json` with the commit subjects described above.

### Step 3: Tag the release

Tag the commit and push the tag to `origin`.

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

**Check:** `git ls-remote --tags origin vX.Y.Z` shows the tag at the same commit as your local `HEAD`.

### Step 4: Publish the release

```bash
make release
```

`make release` checks first and stops before building when any of these is true:

- the working tree has uncommitted changes,
- the repository is a shallow clone,
- `HEAD` has no `vX.Y.Z` tag,
- the tag is not on `origin` at the same commit,
- `gh` is not logged in,
- the GitHub release already exists,
- only an ad-hoc signature is available,
- a Developer ID certificate in the keychain is expired or revoked while no usable one exists (so the release would quietly drop to a lower signing tier),
- the tap repository cannot be reached.

To release on a lower signing tier on purpose, set `ALLOW_TIER_DOWNGRADE=1`; the output then says the downgrade was deliberate. `make app` and `make dmg` only warn about such a certificate.

When the checks pass, `make release` builds and signs the app, creates the DMG, notarizes it when possible, creates a draft GitHub release, uploads the DMG, its `.sha256` file and `release-info.json`, publishes the release, starts the website deploy (`deploy.yml` in `AgentTacho/agenttacho.github.io`) and updates the `agenttacho` cask in `AgentTacho/homebrew-tap`. Before the upload it checks that the checksum in `release-info.json` matches the final DMG.

The cask moves only to the latest published release, and the GitHub release is marked latest only when its tag is the highest one. The website deploy starts only for the latest release of `AgentTacho/agenttacho`; if starting it fails, `make release` prints a warning with the command to run by hand and carries on.

### Step 5: Verify

Confirm the release is live and complete.

- The GitHub release for `vX.Y.Z` is published (not a draft) and carries the DMG, its `.sha256` and `release-info.json`.
- The release notes list the expected changes.
- `brew update && brew info --cask agenttacho/tap/agenttacho` shows the new version (the tap can lag GitHub by a little).
- The website deploy for `AgentTacho/agenttacho.github.io` ran.

### Step 6: Update the site's fallback release

The site's download button reads the latest release from the GitHub API at build time. When that call fails, the build falls back to `src/data/release-fallback.json`, so the file must always name a DMG that exists. `make release` does not touch it, and it is easy to forget: it fell two releases behind before this step existed.

In the site checkout, on a branch, set the version and the DMG name and open a pull request (never push to the site's `main` directly):

```bash
cd <site checkout>
git switch -c release-fallback-X.Y.Z origin/main
printf '{ "version": "X.Y.Z", "dmg": "AgentTacho-X.Y.Z.dmg" }\n' > src/data/release-fallback.json
npm run check && npm run build && npm test
git commit -am "chore: release fallback X.Y.Z"
gh pr create --fill
```

**Check:** after the pull request is merged, `src/data/release-fallback.json` on the site's `main` names `X.Y.Z`. The release is complete only then.

---

## Recovery

### An upload failed, or the release is stuck as a draft

Replacing the assets of a published release turns it back into a draft first and publishes it again once every upload succeeded, so users never see a release with a missing or mismatched DMG; while it is a draft, its downloads are unavailable. If an upload fails, the release stays a draft. Retry or delete it:

```bash
make release REPLACE=1   # replace the assets of the existing release
```

Replacing the assets of an older tag with `REPLACE=1` leaves the cask alone.

### The cask update failed after publishing

Finish it with the command below, which refuses releases that are still drafts:

```bash
make cask VERSION=X.Y.Z
```

`make cask` downloads the release's DMG and stops when its checksum differs from `release-info.json`.

### The website deploy did not start

`make release` prints the command to start it by hand; run that command. The deploy starts only for the latest release of `AgentTacho/agenttacho`.

---

## Reference

### Release variables

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

### Signing on a second Mac or CI

Export the certificate together with its private key as a `.p12` file (select both in Keychain Access, then File > Export Items, and set an export password) and import it there. Both commands ask for their password, so no password ends up on the command line or in the shell history:

```bash
security import AgentTacho-Signing.p12 -k ~/Library/Keychains/login.keychain-db \
  -T /usr/bin/codesign                  # asks for the .p12 export password in a dialog
security set-key-partition-list -S apple-tool:,apple: -s \
  ~/Library/Keychains/login.keychain-db # asks for the login keychain password in the terminal
rm AgentTacho-Signing.p12               # the private key is in the keychain now
```

The second command lets `codesign` use the key without a keychain prompt, which a release without a terminal needs. Delete the `.p12` file after the import (or keep it only in a password manager or vault): anyone with the file and its password can sign builds that macOS treats as AgentTacho. A CI runner has to pass both passwords non-interactively (`-P` and `-k`); take them from the runner's secret store, never from a value typed into a command.

### Test one-click install before a release

To try one-click install end to end before a release contains it, `make app-update-test UPDATE_SOURCE=owner/repo` builds `build/AgentTacho.app` with an update-test flag that reads releases from that repository instead of `AgentTacho/agenttacho` (and checks although it is not a tagged release build). `make app` never sets the flag, and `make release` and `make dmg` refuse to run when `UPDATE_TEST` is set. The procedure is in `specs/013-auto-update/quickstart.md`. The cask's download URL and the `brew install` command in the release notes always name `AgentTacho/agenttacho` and `agenttacho/tap`, whatever these variables say.

### DMG backgrounds

The DMG backgrounds live in `Resources/dmg/` and are generated by `make backgrounds`: the notarized one (used by every Developer ID release) draws its title on the committed artwork `background-notarized-base.png`, and the unnotarized one, with the first-launch steps, is drawn entirely from code. The window size and icon positions for each are in `scripts/release/dmg-settings.py`.
