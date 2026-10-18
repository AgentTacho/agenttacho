# Installation

AgentTacho needs macOS 14 or newer on Apple Silicon.

**Download.** Get `AgentTacho-X.Y.Z.dmg` from the [latest release](https://github.com/AgentTacho/agenttacho/releases/latest), open it and drag AgentTacho onto the Applications folder.

**Homebrew.**

```bash
brew install --cask agenttacho/tap/agenttacho
brew upgrade --cask agenttacho              # install a newer release
brew uninstall --zap --cask agenttacho      # remove the app, its configuration and its logs
```

AgentTacho runs only once. If you start a second copy (for example a build of your own while the installed app runs), it shows the running one with its version, location and process ID, and offers to stop it and start in its place, or gives you the `kill` command to stop it yourself. `brew upgrade` quits a running AgentTacho before the upgrade and opens it again afterwards. Notification permission and start at login carry over to upgrades signed with the same certificate.

## Updates

AgentTacho checks GitHub for a newer release 5 minutes after it starts and then once a day. When one exists, a quiet line at the bottom of the dropdown says "AgentTacho X.Y.Z available", with "Release notes" and one action:

- **Install** (DMG installs in a folder you can write to, such as Applications): downloads the new DMG, verifies it, replaces the app, moves the old version to the Trash and starts the new one. Notification permission, start at login and your configuration stay as they are. "Cancel" stops it while it downloads or verifies. When the download fails or Gatekeeper cannot be reached, the line offers "Try again" next to "Release notes".
- **Upgrade with Homebrew** (installs from the cask): copies `brew upgrade --cask agenttacho` to the clipboard for you to run in a terminal. AgentTacho never runs Homebrew or changes a Homebrew install itself. The tap can take a little longer than GitHub to offer a new release.
- **Download** (everything else, with the reason): opens the release page. This is what you get when AgentTacho runs straight from the opened DMG ("Move AgentTacho to Applications to install updates"), from a folder it cannot write to, or when the downloaded release cannot be verified.

"Check for Updates…" in the gear menu and in Settings > About checks right away and shows the result where you started it: on the dropdown's line until the dropdown closes, or in Settings. Turn off "Check for updates automatically" in Settings > General to stop the daily check; AgentTacho then contacts GitHub only when you ask. Development builds (made with `make app` from a checkout that is not exactly a release tag) never check. Releases up to 0.3.1 have no updater, so install the first release with this feature by hand.
