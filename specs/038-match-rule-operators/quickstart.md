# Quickstart: Validate Session Kinds and Match Conditions

**Feature**: 038-match-rule-operators (reworked 2026-10-28)

## Automated

```bash
make test           # UsageCore and DemoMode suites
make test-release   # release and screenshot scripts, unchanged
make app            # the app builds
make app-demo       # the demo build builds with the migrated scenario
```

Expected: all suites pass, including `SessionKindTests` (kinds per harness, exact checks, disjointness), `SessionKindStorageTests` (new form round trip, every earlier form of contracts/configuration.md with its log note), `AttributionTests` (US1 to US3 acceptance scenarios, SC-001 and SC-002 matrices, subscription markers narrowing), the reused `MatchOperatorTests` and `MatchRuntimeTests`, `MatchOverlapTests` (kind and condition keys, Directory only conflicts), `SessionMatchTextTests` (note order and merges, no forbidden word) and `DefaultScenarioTests` with the migrated `Resources/demo/default.json`.

## By hand (Settings, `make app`, both appearances)

1. Add a token-based Claude Code account: the sheet starts with Sessions "Directory only" and no "Only when"; the note says only sessions from this Claude Code directory count. With the main directory left empty while a Claude subscription uses `~/.claude`, the sheet shows the shared directory warning naming the subscription.
2. Choose "Other provider": the "Only when" checkbox appears unticked; the notes say what Other provider counts and that sessions from the Claude Code directory always count.
3. Tick "Only when": the Condition row shows Model, starts with and an empty text, and the blank text note appears; the "Not applied" line names the account. Type `glm` after switching to "contains": the note disappears and the account saves.
4. Untick and tick again: `glm` with "contains" comes back. Choose "Directory only" and then "Vertex": the condition is back, ticked, unchanged.
5. A token-based Codex account: no Sessions pop-up, the sentence "Counts Codex sessions signed in with an API key." and the checkbox.
6. A token-based OpenCode account, kind "Other provider": the Condition row shows without a checkbox.
7. Choose "matches regex" and type `^gateway-(a`: the invalid pattern note shows and `~/.config/agenttacho/config.json` is unchanged; finish it as `^gateway-(a|b)/` and the file has `"sessionKind"` and `"condition"` with `"operator": "regex"`, and no `matchRule`.
8. Two Codex token-based accounts without a condition: each shows the overlap warning naming the other.
9. Change any pop-up selection: no control moves; narrow the window: the text field moves to a second line, nothing clips.
10. Read every visible text of a token-based account: no "profile", "Match rule", "Custom" or "preset". A subscription account still shows "Custom marker" with its two updated notes.

## Configuration file

Copy a spec 037 file with `"matchRule": {"type": "custom", "field": "model", "text": "intranet/"}` on a Claude Code account and restart: Settings shows Sessions "Other provider", "Only when" ticked, Model starts with `intranet/`; the diagnostic log names the account once; the next save writes `sessionKind` and `condition` only.
