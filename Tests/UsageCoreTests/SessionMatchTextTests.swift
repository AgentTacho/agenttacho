import Testing
@testable import UsageCore

/// spec 038 FR-012 to FR-018, research R13, contracts/settings-ui.md: the
/// texts of the "Which sessions count" section, its notes and the
/// subscription marker.
@Suite struct SessionMatchTextTests {
    typealias Line = SessionMatchText.NoteLine

    @Test func labelsAndItems() {
        #expect(SessionMatchText.harnessLabel == "Harness")
        #expect(SessionMatchText.sectionTitle == "Which sessions count")
        #expect(SessionMatchText.sessionsLabel == "Sessions")
        #expect(SessionMatchText.onlyWhenLabel == "Only when")
        #expect(SessionMatchText.codexSentence == "Counts Codex sessions signed in with an API key.")
        #expect(SessionKind.kinds(for: .claudeCode).map(SessionMatchText.kindItem) == ["Directory only", "Vertex", "Other provider"])
        #expect(SessionKind.kinds(for: .openCode).map(SessionMatchText.kindItem) == ["Vertex", "OpenAI", "Anthropic", "Other provider"])
        #expect(MatchField.allCases.map(SessionMatchText.fieldLabel(for:)) == ["Model", "Request id", "Message id", "Anywhere"])
    }

    /// FR-005, FR-015: operator labels, the Condition row's one visible
    /// label and the accessibility labels of its controls.
    @Test func conditionLabels() {
        #expect(MatchOperator.allCases.map(SessionMatchText.operatorLabel(for:)) == ["starts with", "contains", "matches regex"])
        #expect(SessionMatchText.conditionLabel == "Condition")
        #expect(SessionMatchText.fieldLabel == "Field")
        #expect(SessionMatchText.operatorLabel == "Operator")
        #expect(SessionMatchText.textLabel == "Text")
        #expect(SessionMatchText.invalidPattern == "This regular expression is not valid.")
        #expect(SessionMatchText.blankText == "The condition needs a text.")
    }

    /// FR-015: the prompt fits field and operator, always an invented
    /// example.
    @Test func promptsPerFieldAndOperator() {
        for field in [MatchField.model, .requestId, .messageId] {
            #expect(SessionMatchText.textPrompt(field: field, operator: .startsWith) == "intranet/")
            #expect(SessionMatchText.textPrompt(field: field, operator: .contains) == "glm")
            #expect(SessionMatchText.textPrompt(field: field, operator: .regex) == "^intranet/")
        }
        #expect(SessionMatchText.textPrompt(field: .anywhere, operator: .contains) == "proj-alpha")
        #expect(SessionMatchText.textPrompt(field: .anywhere, operator: .regex) == "proj-(alpha|beta)")
        for field in MatchField.allCases {
            for op in MatchOperator.operators(for: field) {
                #expect(MatchCondition(field: field, operator: op, text: SessionMatchText.textPrompt(field: field, operator: op)).patternProblem == nil)
            }
        }
    }

    /// FR-013 note 1: one sentence per kind, none for Codex.
    @Test func kindCaptions() {
        #expect(SessionMatchText.kindCaption(.claudeCodeDirectoryOnly) == "Counts only sessions that ran from this account's Claude Code directory, nothing else.")
        #expect(SessionMatchText.kindCaption(.claudeCodeVertex) == "Also counts Claude Code requests billed through Vertex (the request id starts with req_vrtx_) from sessions no account's Claude Code directory claims.")
        #expect(SessionMatchText.kindCaption(.claudeCodeOtherProvider) == "Also counts Claude Code requests without an Anthropic request id, such as those through a company gateway, from sessions no account's Claude Code directory claims.")
        #expect(SessionMatchText.kindCaption(.openCodeVertex) == "Counts OpenCode messages whose provider is google-vertex or google-vertex-anthropic.")
        #expect(SessionMatchText.kindCaption(.openCodeOpenAI) == "Counts OpenCode messages whose provider is openai.")
        #expect(SessionMatchText.kindCaption(.openCodeAnthropic)
                == "Counts OpenCode messages whose provider is anthropic, including those of OpenCode sessions signed in with a Claude plan.")
        #expect(SessionMatchText.kindCaption(.openCodeOtherProvider) == "Counts OpenCode messages of any provider other than Vertex, OpenAI and Anthropic. The condition says which.")
        #expect(SessionMatchText.kindCaption(.codexAPIKey) == nil)
    }

    @Test func captions() {
        #expect(SessionMatchText.anywhereCaption
                == "Anywhere searches the whole record line, including tool inputs and outputs, so a session that only mentions the text matches too.")
    }

    /// Walkthrough feedback: the directory note names the field's value,
    /// says when the empty field means the default, and says when another
    /// account shares the directory, since then the choices decide.
    @Test func directoryNoteFollowsTheField() {
        #expect(SessionMatchText.directoryNote(directory: "~/.claude-gateway", sharedWith: [])
                == "Sessions that ran from ~/.claude-gateway always count for this account. The choices above decide for sessions that no account's Claude Code directory claims, such as those from Claude Code before version 2.1.300.")
        #expect(SessionMatchText.directoryNote(directory: nil, sharedWith: [])
                == "Sessions that ran from ~/.claude (the default, since the Claude Code directory is empty) always count for this account. The choices above decide for sessions that no account's Claude Code directory claims, such as those from Claude Code before version 2.1.300.")
        #expect(SessionMatchText.directoryNote(directory: "  ", sharedWith: [])
                == SessionMatchText.directoryNote(directory: nil, sharedWith: []))
        #expect(SessionMatchText.directoryNote(directory: nil, sharedWith: ["Max"])
                == "Sessions that ran from ~/.claude (the default, since the Claude Code directory is empty) also belong to \"Max\", so the choices above decide which of them count for this account, as they do for sessions that no account's Claude Code directory claims.")
        #expect(SessionMatchText.directoryNote(directory: "~/.claude-gateway", sharedWith: ["A", "B"])
                == "Sessions that ran from ~/.claude-gateway also belong to \"A\" and \"B\", so the choices above decide which of them count for this account, as they do for sessions that no account's Claude Code directory claims.")
        #expect(SessionMatchText.openCodeSourceCaption == "OpenCode data directories are set for all accounts in General > Sources.")
    }

    /// FR-018: the subscription marker's notes say it only narrows.
    @Test func subscriptionMarkerNotes() {
        #expect(SessionMatchText.subscriptionMarkerCaption
                == "Leave this empty in most cases. Sessions that ran from this account's own Claude Code directory or Codex home count for it; other usage is assigned by its kind: direct Anthropic requests from Claude Code for a Claude subscription, ChatGPT-plan sessions for a Codex subscription.")
        #expect(SessionMatchText.subscriptionMarkerHint
                == "Use a marker only to tell apart two subscriptions of the same kind. Enter text that appears only in this account's session records, such as a project path or a host name. When it is set, only this subscription's own kind of usage that contains the text counts for it; usage of a token-based account never does.")
    }

    /// FR-013 note 5: the advice follows the harness.
    @Test func overlapWarningsPerHarness() {
        #expect(SessionMatchText.overlapWarning(otherNames: ["Lab gateway"], harness: .claudeCode)
                == "Records that match both this account and \"Lab gateway\" stay Unassigned. Give one of them its own Claude Code directory, another choice under Sessions or another condition.")
        #expect(SessionMatchText.overlapWarning(otherNames: ["Lab gateway"], harness: .openCode)
                == "Records that match both this account and \"Lab gateway\" stay Unassigned. Give one of them another choice under Sessions or another condition.")
        #expect(SessionMatchText.overlapWarning(otherNames: ["Lab gateway"], harness: .codex)
                == "Records that match both this account and \"Lab gateway\" stay Unassigned. Give one of them another condition.")
        #expect(SessionMatchText.overlapWarning(otherNames: ["A", "B"], harness: .codex).contains("\"A\" and \"B\" stay Unassigned"))
        #expect(SessionMatchText.overlapWarning(otherNames: ["A", "B", "C"], harness: .codex).contains("\"A\", \"B\" and \"C\" stay"))
    }

    /// FR-013 note 6, with one, two and three names.
    @Test func directoryOnlyWarning() {
        #expect(SessionMatchText.directoryOnlyWarning(otherNames: ["Claude Max"])
                == "\"Claude Max\" uses the same Claude Code directory, so its sessions count for \"Claude Max\", not for this account. Give this account its own Claude Code directory.")
        #expect(SessionMatchText.directoryOnlyWarning(otherNames: ["A", "B"])
                == "\"A\" and \"B\" use the same Claude Code directory, so its sessions count for \"A\" and \"B\", not for this account. Give this account its own Claude Code directory.")
        #expect(SessionMatchText.directoryOnlyWarning(otherNames: ["A", "B", "C"]).hasPrefix("\"A\", \"B\" and \"C\" use the same"))
    }

    /// contracts/settings-ui.md: the display name prompt and default name
    /// follow the kind.
    @Test func displayNamePrompts() {
        let expected: [SessionKind: String] = [
            .claudeCodeDirectoryOnly: "Claude Code account", .claudeCodeVertex: "Claude Code via Vertex",
            .claudeCodeOtherProvider: "Claude Code via gateway", .codexAPIKey: "Codex API key",
            .openCodeVertex: "OpenCode via Vertex", .openCodeOpenAI: "OpenCode via OpenAI", .openCodeAnthropic: "OpenCode via Anthropic", .openCodeOtherProvider: "OpenCode account",
        ]
        for kind in SessionKind.allCases {
            #expect(SessionMatchText.displayNamePrompt(kind: kind) == expected[kind])
        }
    }

    // MARK: - Note order (FR-013, research R13)

    static let glm = MatchCondition(field: .model, operator: .contains, text: "glm")
    static let overlap = MatchOverlap(accountId: "a", otherNames: ["B"])
    static let conflict = DirectoryOnlyConflict(accountId: "a", otherNames: ["Max"])

    private func lines(_ kind: SessionKind, _ condition: MatchCondition? = nil, overlap: MatchOverlap? = nil,
                       conflict: DirectoryOnlyConflict? = nil, directory: String? = nil, sharedWith: [String] = []) -> [Line] {
        SessionMatchText.noteLines(kind: kind, condition: condition, overlap: overlap, directoryConflict: conflict,
                                   directory: directory, sharedWith: sharedWith)
    }

    private func caption(_ kind: SessionKind) -> Line { Line(text: SessionMatchText.kindCaption(kind)!) }
    private var anywhere: Line { Line(text: SessionMatchText.anywhereCaption) }
    private var directory: Line { Line(text: SessionMatchText.directoryNote(directory: nil, sharedWith: [])) }
    private var blank: Line { Line(text: SessionMatchText.blankText) }
    private var invalid: Line { Line(text: SessionMatchText.invalidPattern) }
    private func warning(_ harness: Harness) -> Line {
        Line(text: SessionMatchText.overlapWarning(otherNames: ["B"], harness: harness), isWarning: true)
    }

    @Test func claudeCodeNotes() {
        #expect(lines(.claudeCodeVertex) == [caption(.claudeCodeVertex), directory])
        #expect(lines(.claudeCodeOtherProvider, Self.glm) == [caption(.claudeCodeOtherProvider), directory])
        #expect(lines(.claudeCodeOtherProvider, MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha"))
                == [caption(.claudeCodeOtherProvider), anywhere, directory])
        #expect(lines(.claudeCodeVertex, MatchCondition(field: .model, operator: .startsWith, text: " ")) == [caption(.claudeCodeVertex), directory, blank])
        #expect(lines(.claudeCodeVertex, MatchCondition(field: .anywhere, operator: .regex, text: "proj-(alpha"), overlap: Self.overlap)
                == [caption(.claudeCodeVertex), anywhere, directory, invalid, warning(.claudeCode)])
    }

    /// research R13: Directory only has its kind sentence instead of the
    /// directory note, never a condition note or an overlap warning, and
    /// the shared directory warning when it applies.
    @Test func directoryOnlyNotes() {
        #expect(lines(.claudeCodeDirectoryOnly) == [caption(.claudeCodeDirectoryOnly)])
        #expect(lines(.claudeCodeDirectoryOnly, MatchCondition(field: .anywhere, operator: .regex, text: "proj-(alpha"), overlap: Self.overlap)
                == [caption(.claudeCodeDirectoryOnly)])
        #expect(lines(.claudeCodeDirectoryOnly, conflict: Self.conflict)
                == [caption(.claudeCodeDirectoryOnly), Line(text: SessionMatchText.directoryOnlyWarning(otherNames: ["Max"]), isWarning: true)])
        // The conflict note is only for Directory only.
        #expect(lines(.claudeCodeVertex, conflict: Self.conflict) == [caption(.claudeCodeVertex), directory])
        // The directory note follows the field and the sharing accounts.
        #expect(lines(.claudeCodeVertex, directory: "~/.claude-gateway", sharedWith: ["Max"])
                == [caption(.claudeCodeVertex),
                    Line(text: SessionMatchText.directoryNote(directory: "~/.claude-gateway", sharedWith: ["Max"]))])
    }

    /// research R13: Codex has no kind sentence (its sentence is the row).
    @Test func codexNotes() {
        #expect(lines(.codexAPIKey).isEmpty)
        #expect(lines(.codexAPIKey, MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha")) == [anywhere])
        #expect(lines(.codexAPIKey, overlap: Self.overlap) == [warning(.codex)])
    }

    /// Edge case "OpenCode Other provider without a condition": the row
    /// shows the initial condition, so the blank text note shows.
    @Test func openCodeNotes() {
        #expect(lines(.openCodeVertex) == [caption(.openCodeVertex)])
        #expect(lines(.openCodeOpenAI, overlap: Self.overlap) == [caption(.openCodeOpenAI), warning(.openCode)])
        #expect(lines(.openCodeOtherProvider) == [caption(.openCodeOtherProvider), blank])
        #expect(lines(.openCodeOtherProvider, Self.glm) == [caption(.openCodeOtherProvider)])
    }

    /// FR-016, contracts/settings-ui.md: the new account sheet shows notes
    /// 1, 2 and 6 as captions; a blank text or invalid pattern shows in its
    /// red validation message on "Add" instead.
    @Test func sheetNotes() {
        let anywhereBlank = MatchCondition(field: .anywhere, operator: .contains, text: "")
        #expect(SessionMatchText.sheetNoteLines(kind: .claudeCodeVertex, condition: anywhereBlank, directoryConflict: nil)
                == [caption(.claudeCodeVertex), anywhere])
        #expect(SessionMatchText.sheetNoteLines(kind: .claudeCodeDirectoryOnly, condition: nil, directoryConflict: Self.conflict)
                == [caption(.claudeCodeDirectoryOnly), Line(text: SessionMatchText.directoryOnlyWarning(otherNames: ["Max"]), isWarning: true)])
        #expect(SessionMatchText.sheetNoteLines(kind: .openCodeOtherProvider, condition: nil, directoryConflict: nil)
                == [caption(.openCodeOtherProvider)])
        #expect(SessionMatchText.sheetNoteLines(kind: .codexAPIKey, condition: nil, directoryConflict: nil).isEmpty)
    }

    // MARK: - Wording (FR-017)

    /// No visible text of a token-based account says "profile", "Match
    /// rule", "Custom" or "preset"; no text holds a dash character;
    /// examples are invented.
    @Test func tokenBasedTextsAvoidMechanismWords() {
        for text in SessionMatchText.tokenBasedTexts {
            for word in ["profile", "match rule", "custom", "preset"] {
                #expect(!text.lowercased().contains(word), "\(word) in \(text)")
            }
        }
        let realTool = ["cc", "deck"].joined(separator: "-")
        let dashes: [Character] = ["\u{2014}", "\u{2013}"]
        for text in SessionMatchText.allFixedTexts {
            #expect(!text.contains(realTool))
            #expect(!text.contains { dashes.contains($0) })
            #expect(!text.isEmpty)
        }
        #expect(SessionMatchText.allFixedTexts.contains("intranet/"))
        #expect(SessionMatchText.allFixedTexts.contains("proj-alpha"))
    }

    /// FR-017: no UI text constant says "profile", subscription texts
    /// included.
    @Test func noTextSaysProfile() {
        for text in SessionMatchText.allFixedTexts + AccountDirectoryText.allFixedTexts {
            #expect(!text.lowercased().contains("profile"), "\(text)")
        }
    }
}
