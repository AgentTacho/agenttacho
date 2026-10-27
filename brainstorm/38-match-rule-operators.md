# Brainstorm: Match Rule Operators and a HIG-Conform Session Matching Section

**Date:** 2026-10-27
**Status:** active

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
