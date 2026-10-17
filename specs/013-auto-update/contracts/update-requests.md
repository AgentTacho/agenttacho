# Contract: Update Requests

The only network traffic this feature adds (FR-004, FR-005, FR-014). The README's "Security and privacy" section must match this file.

## Common rules

- HTTPS only; ephemeral session, no URL cache, no cookie storage, no `Authorization` header.
- `User-Agent: AgentTacho/<CFBundleShortVersionString>`; no other identifying header.
- Host allowlist: every starting URL (including asset URLs taken from the API response) and every redirect must be `https://` with a host among `api.github.com`, `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`. Anything else is never requested, or aborts with `unexpectedHost`.
- Body caps: 1 MB for `releases/latest`, 64 KB for release information, 100 MB for the disk image.
- Timeouts: 30 s per request for the check, 120 s idle timeout for the download.
- Source: `rhuss/agenttacho`. Only an update-test build (spec FR-025) reads another `owner/repo` from its Info.plist key `AgentTachoUpdateSource`.

## 1. Latest release

`GET https://api.github.com/repos/<owner>/<repo>/releases/latest`
Headers: `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`.

Fields read: `tag_name`, `html_url`, `draft`, `prerelease`, `assets[].name`, `assets[].size`, `assets[].browser_download_url`. Everything else is ignored.

| Response | Meaning |
|---|---|
| 200 | evaluate |
| 404 | no published release: treated as "not newer" |
| 403 or 429 | rate limited: check failed |
| other | check failed |

## 2. Release information

`GET <browser_download_url of the asset named release-info.json>` (redirects to an asset host). Body at most 64 KB, JSON per spec 005 `contracts/release-info.md`.

## 3. Disk image (Install only)

`GET <browser_download_url of the asset named release-info.json's dmg>`; aborted when the asset size or the received bytes exceed 100 MB. Written to `$TMPDIR/dev.rhuss.agenttacho-update/download.dmg`.

## Frequency

One check (requests 1 and 2) 5 minutes after launch and every 24 hours of wall-clock time while running, only with `checksForUpdates` on; plus one per "Check for Updates…". Request 3 only after the user clicks Install. Development builds make no request.
