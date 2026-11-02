import SwiftUI
import UsageCore

// MARK: - Accounts tab

struct AccountSettingsView: View {
    @Binding var draft: Configuration
    /// The effective price table, for the Value as pop-up (spec 041 FR-017).
    let prices: PriceTable
    @State private var selection: String?
    /// The type of the account being added; non-nil while the sheet is
    /// shown. `.sheet(item:)` hands the chosen type to the sheet, where
    /// `.sheet(isPresented:)` could build it from the previous choice.
    @State private var newAccountKind: NewAccountSheet.Kind?
    @State private var confirmingRemoval = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                List(draft.accounts, selection: $selection) { account in
                    HStack {
                        labelText(account.icon).bold().frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(account.displayName)
                            subtitle(account)
                        }
                    }
                    .tag(account.id)
                }
                HStack {
                    Menu("Add") {
                        Button("Subscription account") {
                            newAccountKind = .subscription
                        }
                        Button("Token-based account") {
                            newAccountKind = .tokenBased
                        }
                    }
                    .frame(width: 90)
                    Button("Remove…") { confirmingRemoval = true }
                        .disabled(selection == nil)
                }
            }
            .frame(minWidth: 220, maxWidth: 280)

            Group {
                if let selection, let index = draft.accounts.firstIndex(where: { $0.id == selection }) {
                    AccountEditor(account: $draft.accounts[index], draft: $draft, prices: prices)
                } else {
                    Text("Select an account or add one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
        .sheet(item: $newAccountKind) { kind in
            NewAccountSheet(draft: $draft, kind: kind) { id in
                selection = id
            }
        }
        .confirmationDialog(removalTitle, isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) {
                if let selection {
                    draft = draft.removingAccount(id: selection)
                    self.selection = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    /// The list row subtitle. Subscription accounts keep their platform
    /// name (spec 018 FR-006); a token-based account names its session kind and
    /// the budget its spend counts against, built from the unsaved draft
    /// (FR-001, FR-002, FR-005). Only the group icon is drawn here, sized to
    /// the caption text (FR-007); VoiceOver reads the text without the glyph
    /// (FR-007a), and the line truncates at the tail (FR-005a).
    @ViewBuilder
    private func subtitle(_ account: Account) -> some View {
        if let description = AccountBudgetDescription.make(for: account, in: draft) {
            budgetSubtitleText(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel(description.accessibilityText)
        } else {
            Text(subscriptionSubtitle(account))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func budgetSubtitleText(_ description: AccountBudgetDescription) -> Text {
        guard let iconId = description.iconId else { return Text(description.visibleText) }
        let size = NSFont.preferredFont(forTextStyle: .caption1).pointSize
        return Text(description.visiblePrefix) + labelText(iconId, size: size) + Text(" " + description.visibleSuffix)
    }

    private func subscriptionSubtitle(_ account: Account) -> String {
        switch account.kind {
        case .subscription: return SubscriptionPlatform.claude.subscriptionName
        case .codexSubscription: return SubscriptionPlatform.chatgpt.subscriptionName
        // Unreachable while AccountBudgetDescription.make covers every
        // token-based account; listed so a new account kind fails to compile.
        case .tokenBased(let settings): return settings.harness.displayName
        }
    }

    private var selectedAccount: Account? {
        selection.flatMap { id in draft.accounts.first { $0.id == id } }
    }

    private var removalTitle: String {
        "Remove \(selectedAccount?.displayName ?? "account")?"
    }

    /// For the last member of a group, says that the group stays without
    /// accounts; a group is never removed with an account (spec 009 FR-016).
    private var removalMessage: String {
        guard let account = selectedAccount else { return "" }
        let base = "Its usage is no longer shown."
        let undo = "You can undo this with ⌘Z."
        if let groupId = account.kind.tokenBased?.groupId,
           draft.members(of: groupId).count == 1,
           let group = draft.group(id: groupId) {
            return "\(base) The group \"\(group.name)\" stays, without accounts. \(undo)"
        }
        return "\(base) \(undo)"
    }
}

struct AccountEditor: View {
    @Binding var account: Account
    /// The whole draft, so budget switches can move the account between
    /// its own budget, No limit and groups (spec 004 FR-014, spec 041
    /// FR-018).
    @Binding var draft: Configuration
    /// The effective price table, for the Value as pop-up (spec 041 FR-017).
    let prices: PriceTable

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Display name") {
                    TextField("", text: $account.displayName, prompt: Text("Claude Max"))
                        .labelsHidden()
                        .frame(width: 240)
                }
                IconField(icon: $account.icon)
            }
            switch account.kind {
            case .subscription(let settings):
                SubscriptionEditor(settings: Binding(get: { settings }, set: { account.kind = .subscription($0) }),
                                   timeFormat: $account.timeFormat)
            case .tokenBased(let settings):
                TokenBasedEditor(settings: Binding(get: { settings }, set: { account.kind = .tokenBased($0) }),
                                 accountId: account.id, draft: $draft, timeFormat: $account.timeFormat, prices: prices)
            case .codexSubscription(let settings):
                CodexSubscriptionEditor(settings: Binding(get: { settings }, set: { account.kind = .codexSubscription($0) }),
                                        timeFormat: $account.timeFormat)
            }
            // A token-based account's marker became a condition, shown in its
            // "Which sessions count" section; subscriptions keep the marker,
            // which now only narrows their own kind (spec 038 FR-006, FR-018).
            // The marker row takes the room the row leaves it; its two
            // explanations follow inside the group as caption text, as in
            // System Settings.
            if account.kind.tokenBased == nil {
                Section("Session matching (advanced)") {
                    LabeledContent("Custom marker") {
                        TextField("", text: markerBinding, prompt: Text("optional"))
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                    }
                    SectionNotes(lines: [SessionMatchText.subscriptionMarkerCaption, SessionMatchText.subscriptionMarkerHint]
                        .map { SessionMatchText.NoteLine(text: $0) })
                }
            }
        }
        .formStyle(.grouped)
    }

    private var markerBinding: Binding<String> {
        Binding(get: { account.customMarker ?? "" },
                set: { account.customMarker = $0.isEmpty ? nil : $0 })
    }
}

struct SubscriptionEditor: View {
    @Binding var settings: SubscriptionSettings
    /// The account's time format in the dropdown (spec 025 FR-021).
    @Binding var timeFormat: TimeFormat

    var body: some View {
        Section("Subscription") {
            // Bound to the entered value, so a cleared field stays empty
            // while typing; empty means ~/.claude (spec 034 FR-006, FR-006a).
            LabeledContent(AccountDirectoryText.claudeCodeDirectoryLabel) {
                TextField("", text: $settings.enteredCredentialDirectory, prompt: Text(Paths.defaultClaudeDirectory))
                    .labelsHidden()
                    .frame(width: 320)
            }
            Text(AccountDirectoryText.subscriptionCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show in menu bar", isOn: $settings.shownInBar)
            TimeFormatPicker(format: $timeFormat)
        }
        // Session files only, never a login (spec 035 FR-002, FR-009).
        AdditionalSessionDirectoriesSection(harness: .claudeCode, directories: $settings.additionalSessionDirectories)
        Section("Notifications") {
            // No specific Claude window named: the plan's windows come from
            // the answer (spec 040 FR-016, research R12).
            ThresholdsEditor(thresholds: $settings.thresholds,
                             limitDescription: "a plan window such as the 7-day window (each window Anthropic reports is checked on its own)")
        }
    }
}

/// A ChatGPT plan used through Codex: its Codex home (spec 006 FR-015), the
/// bar entry and thresholds per plan window (spec 007 FR-016).
struct CodexSubscriptionEditor: View {
    @Binding var settings: CodexSubscriptionSettings
    /// The account's time format in the dropdown (spec 025 FR-021).
    @Binding var timeFormat: TimeFormat

    var body: some View {
        Section("Codex subscription") {
            // Empty means ~/.codex (spec 034 FR-006, FR-006a).
            LabeledContent(AccountDirectoryText.codexHomeLabel) {
                TextField("", text: $settings.enteredCodexHome, prompt: Text(Paths.defaultCodexHome))
                    .labelsHidden()
                    .frame(width: 320)
            }
            Text(AccountDirectoryText.codexSubscriptionCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show in menu bar", isOn: $settings.shownInBar)
            // spec 007 FR-016, FR-019.
            Toggle("Live limits from the usage service", isOn: $settings.liveLimits)
            Text(settings.liveLimits
                 ? "Reads the Codex sign-in in this Codex home (never changes it) and asks the ChatGPT usage service for the plan's current limits, including usage from other devices. When that fails, the last limits Codex recorded on this Mac are shown."
                 : "Uses only the last limits Codex recorded on this Mac. The Codex sign-in is not read and the usage service is not contacted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TimeFormatPicker(format: $timeFormat)
        }
        // Session files only, never the sign-in or limit snapshots (spec 035
        // FR-002, FR-010).
        AdditionalSessionDirectoriesSection(harness: .codex, directories: $settings.additionalSessionDirectories)
        Section("Notifications") {
            ThresholdsEditor(thresholds: $settings.thresholds,
                             limitDescription: "every plan window (each is checked on its own)")
        }
    }
}

/// Harness, budget, usage source and which sessions count of a token-based
/// account (spec 037 FR-006, spec 038 FR-012). The budget picker offers
/// "Own budget" first, then "No limit", then every group by icon and name;
/// switching goes through the Configuration move helpers (spec 004 FR-013,
/// FR-014, spec 041 FR-018).
struct TokenBasedEditor: View {
    @Binding var settings: TokenBasedSettings
    let accountId: String
    @Binding var draft: Configuration
    /// The account's time format, offered with its own budget and with No
    /// limit: a member's section is the group's (spec 025 FR-021, spec 041
    /// FR-017).
    @Binding var timeFormat: TimeFormat
    /// The effective price table, for the Value as pop-up (spec 041 FR-017).
    let prices: PriceTable

    /// Picker tags of "Own budget" and "No limit"; group ids are UUIDs or
    /// hand-edited ids.
    private static let ownBudgetTag = "\u{0}own-budget"
    private static let noLimitTag = "\u{0}no-limit"

    var body: some View {
        Section("Token-based") {
            Picker(SessionMatchText.harnessLabel, selection: $settings.harness) {
                ForEach(Harness.allCases, id: \.self) { harness in
                    Text(harness.displayName).tag(harness)
                }
            }
            Picker("Budget", selection: budgetChoice) {
                Text("Own budget").tag(Self.ownBudgetTag)
                Text("No limit").tag(Self.noLimitTag)
                ForEach(draft.groups) { group in
                    pickerText(group.icon, name: group.name).tag(group.id)
                }
            }
            if settings.groupId != nil {
                Toggle("Show this account's share in the menu bar", isOn: memberShownInBar)
                Text("The share is this account's spend as a percent of the group budget. Thresholds and notifications belong to the budget group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // The optional session directory, read for session files only; a
        // harness change clears it in UsageCore (spec 034 FR-007, FR-008,
        // spec 037 FR-006). OpenCode data directories are global, so an
        // OpenCode account shows a caption instead (contracts/settings-ui.md).
        Section(AccountDirectoryText.usageSourceSection) {
            if settings.harness == .openCode {
                Text(AccountDirectoryText.tokenBasedCaption(for: .openCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LabeledContent(AccountDirectoryText.tokenBasedLabel(for: settings.harness)) {
                    TextField("", text: $settings.sessionDirectoryField, prompt: Text(AccountDirectoryText.tokenBasedPrompt(for: settings.harness)))
                        .labelsHidden()
                        .frame(width: 320)
                }
                Text(AccountDirectoryText.tokenBasedCaption(for: settings.harness))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Follows the harness; a harness change empties the list in
        // UsageCore (spec 035 FR-002, research R1). None for OpenCode.
        if settings.harness != .openCode {
            AdditionalSessionDirectoriesSection(harness: settings.harness, directories: $settings.additionalSessionDirectories)
        }
        // Which sessions count for records without the Claude Code
        // directory information: the kind, the optional condition, then the
        // notes and warnings (from the unsaved draft) as caption text inside
        // the group (spec 038 FR-012, FR-013, contracts/settings-ui.md).
        Section(SessionMatchText.sectionTitle) {
            // Keyed by account, so a condition remembered for one account
            // never fills in another's (spec 038 FR-014).
            SessionsFields(settings: $settings)
                .id(accountId)
            SectionNotes(lines: SessionMatchText.noteLines(kind: settings.sessionKind, condition: settings.condition,
                                                             overlap: draft.matchOverlap(forAccount: accountId),
                                                             directoryConflict: draft.directoryOnlyConflict(forAccount: accountId),
                                                             directory: settings.sessionDirectory,
                                                             sharedWith: draft.sharedClaudeCodeDirectory(forAccount: accountId)))
        }
        if let budget = settings.ownBudget {
            BudgetFields(budget: Binding(get: { budget }, set: { settings.membership = .ownBudget($0) }),
                         timeFormat: $timeFormat)
        }
        // Period, Value as and Times; no amount, thresholds or "Show in
        // menu bar" (spec 041 FR-017).
        if let noLimit = settings.noLimit {
            NoLimitFields(noLimit: Binding(get: { noLimit }, set: { settings.membership = .noLimit($0) }),
                          valueAs: $settings.valueAs, timeFormat: $timeFormat, prices: prices)
        }
    }

    /// A member's own shown-in-bar setting, off by default (spec 004 FR-016).
    private var memberShownInBar: Binding<Bool> {
        Binding(get: { settings.memberShownInBar },
                set: { shown in
                    if let groupId = settings.groupId {
                        settings.membership = .group(id: groupId, shownInBar: shown)
                    }
                })
    }

    private var budgetChoice: Binding<String> {
        Binding(get: { settings.groupId ?? (settings.noLimit != nil ? Self.noLimitTag : Self.ownBudgetTag) },
                set: { choice in
                    if choice == Self.ownBudgetTag {
                        draft = draft.movingAccountToOwnBudget(accountId: accountId)
                    } else if choice == Self.noLimitTag {
                        draft = draft.movingAccountToNoLimit(accountId: accountId)
                    } else {
                        draft = draft.movingAccountToGroup(accountId: accountId, groupId: choice)
                    }
                })
    }
}

/// The settings of one budget, shared by the group editor and the own-budget
/// editor (spec 004 FR-009, FR-010): period, amount with the period's label
/// and an error naming the period, shown in bar, and thresholds.
struct BudgetFields: View {
    @Binding var budget: BudgetSettings
    /// The owner's time format in the dropdown (spec 025 FR-021): the
    /// group's, or the account's for an own budget.
    @Binding var timeFormat: TimeFormat

    var body: some View {
        Section("Budget") {
            // Period next to the amount; labels follow it (spec 003 FR-014, FR-018).
            PeriodPicker(period: $budget.period)
            LabeledContent(budget.period.budgetLabel) {
                HStack(spacing: 4) {
                    // An amount of 0 reads as empty (spec 041 FR-018).
                    TextField("", value: $budget.enteredAmount, format: DecimalInputFormat(maxFractionDigits: 2))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("USD")
                }
            }
            if budget.budgetUSD <= 0 {
                Text("The \(budget.period.adjective) budget must be greater than 0.").foregroundStyle(.red).font(.caption)
            }
            Toggle("Show in menu bar", isOn: $budget.shownInBar)
            TimeFormatPicker(format: $timeFormat)
        }
        Section("Notifications") {
            ThresholdsEditor(thresholds: $budget.thresholds, limitDescription: "the \(budget.period.adjective) budget")
        }
    }
}

/// The settings of a No limit account (spec 041 FR-017): its period, the
/// "Value as" pop-up with its caption, and the "Times" picker.
struct NoLimitFields: View {
    @Binding var noLimit: NoLimitSettings
    @Binding var valueAs: String?
    @Binding var timeFormat: TimeFormat
    let prices: PriceTable

    var body: some View {
        Section("Budget") {
            PeriodPicker(period: $noLimit.period)
            LabeledContent("Value as") {
                ValueAsMenu(valueAs: $valueAs, options: ValueAsOptions.make(prices: prices, selected: valueAs))
            }
            Text("Shows what this account's tokens would have cost at this model's prices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TimeFormatPicker(format: $timeFormat)
        }
    }
}

/// The "Value as" pop-up (spec 041 FR-017, research R8): "None", the
/// built-in and manually priced models, a "More" submenu with the imported
/// ones, and a stored selection the lists do not hold, as stored or marked
/// "(no price)". A `Menu` rather than a `Picker`, since a picker cannot hold
/// a selectable submenu on macOS 14; the selection carries a checkmark.
struct ValueAsMenu: View {
    @Binding var valueAs: String?
    let options: ValueAsOptions

    private var title: String {
        if let missing = options.missing { return ValueAsOptions.missingLabel(missing) }
        return valueAs ?? "None"
    }

    private func item(_ label: String, model: String?) -> some View {
        Toggle(label, isOn: Binding(get: { valueAs == model }, set: { if $0 { valueAs = model } }))
    }

    var body: some View {
        Menu(title) {
            item("None", model: nil)
            Divider()
            ForEach(options.primary, id: \.self) { model in
                item(model, model: model)
            }
            if !options.more.isEmpty {
                Menu("More") {
                    ForEach(options.more, id: \.self) { model in
                        item(model, model: model)
                    }
                }
            }
            if let unlisted = options.unlisted {
                Divider()
                item(unlisted, model: unlisted)
            }
            if let missing = options.missing {
                Divider()
                item(ValueAsOptions.missingLabel(missing), model: missing)
            }
        }
        .fixedSize()
    }
}

/// Adding an account: a token-based account joins an existing group, gets
/// its own weekly or monthly budget, or has no limit (spec 004 FR-013, spec
/// 003 FR-018, spec 041 FR-016).
struct NewAccountSheet: View {
    /// The two entries of the Add menu. The platform of a subscription is
    /// chosen inside the sheet, as the harness and session kind of a token-based account are.
    enum Kind: String, Identifiable {
        case subscription
        case tokenBased

        var id: String { rawValue }
    }

    @Binding var draft: Configuration
    let kind: Kind
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Starts with the type's default icon (spec 004 FR-002).
    @State private var icon: String
    /// Set once the user picks an icon; until then a harness or kind change
    /// replaces the icon with the kind's default (contracts/settings-ui.md).
    @State private var iconChosen = false
    @State private var displayName = ""
    @State private var credentialDirectory = Paths.defaultClaudeDirectory
    @State private var codexHome = Paths.defaultCodexHome
    /// Harness, kind and condition of a new token-based account; its
    /// membership is set in `add()`. A harness change runs the same
    /// transitions as the account editor (spec 038 FR-016, research R10).
    @State private var sessions = TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 0)))
    @State private var platform: SubscriptionPlatform = .claude
    /// The chosen budget group's id, `ownBudgetTag` or `noLimitTag`. Groups
    /// are made in the Groups tab; the sheet only joins one (walkthrough
    /// feedback).
    @State private var budgetChoice = Self.ownBudgetTag
    /// Period and amount of a new own budget.
    @State private var newBudgetPeriod: BudgetPeriod = .weekly
    @State private var newBudgetAmount: Decimal = 60
    /// The settings of a new No limit account, apart from the own budget's
    /// period, so it starts weekly whatever the own budget had (spec 041
    /// FR-016).
    @State private var newNoLimit = NoLimitSettings()
    @State private var validationMessage: String?

    /// Picker tags of "Own budget" and "No limit"; group ids are UUIDs or
    /// hand-edited ids.
    private static let ownBudgetTag = "\u{0}own-budget"
    private static let noLimitTag = "\u{0}no-limit"

    init(draft: Binding<Configuration>, kind: Kind, onCreate: @escaping (String) -> Void) {
        _draft = draft
        self.kind = kind
        self.onCreate = onCreate
        let icon: String
        switch kind {
        case .subscription: icon = SubscriptionPlatform.claude.defaultIcon
        case .tokenBased: icon = SessionKind.default(for: .claudeCode).defaultIcon
        }
        _icon = State(initialValue: icon)
    }

    private var title: String {
        switch kind {
        case .subscription: return "New subscription account"
        case .tokenBased: return "New token-based account"
        }
    }

    private var namePrompt: String {
        switch kind {
        case .subscription: return platform.namePrompt
        case .tokenBased: return SessionMatchText.displayNamePrompt(kind: sessions.sessionKind)
        }
    }

    private var iconBinding: Binding<String> {
        Binding(get: { icon }, set: { icon = $0; iconChosen = true })
    }

    /// The id of the account being added, for the Directory only warning
    /// computed on the draft with that account in it (spec 038 FR-016).
    private static let candidateId = "\u{0}new-account"

    /// The shared directory warning of the account being added.
    private var directoryConflict: DirectoryOnlyConflict? {
        guard kind == .tokenBased else { return nil }
        var candidate = draft
        candidate.accounts.append(Account(id: Self.candidateId, displayName: "", kind: .tokenBased(sessions)))
        return candidate.directoryOnlyConflict(forAccount: Self.candidateId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                // The account itself, then which sessions count, then the
                // budget: the sections of the account editor (walkthrough
                // feedback).
                Section {
                    LabeledContent("Display name") {
                        TextField("", text: $displayName, prompt: Text(namePrompt))
                            .labelsHidden()
                    }
                    if kind == .subscription {
                        Picker("Platform", selection: $platform) {
                            ForEach(SubscriptionPlatform.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }
                    IconField(icon: iconBinding)
                    if kind == .subscription && platform == .claude {
                        // No token-based directory here: it is set in the
                        // account's "Usage source" section (spec 034 research R11).
                        LabeledContent(AccountDirectoryText.claudeCodeDirectoryLabel) {
                            TextField("", text: $credentialDirectory, prompt: Text(Paths.defaultClaudeDirectory))
                                .labelsHidden()
                        }
                    } else if kind == .subscription {
                        LabeledContent("Codex home") {
                            TextField("", text: $codexHome, prompt: Text(Paths.defaultCodexHome))
                                .labelsHidden()
                        }
                        Text("Shows the plan limits (such as 5-hour and weekly windows, depending on the plan) and the tokens used through the plan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if kind == .tokenBased {
                    Section(SessionMatchText.sectionTitle) {
                        // The harness binds the draft's own harness, so a change
                        // runs the same transitions as the account editor (spec
                        // 038 FR-016, contracts/settings-ui.md).
                        Picker(SessionMatchText.harnessLabel, selection: $sessions.harness) {
                            ForEach(Harness.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        // A Claude Code account gets its own directory in one step,
                        // the setup Directory only needs (plan review decision).
                        if sessions.harness == .claudeCode {
                            LabeledContent(AccountDirectoryText.claudeCodeDirectoryLabel) {
                                TextField("", text: $sessions.sessionDirectoryField,
                                          prompt: Text(AccountDirectoryText.tokenBasedPrompt(for: .claudeCode)))
                                    .labelsHidden()
                            }
                            Text(AccountDirectoryText.tokenBasedCaption(for: .claudeCode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // The same controls as the account editor; notes 1, 2 and
                        // 6 stay below them as captions (spec 038 FR-016).
                        SessionsFields(settings: $sessions,
                                       captions: SessionMatchText.sheetNoteLines(kind: sessions.sessionKind, condition: sessions.condition,
                                                                                 directoryConflict: directoryConflict))
                    }
                    Section("Budget") {
                        // One pop-up: an existing budget group, the
                        // account's own budget or No limit; new groups are
                        // made in the Groups tab (walkthrough feedback).
                        Picker("Budget", selection: $budgetChoice) {
                            ForEach(draft.groups) { group in
                                pickerText(group.icon, name: group.name).tag(group.id)
                            }
                            Text("Own budget").tag(Self.ownBudgetTag)
                            // Appended after the existing choices (spec 041 FR-016).
                            Text("No limit").tag(Self.noLimitTag)
                        }
                        if budgetChoice == Self.ownBudgetTag {
                            budgetAmountFields
                        } else if budgetChoice == Self.noLimitTag {
                            PeriodPicker(period: $newNoLimit.period)
                        }
                        Text(budgetCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // The sheet is as tall as its sections, without empty space
            // below them.
            .fixedSize(horizontal: false, vertical: true)
            .formStyle(.grouped)
            .textFieldStyle(.roundedBorder)
            if let validationMessage {
                Text(validationMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        // Wide enough for the Condition row on one line (spec 038 FR-015).
        .frame(width: 560)
        .onAppear {
            budgetChoice = draft.groups.first?.id ?? Self.ownBudgetTag
        }
        .onChange(of: sessions.sessionKind) { _, newKind in
            // The icon follows the kind until the user picks one
            // (contracts/settings-ui.md).
            if !iconChosen && kind == .tokenBased {
                icon = newKind.defaultIcon
            }
        }
        .onChange(of: platform) { _, newPlatform in
            if !iconChosen && kind == .subscription {
                icon = newPlatform.defaultIcon
            }
        }
    }

    /// The caption below the budget pop-up (spec 041 contracts/ui-strings.md).
    private var budgetCaption: String {
        switch budgetChoice {
        case Self.ownBudgetTag:
            return "Shown in the menu bar, with notifications at 80% and 100%. To share a budget with other accounts, create a budget group in the Groups tab first."
        case Self.noLimitTag:
            return "Counts tokens without a limit. Not shown in the menu bar."
        default:
            return "To share a budget with other accounts, create a budget group in the Groups tab first."
        }
    }

    @ViewBuilder
    private var budgetAmountFields: some View {
        PeriodPicker(period: $newBudgetPeriod)
        LabeledContent(newBudgetPeriod.budgetLabel) {
            HStack(spacing: 4) {
                TextField("", value: $newBudgetAmount, format: DecimalInputFormat(maxFractionDigits: 2))
                    .labelsHidden()
                    .frame(width: 90)
                Text("USD")
            }
        }
    }

    private func add() {
        var candidate = draft
        let id = UUID().uuidString
        let defaultName: String
        switch kind {
        case .subscription: defaultName = platform.subscriptionName
        case .tokenBased: defaultName = SessionMatchText.displayNamePrompt(kind: sessions.sessionKind)
        }
        let name = displayName.isEmpty ? defaultName : displayName
        if kind == .subscription && platform == .claude {
            candidate.accounts.append(Account(id: id, icon: icon, displayName: name,
                                              kind: .subscription(SubscriptionSettings(credentialDirectory: credentialDirectory, shownInBar: true, thresholds: [80, 100]))))
        } else if kind == .subscription {
            candidate.accounts.append(Account(id: id, icon: icon, displayName: name,
                                              kind: .codexSubscription(CodexSubscriptionSettings(codexHome: codexHome))))
        } else {
            // An own budget starts weekly or monthly as chosen, shown in bar,
            // with thresholds 80% and 100%; a member's share starts hidden
            // (spec 004 FR-013). No limit starts weekly unless changed under
            // No limit, with no Value as model and relative times (spec 041
            // FR-016).
            let membership: TokenMembership
            switch budgetChoice {
            case Self.ownBudgetTag:
                membership = .ownBudget(BudgetSettings(period: newBudgetPeriod, budgetUSD: newBudgetAmount, shownInBar: true, thresholds: [80, 100]))
            case Self.noLimitTag:
                membership = .noLimit(newNoLimit)
            default:
                membership = .group(id: budgetChoice, shownInBar: false)
            }
            var settings = sessions
            settings.membership = membership
            candidate.accounts.append(Account(id: id, icon: icon, displayName: name, kind: .tokenBased(settings)))
        }
        do {
            // Also refuses an invalid pattern or a blank text (spec 038 FR-008, FR-016).
            try candidate.validateForSaving()
            draft = candidate
            onCreate(id)
            dismiss()
        } catch let error as ConfigurationError {
            validationMessage = error.message
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

// MARK: - Groups tab

struct GroupSettingsView: View {
    @Binding var draft: Configuration
    @State private var selection: String?
    /// The group whose removal sheet is shown (spec 009 FR-008).
    @State private var removing: BudgetGroup?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                List(draft.groups, selection: $selection) { group in
                    HStack {
                        labelText(group.icon).bold().frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(group.name)
                            // Same amount style as the Accounts list (spec 018 FR-004).
                            Text(GroupListSubtitle.text(group: group, memberCount: draft.members(of: group.id).count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(group.id)
                }
                HStack {
                    // Appends a group with the defaults and selects it; the
                    // arrangement places it last (spec 009 FR-007).
                    Button("Add") {
                        let id = UUID().uuidString
                        draft = draft.addingGroup(id: id)
                        selection = id
                    }
                    .frame(width: 90)
                    Button("Remove…") { removing = selectedGroup }
                        .disabled(selectedGroup == nil)
                }
                Text("Add and remove groups here. A group stays when its last account leaves; membership is set in each account's Budget picker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 220, maxWidth: 280)

            Group {
                if let selection, let index = draft.groups.firstIndex(where: { $0.id == selection }) {
                    GroupEditor(group: $draft.groups[index], members: draft.members(of: selection))
                } else {
                    Text("Select a group or add one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
        .sheet(item: $removing) { group in
            RemoveGroupSheet(group: group, members: draft.members(of: group.id),
                             otherGroups: draft.groups.filter { $0.id != group.id }) { destination in
                // Undo goes through the Settings flow like any edit (FR-012).
                draft = draft.removingGroup(id: group.id, destination: destination)
                selection = nil
            }
        }
    }

    private var selectedGroup: BudgetGroup? {
        selection.flatMap { draft.group(id: $0) }
    }
}

/// Confirms the removal of a group (spec 009 FR-008 to FR-010,
/// contracts/groups-tab.md): a plain confirmation for an empty group; for a
/// group with members, their names and one destination for all of them,
/// "Own budgets" or another group in Groups tab order. Cancel changes nothing.
struct RemoveGroupSheet: View {
    let group: BudgetGroup
    let members: [Account]
    let otherGroups: [BudgetGroup]
    let onRemove: (GroupRemovalDestination) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destination: GroupRemovalDestination = .ownBudgets

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove \"\(group.name)\"?").font(.headline)
            if members.isEmpty {
                Text("The group has no accounts. You can undo this with ⌘Z.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Its accounts:")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(members) { member in
                        HStack {
                            labelText(member.icon)
                            Text(member.displayName)
                        }
                    }
                }
                .padding(.leading, 12)
                // With no other group only "Own budgets" is offered (FR-010).
                Picker("Move its accounts to", selection: $destination) {
                    Text("Own budgets").tag(GroupRemovalDestination.ownBudgets)
                    ForEach(otherGroups) { other in
                        Text(other.name).tag(GroupRemovalDestination.group(id: other.id))
                    }
                }
                Text(destinationNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Remove", role: .destructive) {
                    onRemove(destination)
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    private var destinationNote: String {
        switch destination {
        case .ownBudgets:
            return "Each account gets its own budget with this group's period, amount, thresholds and menu bar setting. You can undo this with ⌘Z."
        case .group:
            return "The accounts join that group, their shares hidden from the menu bar. You can undo this with ⌘Z."
        }
    }
}

struct GroupEditor: View {
    @Binding var group: BudgetGroup
    let members: [Account]

    var body: some View {
        Form {
            Section("Budget group") {
                LabeledContent("Name") {
                    TextField("", text: $group.name, prompt: Text("Vertex"))
                        .labelsHidden()
                        .frame(width: 240)
                }
                IconField(icon: $group.icon)
            }
            BudgetFields(budget: $group.budget, timeFormat: $group.timeFormat)
            // Membership is set in each account's Budget picker; the editor
            // only lists it (spec 009 FR-013).
            Section("Members") {
                if members.isEmpty {
                    Text("No accounts in this group yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(members) { member in
                    HStack {
                        labelText(member.icon)
                        Text(member.displayName)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// How the section's reset and run-out times read in the dropdown, as a
/// segmented control labeled "Times" (spec 025 FR-021, clarification).
/// Bound to the Settings draft like every other setting.
struct TimeFormatPicker: View {
    @Binding var format: TimeFormat

    var body: some View {
        Picker("Times", selection: $format) {
            Text("Relative").tag(TimeFormat.relative)
            Text("Absolute").tag(TimeFormat.absolute)
        }
        .pickerStyle(.segmented)
        // Like PeriodPicker: a fixed size made the segmented control's ideal
        // width the form's minimum, which widened the form past the detail
        // pane and cropped it on both sides.
        .frame(maxWidth: 240)
    }
}

/// Weekly or monthly, as a segmented control (spec 003 FR-018).
struct PeriodPicker: View {
    @Binding var period: BudgetPeriod

    var body: some View {
        Picker("Period", selection: $period) {
            ForEach(BudgetPeriod.allCases, id: \.self) { period in
                Text(period.adjective.capitalized).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }
}

/// The platform of a subscription account, chosen in the new-account sheet:
/// a Claude plan used through Claude Code, or a ChatGPT plan used through
/// Codex (spec 006 FR-017).
enum SubscriptionPlatform: CaseIterable {
    case claude
    case chatgpt

    var displayName: String {
        switch self {
        case .claude: return "Claude (Claude Code)"
        case .chatgpt: return "ChatGPT (Codex)"
        }
    }

    /// Default display name and list subtitle.
    var subscriptionName: String {
        switch self {
        case .claude: return "Claude subscription"
        case .chatgpt: return "ChatGPT subscription"
        }
    }

    var namePrompt: String {
        switch self {
        case .claude: return "Claude Max"
        case .chatgpt: return "ChatGPT Plus"
        }
    }

    var defaultIcon: String {
        switch self {
        case .claude: return IconDefaults.subscription
        case .chatgpt: return IconDefaults.openai
        }
    }
}

/// The "Additional session directories" section of an account, below its
/// main directory; texts follow the account's session harness (spec 035
/// FR-002).
struct AdditionalSessionDirectoriesSection: View {
    let harness: Harness
    @Binding var directories: [String]

    var body: some View {
        DirectoryListSection(title: AccountDirectoryText.additionalDirectoriesSection,
                             caption: AccountDirectoryText.additionalDirectoriesCaption(for: harness),
                             prompt: AccountDirectoryText.additionalDirectoriesPrompt(for: harness),
                             harness: harness,
                             directories: $directories)
    }
}

/// The controls of a "Which sessions count" section (spec 038 FR-012,
/// FR-014, FR-016, contracts/settings-ui.md): the Sessions pop-up, or for
/// Codex the sentence that replaces it; the "Only when" checkbox when the
/// kind offers an optional condition; and the Condition row when the
/// condition is on or required. Shared by the account editor, which shows
/// the notes below inside the section, and the new account sheet, which
/// passes its notes as `captions`. All transitions live in UsageCore
/// (`TokenBasedSettings.choosingKind`, `settingConditionOn`, the `harness`
/// didSet); the view only remembers the last condition, so unticking and
/// ticking again, or Directory only and back, brings it back. Callers give
/// the view the account's id as its identity, so a remembered condition
/// never carries over to another account.
struct SessionsFields: View {
    @Binding var settings: TokenBasedSettings
    /// The notes of the new account sheet; empty in the account editor.
    var captions: [SessionMatchText.NoteLine] = []
    @State private var lastCondition: MatchCondition?

    private var kind: Binding<SessionKind> {
        Binding(get: { settings.sessionKind },
                set: { settings = settings.choosingKind($0, remembered: lastCondition) })
    }

    private var conditionOn: Binding<Bool> {
        Binding(get: { settings.condition != nil },
                set: { settings = settings.settingConditionOn($0, remembered: lastCondition) })
    }

    var body: some View {
        Group {
            if settings.sessionKind.showsPopUp {
                LabeledContent(SessionMatchText.sessionsLabel) {
                    StableWidthPicker(label: SessionMatchText.sessionsLabel, selection: kind,
                                      items: SessionKind.kinds(for: settings.harness), sizingItems: SessionKind.kinds(for: settings.harness),
                                      title: SessionMatchText.kindItem)
                }
            } else {
                Text(SessionMatchText.codexSentence)
            }
            if settings.sessionKind.offersCondition && !settings.sessionKind.requiresCondition {
                Toggle(SessionMatchText.onlyWhenLabel, isOn: conditionOn)
                    .toggleStyle(.checkbox)
            }
            if settings.effectiveCondition != nil || settings.sessionKind.requiresCondition {
                // The label sits above the controls everywhere, so the row
                // looks the same in the editor and the wider sheet
                // (walkthrough feedback).
                VStack(alignment: .leading, spacing: 6) {
                    Text(SessionMatchText.conditionLabel)
                    ConditionControls(harness: settings.harness, condition: $settings.conditionForEditing)
                }
            }
            if !captions.isEmpty {
                SectionNotes(lines: captions)
            }
        }
        // Every condition that is replaced or turned off is remembered, so
        // the next tick or kind brings it back (FR-014).
        .onChange(of: settings.condition) { old, _ in
            if let old { lastCondition = old }
        }
    }
}

/// The controls of the Condition row: field pop-up, operator pop-up and
/// text field, read like a Mail rule. The pop-ups are bordered and as wide
/// as their widest item, so a choice never moves anything; the text field
/// takes the rest of the row. The layout is one fixed line, never measured,
/// so it cannot flip back and forth while a window sizes itself to its
/// content (spec 038 FR-015, walkthrough feedback). Field changes go through
/// `MatchCondition.withField`, operator changes replace only the operator
/// (FR-014).
struct ConditionControls: View {
    let harness: Harness
    @Binding var condition: MatchCondition

    private var field: Binding<MatchField> {
        Binding(get: { condition.field }, set: { condition = condition.withField($0) })
    }

    private var op: Binding<MatchOperator> {
        Binding(get: {
            MatchOperator.operators(for: condition.field).contains(condition.operator) ? condition.operator : .default(for: condition.field)
        }, set: { condition.operator = $0 })
    }

    private var text: Binding<String> {
        Binding(get: { condition.text }, set: { condition.text = $0 })
    }

    var body: some View {
        HStack(spacing: 8) {
            fieldPicker
            operatorPicker
            textField
                .frame(maxWidth: .infinity)
        }
    }

    private var fieldPicker: some View {
        BorderedPopUp(label: SessionMatchText.fieldLabel, selection: field,
                      items: MatchField.fields(for: harness), title: SessionMatchText.fieldLabel(for:))
            .fixedSize()
    }

    // The widest operator, "matches regex", is offered for every field, so
    // the width stays when Anywhere offers fewer operators.
    private var operatorPicker: some View {
        BorderedPopUp(label: SessionMatchText.operatorLabel, selection: op,
                      items: MatchOperator.operators(for: field.wrappedValue), title: SessionMatchText.operatorLabel(for:))
            .fixedSize()
    }

    private var textField: some View {
        TextField(SessionMatchText.textLabel, text: text,
                  prompt: Text(SessionMatchText.textPrompt(field: field.wrappedValue, operator: op.wrappedValue)))
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .accessibilityLabel(SessionMatchText.textLabel)
    }
}

/// The notes of a "Which sessions count" or "Session matching (advanced)"
/// section, inside the group below its controls as System Settings shows
/// explanations: caption size, secondary color, leading aligned; warnings
/// with their warning symbol (spec 038 FR-013, FR-018). Empty when there is
/// nothing to say.
struct SectionNotes: View {
    let lines: [SessionMatchText.NoteLine]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.isWarning {
                        Label(line.text, systemImage: "exclamationmark.triangle")
                    } else {
                        Text(line.text)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A pop-up whose width is that of its widest item in `sizingItems`, not of
/// the selected one: hidden copies, each showing one item, size a ZStack,
/// and the visible pop-up fills it. Widths come from the system's own
/// rendering, never from a fixed number (spec 038 FR-015).
struct StableWidthPicker<Item: Hashable>: View {
    let label: String
    @Binding var selection: Item
    let items: [Item]
    let sizingItems: [Item]
    let title: (Item) -> String
    /// Where the visible pop-up sits in its slot: trailing for a row's
    /// only control, so its arrow lines up with the form's other pop-ups;
    /// leading in the Condition row, which reads left to right like a
    /// sentence (walkthrough feedback).
    var alignment: Alignment = .trailing

    var body: some View {
        // The hidden copies only size the slot; a grouped form draws
        // pop-ups without a bezel, so the visible one keeps its natural
        // width and sits at `alignment` in the slot.
        ZStack {
            ForEach(sizingItems, id: \.self) { item in
                picker(selection: .constant(item), items: [item])
                    .fixedSize()
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .fixedSize()
        .overlay(alignment: alignment) {
            picker(selection: $selection, items: items)
                .fixedSize()
                .accessibilityLabel(label)
        }
    }

    private func picker(selection: Binding<Item>, items: [Item]) -> some View {
        Picker(label, selection: selection) {
            ForEach(items, id: \.self) { item in
                Text(title(item)).tag(item)
            }
        }
        .labelsHidden()
    }
}

/// A bordered AppKit pop-up button, which is always as wide as its widest
/// item, so choosing another item never moves the controls next to it. A
/// grouped SwiftUI form draws its own pop-ups without a bezel, where the
/// width follows the selected text (spec 038 FR-015, walkthrough feedback).
struct BorderedPopUp<Item: Hashable>: NSViewRepresentable {
    let label: String
    @Binding var selection: Item
    let items: [Item]
    let title: (Item) -> String

    func makeCoordinator() -> PopUpTarget { PopUpTarget() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(PopUpTarget.changed(_:))
        button.setAccessibilityLabel(label)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let items = items
        let binding = $selection
        context.coordinator.onSelect = { index in
            if items.indices.contains(index) { binding.wrappedValue = items[index] }
        }
        let titles = items.map(title)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if let index = items.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }
}

/// The target of a `BorderedPopUp`: hands the chosen index to the binding.
final class PopUpTarget: NSObject {
    var onSelect: (Int) -> Void = { _ in }

    @objc func changed(_ sender: NSPopUpButton) {
        onSelect(sender.indexOfSelectedItem)
    }
}
