# Data Model: Session Kinds and Match Conditions

**Feature**: 038-match-rule-operators | **Date**: 2026-10-27, reworked 2026-10-28

Types marked **Reused** exist on the branch from the first version and keep their behavior; **Changed** types keep their code but change shape; **New** and **Removed** are the rework.

## SessionKind (New, UsageCore; replaces `MatchPreset`)

| Case | Harness | Stored | Pop-up / subtitle | Matches a record of its harness when (exact, case-sensitive) |
|---|---|---|---|---|
| `claudeCodeDirectoryOnly` | Claude Code | `directoryOnly` | Directory only | never (only the profile step counts for it) |
| `claudeCodeVertex` | Claude Code | `vertex` | Vertex | the request id starts with `req_vrtx_` |
| `claudeCodeOtherProvider` | Claude Code | `otherProvider` | Other provider | the request id does not start with `req_` (empty included) |
| `codexAPIKey` | Codex | `apiKey` | API key | the provider hint is `apikey` |
| `openCodeVertex` | OpenCode | `vertex` | Vertex | the provider is `google-vertex` or `google-vertex-anthropic` |
| `openCodeOpenAI` | OpenCode | `openai` | OpenAI | the provider is `openai` |
| `openCodeOtherProvider` | OpenCode | `otherProvider` | Other provider | a provider is set and is none of the three above |

- `harness`, `storedValue`, `displayName` (the pop-up item and the account list subtitle, FR-012).
- `kinds(for:)`: the table order per harness; the first is `default(for:)` (FR-001).
- `kind(stored:harness:)`: nil for an unknown value or one of another harness.
- `offersCondition`: false for Directory only. `requiresCondition`: true for OpenCode Other provider. `showsPopUp`: false for Codex.
- `fallback(for:)`: Directory only, API key, OpenCode Other provider (research R7).
- `matches(record:)`: `record.harness == harness` and the check above (research R11).
- `defaultIcon`: Google for the Vertex kinds, OpenAI for API key and OpenCode OpenAI, else the harness icon (replaces `IconDefaults.defaultIcon(harness:rule:)`).

## MatchField, MatchOperator (Reused)

Unchanged: fields per harness (Claude Code: Model, Request id, Message id, Anywhere; Codex and OpenCode: Model, Anywhere), `value(of:rawLine:)`, operators per field (Anywhere: contains, regex), `default(for:)`.

## MatchCondition (Changed, UsageCore; was `MatchRule.custom`)

```text
struct MatchCondition: Equatable, Hashable, Sendable {
    var field: MatchField
    var `operator`: MatchOperator
    var text: String
}
```

- `static let initial`: Model, starts with, empty text (FR-014).
- `matches(record:rawLine:)`, `compile`, `find`, `search`, `regexLimit`, `clockInterval`, `RegexOutcome`: moved from `MatchRule` unchanged (research R1 to R3).
- `isOffered(for harness:)`, `needsRawLine`, `hasBlankText`, `patternProblem`, `withField(_:)`: moved unchanged.
- `overlapKey: MatchConditionOverlapKey`: field, operator, text folded for literal operators and as written for regex (FR-009).

## TokenBasedSettings (Changed)

| Property | Before | After |
|---|---|---|
| `matchRule: MatchRule` | preset, custom or none | removed |
| `sessionKind: SessionKind` | | new; always of `harness` |
| `condition: MatchCondition?` | | new; nil when "Only when" is off |
| `effectiveCondition` | | new, computed: `condition` when `sessionKind.offersCondition`, else nil |

State transitions (research R10), each with tests:

- `harness` didSet (when it changes): directories cleared (unchanged), `sessionKind = .default(for: harness)`, `condition` kept, with `withField(.model)` when its field is not offered for the new harness.
- `choosingKind(_ kind:, remembered: MatchCondition?)`: sets the kind; `condition` unchanged, except that a kind that requires a condition and has none gets `remembered ?? .initial`.
- `settingConditionOn(_ on: Bool, remembered:)`: on: `condition = condition ?? remembered ?? .initial`; off: `condition = nil`, ignored when the kind requires a condition.
- `conditionForEditing`: `condition ?? .initial`, for the Condition row of OpenCode Other provider loaded without a condition; writing through it sets `condition`.

Initializers take `sessionKind: SessionKind? = nil` (nil: the harness's default) and `condition: MatchCondition? = nil`.

## Stored form (Changed, configuration file; contracts/configuration.md)

- New keys `sessionKind` (string) and `condition` (`StoredCondition`: `field`, `operator`, `text`).
- `StoredMatchRule` stays for reading only (spec 037 and first 038 files); its `rule(for:)` becomes `migrated(for harness:) -> (SessionKind, MatchCondition?)?`.
- `LegacyProvider` stays for reading v0.8.0 files.
- Decoding order and load notes: research R7.

## Attributor (Changed)

- `CandidateKind.tokenBased(Harness, MatchRule)` becomes `tokenBased(SessionKind, MatchCondition?)` (the effective condition); its description, and so the fingerprint, contains both.
- Rule step per research R11: kind first, then condition (token-based through `MatchRuntime`, subscription marker as `DetectionRule.rawContains`), conditioned matches beat plain ones; a token-based candidate whose kind `requiresCondition` and whose effective condition is nil never matches.
- `claudeCodeTokenRules` removed.
- `needsRawLine`: a subscription marker or an effective condition on Anywhere.
- `sitOutLogLine` wording: "condition" instead of "match rule".

## MatchRuntime, MatchMemory (Reused; entry changes)

- `MatchRuntime.Entry(id:name:condition:)` instead of `rule:`; `CompiledMatchRule` becomes `CompiledCondition` (no preset branch). Memory, retry, given-up, sit-out, counters and the log drain unchanged.

## Configuration (Changed)

- `validate()`: an effective condition with a blank text throws `ConfigurationError(kind: .condition, message: "Account \"<name>\": the condition needs a text")` (kind renamed from `.matchRule`).
- `validateForSaving()`: `validate()`, then per account the invalid pattern (`... the regular expression is not valid`, reused) and OpenCode Other provider without a condition (`... the condition needs a text`).
- `matchOverlaps(paths:)`: keyed per research R12, Directory only accounts skipped.
- `directoryOnlyConflict(forAccount:paths:) -> DirectoryOnlyConflict?` (new): the other accounts with the same canonical main Claude Code directory, in accounts order; nil unless the account is a Directory only account with at least one such other account. `DirectoryOnlyConflict` has the shape of `MatchOverlap` (`accountId`, `otherNames`).

## SessionMatchText (Changed, UsageCore; renamed from `MatchRuleText`)

Every text is in contracts/settings-ui.md. Functions:

- `kindItem(_:)`, `kindCaption(_:)` (nil for Codex, whose sentence is the row), `codexSentence`.
- `noteLines(kind:condition:overlap:directoryConflict:) -> [NoteLine]` in FR-013 order with the merges of research R13.
- `displayNamePrompt(kind:)`, `overlapWarning(otherNames:harness:)` (the advice follows the harness: Codex has no other kind to choose), `directoryOnlyWarning(otherNames:)`. `noteLines` builds the overlap warning from `overlap.otherNames` and `kind.harness`.
- Reused: field labels, operator labels, `conditionLabel`, accessibility labels, `textPrompt(field:operator:)`, `anywhereCaption`, `invalidPattern`, `NoteLine`, `namesList`, `allFixedTexts` (extended).
- Removed: `matchRuleLabel`, `customItem`, `noneItem`, `droppedNoneItem`, `noneCaption`, `droppedNoneCaption`, `presetCaption`, `ruleItem`, `sessionMatchingSection`.

## AccountBudgetDescription (Changed)

- `sourceName`: `settings.sessionKind.displayName` for every token-based account (FR-012).

## Removed

`MatchPreset`, `MatchRule`, `MatchRuleChoice`, `MatchRuleOverlapKey`, `MatchRule.choices`, `MatchRule.choosing`, `IconDefaults.defaultIcon(harness:rule:)`.
