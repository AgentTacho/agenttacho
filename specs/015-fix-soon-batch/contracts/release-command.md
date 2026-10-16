# Contract: Release Command Changes (spec 015)

Extends `specs/005-macos-distribution/contracts/make-targets.md`. Only the differences are listed.

## Variables

| Variable | Used by | Effect |
|---|---|---|
| `ALLOW_TIER_DOWNGRADE=1` | `make release`, `make dmg` (dry run) | Lets a release continue on the next tier when a Developer ID certificate is expired or revoked and no usable one exists. Passed through by the Makefile like `ALLOW_ADHOC`. |

## Preflight outcomes (automatic identity selection, no `SIGN_IDENTITY`)

| Keychain | `ALLOW_TIER_DOWNGRADE` | `make release` | `make dmg` (dry run) | `make app` |
|---|---|---|---|---|
| usable Developer ID (any other, also not-trusted) | any | Developer ID, as today | as today | as today |
| expired/revoked Developer ID + self-signed | unset | stops: `error: Developer ID certificate "<name>" is expired; renew it, or set ALLOW_TIER_DOWNGRADE=1 to release as self-signed` (revoked: `is revoked`) | warning with the same facts plus `a real release would stop unless ALLOW_TIER_DOWNGRADE=1 is set` | self-signed, warning naming the certificate |
| expired/revoked Developer ID + self-signed | `1` | self-signed, warning `releasing on a lower tier than Developer ID (deliberate tier downgrade)` | same warning | as above |
| expired/revoked Developer ID only | unset | stops: same message, ending `to release on the next tier (ad-hoc, which also needs ALLOW_ADHOC=1)` | warnings (tier guard and ad-hoc) | ad-hoc, warning |
| expired/revoked Developer ID only | `1` | stops unless `ALLOW_ADHOC=1` too (existing ad-hoc check) | warnings | ad-hoc, warning |
| no Developer ID at all | any | as today | as today | as today |

With `SIGN_IDENTITY` set, the guard does not apply (clarification Q2). The `make app` warning appears only when `SIGN_IDENTITY` is empty; `release.sh` calls the build with a forced identity, so a release does not print it again.

## Replacing a published release (`REPLACE=1`)

Order of `gh` calls after the build:

1. `gh release view <tag>` (exists, isDraft false) and the latest check by version: `gh release list --exclude-drafts --json tagName` plus `<tag>` through `highest_release_tag`; `<tag>` is latest when it is the result.
2. `gh release edit <tag> --draft=true`; the phase is now `draft`.
3. `gh release upload <tag> <asset> --clobber` for the DMG, checksum and release-info.json.
4. `gh release edit <tag> --draft=false --notes-file <notes>` plus `--latest` when `<tag>` is latest, otherwise `--latest=false`.
5. Cask update as today.

Every publish uses step 4's flags: a new release, a replacement of a draft, and a retry after a failed replacement (which finds a draft), so a retried older tag never becomes "Latest".

On a failure after step 2, the exit message is the existing draft message: `error: <step> failed; draft release <tag> left in place, retry with: make release REPLACE=1, or delete with: gh release delete <tag> -R <repo> --yes`. A failure in step 2 itself leaves the release published and unchanged.
