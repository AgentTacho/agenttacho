# Brainstorm: Match Rule Operators and a HIG-Conform Session Matching Section

**Date:** 2026-10-27
**Status:** active (revisited 2026-10-28)

## Problem Framing

Spec 037 (merged as `844b431`, not yet released; the last release is v0.8.0) gave token-based accounts a custom match rule: a field (Model, Request id, Message id, Anywhere in the record line) and a text. The operator is fixed and implicit:

- Model, Request id and Message id match when the field **starts with** the text (`MatchField.matches`, `Sources/UsageCore/Config/MatchRule.swift`).
- Anywhere matches when the raw record line **contains** the text.
- Both compare case-sensitively, exactly as entered.

A user cannot say "the model contains `glm`" or "the model matches `^(gateway-a|gateway-b)/`". The maintainer wants the familiar set of operators from Mail rules and Finder Smart Folders: **starts with**, **contains** and **matches regex**. There is no concrete case yet that starts with cannot handle; the goal is flexibility in a form macOS users already know.

The Settings section that edits the rule also departs from Apple's Human Interface Guidelines for grouped forms (System Settings style):

- Explanations are rows of their own: the preset caption, the Anywhere caption, the Claude Code note and the overlap warning each take a row inside the group, where the HIG puts explanatory text in the section footer.
- The text field has a hard-coded width (`.frame(width: 240)`).
- Field and text are two separate rows, so the rule does not read as one condition.

The subscription accounts' "Session matching (advanced)" section has the same issues: a fixed-width "Custom marker" field (240 pt) followed by two caption rows (`subscriptionMarkerCaption`, `subscriptionMarkerHint`).

## Approaches Considered

### A: Condition row (chosen)

Under the "Match rule" pop-up, a custom rule shows one row that reads like a Mail rule or Smart Folder criterion: `Condition [Model ▾] [contains ▾] [text field]`. Captions and the overlap warning move to the section footer.

- Pros: the rule reads as one sentence; it is the established macOS pattern for a single condition; fewer rows.
- Cons: three controls in one row need care at the Settings window's width (720 pt, editor at least 300 pt); the text field must flex rather than have a fixed width.

### B: Stacked rows

Three labeled rows, Field, Operator and Text, the way System Settings stacks single controls; captions in the footer.

- Pros: strictly one label, one control per row; no width pressure.
- Cons: the condition no longer reads as one sentence; one more row than today.

### C: Rule sheet

The section shows the rule as a line of text with an "Edit…" button that opens a sheet with a condition editor.

- Pros: most room; could later grow to several conditions.
- Cons: one more click for a single condition; YAGNI, since one condition per account is all spec 037 needs.

## Decision

Approach A, the condition row, for the token-based "Session matching" section, plus the same HIG pass on the subscription "Session matching (advanced)" section.

Decisions made in the session:

1. **Operators:** starts with, contains, matches regex.
2. **Anywhere:** stays as a field and offers only *contains* and *matches regex*; "starts with" on a raw JSON line has no use. Choosing Anywhere while the operator is *starts with* switches it to *contains*.
3. **Case:** all three operators ignore case, as Mail rules and Finder searches do. A regex can turn case sensitivity back on inline (`(?-i)`). This changes today's case-sensitive prefix match; acceptable, since spec 037 is unreleased.
4. **Layout:** the condition row of approach A; explanations and the overlap warning in the section footer; no hard-coded control widths.
5. **Scope includes the subscription marker section:** its captions move to the footer and its text field loses the fixed width. The marker keeps its meaning (the record contains the text); it gets no operator pop-up.

## Key Requirements

- A custom rule has field, operator and text. The operator pop-up offers starts with, contains and matches regex for Model, Request id and Message id, and contains and matches regex for Anywhere in the record line.
- Matching ignores case for all operators. *Starts with* and *contains* compare the text as entered (no trimming beyond today's blank check). *Matches regex* searches the field for the pattern anywhere (unanchored); `^` and `$` anchor it.
- An invalid regular expression is refused like a blank text today (spec 037 FR-011): Settings shows the error in the section footer and does not save; a hand-edited file with an invalid pattern loads, the rule matches nothing, and the log says why once per load.
- New custom rules start as Model, starts with, empty text. Switching between a preset and Custom keeps the last custom field, operator and text for that account, as today.
- Configuration: a custom rule gains an `operator` key (`startsWith`, `contains`, `regex`). A rule without it is `startsWith`, so files written by the unreleased spec 037 build keep working. Anywhere with `startsWith` in a hand-edited file loads as `contains`.
- The overlap warning (spec 037 FR-013) treats two custom rules as the same when harness, field, operator and text (compared without case) and, for Claude Code, the directory are equal. Two different patterns that match the same records are not detected; the documentation says so.
- Token-based "Session matching" section: rows are the Match rule pop-up and, for Custom, the condition row. The preset caption, the Anywhere caption, the Claude Code note, the regex error and the overlap warning (with its warning symbol) are in the footer. No control has a hard-coded width.
- Subscription "Session matching (advanced)" section: the Custom marker row without a fixed width; both explanations in the footer.
- Logic (operator semantics, regex validation, choice transitions, captions) lives in UsageCore with tests first; the SwiftUI layer only lays out (constitution II).
- `docs/configuration.md` describes the operators, the `operator` key, case handling, the regex flavor and the limits of the overlap warning.

## Open Questions

- Which regex flavor and options exactly (ICU via `NSRegularExpression` is the obvious one); is a pattern length limit or a match timeout needed for the Anywhere field, which runs over every raw record line?
- Does the condition row fit the editor pane at its minimum width, or must it wrap (for example the text field to its own line below the two pop-ups)? The plan should check with the real window.
- Should the operator pop-up name *matches regex* as "matches regular expression" or "matches pattern"? Mail uses neither; Finder's raw query uses neither. Pick one and keep it in `MatchRuleText`.
- Does any screenshot stem show the Accounts tab's Session matching section? If not, "No visible change in the shot list" with the reason; otherwise a recapture.
- Should a regex rule be offered a "Test" affordance (count of matching records in the current window)? Probably not for this round (YAGNI), but the spec should say so.

---

## Revisit: 2026-10-28

### Updated Problem Framing

The spec 038 walkthrough showed that the "Match rule" pop-up mixes two different questions:

1. **Which sessions** an account pays for: Codex sessions signed in with an API key (not a ChatGPT plan), OpenCode messages of a provider (Vertex, OpenAI, others), Claude Code records billed through Vertex or through another provider.
2. **Which of those**, as an optional narrowing condition (field, operator, text).

"Custom" sat next to the presets as an alternative, but it only checks its text, never the sign-in or the provider, and it wins over every built-in rule (spec 037 FR-010, `Attribution.swift` rule step). A Codex account with Custom "Model starts with gpt-5" therefore also takes the ChatGPT-plan sessions of the Codex subscription; a broad Claude Code custom rule can take direct Anthropic records of a Claude subscription. For a token-based Codex account "API key" is always implied, so offering it as a choice confused the maintainer, and "Any without a condition" would be wrong.

The walkthrough also found wording problems: "profile" is a term of workspace managers such as cc-deck, not of Anthropic (Claude Code calls it the configuration directory, `CLAUDE_CONFIG_DIR`; AgentTacho's field is "Claude Code directory"), and "None (profile only)" leaked it into the UI. The add sheet should start with the Claude Code default that needs no further input.

### New Approaches Considered

#### A: Session kind plus an optional narrowing condition (chosen)

The account type already says "pay per token". A **session kind** says which per-token sessions; an optional **"Only when"** condition narrows that kind and never widens it.

- Pros: a token-based account can no longer take subscription sessions; every choice in the pop-up is a real choice; gateways need no condition in the common case.
- Cons: reshapes the rule model, the configuration format and the Settings section of the unreleased specs 037 and 038.

#### B: Keep "Custom" as an alternative, but let it inherit the harness's billing check

- Pros: smaller change.
- Cons: the pop-up still presents two axes as one list; Codex keeps a meaningless choice.

#### C: Keep everything, document the pitfall

- Cons: the confusion and the misattribution stay.

### Updated Decision

Approach A.

| Harness | "Sessions" pop-up (default first) | "Only when" condition |
|---|---|---|
| Claude Code | **Directory only**, Vertex, Other provider | hidden for "Directory only"; optional otherwise |
| Codex | no pop-up; caption "Codex sessions signed in with an API key" | optional |
| OpenCode | **Vertex**, OpenAI, Other provider | optional; required for "Other provider" |

- Sessions that ran from the account's Claude Code directory always count for it (spec 037, unchanged); kind and condition decide only for sessions without that information.
- Claude Code kinds: Vertex = request id starts with `req_vrtx_`; Other provider = records without an Anthropic request id (company gateways); Directory only = nothing beyond the directory.
- OpenCode "Other provider" = any provider other than Vertex and OpenAI (for example OpenRouter); it needs a condition to say which.
- The condition keeps spec 038's operators (starts with, contains, matches regex), case-insensitive matching and the 50 ms regex limit.
- UI: section "Which sessions count"; a "Sessions" pop-up; an "Only when" checkbox that reveals the Condition row (field, operator, text); explanations as caption text inside the group. No "profile", "Match rule" or "Custom" in the UI. Pop-ups keep the width of their widest item.
- Migration: a v0.8.0 token-based account with provider and marker becomes that kind plus "Only when Anywhere contains <marker>"; a 037/038-style custom rule (unreleased) becomes Claude Code "Other provider", Codex API key or OpenCode "Other provider", with its condition.
- Subscription accounts keep their Custom marker unchanged.
- Delivery: rework spec 038 on its open branch (`038-match-rule-operators`) before it is merged.

### Open Threads

- Is "no Anthropic request id" a reliable signal for gateways, including Bedrock and other proxies? Check real records of each before the spec fixes it.
- Overlap warning: two accounts with the same kind and no condition (Codex API key twice, two Other provider accounts) must warn; what does it say?
- Can an OpenCode "Other provider" condition use the provider field directly (a field "Provider"), instead of Anywhere?
- Does the dropdown's Unassigned hint need to explain that sessions of no kind stay Unassigned?
