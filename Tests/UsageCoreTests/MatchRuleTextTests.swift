import Testing
@testable import UsageCore

/// spec 037 FR-007, FR-013, FR-018, contracts/settings-ui.md: the texts of
/// harness, match rule and overlap warning.
@Suite struct MatchRuleTextTests {
    @Test func labelsAndItems() {
        #expect(MatchRuleText.harnessLabel == "Harness")
        #expect(MatchRuleText.sessionMatchingSection == "Session matching")
        #expect(MatchRuleText.matchRuleLabel == "Match rule")
        #expect(MatchRuleText.customItem == "Custom")
        #expect(MatchRuleText.noneItem == "None (profile only)")
        #expect(MatchRuleText.fieldLabel == "Field")
        #expect(MatchField.allCases.map(MatchRuleText.fieldLabel(for:))
                == ["Model", "Request id", "Message id", "Anywhere in the record line"])
        #expect(MatchPreset.allCases.map(\.displayName) == ["Vertex", "API key", "Vertex", "OpenAI"])
    }

    @Test func ruleItemsFollowTheHarness() {
        #expect(MatchRuleText.ruleItem(.preset(.claudeCodeVertex), harness: .claudeCode) == "Vertex")
        #expect(MatchRuleText.ruleItem(.custom(field: .model, text: "intranet/"), harness: .codex) == "Custom")
        #expect(MatchRuleText.ruleItem(.none, harness: .claudeCode) == "None (profile only)")
        #expect(MatchRuleText.ruleItem(.none, harness: .openCode) == "None")
    }

    @Test func presetCaptionsSayWhatTheyCheck() {
        #expect(MatchRuleText.presetCaption(.claudeCodeVertex) == "Request id starts with req_vrtx_")
        #expect(MatchRuleText.presetCaption(.codexAPIKey) == "The session signs in with an API key")
        #expect(MatchRuleText.presetCaption(.openCodeVertex) == "Provider is google-vertex or google-vertex-anthropic")
        #expect(MatchRuleText.presetCaption(.openCodeOpenAI) == "Provider is openai")
    }

    @Test func customRuleTexts() {
        #expect(MatchRuleText.textPrompt(for: .model) == "intranet/")
        #expect(MatchRuleText.textPrompt(for: .anywhere) == "proj-alpha")
        #expect(MatchRuleText.textLabel(for: .model) == "Starts with")
        #expect(MatchRuleText.textLabel(for: .anywhere) == "Contains")
        #expect(MatchRuleText.anywhereCaption
                == "Also searches tool inputs and outputs, so a session that only mentions the text matches too.")
    }

    @Test func captions() {
        #expect(MatchRuleText.claudeCodeCaption
                == "Sessions that ran from this account's Claude Code directory count for it whatever the rule says. The rule decides for sessions without that information, such as older ones.")
        #expect(MatchRuleText.noneCaption == "Only sessions that ran from this account's Claude Code directory count.")
        #expect(MatchRuleText.openCodeSourceCaption == "OpenCode data directories are set for all accounts in General > Sources.")
        #expect(MatchRuleText.subscriptionMarkerCaption
                == "Leave this empty in most cases. Sessions that ran from this account's Claude Code directory count for it; other usage is assigned by its kind: direct Anthropic requests from Claude Code for a Claude subscription, ChatGPT-plan sessions for a Codex subscription.")
        // FR-009: the subscription caption no longer says Vertex counts OpenCode.
        #expect(!MatchRuleText.subscriptionMarkerCaption.contains("OpenCode"))
        #expect(!MatchRuleText.subscriptionMarkerCaption.contains("Vertex"))
    }

    @Test func displayNamePrompts() {
        #expect(MatchRuleText.displayNamePrompt(harness: .claudeCode, rule: .preset(.claudeCodeVertex)) == "Claude Code via Vertex")
        #expect(MatchRuleText.displayNamePrompt(harness: .codex, rule: .preset(.codexAPIKey)) == "Codex API key")
        #expect(MatchRuleText.displayNamePrompt(harness: .openCode, rule: .preset(.openCodeVertex)) == "OpenCode via Vertex")
        #expect(MatchRuleText.displayNamePrompt(harness: .openCode, rule: .preset(.openCodeOpenAI)) == "OpenCode via OpenAI")
        #expect(MatchRuleText.displayNamePrompt(harness: .claudeCode, rule: .custom(field: .model, text: "intranet/")) == "Claude Code account")
        #expect(MatchRuleText.displayNamePrompt(harness: .codex, rule: .none) == "Codex account")
        #expect(MatchRuleText.displayNamePrompt(harness: .openCode, rule: .custom(field: .anywhere, text: "x")) == "OpenCode account")
    }

    /// FR-013: the warning names the other accounts.
    @Test func overlapWarningNamesTheOthers() {
        #expect(MatchRuleText.overlapWarning(otherNames: ["Lab gateway"])
                == "Records that match both this account and \"Lab gateway\" stay Unassigned. Give one of them another rule or, for Claude Code, another directory.")
        #expect(MatchRuleText.overlapWarning(otherNames: ["A", "B"]).contains("\"A\" and \"B\" stay Unassigned"))
        #expect(MatchRuleText.overlapWarning(otherNames: ["A", "B", "C"]).contains("\"A\", \"B\" and \"C\" stay"))
    }

    /// FR-018: examples are invented, and no text holds a dash character.
    @Test func textsAreInventedAndDashFree() {
        let realTool = ["cc", "deck"].joined(separator: "-")
        let dashes: [Character] = ["\u{2014}", "\u{2013}"]
        for text in MatchRuleText.allFixedTexts {
            #expect(!text.contains(realTool))
            #expect(!text.contains { dashes.contains($0) })
            #expect(!text.isEmpty)
        }
        #expect(MatchRuleText.allFixedTexts.contains("intranet/"))
        #expect(MatchRuleText.allFixedTexts.contains("proj-alpha"))
    }
}
