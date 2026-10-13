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
                        labelText(account.shownLabel).bold().frame(width: 36, alignment: .leading)
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
                    AccountEditor(account: $draft.accounts[index], groups: draft.groups)
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
    let groups: [BudgetGroup]

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Display name") {
                    TextField("", text: $account.displayName, prompt: Text("Claude Max"))
                        .labelsHidden()
                        .frame(width: 240)
                }
                LabelEditor(label: $account.label, icon: $account.icon)
            }
            switch account.kind {
            case .subscription(let settings):
                SubscriptionEditor(settings: Binding(get: { settings }, set: { account.kind = .subscription($0) }))
            case .tokenBased(let settings):
                TokenBasedEditor(settings: Binding(get: { settings }, set: { account.kind = .tokenBased($0) }), groups: groups)
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

struct TokenBasedEditor: View {
    @Binding var settings: TokenBasedSettings
    let groups: [BudgetGroup]

    var body: some View {
        Section("Token-based") {
            Picker("Provider", selection: $settings.provider) {
                ForEach(Provider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            Picker("Budget group", selection: $settings.groupId) {
                ForEach(groups) { group in
                    pickerText(group.shownLabel, name: group.name).tag(group.id)
                }
            }
            Text("Shown-in-bar and thresholds belong to the budget group.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Adding an account: a token-based account must pick an existing group or
/// create a new one with a weekly budget (FR-019).
struct NewAccountSheet: View {
    @Binding var draft: Configuration
    let isSubscription: Bool
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var icon: String?
    @State private var displayName = ""
    @State private var credentialDirectory = Paths.defaultClaudeDirectory
    @State private var provider: Provider = .vertex
    @State private var groupChoice = ""          // existing group id, or "" for a new group
    @State private var newGroupName = ""
    @State private var newGroupLabel = ""
    @State private var newGroupIcon: String?
    @State private var newGroupBudget: Decimal = 60
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isSubscription ? "New subscription account" : "New token-based account").font(.headline)
            Form {
                LabeledContent("Display name") {
                    TextField("", text: $displayName, prompt: Text(isSubscription ? "Claude Max" : "Claude Code via Vertex"))
                        .labelsHidden()
                }
                LabelEditor(label: $label, icon: $icon)
                if isSubscription {
                    LabeledContent("Credential directory") {
                        TextField("", text: $credentialDirectory, prompt: Text("~/.claude"))
                            .labelsHidden()
                    }
                } else {
                    Picker("Provider", selection: $provider) {
                        ForEach(Provider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Budget group", selection: $groupChoice) {
                        ForEach(draft.groups) { group in
                            pickerText(group.shownLabel, name: group.name).tag(group.id)
                        }
                        Text("New group…").tag("")
                    }
                    if groupChoice.isEmpty {
                        LabeledContent("Group name") {
                            TextField("", text: $newGroupName, prompt: Text("Vertex weekly"))
                                .labelsHidden()
                        }
                        LabelEditor(label: $newGroupLabel, icon: $newGroupIcon, title: "Group label")
                        LabeledContent("Weekly budget") {
                            HStack(spacing: 4) {
                                TextField("", value: $newGroupBudget, format: .number)
                                    .labelsHidden()
                                    .frame(width: 90)
                                Text("USD")
                            }
                        }
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
        }
    }

    private func add() {
        var candidate = draft
        let id = UUID().uuidString
        let name = displayName.isEmpty ? LabelContent(text: label, icon: icon).plain : displayName
        if isSubscription {
            candidate.accounts.append(Account(id: id, label: label, icon: icon, displayName: name,
                                              kind: .subscription(SubscriptionSettings(credentialDirectory: credentialDirectory, shownInBar: true, thresholds: [80, 100]))))
        } else {
            var groupId = groupChoice
            if groupId.isEmpty {
                groupId = UUID().uuidString
                candidate.groups.append(BudgetGroup(id: groupId,
                                                    name: newGroupName.isEmpty ? LabelContent(text: newGroupLabel, icon: newGroupIcon).plain : newGroupName,
                                                    label: newGroupLabel, icon: newGroupIcon, weeklyBudgetUSD: newGroupBudget, shownInBar: true, thresholds: [80, 100]))
            }
            candidate.accounts.append(Account(id: id, label: label, icon: icon, displayName: name,
                                              kind: .tokenBased(TokenBasedSettings(groupId: groupId, provider: provider))))
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
                        labelText(group.shownLabel).bold().frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(group.name)
                            Text("\(UsageFormat.usd(group.weeklyBudgetUSD)) per week, \(draft.members(of: group.id).count) member(s)")
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
                    TextField("", text: $group.name, prompt: Text("Vertex weekly"))
                        .labelsHidden()
                        .frame(width: 240)
                }
                LabelEditor(label: $group.label, icon: $group.icon)
                LabeledContent("Weekly budget") {
                    HStack(spacing: 4) {
                        TextField("", value: $group.weeklyBudgetUSD, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("USD")
                    }
                }
                if group.weeklyBudgetUSD <= 0 {
                    Text("The weekly budget must be greater than 0.").foregroundStyle(.red).font(.caption)
                }
                Toggle("Show in menu bar", isOn: $group.shownInBar)
            }
            Section("Notifications") {
                ThresholdsEditor(thresholds: $group.thresholds, limitDescription: "the weekly budget")
            }
            Section("Members") {
                ForEach(members) { member in
                    HStack {
                        labelText(member.shownLabel)
                        Text(member.displayName)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
