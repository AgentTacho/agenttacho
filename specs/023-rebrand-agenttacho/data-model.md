# Data Model: Rebrand AgentMeter to AgentTacho

## Paths (changed)

`Paths` keeps its injectable home directory. Current locations move to the new name; the old ones become read-only legacy locations.

| Property | Value |
|---|---|
| `configDirectoryURL` (new) | `~/.config/agenttacho/` |
| `configFileURL` | `~/.config/agenttacho/config.json` |
| `importedPricesFileURL` | `~/.config/agenttacho/imported-prices.json` |
| `logFileURL` | `~/Library/Logs/agenttacho/usage.log` |
| `lastGoodFileURL` | `~/Library/Application Support/agenttacho/last-good.json` |
| `legacyConfigFileURL` (new) | `~/.config/agentmeter/config.json` |
| `legacyImportedPricesFileURL` (new) | `~/.config/agentmeter/imported-prices.json` |
| `legacyLastGoodFileURL` (new) | `~/Library/Application Support/agentmeter/last-good.json` |

Rule: no code path writes to a `legacy*` location (FR-009).

## LegacyDataMove (new, UsageCore)

Copies AgentMeter's carried-over files once (FR-008 to FR-011, FR-027).

- **Input**: `Paths`, a `FileManager`.
- **Precondition for any copy**: the directory of `configFileURL` does not exist.
- **Items**: three pairs, `legacyConfigFileURL` to `configFileURL`, `legacyImportedPricesFileURL` to `importedPricesFileURL`, `legacyLastGoodFileURL` to `lastGoodFileURL`.
- **Result** (`LegacyDataMove.Outcome`):
  - `.skipped`: the new configuration folder exists, nothing was looked at.
  - `.nothingToMove`: the new folder was missing and no legacy file exists; nothing was created.
  - `.moved(copied: [String], failed: [(file: String, reason: String)])`: file names relative to their folder.
- **Copy rule**: create the destination directory; copy the source to a uniquely named temporary file in the destination directory; move it to the destination name; on any error remove the temporary file and record a failure. A destination is never left partial.
- **Log lines** (written by `AppModel`, source `move`): `copied from AgentMeter: config.json, imported-prices.json, last-good.json` once; `could not copy <file> from AgentMeter: <reason>, starting with defaults` per failure. No values are logged.

## RunningInstance (changed)

- `others(from:ownPID:bundleIdentifiers:)`: processes whose bundle identifier is in the given set (own and legacy), other than the own PID and not terminated.
- New field `appName`: "AgentTacho" for `dev.rhuss.agenttacho`, "AgentMeter" for `dev.rhuss.agentmeter`.
- `summary(paths:)`: "<appName> <version> is already running from <path> (process <pid>)."

## Identifiers and names (renamed)

| Item | Old | New |
|---|---|---|
| Bundle identifier | `dev.rhuss.agentmeter` | `dev.rhuss.agenttacho` |
| App / executable | `AgentMeter.app` / `AgentMeter` | `AgentTacho.app` / `AgentTacho` |
| Info.plist keys | `AgentMeterVersionDisplay`, `AgentMeterCommit`, `AgentMeterBuildDate`, `AgentMeterReleaseTag`, `AgentMeterSigning`, `AgentMeterNotarized`, `AgentMeterUpdateSource` | same with `AgentTacho` prefix |
| Update temporary folder | `dev.rhuss.agentmeter-update` | `dev.rhuss.agenttacho-update` |
| Config notes identifier | `agentmeter.configurationLoadNotes` | `agenttacho.configurationLoadNotes` |
| Official update source | `rhuss/agentmeter` | `AgentTacho/agenttacho` |
| Expected DMG | `AgentMeter-<v>.dmg` | `AgentTacho-<v>.dmg` |
| Homebrew cask / app | `agentmeter` / `AgentMeter.app` | `agenttacho` / `AgentTacho.app` |
| User-Agent | `AgentMeter/<v>` | `AgentTacho/<v>` |
| Notary profile default | `agentmeter-notary` | `agenttacho-notary` |
| Self-signed identity default | `AgentMeter Signing` | `AgentTacho Signing` |
