# Quickstart: Account Budget Subtitle

## Automated checks

```bash
make test   # AccountBudgetDescriptionTests: group, own budget, missing group, both periods, whole and fractional amounts, accessibility text, Groups list text
make app
```

## Manual checks

1. Run the app (`make run`), open Settings > Accounts: each token-based account's subtitle shows provider, budget (group icon and name, or "own budget") and "$amount / period"; subscription accounts are unchanged.
2. Select an account, switch its Budget picker between "Own budget" and a group: the subtitle in the list changes before saving.
3. Settings > Groups: each group reads "$amount / period, N member(s)".
4. With VoiceOver on (Cmd-F5), move over an account row: the subtitle is read without the icon glyph.
5. Rename a group to a 60-character name: the account subtitle stays on one line, keeps "Vertex · " and the icon visible, and ends in an ellipsis.
