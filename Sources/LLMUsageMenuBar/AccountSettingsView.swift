import SwiftUI
import UsageCore

// MARK: - Accounts tab

struct AccountSettingsView: View {
    @Binding var draft: Configuration
    @State private var selection: String?
    @State private var showingNewAccount = false
    @State private var newAccountSubscription = true

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                List(draft.accounts, selection: $selection) { account in
                    HStack {
                        Text(account.label).monospaced().bold().frame(width: 36, alignment: .leading)
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
                    Button("Remove") {
                        if let selection {
                            draft = draft.removingAccount(id: selection)
                            self.selection = nil
                        }
                    }
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
    }
}

struct AccountEditor: View {
    @Binding var account: Account
    let groups: [BudgetGroup]

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    TextField("Label (1 to 3 characters)", text: $account.label)
                    if account.label.isEmpty || account.label.count > Configuration.maxLabelLength {
                        Text("1 to \(Configuration.maxLabelLength) characters").foregroundStyle(.red).font(.caption)
                    }
                }
                TextField("Display name", text: $account.displayName)
                TextField("Custom marker (substring of the session record, optional)", text: markerBinding)
                    .monospaced()
            }
            switch account.kind {
            case .subscription(let settings):
                SubscriptionEditor(settings: Binding(get: { settings }, set: { account.kind = .subscription($0) }))
            case .tokenBased(let settings):
                TokenBasedEditor(settings: Binding(get: { settings }, set: { account.kind = .tokenBased($0) }), groups: groups)
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
            TextField("Credential directory (Claude Code config directory)", text: $settings.credentialDirectory)
                .monospaced()
            Toggle("Show in menu bar", isOn: $settings.shownInBar)
            LabeledContent("Notification thresholds (%)") {
                ThresholdsField(thresholds: $settings.thresholds)
            }
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
                    Text("\(group.label)  \(group.name)").tag(group.id)
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
    @State private var displayName = ""
    @State private var credentialDirectory = Paths.defaultClaudeDirectory
    @State private var provider: Provider = .vertex
    @State private var groupChoice = ""          // existing group id, or "" for a new group
    @State private var newGroupName = ""
    @State private var newGroupLabel = ""
    @State private var newGroupBudget: Decimal = 60
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isSubscription ? "New subscription account" : "New token-based account").font(.headline)
            Form {
                TextField("Label (1 to 3 characters)", text: $label)
                TextField("Display name", text: $displayName)
                if isSubscription {
                    TextField("Credential directory", text: $credentialDirectory).monospaced()
                } else {
                    Picker("Provider", selection: $provider) {
                        ForEach(Provider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Budget group", selection: $groupChoice) {
                        ForEach(draft.groups) { group in
                            Text("\(group.label)  \(group.name)").tag(group.id)
                        }
                        Text("New group…").tag("")
                    }
                    if groupChoice.isEmpty {
                        TextField("Group name", text: $newGroupName)
                        TextField("Group label (1 to 3 characters)", text: $newGroupLabel)
                        TextField("Weekly budget (USD)", value: $newGroupBudget, format: .number)
                    }
                }
            }
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
        let name = displayName.isEmpty ? label : displayName
        if isSubscription {
            candidate.accounts.append(Account(id: id, label: label, displayName: name,
                                              kind: .subscription(SubscriptionSettings(credentialDirectory: credentialDirectory, shownInBar: true, thresholds: [80, 100]))))
        } else {
            var groupId = groupChoice
            if groupId.isEmpty {
                groupId = UUID().uuidString
                candidate.groups.append(BudgetGroup(id: groupId, name: newGroupName.isEmpty ? newGroupLabel : newGroupName,
                                                    label: newGroupLabel, weeklyBudgetUSD: newGroupBudget, shownInBar: true, thresholds: [80, 100]))
            }
            candidate.accounts.append(Account(id: id, label: label, displayName: name,
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
                        Text(group.label).monospaced().bold().frame(width: 36, alignment: .leading)
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
                TextField("Name", text: $group.name)
                HStack {
                    TextField("Label (1 to 3 characters)", text: $group.label)
                    if group.label.isEmpty || group.label.count > Configuration.maxLabelLength {
                        Text("1 to \(Configuration.maxLabelLength) characters").foregroundStyle(.red).font(.caption)
                    }
                }
                HStack {
                    TextField("Weekly budget (USD)", value: $group.weeklyBudgetUSD, format: .number)
                    if group.weeklyBudgetUSD <= 0 {
                        Text("must be greater than 0").foregroundStyle(.red).font(.caption)
                    }
                }
                Toggle("Show in menu bar", isOn: $group.shownInBar)
                LabeledContent("Notification thresholds (%)") {
                    ThresholdsField(thresholds: $group.thresholds)
                }
            }
            Section("Members") {
                ForEach(members) { member in
                    HStack {
                        Text(member.label).monospaced()
                        Text(member.displayName)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
