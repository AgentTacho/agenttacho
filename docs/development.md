# Build and development

## Build and run

Requirements: macOS 14 or newer on Apple Silicon, and the Xcode Command Line Tools with Swift 5.10 or newer. There are no third-party Swift packages.

```bash
make test     # unit tests for the UsageCore library (Swift Testing)
make app      # builds build/AgentTacho.app, signed with the best available identity
make app-demo # builds build/AgentTacho Demo.app, which plays a made-up scenario for screenshots
make run      # builds and opens the app
```

Run the app bundle rather than `swift run`, because notifications and start at login need an application bundle.

`make app-demo` builds a separate app, "AgentTacho Demo.app", for screenshots. It has its own bundle identifier (`dev.rhuss.agenttacho.demo`) and its own folders (`~/.config/agenttacho-demo`, `~/Library/Logs/agenttacho-demo`, `~/Library/Application Support/agenttacho-demo`), so it runs next to an installed AgentTacho without touching that app's settings, saved values or log. Instead of reading your agents' files, it plays a made-up scenario from `Resources/demo/`. It reads no keychain item and makes no network request. Settings > About shows "Build: Demo". `make app`, `make dmg` and `make release` never build it, and a release refuses to run while the `DEMO` environment variable is set.

`make app` signs with a Developer ID certificate if there is one, otherwise with the self-signed "AgentTacho Signing" certificate (see [HOWTO_RELEASE.md](../HOWTO_RELEASE.md)), otherwise ad-hoc. It prints the version and the signing tier it used. With an ad-hoc signature, macOS treats every rebuild as a new app, so notification permission and start at login are lost after each build. `make app SIGN_IDENTITY=-` forces an ad-hoc signature.

On first launch, AgentTacho creates a configuration with one subscription account if Claude Code is signed in with the default configuration directory `~/.claude`. If you run Claude Code with a different directory (for example through `CLAUDE_CONFIG_DIR`), set that directory as the account's credential directory in Settings. AgentTacho also reads the session logs in each subscription account's credential directory, so you do not need to list it again under the extra Claude Code directories.

## Project layout

- `Sources/UsageCore`: all logic (configuration, log parsing, pricing, attribution, weekly windows, aggregation, thresholds, icon catalog), with no UI code.
- `Sources/AgentTacho`: the SwiftUI menu bar app.
- `Tests/UsageCoreTests`: Swift Testing suites with small synthetic session-log fixtures.
- `scripts/sum-vertex.sh <start> <end> [dir...]`: recomputes Vertex spend for a window with `jq`, as an independent check of the app.
- `scripts/build-icon-catalog.sh`: regenerates the bundled Font Awesome files from a pinned release, with an integrity check.
- `Sources/DemoMode` and `Resources/demo/`: the demo build. A scenario such as `default.json` holds a configuration, plan windows, usage records and timed frames, with every time relative to launch. `make test` checks that the default scenario produces each level, marker and pace state the screenshots show, plus exactly one alert. Launch the demo app with `-demoScenario <name>` to play another file.
- `scripts/screenshots/capture.sh <dir>`: writes the seven landing page screenshots from the demo build, each in light and dark (14 WebP files), and leaves every other file in `<dir>` alone. It quits a running AgentTacho, switches the system appearance for the dark pass, and puts both back when it ends, even after a failure or Ctrl-C. It needs `brew install webp imagemagick`. Before the first capture, give your terminal Accessibility, Screen Recording and Automation (System Events) permission; the demo app needs no notification permission. A run takes a few minutes and moves the mouse, so leave the Mac alone until it finishes.
- `scripts/release/`: the build, DMG, release and cask scripts behind `make app`, `make dmg`, `make release` and `make cask`. `make test-release` runs their tests, which use stubs and local repositories and publish nothing.
- `specs/001-agenttacho` and `docs/superpowers/specs`: the specification, plan and design notes the app was built from.
