import SwiftUI
import UsageCore

/// Settings window, following Apple's guidelines for macOS settings:
/// toolbar panes, the window title names the pane, the last pane is
/// restored, and changes take effect as they are made. There are no Save,
/// Cancel or Revert buttons.
///
/// Edits go to a draft. After a short pause the draft is validated through
/// the store's validator (FR-031) and written when it is valid. An invalid
/// draft is not applied; the reason is shown at the bottom of the window
/// until the input is fixed. Each applied change can be undone with ⌘Z.
struct SettingsView: View {
    let model: AppModel

    @State private var draft: Configuration
    /// The configuration last written (or loaded), the baseline for undo.
    @State private var applied: Configuration
    @State private var problem: String?
    @State private var pendingApply: Task<Void, Never>?
    /// Set while an undo restores the draft, so that applying the restored
    /// draft does not register a new undo step.
    @State private var restoringUndo = false
    @AppStorage("settingsPane") private var pane = "general"
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.configuration)
        _applied = State(initialValue: model.configuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pane) {
                GeneralSettingsTab(draft: $draft)
                    .tabItem { Label("General", systemImage: "gear") }
                    .tag("general")
                AccountSettingsView(draft: $draft)
                    .padding(20)
                    .tabItem { Label("Accounts", systemImage: "person.2") }
                    .tag("accounts")
                GroupSettingsView(draft: $draft)
                    .padding(20)
                    .tabItem { Label("Groups", systemImage: "dollarsign.circle") }
                    .tag("groups")
                PriceSettingsTab(draft: $draft, builtIn: model.builtInPrices)
                    .padding(20)
                    .tabItem { Label("Prices", systemImage: "tag") }
                    .tag("prices")
            }
            // Bordered fields: in grouped forms the default style draws
            // text fields without any frame, so they were hard to spot.
            .textFieldStyle(.roundedBorder)

            if let problem {
                Divider()
                Label("Not applied: \(problem)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 720, height: 560)
        .onChange(of: draft) { _, _ in scheduleApply() }
        .onChange(of: model.configuration) { _, newValue in
            // A hand edit of config.json reloaded by the app: take it over
            // when there is no unapplied edit in the window.
            if draft == applied, newValue != applied {
                applied = newValue
                draft = newValue
            }
        }
        .onDisappear { applyNow() }
    }

    /// Applies after a short pause so typing does not write on every key.
    private func scheduleApply() {
        pendingApply?.cancel()
        pendingApply = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            applyNow()
        }
    }

    private func applyNow() {
        pendingApply?.cancel()
        // A group left without members (its last account moved to another
        // group) is deleted, like on account removal (FR-019).
        let candidate = draft.pruningEmptyGroups()
        guard candidate != applied else {
            problem = nil
            restoringUndo = false
            return
        }
        do {
            try model.saveConfiguration(candidate)
            let previous = applied
            applied = candidate
            if candidate != draft { draft = candidate }
            problem = nil
            if restoringUndo {
                restoringUndo = false
            } else {
                registerUndo(restoring: previous)
            }
        } catch let error as ConfigurationError {
            problem = error.message
        } catch {
            problem = error.localizedDescription
        }
    }

    private func registerUndo(restoring previous: Configuration) {
        guard let undoManager else { return }
        let draftBinding = $draft
        let restoring = $restoringUndo
        undoManager.registerUndo(withTarget: model) { _ in
            restoring.wrappedValue = true
            draftBinding.wrappedValue = previous
        }
        undoManager.setActionName("Settings Change")
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
                LabeledContent("Refresh interval") {
                    HStack(spacing: 4) {
                        TextField("", value: $draft.refreshIntervalSeconds, format: .number.grouping(.never),
                                  prompt: Text("\(Configuration.defaultRefreshIntervalSeconds)"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("seconds")
                    }
                }
                if draft.refreshIntervalSeconds < Configuration.minimumRefreshIntervalSeconds {
                    Text("The minimum is \(Configuration.minimumRefreshIntervalSeconds) seconds.")
                        .foregroundStyle(.red)
                        .font(.caption)
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
                        Text(dir)
                        Spacer()
                        Button("Remove") { draft.logDirectories.remove(at: index) }
                    }
                }
                LabeledContent("Add directory") {
                    HStack(spacing: 6) {
                    TextField("", text: $newDirectory, prompt: Text("~/.local/share/cc-deck/profiles/work/claude"))
                        .labelsHidden()
                        .frame(width: 320)
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
                TextField("", text: $newModel, prompt: Text("claude-new-model"))
                    .labelsHidden()
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
