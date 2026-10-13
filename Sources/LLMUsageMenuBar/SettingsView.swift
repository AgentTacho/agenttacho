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
            // Bordered fields: in grouped forms the default style draws
            // text fields without any frame, so they were hard to spot.
            .textFieldStyle(.roundedBorder)
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
                        pickerText(account.shownLabel, name: account.displayName).tag(account.id)
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

/// Label editor in two rows: a short text label and an optional Font
/// Awesome icon. When both are set, the icon is shown in the menu bar and
/// the dropdown.
struct LabelEditor: View {
    @Binding var label: String
    @Binding var icon: String?
    var title = "Label"

    @State private var choosing = false

    private var entry: IconEntry? {
        icon.flatMap { IconCatalog.shared.icon(for: $0) }
    }

    var body: some View {
        LabeledContent("\(title) text") {
            TextField("", text: $label, prompt: Text("1 to \(Configuration.maxLabelLength) characters"))
                .labelsHidden()
                .frame(width: 140)
        }
        LabeledContent("\(title) icon") {
            HStack(spacing: 8) {
                if let entry {
                    IconGlyph(entry: entry, size: 16)
                    Text(entry.label).foregroundStyle(.secondary)
                } else if let icon, !icon.isEmpty {
                    Text("unknown icon \(icon)").foregroundStyle(.red)
                } else {
                    Text("none").foregroundStyle(.secondary)
                }
                Button("Choose…") { choosing = true }
                if icon != nil {
                    Button("Remove") { icon = nil }
                }
            }
        }
        .sheet(isPresented: $choosing) {
            IconPickerSheet(selection: $icon)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Shown in the menu bar and the dropdown. When an icon is chosen, it is shown instead of the text.")
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var problem: String? {
        let hasIcon = !(icon ?? "").isEmpty
        if label.count > Configuration.maxLabelLength {
            return "The text can have at most \(Configuration.maxLabelLength) characters."
        }
        if label.isEmpty && !hasIcon {
            return "Enter 1 to \(Configuration.maxLabelLength) characters or choose an icon."
        }
        return nil
    }
}

/// Two notification thresholds as separate whole-number fields (FR-027).
/// Bound straight to the entity, so switching the selection in the list
/// always shows the selected entity's values. Further thresholds from a
/// hand-edited config file are kept as they are.
struct ThresholdsEditor: View {
    @Binding var thresholds: [Int]
    /// What 100% means for this entity, used in the explanation.
    let limitDescription: String

    var body: some View {
        LabeledContent("First notification at") {
            percentField(index: 0, placeholder: "80")
        }
        LabeledContent("Second notification at") {
            percentField(index: 1, placeholder: "100")
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("macOS notifies you once each time usage rises past one of these percentages of \(limitDescription). Leave a field empty to turn it off.")
            Text("The lower value also marks the entry with ⚠ in the menu bar (80% when both are empty). At 100% it is marked with ‼.")
            if invalid {
                Text("Use whole numbers greater than 0.").foregroundStyle(.red)
            }
            if thresholds.count > 2 {
                Text("Also active from the configuration file: \(thresholds.dropFirst(2).map { "\($0)%" }.joined(separator: ", ")).")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var invalid: Bool {
        thresholds.contains { $0 <= 0 }
    }

    private func percentField(index: Int, placeholder: String) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value(at: index), format: .number.grouping(.never), prompt: Text(placeholder))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text("%")
        }
    }

    /// Reads and writes slot 0 or 1; an empty field removes that slot.
    private func value(at index: Int) -> Binding<Int?> {
        Binding(
            get: { index < thresholds.count ? thresholds[index] : nil },
            set: { newValue in
                var first: Int? = thresholds.count > 0 ? thresholds[0] : nil
                var second: Int? = thresholds.count > 1 ? thresholds[1] : nil
                let rest = Array(thresholds.dropFirst(2))
                if index == 0 { first = newValue } else { second = newValue }
                thresholds = [first, second].compactMap { $0 } + rest
            })
    }
}
