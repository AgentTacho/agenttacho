# Data Model: Name the app AgentTacho

## Paths

`Paths` keeps its injectable home directory. Its locations use the data folders (FR-007).

| Property | Value |
|---|---|
| `configFileURL` | `~/.config/agenttacho/config.json` |
| `importedPricesFileURL` | `~/.config/agenttacho/imported-prices.json` |
| `logFileURL` | `~/Library/Logs/agenttacho/usage.log` |
| `lastGoodFileURL` | `~/Library/Application Support/agenttacho/last-good.json` |

## Identifiers and names

| Item | Value |
|---|---|
| Bundle identifier | `dev.rhuss.agenttacho` |
| App / executable | `AgentTacho.app` / `AgentTacho` |
| Info.plist keys | `AgentTachoVersionDisplay`, `AgentTachoCommit`, `AgentTachoBuildDate`, `AgentTachoReleaseTag`, `AgentTachoSigning`, `AgentTachoNotarized`, `AgentTachoUpdateSource` |
| Update temporary folder | `dev.rhuss.agenttacho-update` |
| Config notes identifier | `agenttacho.configurationLoadNotes` |
| Official update source | `AgentTacho/agenttacho` |
| Expected DMG | `AgentTacho-<v>.dmg` |
| Homebrew cask / app | `agenttacho` / `AgentTacho.app` |
| User-Agent | `AgentTacho/<v>` |
| Notary profile default | `agenttacho-notary` |
| Self-signed identity default | `AgentTacho Signing` |
