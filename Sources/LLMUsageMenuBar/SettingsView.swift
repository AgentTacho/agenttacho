import SwiftUI
import UsageCore

/// Settings window: edits a draft `Configuration` and saves it through the
/// store's validator (FR-031). Validation messages appear inline.
struct SettingsView: View {
    let model: AppModel

    @State private var draft: Configuration
    @State private var errorMessage: String?
    @State private var savedAt: Date?

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.configuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralSettingsTab(draft: $draft)
                    .tabItem { Label("General", systemImage: "gear") }
                AccountSettingsView(draft: $draft)
                    .tabItem { Label("Accounts", systemImage: "person.2") }
                GroupSettingsView(draft: $draft)
                    .tabItem { Label("Groups", systemImage: "dollarsign.circle") }
                PriceSettingsTab(draft: $draft, builtIn: model.builtInPrices)
                    .tabItem { Label("Prices", systemImage: "tag") }
            }
            .padding()

            Divider()
            HStack {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let savedAt {
                    Text("Saved \(savedAt.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button("Revert") {
                    draft = model.configuration
                    errorMessage = nil
                }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private func save() {
        do {
            // A group left without members (its last account moved to another
            // group) is deleted on save, like on account removal (FR-019).
            let pruned = draft.pruningEmptyGroups()
            try model.saveConfiguration(pruned)
            draft = pruned
            errorMessage = nil
            savedAt = Date()
        } catch let error as ConfigurationError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @Binding var draft: Configuration
    @State private var newDirectory = ""

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        Form {
            Section("Refresh") {
                HStack {
                    TextField("Refresh interval (seconds)", value: $draft.refreshIntervalSeconds, format: .number)
                        .frame(width: 320)
                    if draft.refreshIntervalSeconds < Configuration.minimumRefreshIntervalSeconds {
                        Text("minimum is \(Configuration.minimumRefreshIntervalSeconds) seconds")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            Section("Weekly window") {
                Picker("Align with subscription account", selection: alignmentBinding) {
                    Text("First subscription account").tag("")
                    ForEach(draft.subscriptionAccounts) { account in
                        Text("\(account.label)  \(account.displayName)").tag(account.id)
                    }
                }
                Picker("Fallback weekday", selection: $draft.weekFallback.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Self.weekdayNames[day - 1]).tag(day)
                    }
                }
                Stepper("Fallback hour: \(String(format: "%02d:00", draft.weekFallback.hour))", value: $draft.weekFallback.hour, in: 0...23)
                Text("Used while no 7-day reset has been fetched from the provider since launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Launch") {
                Toggle("Start at login", isOn: $draft.startAtLogin)
            }

            Section("Additional Claude Code directories") {
                Text("~/.claude is always scanned. Add profile directories that have their own projects tree.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(draft.logDirectories.enumerated()), id: \.offset) { index, dir in
                    HStack {
                        Text(dir).monospaced()
                        Spacer()
                        Button("Remove") { draft.logDirectories.remove(at: index) }
                    }
                }
                HStack {
                    TextField("~/.local/share/cc-deck/profiles/work/claude", text: $newDirectory)
                    Button("Add") {
                        let trimmed = newDirectory.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !draft.logDirectories.contains(trimmed) else { return }
                        draft.logDirectories.append(trimmed)
                        newDirectory = ""
                    }
                    .disabled(newDirectory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var alignmentBinding: Binding<String> {
        Binding(get: { draft.alignmentAccountId ?? "" },
                set: { draft.alignmentAccountId = $0.isEmpty ? nil : $0 })
    }
}

// MARK: - Prices

struct PriceSettingsTab: View {
    @Binding var draft: Configuration
    let builtIn: PriceTable
    @State private var newModel = ""

    private var merged: PriceTable { builtIn.merging(overrides: draft.priceOverrides) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("USD per million tokens. Overrides replace the built-in entry for the same model; add a model to price one that is reported as unpriced.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("Model").gridColumnAlignment(.leading)
                        Text("Input")
                        Text("Output")
                        Text("Cache 5m")
                        Text("Cache 1h")
                        Text("Cache read")
                        Text("")
                    }
                    .font(.caption.bold())
                    Divider()
                    ForEach(merged.entries) { entry in
                        if let index = draft.priceOverrides.firstIndex(where: { PriceTable.canonicalModel($0.model) == entry.model }) {
                            OverrideRow(entry: $draft.priceOverrides[index]) {
                                draft.priceOverrides.remove(at: index)
                            }
                        } else {
                            BuiltInRow(entry: entry) {
                                var copy = entry
                                copy.source = .override
                                draft.priceOverrides.append(copy)
                            }
                        }
                    }
                }
                .font(.callout)
            }
            HStack {
                TextField("claude-new-model", text: $newModel)
                Button("Add model") {
                    let model = PriceTable.canonicalModel(newModel.trimmingCharacters(in: .whitespaces))
                    guard !model.isEmpty, !draft.priceOverrides.contains(where: { $0.model == model }) else { return }
                    draft.priceOverrides.append(PriceEntry(model: model, inputPerMTok: 0, outputPerMTok: 0, cacheWrite5mPerMTok: 0, cacheWrite1hPerMTok: 0, cacheReadPerMTok: 0))
                    newModel = ""
                }
                .disabled(newModel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct BuiltInRow: View {
    let entry: PriceEntry
    let override: () -> Void

    var body: some View {
        GridRow {
            Text(entry.model).monospaced().gridColumnAlignment(.leading)
            Text(entry.inputPerMTok.formatted())
            Text(entry.outputPerMTok.formatted())
            Text(entry.cacheWrite5mPerMTok.formatted())
            Text(entry.cacheWrite1hPerMTok.formatted())
            Text(entry.cacheReadPerMTok.formatted())
            Button("Override", action: override).controlSize(.small)
        }
        .foregroundStyle(.secondary)
    }
}

private struct OverrideRow: View {
    @Binding var entry: PriceEntry
    let remove: () -> Void

    var body: some View {
        GridRow {
            Text(entry.model).monospaced().bold().gridColumnAlignment(.leading)
            DecimalField(value: $entry.inputPerMTok)
            DecimalField(value: $entry.outputPerMTok)
            DecimalField(value: $entry.cacheWrite5mPerMTok)
            DecimalField(value: $entry.cacheWrite1hPerMTok)
            DecimalField(value: $entry.cacheReadPerMTok)
            Button("Remove", action: remove).controlSize(.small)
        }
    }
}

struct DecimalField: View {
    @Binding var value: Decimal

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(0...4)))
            .multilineTextAlignment(.trailing)
            .frame(width: 70)
    }
}

/// Comma-separated whole-number percents (FR-027).
struct ThresholdsField: View {
    @Binding var thresholds: [Int]
    @State private var text: String = ""

    var body: some View {
        TextField("80, 100", text: $text)
            .onAppear { text = thresholds.map(String.init).joined(separator: ", ") }
            .onChange(of: text) { _, newValue in
                thresholds = newValue.split(whereSeparator: { $0 == "," || $0 == " " })
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            }
    }
}
