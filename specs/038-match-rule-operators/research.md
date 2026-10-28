# Research: Session Kinds and Match Conditions for Token-Based Accounts

**Feature**: 038-match-rule-operators | **Date**: 2026-10-27, reworked 2026-10-28

The first version of this spec is implemented on the branch (commits `f2ae41f` to `88b6ed2`). Decisions R1 to R5 and the layout parts of R8 are kept as built and marked **Reused**; R6, R7 and the structure of R8 are replaced; R9 to R14 are new for the rework.

## R1: Literal operators that ignore case but not diacritics (FR-005) **Reused**

**Decision**: "Starts with" and "contains" compile the text once as an ICU literal (`NSRegularExpression` with `[.caseInsensitive, .ignoreMetacharacters]`); "starts with" searches with `.anchored`, "contains" without. Built in `MatchRule.compile(_:_:)` and `MatchRule.find(...)` (commit `a705ad6`); the rework moves them unchanged to `MatchCondition`.

**Rationale**: ICU case folding ignores Unicode case (`Ä`/`ä`, `GLM`/`glm`) and leaves diacritics alone; a precompiled literal search was several times faster than `String.range(of:options:)` over long raw lines. Text is compared literally, so `a.b` never acts as a pattern.

**Alternatives considered**: `lowercased()` on both sides (allocations, different folding); `localizedCaseInsensitiveContains` (locale dependent).

## R2: Regular expressions (FR-005, FR-008) **Reused**

**Decision**: `NSRegularExpression(pattern:options: [.caseInsensitive])`, ICU syntax, unanchored over the whole field, compiled once per attributor. Validity is "the initializer does not throw"; the note says "This regular expression is not valid." and the "Not applied" line adds the account name.

**Rationale**: ICU is the syntax macOS documents for apps; `(?-i)` turns case sensitivity back on as FR-005 allows. Swift `Regex` has no progress callback, so it cannot be bounded in time (R3).

## R3: A 50 ms limit per record (FR-007, SC-005) **Reused**

**Decision**: `enumerateMatches(in:options: [.reportProgress], range:)`, stopping at the first match or, on every 16th progress call, when `ContinuousClock` has passed the 50 ms deadline (`MatchRule.search`, `clockInterval`). A time-out counts as no match.

**Rationale**: `.reportProgress` is the documented way to interrupt a long ICU run; reading the clock on every 16th call keeps normal searches fast, and a catastrophic pattern stops within a few milliseconds of the limit.

## R4: Where the sit-out state lives (FR-007) **Reused, entry type changes**

**Decision**: `MatchRuntime` (lock-protected final class, one per attributor) with `MatchMemory` carried by each source from one refresh to the next: per account the slow values (hashes of field values the pattern ran out of time on, at most 1,000), the given-up set (a condition that timed out again during its retry no longer marks records for another attribution), the sit-out set, `timeOuts`, `skippedDecisions` and the names for the once-per-refresh log line. The rework changes only what an entry holds: `MatchRuntime.Entry.rule: MatchRule` becomes `condition: MatchCondition`, and `CompiledMatchRule` becomes `CompiledCondition` (same matcher, no preset branch).

**Rationale**: The attributor spans one refresh per source and every record passes it; the memory and retry rules were settled at the first version's code review (FR-007's last sentence) and do not depend on the rule model.

## R5: Records attributed while a condition sat out are attributed again (FR-007) **Reused**

**Decision**: As built: `Attributor.tracking(retry:_:)` tells a source whether the records it just attributed must be attributed again; `LogIndex` drops the entries of those files, `CodexSessionSource` and `OpenCodeSource` set their re-attribution flag (commits `08a52d0`, `2a9fe17`, `18a1def`, `3685240`). Only the log line's wording changes, from "match rule" to "condition": `account "<name>": condition took longer than 50 ms on one record and was skipped for the rest of this refresh`.

**Rationale**: Nothing in the retry depends on whether the slow pattern belongs to a "custom rule" or a "condition".

## R6: Stored form (FR-010) **Replaced**

**Decision**: A token-based account stores two keys next to `harness`:

- `sessionKind`: a string, unique per harness and read together with `harness` (like the spec 037 preset values): `directoryOnly`, `vertex`, `otherProvider` (Claude Code); `apiKey` (Codex); `vertex`, `openai`, `otherProvider` (OpenCode). Always written.
- `condition`: an object `{"field", "operator", "text"}` with the first version's values (`model`, `requestId`, `messageId`, `anywhere`; `startsWith`, `contains`, `regex`). Written only when the condition is on and the kind offers one.

The presence of `sessionKind` marks the new form. Loading takes the first form that applies: `sessionKind` (new), `matchRule` (spec 037 and first 038 builds), `provider` and `customMarker` (v0.8.0). Writing never writes `matchRule`, `provider` or a token-based `customMarker`.

**Rationale**: Two flat keys mirror the two questions of the UI (which sessions, which of those) and read well in a hand-edited file; reusing the field and operator values keeps the first version's documentation valid.

**Alternatives considered**: Keeping `matchRule` with new type values (the old "custom" type would have to mean "Other provider with a condition" on Claude Code and "API key with a condition" on Codex, which is the confusion the rework removes); a nested `sessions` object (`harness` is already flat; one more level only adds noise).

## R7: Reading earlier forms and unreadable values (FR-011, SC-004) **Replaced**

**Decision**:

| Stored | Loaded as | Log (once per account and load) |
|---|---|---|
| v0.8.0 `provider` `vertex` or none | Claude Code, Vertex | `account "<name>" migrated from provider vertex to Claude Code, sessions Vertex` |
| the same with a token-based `customMarker` M | Claude Code, Vertex, condition Anywhere contains M | the same line plus `; its marker became the condition "Anywhere contains M" of Vertex sessions, a company gateway needs Other provider` |
| v0.8.0 `provider` `openai` (marker M optional) | Codex, API key (with M: condition Anywhere contains M) | `account "<name>" migrated from provider openai to Codex, sessions API key` |
| `matchRule` preset | that kind | `account "<name>": match rule migrated to sessions <kind>` |
| `matchRule` `none` | Claude Code: Directory only; Codex: API key; OpenCode: unreadable (row below) | as above |
| `matchRule` custom F, O, T | Claude Code Other provider, Codex API key, OpenCode Other provider; condition F, O (missing: the field's default; `startsWith` on `anywhere`: `contains`), T | `account "<name>": match rule migrated to sessions <kind> with a condition` |
| unknown or other-harness `sessionKind` or `matchRule`; an unreadable `condition` (not an object, unknown field or operator, field not offered for the harness, blank or missing text) | the harness's fallback without a condition: Claude Code Directory only, Codex API key, OpenCode Other provider | `account "<name>": which sessions count could not be read; it counts <fallback> until you choose in Settings` |
| `condition` on Directory only | Directory only, condition ignored (decoded as `condition` nil, so choosing another kind in Settings does not bring it back) | `condition of account "<name>" does not apply to Directory only, ignored` |
| `condition` with an invalid regex | kept as written, matches no record | `account "<name>": the regular expression of the condition is not valid; it matches no usage until you correct it in Settings` |
| OpenCode Other provider without `condition` | kept; matches no record | none (Settings shows the blank text note) |

The fallback per harness is `SessionKind.fallback(for:)`. Directory only and OpenCode Other provider without a condition match no record outside the directory step, so an unreadable setting never widens what a Claude Code or OpenCode account counts. Codex has only one kind, so its fallback is API key without a condition, as FR-011 says.

**Rationale**: FR-011 lists each mapping; one log line per account keeps the "names each migrated account once" rule, and folding the v0.8.0 gateway hint into the migration line avoids a second line for the same account.

**Alternatives considered**: Keeping the kind and dropping only an unreadable condition (silently widens a Vertex or Codex account; the spec chose the whole setting); refusing to load (the dropdown would stop working over one hand-edited key).

## R8: Settings layout (FR-012 to FR-016, FR-019) **Layout reused, structure replaced**

**Decision**:

- Reused as built: `ConditionControls` (field pop-up, operator pop-up, text field, `ViewThatFits` with the one-line and two-line layouts, the minimum of about 12 characters, accessibility labels), `StableWidthPicker` (a pop-up keeps the width of its widest item, commit `88b6ed2`), `MatchRuleNotes` (caption notes inside the group with the warning symbol, commit `efe2b72`), the subscription marker row without a fixed width. `ConditionControls` binds to a `MatchCondition` instead of a `MatchRule`.
- Replaced: the "Session matching" section with its "Match rule" pop-up becomes `Section("Which sessions count")` with, in order: `StableWidthPicker("Sessions")` over `SessionKind.kinds(for:)` (Claude Code and OpenCode), or for Codex a text row "Counts Codex sessions signed in with an API key."; a `Toggle("Only when")` with `.toggleStyle(.checkbox)` when the kind offers an optional condition; `LabeledContent("Condition") { ConditionControls }` when the condition is on (always for OpenCode Other provider); the notes from `SessionMatchText.noteLines(...)`.
- The remembered condition (FR-014 "keeps the condition for the next time") stays in the view's `@State`, keyed by the account through `.id(accountId)`, like the first version's `lastCustom`. All transitions are UsageCore functions on `TokenBasedSettings` (R10), so the view only stores the last non-nil condition.
- The new account sheet uses the same `SessionsFields` view with `captions: true` (notes below the controls), starts with the harness's default kind (Claude Code: Directory only), and `add()` keeps `validateForSaving()`.

**Rationale**: A checkbox that reveals a dependent row is the macOS pattern for an optional setting (Mail rules, Finder search), and a checkbox-style `Toggle` is the standard control for one setting in a grouped form (HIG "Toggles"). The rest is the first version's HIG pass, kept.

**Alternatives considered**: An "Any" item in a condition pop-up instead of the checkbox (mixes the two questions again); a disclosure group (hides whether a condition is on).

## R9: Is "no `req_` request id" a reliable signal for gateways? (FR-002, spec assumption)

**Decision**: Yes for the setups known today. Claude Code Other provider: the record's request id does not start with `req_` (an empty request id included).

**Evidence** (checked on 2026-10-28):
- Parsers: `SessionRecordParser` reads `requestId` from the line envelope and uses `""` when it is missing; it keeps a record with a message id or a request id and drops every record whose token counts are all zero, so Claude Code's `<synthetic>` placeholder records (no request id, zero usage) never reach attribution. Codex and OpenCode records always have `requestId: ""`, so every kind checks `record.harness` first.
- Fixtures in `Tests/UsageCoreTests/Fixtures`: only `req_vrtx_…` (Vertex) and `req_011…` (direct) request ids; no gateway fixture exists, so the tasks add one (a record without `requestId`, model `intranet/glm-5`).
- The maintainer's local Claude Code directories (three workspace directories; counts only, nothing kept): about 18,000 `req_vrtx_` and 1,400 to 1,800 direct `req_` ids each; 21 to 31 assistant lines without a request id, of which 15 to 17 are zero-usage `<synthetic>` placeholders (dropped by the parser) and the rest, in the one directory that runs through a company gateway, carry gateway model names with a `/`. No other request id shape occurs.

**Consequence**: A future proxy with `req_` ids of another infix matches no Claude Code kind and stays Unassigned (spec assumption); Bedrock is unchecked and the documentation says so.

## R10: Rule model and transitions (FR-001, FR-004, FR-014, edge cases)

**Decision**:
- `SessionKind` replaces `MatchPreset` (same shape: harness-qualified cases, stored value unique per harness, display name, detection) and adds `claudeCodeDirectoryOnly`, `claudeCodeOtherProvider` and `openCodeOtherProvider`. `kinds(for:)` gives pop-up order, the first is the default; `offersCondition` is false for Directory only; `requiresCondition` is true for OpenCode Other provider; `fallback(for:)` is R7's.
- `MatchCondition` (field, operator, text) replaces `MatchRule.custom` and keeps its matching code, `withField`, `patternProblem`, `overlapKey` and `needsRawLine`. `MatchRule`, `MatchRuleChoice` and `MatchRuleOverlapKey` are removed (the latter becomes `MatchConditionOverlapKey`).
- `TokenBasedSettings` holds `sessionKind` and `condition: MatchCondition?` (nil: "Only when" is off). `effectiveCondition` is `condition` when the kind offers one, else nil; attribution, overlap, validation, fingerprint and encoding use it. So choosing Directory only hides the condition and keeps it in the draft (edge case "Kind change"), and it is not written to the file.
- Transitions, all in UsageCore with tests: `choosingKind(_:remembered:)` (keeps the condition; OpenCode Other provider turns it on with the remembered one or `MatchCondition.initial`, which is Model, starts with, empty text); `settingConditionOn(_:remembered:)` (off: nil; ignored for a kind that requires one); the `harness` `didSet` (the kind becomes the new harness's default, the condition stays, its field becomes Model through `withField(.model)` when the new harness does not offer it, which also applies the operator fix-up).

**Rationale**: One kind type per harness keeps decoding and the pop-up as simple as the presets were. Keeping the hidden condition inside the settings, not only in the view, makes "the condition stays as it is" testable and undoable, while `effectiveCondition` keeps it from changing what counts.

**Alternatives considered**: `condition` plus a separate `conditionOn` flag (two values that must agree; nil already says off); clearing the condition on Directory only and remembering it in the view only (undo would not bring it back).

## R11: Attribution order (FR-003, FR-006, SC-001, SC-002)

**Decision**: The profile step (spec 037) is unchanged. The rule step becomes, for each candidate in the pool:

1. **Kind**: a token-based account matches when `record.harness == harness` and `sessionKind.matches(record)` (Directory only never); a Claude subscription when the record is Claude Code with a direct request id (`req_` with no further `_`); a Codex subscription when the record is Codex with the ChatGPT-plan hint. Without a kind match the candidate is out.
2. **Condition**: a token-based account with an effective condition runs it through `MatchRuntime`; a subscription with a custom marker runs the case-sensitive raw-line check. A condition that does not match (or sits out) puts the candidate out; a matching one makes it a *conditioned* match; a candidate without a condition is a *plain* match, except a token-based account whose kind requires a condition (OpenCode Other provider) and has none: it is out, so it matches no record (spec edge case "OpenCode Other provider without a condition", FR-011, R7).
3. **Choice**: the conditioned matches if there are any, else the plain matches. One wins; several subscriptions of the same kind go to the existing directory tie-breaker; anything else is Unassigned.

The kinds of one harness are disjoint (direct ids have no second `_`, Vertex ids do, Other provider has no `req_` id; Codex plan and API key hints; OpenCode providers), so step 3 only ever compares accounts of one kind, and a condition can never move a record to another kind (FR-004, SC-001). `claudeCodeTokenRules` (the subscription's "no token-based preset claims it" check) is no longer needed and is removed. The condition runs only on records of the account's kind, so a slow pattern costs less than before.

**Rationale**: It is the spec 037 rule step with "custom beats built-in" restricted to one kind, which is FR-006's wording.

**Alternatives considered**: Checking conditions before kinds (a slow pattern would run on every record of the harness, for records it can never take).

## R12: Overlap and the Directory only warning (FR-009, FR-013)

**Decision**: `matchOverlaps` keys token-based accounts on `(harness, sessionKind, effectiveCondition?.overlapKey, main directory for Claude Code)` and skips Directory only accounts. A new `directoryOnlyConflict(forAccount:paths:)` lists, for a Directory only account, every other account (subscription or token-based, any kind) whose main Claude Code directory is the same canonical path (an empty field is `~/.claude`). For a Directory only account its warning replaces the overlap warning, so two Directory only accounts on one directory get one warning each, not two.

**Rationale**: A Directory only account counts only through the profile step; sharing its directory with any account makes the profile step tie, and the rule step never picks Directory only, so the account counts nothing. The overlap warning's advice (another condition) would be wrong for it.

## R13: Notes and duplicates (FR-012, FR-013)

**Decision**: `SessionMatchText.noteLines(kind:condition:overlap:directoryConflict:)` returns the notes in FR-013 order, with these merges from the spec review:
- Directory only: its kind sentence ("Only sessions that ran from this account's Claude Code directory count.") replaces the directory note, which would say the same.
- Codex: the fixed sentence is the row in place of the pop-up; the notes add no kind sentence for Codex.
- The blank text note and the invalid pattern note share one slot (a blank text has no pattern to check).

**Rationale**: The spec review found both pairs saying the same thing twice in one group.

## R14: Validation split (FR-008, edge case "OpenCode Other provider without a condition")

**Decision**: `Configuration.validate()` (load and `ConfigStore.update`) checks a blank text of an effective condition, which no file can produce since reading treats it as unreadable. `validateForSaving()` adds the invalid pattern check (reused) and the missing condition of OpenCode Other provider, with the messages `Account "<name>": the regular expression is not valid` and `Account "<name>": the condition needs a text`.

**Rationale**: A file with an invalid pattern, or with OpenCode Other provider without a condition, must load (FR-008, edge case), while Settings must refuse to save them; the first version's split by caller already gives that.
