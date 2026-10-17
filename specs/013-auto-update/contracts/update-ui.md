# Contract: Update Line and Settings

## Dropdown update line (FR-009, FR-010, FR-018)

One line between the last content section and the footer. Hidden for `notCheckedYet`, and for `checking`, `upToDate`, `checkFailed` and `developmentBuild` except right after "Check for Updates…" from the dropdown's gear menu, until the dropdown closes (FR-003). A check started from Settings > About shows these states in Settings only; the line keeps showing a known update, if any.

| State | Text | Controls |
|---|---|---|
| available, install | AgentTacho X.Y.Z available | `Install`, `Release notes` |
| available, homebrew | AgentTacho X.Y.Z available | `Upgrade with Homebrew`, `Release notes` |
| available, download | AgentTacho X.Y.Z available · <reason> | `Download`, `Release notes` |
| available, try again (after a failed download, or Gatekeeper not reachable) | AgentTacho X.Y.Z available · <reason> | `Try again`, `Release notes` |
| commandCopied | Copied "brew upgrade --cask agenttacho". If Homebrew finds nothing new yet, try again later. | `Release notes` |
| checking (from the dropdown) | Checking for updates… | none |
| upToDate (from the dropdown) | AgentTacho is up to date | none |
| checkFailed (from the dropdown) | Could not check for updates: <short error> | none |
| developmentBuild (from the dropdown) | Development build: updates are not checked | none |
| downloading | Downloading AgentTacho X.Y.Z… <n>% | `Cancel` |
| verifying | Verifying AgentTacho X.Y.Z… | `Cancel` |
| installing | Installing AgentTacho X.Y.Z… | none |
| installFailed (from the previous run, shown after launch until the dropdown closes; the automatic check does not replace it) | Could not install the update: <reason> | `Release page` |
| restartRequired (swapped in, relaunch failed) | AgentTacho X.Y.Z is installed; quit AgentTacho and open it again to use it | none |

`Release notes` and `Download` open the release page (`html_url`) in the default browser; `Release page` opens the latest release page of the release source, because the release of the previous run is no longer known. `Try again` starts the install again; Cancel during a Try again returns to `Install`. Secondary text style, one line, truncates the reason with a tooltip showing the full text. Nothing changes in the menu bar; no notification, no window.

## Gear menu

`Check for Updates…` between `About AgentTacho` and `Settings…`.

## Settings > About (FR-011)

Below the version information, centered, without a heading (spec 020):
- `Check for Updates…` button.
- Status below the button, in body-size secondary text with the actions in link style: "AgentTacho X.Y.Z available" (with the reason after a middle dot, as on the line) with the same action and `Release notes`, or "Up to date (checked HH:mm)", or "Not checked yet", or "Development build: updates are not checked", or the last error (with a known update on a second line below it). The result of a check started here stays in Settings and does not appear on the dropdown line.
- No toggle; it is in Settings > General.

## Settings > General (FR-002, spec 020)

A section "Updates" directly after "Launch":
- Toggle "Check for updates automatically" (default on), saved to `checksForUpdates` through the Settings draft like every other General setting.

## Accessibility

The line is an accessibility container: its text is read as one element and each button stays a separate, actionable element labeled with its title.
