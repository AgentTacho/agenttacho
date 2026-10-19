# Quickstart: checking the dropdown layout polish

```bash
make test && make test-release && make app-demo
open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default
```

1. "Company budget": two member lines, one "Details"; expand it, press "Show account details": both members' tables appear below; switch the view picker: all tables follow; "Hide account details" hides them.
2. Claude Details: no "This week" line; the day row ends with "Σ"; hover Σ for "Total: … tokens".
3. Expand several Details until the panel reaches its cap: only the sections scroll; the footer row "↻ Last refreshed …  ⚙ ⏻" stays.
4. Relaunch with `-demoScenario variants`: the one-member "Team budget" has no member lines and no "Show account details".
