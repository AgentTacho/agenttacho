import Foundation

/// The labels, captions, prompts and notes of a token-based account's
/// "Which sessions count" section in Settings > Accounts and in the new
/// account sheet, and of a subscription's marker (spec 038 FR-012 to
/// FR-018, contracts/settings-ui.md). Kept in UsageCore so tests check the
/// wording, the note order and that every example is invented.
public enum SessionMatchText {
    /// The label of the harness pop-up (spec 037 FR-006).
    public static let harnessLabel = "Harness"

    /// The section of a token-based account that says which sessions count
    /// (spec 038 FR-012).
    public static let sectionTitle = "Which sessions count"

    /// The label of the kind pop-up (spec 038 FR-012).
    public static let sessionsLabel = "Sessions"

    /// The Sessions pop-up item of `kind` (spec 038 FR-001, FR-012).
    public static func kindItem(_ kind: SessionKind) -> String { kind.displayName }

    /// The row that replaces the pop-up for Codex, whose only kind is API
    /// key (spec 038 FR-012).
    public static let codexSentence = "Counts Codex sessions signed in with an API key."

    /// The checkbox that turns the condition on (spec 038 FR-012, FR-014).
    public static let onlyWhenLabel = "Only when"

    /// The one visible label of the Condition row (spec 038 FR-015).
    public static let conditionLabel = "Condition"

    /// The accessibility label of the field pop-up (spec 038 FR-015).
    public static let fieldLabel = "Field"

    /// The accessibility label of the operator pop-up (spec 038 FR-015).
    public static let operatorLabel = "Operator"

    /// The accessibility label of the text field (spec 038 FR-015).
    public static let textLabel = "Text"

    /// The pop-up title of `field` (spec 038 FR-004, FR-017).
    public static func fieldLabel(for field: MatchField) -> String {
        switch field {
        case .model: return "Model"
        case .requestId: return "Request id"
        case .messageId: return "Message id"
        case .anywhere: return "Anywhere"
        }
    }

    /// The operator pop-up item of `op` (spec 038 FR-005).
    public static func operatorLabel(for op: MatchOperator) -> String {
        switch op {
        case .startsWith: return "starts with"
        case .contains: return "contains"
        case .regex: return "matches regex"
        }
    }

    /// The invented example in the empty text field, fitting field and
    /// operator (spec 038 FR-015, contracts/settings-ui.md).
    public static func textPrompt(field: MatchField, operator op: MatchOperator) -> String {
        switch (field, op) {
        case (.anywhere, .regex): return "proj-(alpha|beta)"
        case (.anywhere, _): return "proj-alpha"
        case (_, .startsWith): return "intranet/"
        case (_, .contains): return "glm"
        case (_, .regex): return "^intranet/"
        }
    }

    /// What `kind` counts, the first note of the section; nil for Codex,
    /// whose sentence is the row (spec 038 FR-013 note 1, research R13).
    public static func kindCaption(_ kind: SessionKind) -> String? {
        switch kind {
        case .claudeCodeDirectoryOnly: return "Counts only sessions that ran from this account's Claude Code directory, nothing else."
        case .claudeCodeVertex: return "Also counts Claude Code requests billed through Vertex (the request id starts with req_vrtx_) from sessions no account's Claude Code directory claims."
        case .claudeCodeOtherProvider: return "Also counts Claude Code requests without an Anthropic request id, such as those through a company gateway, from sessions no account's Claude Code directory claims."
        case .codexAPIKey: return nil
        case .openCodeVertex: return "Counts OpenCode messages whose provider is google-vertex or google-vertex-anthropic."
        case .openCodeOpenAI: return "Counts OpenCode messages whose provider is openai."
        case .openCodeAnthropic: return "Counts OpenCode messages whose provider is anthropic, including those of OpenCode sessions signed in with a Claude plan."
        case .openCodeOtherProvider: return "Counts OpenCode messages of any provider other than Vertex, OpenAI and Anthropic. The condition says which."
        }
    }

    /// The note of the field Anywhere, which says what the short label
    /// means: the whole raw record line (spec 038 FR-013 note 2).
    public static let anywhereCaption = "Anywhere searches the whole record line, including tool inputs and outputs, so a session that only mentions the text matches too."

    /// The note that sessions from the account's Claude Code directory
    /// count for it, naming the field's value (`~/.claude` with a hint when
    /// the field is empty); when other accounts use the same directory, it
    /// says that kind and condition decide among them instead (spec 038
    /// FR-013 note 3, walkthrough feedback).
    public static func directoryNote(directory: String?, sharedWith others: [String]) -> String {
        let entered = directory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let place = entered.isEmpty ? "~/.claude (the default, since the Claude Code directory is empty)" : entered
        guard others.isEmpty else {
            return "Sessions that ran from \(place) also belong to \(namesList(others)), so the choices above decide which of them count for this account, as they do for sessions that no account's Claude Code directory claims."
        }
        return "Sessions that ran from \(place) always count for this account. The choices above decide for sessions that no account's Claude Code directory claims, such as those from Claude Code before version 2.1.300."
    }

    /// The note of a shown condition with a blank text (spec 038 FR-008,
    /// FR-013 note 4).
    public static let blankText = "The condition needs a text."

    /// The note of a regex that does not compile (spec 038 FR-008, FR-013
    /// note 4).
    public static let invalidPattern = "This regular expression is not valid."

    /// The caption that replaces the directory field of an OpenCode account
    /// (spec 037 contracts/settings-ui.md).
    public static let openCodeSourceCaption = "OpenCode data directories are set for all accounts in General > Sources."

    /// The first note of a subscription's custom marker (spec 038 FR-018).
    public static let subscriptionMarkerCaption = "Leave this empty in most cases. Sessions that ran from this account's own Claude Code directory or Codex home count for it; other usage is assigned by its kind: direct Anthropic requests from Claude Code for a Claude subscription, ChatGPT-plan sessions for a Codex subscription."

    /// The second note of a subscription's custom marker: it only narrows
    /// the subscription's own kind (spec 038 FR-006, FR-018).
    public static let subscriptionMarkerHint = "Use a marker only to tell apart two subscriptions of the same kind. Enter text that appears only in this account's session records, such as a project path or a host name. When it is set, only this subscription's own kind of usage that contains the text counts for it; usage of a token-based account never does."

    /// The overlap warning of one account, naming the others; the advice
    /// follows the harness, since Codex has no other kind to choose (spec
    /// 038 FR-009, FR-013 note 5).
    public static func overlapWarning(otherNames: [String], harness: Harness) -> String {
        let advice: String
        switch harness {
        case .claudeCode: advice = "its own Claude Code directory, another choice under Sessions or another condition"
        case .openCode: advice = "another choice under Sessions or another condition"
        case .codex: advice = "another condition"
        }
        return "Records that match both this account and \(namesList(otherNames)) stay Unassigned. Give one of them \(advice)."
    }

    /// The warning of a Directory only account whose main Claude Code
    /// directory other accounts use too (spec 038 FR-013 note 6).
    public static func directoryOnlyWarning(otherNames: [String]) -> String {
        let names = namesList(otherNames)
        let verb = otherNames.count == 1 ? "uses" : "use"
        return "\(names) \(verb) the same Claude Code directory, so its sessions count for \(names), not for this account. Give this account its own Claude Code directory."
    }

    /// The display name prompt and default name of a new token-based
    /// account of `kind` (contracts/settings-ui.md).
    public static func displayNamePrompt(kind: SessionKind) -> String {
        switch kind {
        case .claudeCodeDirectoryOnly: return "Claude Code account"
        case .claudeCodeVertex: return "Claude Code via Vertex"
        case .claudeCodeOtherProvider: return "Claude Code via gateway"
        case .codexAPIKey: return "Codex API key"
        case .openCodeVertex: return "OpenCode via Vertex"
        case .openCodeOpenAI: return "OpenCode via OpenAI"
        case .openCodeAnthropic: return "OpenCode via Anthropic"
        case .openCodeOtherProvider: return "OpenCode account"
        }
    }

    /// One note of a section (spec 038 FR-013).
    public struct NoteLine: Equatable, Sendable {
        public let text: String
        /// A warning, shown with a warning symbol.
        public let isWarning: Bool

        public init(text: String, isWarning: Bool = false) {
            self.text = text
            self.isWarning = isWarning
        }
    }

    /// The condition the Condition row shows for `kind` with the stored
    /// `condition`: none for a kind without one, the initial one for a kind
    /// that requires one and has none (spec 038 FR-014, edge case "OpenCode
    /// Other provider without a condition").
    static func shownCondition(kind: SessionKind, condition: MatchCondition?) -> MatchCondition? {
        guard kind.offersCondition else { return nil }
        return kind.requiresCondition ? (condition ?? .initial) : condition
    }

    /// The notes below the controls, in order and only when they apply:
    /// what the kind counts, the Anywhere caption, the directory note
    /// (Claude Code, not for Directory only, whose kind sentence says it),
    /// the blank text or invalid pattern note, the overlap warning (not for
    /// Directory only) and the shared directory warning (Directory only)
    /// (spec 038 FR-013, research R13). `condition` is the stored one.
    public static func noteLines(kind: SessionKind, condition: MatchCondition?, overlap: MatchOverlap?,
                                 directoryConflict: DirectoryOnlyConflict?, directory: String? = nil,
                                 sharedWith: [String] = []) -> [NoteLine] {
        var lines: [NoteLine] = []
        if let caption = kindCaption(kind) { lines.append(NoteLine(text: caption)) }
        let shown = shownCondition(kind: kind, condition: condition)
        if shown?.field == .anywhere { lines.append(NoteLine(text: anywhereCaption)) }
        let directoryOnly = kind == .claudeCodeDirectoryOnly
        if kind.harness == .claudeCode && !directoryOnly {
            lines.append(NoteLine(text: directoryNote(directory: directory, sharedWith: sharedWith)))
        }
        if let shown {
            if shown.hasBlankText {
                lines.append(NoteLine(text: blankText))
            } else if let problem = shown.patternProblem {
                lines.append(NoteLine(text: problem))
            }
        }
        if let overlap, !directoryOnly {
            lines.append(NoteLine(text: overlapWarning(otherNames: overlap.otherNames, harness: kind.harness), isWarning: true))
        }
        if let directoryConflict, directoryOnly {
            lines.append(NoteLine(text: directoryOnlyWarning(otherNames: directoryConflict.otherNames), isWarning: true))
        }
        return lines
    }

    /// The notes of the new account sheet, captions below its controls:
    /// what the kind counts, the Anywhere caption and the shared directory
    /// warning (notes 1, 2 and 6); a blank text or invalid pattern shows in
    /// the sheet's validation message on "Add" instead (spec 038 FR-016,
    /// contracts/settings-ui.md).
    public static func sheetNoteLines(kind: SessionKind, condition: MatchCondition?,
                                      directoryConflict: DirectoryOnlyConflict?) -> [NoteLine] {
        noteLines(kind: kind, condition: condition, overlap: nil, directoryConflict: directoryConflict)
            .filter { ![directoryNote(directory: nil, sharedWith: []), blankText, invalidPattern].contains($0.text) }
    }

    /// `"A"`, `"A" and "B"`, `"A", "B" and "C"`.
    static func namesList(_ names: [String]) -> String {
        let quoted = names.map { "\"\($0)\"" }
        guard quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
    }

    /// Every text a token-based account shows, for the wording tests (spec
    /// 038 FR-017).
    static var tokenBasedTexts: [String] {
        [harnessLabel, sectionTitle, sessionsLabel, codexSentence, onlyWhenLabel, conditionLabel, fieldLabel, operatorLabel,
         textLabel, anywhereCaption, directoryNote(directory: nil, sharedWith: []),
         directoryNote(directory: "~/.claude-gateway", sharedWith: ["Lab gateway"]), blankText, invalidPattern, openCodeSourceCaption,
         directoryOnlyWarning(otherNames: ["Lab gateway"])]
            + Harness.allCases.map { overlapWarning(otherNames: ["Lab gateway"], harness: $0) }
            + MatchField.allCases.map { fieldLabel(for: $0) }
            + MatchOperator.allCases.map { operatorLabel(for: $0) }
            + MatchField.allCases.flatMap { field in
                MatchOperator.operators(for: field).map { textPrompt(field: field, operator: $0) }
            }
            + SessionKind.allCases.flatMap { [kindItem($0), displayNamePrompt(kind: $0)] + (kindCaption($0).map { [$0] } ?? []) }
    }

    /// Every fixed text, subscription marker notes included.
    static var allFixedTexts: [String] {
        tokenBasedTexts + [subscriptionMarkerCaption, subscriptionMarkerHint]
    }
}
