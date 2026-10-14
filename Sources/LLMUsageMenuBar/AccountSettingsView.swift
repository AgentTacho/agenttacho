import SwiftUI
import UsageCore

// MARK: - Accounts tab

struct AccountSettingsView: View {
    @Binding var draft: Configuration
    @State private var selection: String?
    @State private var showingNewAccount = false
    @State private var newAccountSubscription = true
    @State private var confirmingRemoval = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                List(draft.accounts, selection: $selection) { account in
                    HStack {
                        labelText(account.icon).bold().frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(account.displayName)
                            Text(account.kind.isSubscription ? "subscription" : "token-based (\(account.kind.tokenBased?.provider.rawValue ?? ""))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(account.id)
                }
                HStack {
                    Menu("Add") {
                        Button("Subscription account") {
                            newAccountSubscription = true
                            showingNewAccount = true
                        }
                        Button("Token-based account") {
                            newAccountSubscription = false
                            showingNewAccount = true
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
        .sheet(isPresented: $showingNewAccount) {
            NewAccountSheet(draft: $draft, isSubscription: newAccountSubscription) { id in
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

    private var selectedAccount: Account? {
        selection.flatMap { id in draft.accounts.first { $0.id == id } }
    }

    private var removalTitle: String {
        "Remove \(selectedAccount?.displayName ?? "account")?"
    }

    /// Mentions the group that disappears with its last member (FR-019).
    private var removalMessage: String {
        guard let account = selectedAccount else { return "" }
        if let groupId = account.kind.tokenBased?.groupId,
           draft.members(of: groupId).count == 1,
           let group = draft.groups.first(where: { $0.id == groupId }) {
            return "This also removes the budget group \"\(group.name)\", which has no other members. You can undo this with ⌘Z."
        }
        return "Its usage is no longer shown. You can undo this with ⌘Z."
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
                SubscriptionEditor(settings: Binding(get: { settings }, set: { account.kind = .subscription($0) }))
            case .tokenBased(let settings):
                TokenBasedEditor(settings: Binding(get: { settings }, set: { account.kind = .tokenBased($0) }),
                                 accountId: account.id, draft: $draft)
            }
            Section("Session matching (advanced)") {
                LabeledContent("Custom marker") {
                    TextField("", text: markerBinding, prompt: Text("optional"))
                        .labelsHidden()
                        .frame(width: 240)
                }
                Text("""
                Leave this empty in most cases. Usage from the session logs is assigned to accounts automatically: \
                requests that went through Vertex count for the Vertex account, direct Anthropic requests for the subscription.
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
        }
        Section("Notifications") {
            ThresholdsEditor(thresholds: $settings.thresholds,
                             limitDescription: "the 5-hour or the 7-day limit (each is checked on its own)")
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

    /// Picker tag of "Own budget"; group ids are UUIDs or hand-edited ids.
    private static let ownBudgetTag = "\u{0}own-budget"

    var body: some View {
        Section("Token-based") {
            Picker("Provider", selection: $settings.provider) {
                ForEach(Provider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
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
            BudgetFields(budget: Binding(get: { budget }, set: { settings.membership = .ownBudget($0) }))
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
    @Binding var draft: Configuration
    let isSubscription: Bool
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Starts with the type's default icon (spec 004 FR-002).
    @State private var icon: String
    /// Set once the user picks an icon; until then a provider change
    /// replaces the icon with that provider's default.
    @State private var iconChosen = false
    @State private var displayName = ""
    @State private var credentialDirectory = Paths.defaultClaudeDirectory
    @State private var provider: Provider = .vertex
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

    init(draft: Binding<Configuration>, isSubscription: Bool, onCreate: @escaping (String) -> Void) {
        _draft = draft
        self.isSubscription = isSubscription
        self.onCreate = onCreate
        _icon = State(initialValue: isSubscription ? IconDefaults.subscription : IconDefaults.defaultIcon(for: .vertex))
    }

    private var iconBinding: Binding<String> {
        Binding(get: { icon }, set: { icon = $0; iconChosen = true })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isSubscription ? "New subscription account" : "New token-based account").font(.headline)
            Form {
                LabeledContent("Display name") {
                    TextField("", text: $displayName, prompt: Text(isSubscription ? "Claude Max" : "Claude Code via Vertex"))
                        .labelsHidden()
                }
                IconField(icon: iconBinding)
                if isSubscription {
                    LabeledContent("Credential directory") {
                        TextField("", text: $credentialDirectory, prompt: Text("~/.claude"))
                            .labelsHidden()
                    }
                } else {
                    Picker("Provider", selection: $provider) {
                        ForEach(Provider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
            if !iconChosen && !isSubscription {
                icon = IconDefaults.defaultIcon(for: newProvider)
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
        let name = displayName.isEmpty ? (isSubscription ? "Claude subscription" : "Claude Code via \(provider.rawValue.capitalized)") : displayName
        if isSubscription {
            candidate.accounts.append(Account(id: id, icon: icon, displayName: name,
                                              kind: .subscription(SubscriptionSettings(credentialDirectory: credentialDirectory, shownInBar: true, thresholds: [80, 100]))))
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

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                List(draft.groups, selection: $selection) { group in
                    HStack {
                        labelText(group.icon).bold().frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(group.name)
                            Text("\(UsageFormat.usd(group.budgetUSD)) \(group.period.perUnit), \(draft.members(of: group.id).count) member(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(group.id)
                }
                Text("Groups are created with their first token-based account and removed with their last one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 220, maxWidth: 280)

            Group {
                if let selection, let index = draft.groups.firstIndex(where: { $0.id == selection }) {
                    GroupEditor(group: $draft.groups[index], members: draft.members(of: selection))
                } else {
                    Text("Select a group.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
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
            BudgetFields(budget: $group.budget)
            Section("Members") {
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
