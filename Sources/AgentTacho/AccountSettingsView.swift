import SwiftUI
import UsageCore

// MARK: - Accounts tab

struct AccountSettingsView: View {
    @Binding var draft: Configuration
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
                    AccountEditor(account: $draft.accounts[index], draft: $draft)
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
    /// name (spec 018 FR-006); a token-based account names its provider and
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
        case .tokenBased(let settings): return settings.provider.displayName
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
    /// its own budget and groups (spec 004 FR-014).
    @Binding var draft: Configuration

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
                                 accountId: account.id, draft: $draft, timeFormat: $account.timeFormat)
            case .codexSubscription(let settings):
                CodexSubscriptionEditor(settings: Binding(get: { settings }, set: { account.kind = .codexSubscription($0) }),
                                        timeFormat: $account.timeFormat)
            }
            Section("Session matching (advanced)") {
                LabeledContent("Custom marker") {
                    TextField("", text: markerBinding, prompt: Text("optional"))
                        .labelsHidden()
                        .frame(width: 240)
                }
                Text("""
                Leave this empty in most cases. Usage is assigned to accounts automatically: requests that went through \
                Vertex (from Claude Code or OpenCode) count for the Vertex account, direct Anthropic requests from Claude Code \
                for the subscription, Codex API-key sessions and OpenCode on OpenAI for the OpenAI account, and Codex \
                ChatGPT-plan sessions for the Codex subscription.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("""
                Use a marker only to tell apart two accounts of the same kind, for example two Vertex projects. \
                Enter text that appears only in this account's session records, such as a project path or a host name. \
                When it is set, only sessions containing this text count for this account.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            LabeledContent("Credential directory") {
                TextField("", text: $settings.credentialDirectory, prompt: Text("~/.claude"))
                    .labelsHidden()
                    .frame(width: 320)
            }
            Text("The Claude Code configuration directory whose login this account uses: ~/.claude, or a profile directory such as ~/.local/share/cc-deck/profiles/private/claude. Use the directory you run Claude Code with, so its login stays fresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show in menu bar", isOn: $settings.shownInBar)
            TimeFormatPicker(format: $timeFormat)
        }
        Section("Notifications") {
            ThresholdsEditor(thresholds: $settings.thresholds,
                             limitDescription: "the 5-hour or the 7-day limit (each is checked on its own)")
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
            LabeledContent("Codex home") {
                TextField("", text: $settings.codexHome, prompt: Text(Paths.defaultCodexHome))
                    .labelsHidden()
                    .frame(width: 320)
            }
            Text("The Codex home whose sessions ran with this ChatGPT plan login. It only matters when you have more than one Codex subscription account.")
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
        Section("Notifications") {
            ThresholdsEditor(thresholds: $settings.thresholds,
                             limitDescription: "every plan window (each is checked on its own)")
        }
    }
}

/// Provider and budget of a token-based account. The budget picker offers
/// "Own budget" first, then every group by icon and name; switching goes
/// through the Configuration move helpers (spec 004 FR-013, FR-014).
struct TokenBasedEditor: View {
    @Binding var settings: TokenBasedSettings
    let accountId: String
    @Binding var draft: Configuration
    /// The account's time format, offered only with its own budget: a
    /// member's section is the group's (spec 025 FR-021).
    @Binding var timeFormat: TimeFormat

    /// Picker tag of "Own budget"; group ids are UUIDs or hand-edited ids.
    private static let ownBudgetTag = "\u{0}own-budget"

    var body: some View {
        Section("Token-based") {
            Picker("Provider", selection: $settings.provider) {
                ForEach(Provider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            Picker("Budget", selection: budgetChoice) {
                Text("Own budget").tag(Self.ownBudgetTag)
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
        if let budget = settings.ownBudget {
            BudgetFields(budget: Binding(get: { budget }, set: { settings.membership = .ownBudget($0) }),
                         timeFormat: $timeFormat)
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
        Binding(get: { settings.groupId ?? Self.ownBudgetTag },
                set: { choice in
                    if choice == Self.ownBudgetTag {
                        draft = draft.movingAccountToOwnBudget(accountId: accountId)
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
                    TextField("", value: $budget.budgetUSD, format: .number)
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

/// Adding an account: a token-based account joins an existing group, creates
/// a new group, or gets its own budget, each with a weekly or monthly budget
/// (spec 004 FR-013, spec 003 FR-018).
struct NewAccountSheet: View {
    /// The two entries of the Add menu. The platform of a subscription is
    /// chosen inside the sheet, as the provider of a token-based account is.
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
    /// Set once the user picks an icon; until then a provider change
    /// replaces the icon with that provider's default.
    @State private var iconChosen = false
    @State private var displayName = ""
    @State private var credentialDirectory = Paths.defaultClaudeDirectory
    @State private var codexHome = Paths.defaultCodexHome
    @State private var provider: Provider = .vertex
    @State private var platform: SubscriptionPlatform = .claude
    @State private var budgetChoice: BudgetChoice = .newGroup
    @State private var groupChoice = ""          // existing group id
    @State private var newGroupName = ""
    @State private var newGroupIcon = IconDefaults.group
    /// Period and amount of a new group or a new own budget.
    @State private var newBudgetPeriod: BudgetPeriod = .weekly
    @State private var newBudgetAmount: Decimal = 60
    @State private var validationMessage: String?

    enum BudgetChoice: Hashable {
        case existingGroup
        case newGroup
        case ownBudget
    }

    init(draft: Binding<Configuration>, kind: Kind, onCreate: @escaping (String) -> Void) {
        _draft = draft
        self.kind = kind
        self.onCreate = onCreate
        let icon: String
        switch kind {
        case .subscription: icon = SubscriptionPlatform.claude.defaultIcon
        case .tokenBased: icon = IconDefaults.defaultIcon(for: .vertex)
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
        case .tokenBased: return provider.defaultAccountName
        }
    }

    private var iconBinding: Binding<String> {
        Binding(get: { icon }, set: { icon = $0; iconChosen = true })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
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
                    LabeledContent("Credential directory") {
                        TextField("", text: $credentialDirectory, prompt: Text("~/.claude"))
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
                } else {
                    Picker("Provider", selection: $provider) {
                        ForEach(Provider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Budget", selection: $budgetChoice) {
                        if !draft.groups.isEmpty {
                            Text("Existing group").tag(BudgetChoice.existingGroup)
                        }
                        Text("New group").tag(BudgetChoice.newGroup)
                        Text("Own budget").tag(BudgetChoice.ownBudget)
                    }
                    .pickerStyle(.segmented)
                    switch budgetChoice {
                    case .existingGroup:
                        Picker("Budget group", selection: $groupChoice) {
                            ForEach(draft.groups) { group in
                                pickerText(group.icon, name: group.name).tag(group.id)
                            }
                        }
                    case .newGroup:
                        LabeledContent("Group name") {
                            TextField("", text: $newGroupName, prompt: Text("Vertex"))
                                .labelsHidden()
                        }
                        IconField(icon: $newGroupIcon, title: "Group icon")
                        budgetAmountFields
                    case .ownBudget:
                        budgetAmountFields
                        Text("Shown in the menu bar, with notifications at 80% and 100%. You can change this after adding the account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
        .frame(width: 440)
        .onAppear {
            groupChoice = draft.groups.first?.id ?? ""
            budgetChoice = draft.groups.isEmpty ? .newGroup : .existingGroup
        }
        .onChange(of: provider) { _, newProvider in
            if !iconChosen && kind == .tokenBased {
                icon = IconDefaults.defaultIcon(for: newProvider)
            }
        }
        .onChange(of: platform) { _, newPlatform in
            if !iconChosen && kind == .subscription {
                icon = newPlatform.defaultIcon
            }
        }
    }

    @ViewBuilder
    private var budgetAmountFields: some View {
        PeriodPicker(period: $newBudgetPeriod)
        LabeledContent(newBudgetPeriod.budgetLabel) {
            HStack(spacing: 4) {
                TextField("", value: $newBudgetAmount, format: .number)
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
        case .tokenBased: defaultName = provider.defaultAccountName
        }
        let name = displayName.isEmpty ? defaultName : displayName
        if kind == .subscription && platform == .claude {
            candidate.accounts.append(Account(id: id, icon: icon, displayName: name,
                                              kind: .subscription(SubscriptionSettings(credentialDirectory: credentialDirectory, shownInBar: true, thresholds: [80, 100]))))
        } else if kind == .subscription {
            candidate.accounts.append(Account(id: id, icon: icon, displayName: name, harness: .codex,
                                              kind: .codexSubscription(CodexSubscriptionSettings(codexHome: codexHome))))
        } else {
            // New groups and own budgets start weekly or monthly as chosen,
            // shown in bar, with thresholds 80% and 100%; a member's share
            // starts hidden (spec 004 FR-013).
            let membership: TokenMembership
            switch budgetChoice {
            case .existingGroup:
                membership = .group(id: groupChoice, shownInBar: false)
            case .newGroup:
                let groupId = UUID().uuidString
                candidate.groups.append(BudgetGroup(id: groupId,
                                                    name: newGroupName.isEmpty ? "Budget group" : newGroupName,
                                                    icon: newGroupIcon, period: newBudgetPeriod, budgetUSD: newBudgetAmount, shownInBar: true, thresholds: [80, 100]))
                membership = .group(id: groupId, shownInBar: false)
            case .ownBudget:
                membership = .ownBudget(BudgetSettings(period: newBudgetPeriod, budgetUSD: newBudgetAmount, shownInBar: true, thresholds: [80, 100]))
            }
            candidate.accounts.append(Account(id: id, icon: icon, displayName: name,
                                              kind: .tokenBased(TokenBasedSettings(membership: membership, provider: provider))))
        }
        do {
            try candidate.validate()
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
