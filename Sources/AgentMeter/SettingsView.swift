import AppKit
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
    /// The configuration the last undo restored (exactly what was applied
    /// before the undone change), set until the next apply. It is the state
    /// the user sees: the placement rules judge the draft against it, not
    /// against the undone state, and an edit made on top of it within the
    /// debounce can be undone back to it. Applying it unchanged registers
    /// no new undo step (spec 008 FR-014, research R3).
    @State private var undoTarget: Configuration?
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
                // Second, directly after General (spec 008 FR-009).
                MenuBarSettingsTab(draft: $draft, model: model)
                    .padding(20)
                    .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                    .tag("menubar")
                AccountSettingsView(draft: $draft)
                    .padding(20)
                    .tabItem { Label("Accounts", systemImage: "person.2") }
                    .tag("accounts")
                GroupSettingsView(draft: $draft)
                    .padding(20)
                    .tabItem { Label("Groups", systemImage: "dollarsign.circle") }
                    .tag("groups")
                PriceSettingsTab(draft: $draft, model: model)
                    .padding(20)
                    .tabItem { Label("Prices", systemImage: "tag") }
                    .tag("prices")
                // Last: release data and links, nothing to edit.
                AboutSettingsTab()
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag("about")
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
                // The reloaded file is now what the user sees.
                undoTarget = nil
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
        // group) is deleted, like on account removal (FR-019). The placement
        // rules of the arrangement then compare the candidate with the state
        // the user last saw (spec 008 FR-004a to FR-008, FR-014).
        let candidate = draft.settingsCandidate(applied: applied, undoTarget: undoTarget)
        // What the user saw before this edit: an undo's target until it is
        // applied, otherwise the last applied configuration.
        let shown = undoTarget ?? applied
        guard candidate != applied else {
            // Nothing to write. An undo edited straight back to the applied
            // state still gets its undo step back to what the user saw.
            if candidate != shown { registerUndo(restoring: shown) }
            // A reorder back to the default order stores nothing (spec 008
            // FR-004a): drop the draft's copy of that order, so the draft
            // matches what is applied again. Other differences stay.
            var withoutOrder = draft
            withoutOrder.arrangement = candidate.arrangement
            if draft != candidate, withoutOrder == candidate { draft = candidate }
            problem = nil
            undoTarget = nil
            return
        }
        do {
            try model.saveConfiguration(candidate)
            applied = candidate
            undoTarget = nil
            if candidate != draft { draft = candidate }
            problem = nil
            // Applying an undo as it is registers nothing; any other change
            // can be undone back to what the user saw before it.
            if candidate != shown {
                registerUndo(restoring: shown)
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
        let target = $undoTarget
        undoManager.registerUndo(withTarget: model) { _ in
            target.wrappedValue = previous
            draftBinding.wrappedValue = previous
        }
        undoManager.setActionName("Settings Change")
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @Binding var draft: Configuration

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    // The version is on the About tab.
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
                        pickerText(account.icon, name: account.displayName).tag(account.id)
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
                // Spec 003 FR-020: visible regardless of group periods.
                Text("Applies to weekly budget groups and the Unassigned entry. Monthly groups always run from the 1st to the end of the month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Launch") {
                Toggle("Start at login", isOn: $draft.startAtLogin)
            }

            DirectoryListSection(title: "Additional Claude Code directories",
                                 caption: "~/.claude is always scanned. Add profile directories that have their own projects tree.",
                                 prompt: "~/.local/share/cc-deck/profiles/work/claude",
                                 directories: $draft.logDirectories)
            // Extra harness locations (spec 006 FR-003).
            DirectoryListSection(title: "Additional Codex homes",
                                 caption: "\(Paths.defaultCodexHome) is always read. Add other Codex homes whose sessions folder should count too.",
                                 prompt: "~/.codex-work",
                                 directories: $draft.codexHomes)
            DirectoryListSection(title: "Additional OpenCode data directories",
                                 caption: "\(Paths.defaultOpenCodeDirectory) is always read. Add other OpenCode data directories that hold an opencode.db.",
                                 prompt: "~/.local/share/opencode-work",
                                 directories: $draft.openCodeDirectories)
        }
        .formStyle(.grouped)
    }

    private var alignmentBinding: Binding<String> {
        Binding(get: { draft.alignmentAccountId ?? "" },
                set: { draft.alignmentAccountId = $0.isEmpty ? nil : $0 })
    }
}

/// A list of extra directories with add and remove, for the Claude Code
/// directories and the harness locations (spec 006 FR-003).
struct DirectoryListSection: View {
    let title: String
    let caption: String
    let prompt: String
    @Binding var directories: [String]
    @State private var newDirectory = ""

    var body: some View {
        Section(title) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(directories.enumerated()), id: \.offset) { index, dir in
                HStack {
                    Text(dir)
                    Spacer()
                    Button("Remove") { directories.remove(at: index) }
                }
            }
            LabeledContent("Add directory") {
                HStack(spacing: 6) {
                    TextField("", text: $newDirectory, prompt: Text(prompt))
                        .labelsHidden()
                        .frame(width: 320)
                    Button("Add") {
                        let trimmed = newDirectory.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !directories.contains(trimmed) else { return }
                        directories.append(trimmed)
                        newDirectory = ""
                    }
                    .disabled(newDirectory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Prices

struct PriceSettingsTab: View {
    @Binding var draft: Configuration
    let model: AppModel
    @State private var newModel = ""
    @State private var importRequest: PriceImportRequest?
    /// The import whose removal waits for confirmation (FR-023).
    @State private var pendingRemoval: ImportKind?
    @State private var alertMessage: String?
    /// "used" (default) or "all", remembered across launches (FR-030).
    @AppStorage("priceFilter") private var filter = "used"

    /// The layered table: manual overrides, CSV import, provider imports,
    /// built-in prices (FR-001).
    private var merged: PriceTable { model.effectivePrices(overrides: draft.priceOverrides) }

    /// Rows shown under the current filter. "Used in this window" shows the
    /// rows that a used model id resolves to plus every manual override, and
    /// all rows before the first snapshot (FR-030, research R9).
    private var visibleEntries: [PriceEntry] {
        let table = merged
        guard filter == "used", let used = model.usedModels else { return table.entries }
        let overridden = Set(draft.priceOverrides.map { PriceTable.canonicalModel($0.model) })
        let shown = table.resolvedModels(for: used).union(overridden)
        return table.entries.filter { shown.contains($0.model) }
    }

    /// Stored imports in menu order.
    private var batches: [PriceBatch] {
        ImportKind.allCases.compactMap { model.importedPrices.batch(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("USD per million tokens. Imported prices replace built-in ones; manual overrides win over both. Add a model to price one that is reported as unpriced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                importMenu
            }
            Picker("Show", selection: $filter) {
                Text("Used in this window").tag("used")
                Text("All").tag("all")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            ScrollView {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("Model").gridColumnAlignment(.leading)
                        Text("Input")
                        Text("Output")
                        Text("Cache 5m")
                        Text("Cache 1h")
                        Text("Cache read")
                        Text("Source").gridColumnAlignment(.leading)
                        Text("")
                    }
                    .font(.caption.bold())
                    Divider()
                    ForEach(visibleEntries) { entry in
                        if let index = draft.priceOverrides.firstIndex(where: { PriceTable.canonicalModel($0.model) == entry.model }) {
                            OverrideRow(entry: $draft.priceOverrides[index]) {
                                draft.priceOverrides.remove(at: index)
                            }
                        } else {
                            // Built-in and imported rows: Override copies the
                            // entry into the manual overrides (FR-032).
                            ReadOnlyPriceRow(entry: entry) {
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
                    let model = PriceTable.canonicalModel(newModel.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .whitespaces)
                    // The CSV import's id rule, so that an export of the table
                    // re-imports without skipped rows (SC-005).
                    guard PriceTable.isAcceptableImportedModelId(model, allowingSpaces: true),
                          !draft.priceOverrides.contains(where: { $0.model == model }) else { return }
                    draft.priceOverrides.append(PriceEntry(model: model, inputPerMTok: 0, outputPerMTok: 0, cacheWrite5mPerMTok: 0, cacheWrite1hPerMTok: 0, cacheReadPerMTok: 0))
                    newModel = ""
                }
                .disabled(!PriceTable.isAcceptableImportedModelId(
                    PriceTable.canonicalModel(newModel.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .whitespaces),
                    allowingSpaces: true))
            }
            statusLines
        }
        .sheet(item: $importRequest) { request in
            PriceImportSheet(model: model, request: request)
        }
        .confirmationDialog(pendingRemoval.map { "Remove \($0.displayName) prices?" } ?? "",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            presenting: pendingRemoval) { kind in
            Button("Remove", role: .destructive) { remove(kind) }
            Button("Cancel", role: .cancel) {}
        } message: { kind in
            Text("\(model.removalImpact(kind, overrides: draft.priceOverrides).removed.count) models fall back to another price or become unpriced.")
        }
        .alert("Prices", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    /// One line per stored import with its age, and the notice for an
    /// unreadable imported prices file (FR-027, FR-031).
    @ViewBuilder
    private var statusLines: some View {
        if !batches.isEmpty || model.importedPricesNotice != nil {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(batches, id: \.kind) { batch in
                    Text(PriceFormat.status(batch))
                }
                if let notice = model.importedPricesNotice {
                    Text(notice).foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Import menu (FR-028, contracts/prices-tab-ui.md). Provider imports
    /// fetch only from here (FR-034).
    private var importMenu: some View {
        Menu("Import") {
            Button("Anthropic prices (LiteLLM)") { importRequest = PriceImportRequest(kind: .provider(.anthropic), overrides: draft.priceOverrides) }
            Button("OpenAI prices (LiteLLM, direct and Vertex)") { importRequest = PriceImportRequest(kind: .provider(.openai), overrides: draft.priceOverrides) }
            Button("Google Gemini prices (LiteLLM)") { importRequest = PriceImportRequest(kind: .provider(.gemini), overrides: draft.priceOverrides) }
            Divider()
            Button("From CSV file…") { chooseCSVFile() }
            Button("Export current prices as CSV…") { exportCSV() }
            if !batches.isEmpty {
                Divider()
                ForEach(batches, id: \.kind) { batch in
                    Button("Remove \(batch.kind.displayName) prices (imported \(PriceFormat.date(batch.importedAt)))") {
                        pendingRemoval = batch.kind
                    }
                }
            }
        }
        .fixedSize()
    }

    /// Opens a CSV file and shows its preview, or the reason it could not be
    /// read (FR-024).
    private func chooseCSVFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a CSV file with model, input and output columns."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let result = Result { try model.previewCSVImport(url: url, overrides: draft.priceOverrides) }
        importRequest = PriceImportRequest(kind: .csv(result), overrides: draft.priceOverrides)
    }

    /// Saves the effective table as CSV (FR-019); a write failure shows its
    /// reason (FR-024).
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "prices.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportPrices(to: url, overrides: draft.priceOverrides)
        } catch {
            alertMessage = "The prices could not be exported: \(error.localizedDescription)"
        }
    }

    private func remove(_ kind: ImportKind) {
        do {
            try model.removeImport(kind, overrides: draft.priceOverrides)
        } catch {
            alertMessage = String(describing: error)
        }
    }
}

private struct ReadOnlyPriceRow: View {
    let entry: PriceEntry
    let override: () -> Void

    var body: some View {
        GridRow {
            Text(entry.model).monospaced().gridColumnAlignment(.leading)
            Text(PriceFormat.value(entry.inputPerMTok))
            Text(PriceFormat.value(entry.outputPerMTok))
            Text(PriceFormat.value(entry.cacheWrite5mPerMTok))
            Text(PriceFormat.value(entry.cacheWrite1hPerMTok))
            Text(PriceFormat.value(entry.cacheReadPerMTok))
            Text(PriceFormat.source(entry.source)).lineLimit(1).gridColumnAlignment(.leading)
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
            Text(PriceFormat.source(.override)).gridColumnAlignment(.leading)
            Button("Remove", action: remove).controlSize(.small)
        }
    }
}

struct DecimalField: View {
    @Binding var value: Decimal

    var body: some View {
        // Up to 6 decimals, like imported prices (FR-008), so that overriding
        // an imported row keeps its exact value.
        TextField("", value: $value, format: .number.precision(.fractionLength(0...6)))
            .multilineTextAlignment(.trailing)
            .frame(width: 70)
    }
}

/// Icon field: the current glyph with its catalog name and a "Choose…"
/// button that opens the picker. There is no text field and no remove
/// button, so an entry always keeps exactly one icon (spec 004 FR-001,
/// FR-002, FR-004).
struct IconField: View {
    @Binding var icon: String
    var title = "Icon"

    @State private var choosing = false

    private var entry: IconEntry? {
        IconCatalog.shared.icon(for: icon)
    }

    /// The picker works with an optional selection; a nil from it is ignored
    /// so the icon can never be cleared.
    private var selection: Binding<String?> {
        Binding(get: { icon }, set: { if let newValue = $0, !newValue.isEmpty { icon = newValue } })
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if let entry {
                    IconGlyph(entry: entry, size: 16)
                    Text(entry.label).foregroundStyle(.secondary)
                } else {
                    Text("unknown icon \(icon)").foregroundStyle(.red)
                }
                Button("Choose…") { choosing = true }
            }
        }
        .sheet(isPresented: $choosing) {
            IconPickerSheet(selection: selection)
        }
        Text("Shown in the menu bar and the dropdown. Several entries may share an icon.")
            .font(.caption)
            .foregroundStyle(.secondary)
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
