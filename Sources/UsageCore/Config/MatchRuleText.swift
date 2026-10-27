import Foundation

/// The labels, captions and prompts of a token-based account's harness and
/// match rule in Settings > Accounts and in the new account sheet, and the
/// overlap warning (spec 037 FR-007, FR-013, FR-018,
/// contracts/settings-ui.md). Kept in UsageCore so tests check the wording
/// and that every example is invented.
public enum MatchRuleText {
    /// The label of the harness pop-up (spec 037 FR-006).
    public static let harnessLabel = "Harness"

    /// The section that holds the rule pop-up (contracts/settings-ui.md).
    public static let sessionMatchingSection = "Session matching"

    /// The label of the rule pop-up (spec 037 FR-007).
    public static let matchRuleLabel = "Match rule"

    /// The rule pop-up item of a custom rule.
    public static let customItem = "Custom"

    /// The rule pop-up item of `.none` for Claude Code (spec 037 FR-007).
    public static let noneItem = "None (profile only)"

    /// The current item of a Codex or OpenCode account whose rule was
    /// dropped while loading (spec 037 FR-015, contracts/settings-ui.md).
    public static let droppedNoneItem = "None"

    /// The label of the custom rule's field pop-up.
    public static let fieldLabel = "Field"

    /// The pop-up title of `field` (spec 037 FR-007).
    public static func fieldLabel(for field: MatchField) -> String {
        switch field {
        case .model: return "Model"
        case .requestId: return "Request id"
        case .messageId: return "Message id"
        case .anywhere: return "Anywhere in the record line"
        }
    }

    /// The label of the custom rule's text field: a prefix for the record
    /// fields, a text for the raw line.
    public static func textLabel(for field: MatchField) -> String {
        field == .anywhere ? "Contains" : "Starts with"
    }

    /// The invented example in the custom rule's empty text field (spec 037
    /// FR-018).
    public static func textPrompt(for field: MatchField) -> String {
        field == .anywhere ? "proj-alpha" : "intranet/"
    }

    /// The read-only caption of a preset: what it checks (spec 037 FR-007).
    public static func presetCaption(_ preset: MatchPreset) -> String {
        switch preset {
        case .claudeCodeVertex: return "Request id starts with req_vrtx_"
        case .codexAPIKey: return "The session signs in with an API key"
        case .openCodeVertex: return "Provider is google-vertex or google-vertex-anthropic"
        case .openCodeOpenAI: return "Provider is openai"
        }
    }

    /// The caption of "Anywhere in the record line" (spec 037 edge case
    /// "Anywhere in the record line").
    public static let anywhereCaption = "Also searches tool inputs and outputs, so a session that only mentions the text matches too."

    /// Shown for every Claude Code account: the profile beats the rule
    /// (spec 037 FR-003).
    public static let claudeCodeCaption = "Sessions that ran from this account's Claude Code directory count for it whatever the rule says. The rule decides for sessions without that information, such as older ones."

    /// The caption of "None (profile only)".
    public static let noneCaption = "Only sessions that ran from this account's Claude Code directory count."

    /// The caption of a Codex or OpenCode account whose rule was dropped
    /// while loading (spec 037 FR-015).
    public static let droppedNoneCaption = "This account matches no usage until you choose a rule."

    /// The caption that replaces the directory field of an OpenCode account
    /// (contracts/settings-ui.md).
    public static let openCodeSourceCaption = "OpenCode data directories are set for all accounts in General > Sources."

    /// The first caption of a subscription's custom marker; it no longer
    /// says that Vertex counts OpenCode usage (spec 037 FR-009,
    /// contracts/settings-ui.md).
    public static let subscriptionMarkerCaption = "Leave this empty in most cases. Sessions that ran from this account's Claude Code directory count for it; other usage is assigned by its kind: direct Anthropic requests from Claude Code for a Claude subscription, ChatGPT-plan sessions for a Codex subscription."

    /// The second caption of a subscription's custom marker.
    public static let subscriptionMarkerHint = "Use a marker only to tell apart two subscriptions of the same kind. Enter text that appears only in this account's session records, such as a project path or a host name. When it is set, only sessions containing this text count for this account."

    /// The display name prompt and default name of a new token-based
    /// account, following harness and rule (contracts/settings-ui.md).
    public static func displayNamePrompt(harness: Harness, rule: MatchRule) -> String {
        if case .preset(let preset) = rule, preset.harness == harness {
            switch preset {
            case .claudeCodeVertex: return "Claude Code via Vertex"
            case .codexAPIKey: return "Codex API key"
            case .openCodeVertex: return "OpenCode via Vertex"
            case .openCodeOpenAI: return "OpenCode via OpenAI"
            }
        }
        return "\(harness.displayName) account"
    }

    /// The pop-up title of `rule` (spec 037 FR-007): the preset's name,
    /// "Custom", or "None (profile only)" for Claude Code and "None" for a
    /// rule dropped on another harness.
    public static func ruleItem(_ rule: MatchRule, harness: Harness) -> String {
        switch rule {
        case .preset(let preset): return preset.displayName
        case .custom: return customItem
        case .none: return harness == .claudeCode ? noneItem : droppedNoneItem
        }
    }

    /// The overlap warning of one account, naming the others (spec 037
    /// FR-013, contracts/settings-ui.md).
    public static func overlapWarning(otherNames: [String]) -> String {
        "Records that match both this account and \(namesList(otherNames)) stay Unassigned. Give one of them another rule or, for Claude Code, another directory."
    }

    /// `"A"`, `"A" and "B"`, `"A", "B" and "C"`.
    static func namesList(_ names: [String]) -> String {
        let quoted = names.map { "\"\($0)\"" }
        guard quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
    }

    /// Every fixed text, for the tests that check wording rules.
    static var allFixedTexts: [String] {
        [harnessLabel, sessionMatchingSection, matchRuleLabel, customItem, noneItem, droppedNoneItem, fieldLabel,
         anywhereCaption, claudeCodeCaption, noneCaption, droppedNoneCaption, openCodeSourceCaption,
         subscriptionMarkerCaption, subscriptionMarkerHint, overlapWarning(otherNames: ["Lab gateway"])]
            + MatchField.allCases.flatMap { [fieldLabel(for: $0), textLabel(for: $0), textPrompt(for: $0)] }
            + MatchPreset.allCases.flatMap { [presetCaption($0), $0.displayName] }
            + Harness.allCases.flatMap { harness in
                [displayNamePrompt(harness: harness, rule: .none)]
                    + MatchPreset.presets(for: harness).map { displayNamePrompt(harness: harness, rule: .preset($0)) }
            }
    }
}
