# Contract: release-info.json

Uploaded as an asset of every GitHub release. Read by `make cask` to render the cask for an existing release.

## Schema

```json
{
  "version": "X.Y.Z",
  "dmg": "AgentTacho-X.Y.Z.dmg",
  "sha256": "<64 lowercase hex characters>",
  "tier": "developer-id | self-signed | ad-hoc",
  "notarized": true
}
```

Rules:
- All five keys are required; no other keys are written.
- `version` matches `^[0-9]+\.[0-9]+\.[0-9]+$` and equals the tag without `v`.
- `dmg` equals `AgentTacho-<version>.dmg` and is an asset of the same release.
- `sha256` equals the content of `AgentTacho-<version>.dmg.sha256` (the first field) and the SHA-256 of the uploaded DMG.
- `notarized` is `true` only when `tier` is `developer-id`.

## Example (self-signed release)

```json
{
  "version": "0.2.0",
  "dmg": "AgentTacho-0.2.0.dmg",
  "sha256": "3b1f0c9e4a8d2b7f6e5c4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d",
  "tier": "self-signed",
  "notarized": false
}
```

## Checksum file

`AgentTacho-<version>.dmg.sha256` contains one line in `shasum -a 256` format: `<sha256>  AgentTacho-<version>.dmg`.
