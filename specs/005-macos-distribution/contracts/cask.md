# Contract: Homebrew Cask `agenttacho`

Location: `Casks/agenttacho.rb` in `rhuss/homebrew-tap` (branch `main`). Installed with `brew install --cask rhuss/tap/agenttacho`.

## Rendered content (not notarized)

```ruby
cask "agenttacho" do
  version "0.2.0"
  sha256 "<sha256 from release-info.json>"

  url "https://github.com/rhuss/agenttacho/releases/download/v#{version}/AgentTacho-#{version}.dmg"
  name "AgentTacho"
  desc "Menu bar meter for coding-agent usage limits and budgets"
  homepage "https://github.com/rhuss/agenttacho"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "AgentTacho.app"

  uninstall quit: "dev.rhuss.agenttacho"

  zap trash: [
    "~/.config/agenttacho",
    "~/Library/Logs/agenttacho",
    "~/Library/Preferences/dev.rhuss.agenttacho.plist",
  ]

  caveats <<~EOS
    AgentTacho is not notarized by Apple. After each install or upgrade,
    allow it once before it starts:
      macOS 14:          Control-click AgentTacho in Applications and choose Open.
      macOS 15 or later: open AgentTacho, then choose "Open Anyway" in
                         System Settings > Privacy & Security.
    Or run: xattr -dr com.apple.quarantine /Applications/AgentTacho.app

    Homebrew quits AgentTacho before an upgrade and opens it
    again afterwards.
  EOS
end
```

## Rules

- For a notarized release, the `caveats` block contains only the last paragraph (Homebrew quits AgentTacho before an upgrade and opens it again afterwards). Homebrew records the apps that `uninstall quit:` closed during `brew upgrade` and reopens them once the upgrade succeeded; for a release that is not notarized, macOS then blocks the new version until the user allows it as the first paragraph describes.
- The rendered file passes `ruby -c`.
- `version` and `sha256` come from `release-info.json`; nothing else changes between releases.
- The commit message in the tap is `agenttacho <version>`.
