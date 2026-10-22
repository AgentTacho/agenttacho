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
                LogSettingsTab(model: model)
                    .padding(20)
                    .tabItem { Label("Log", systemImage: "doc.text.magnifyingglass") }
                    .tag("log")
                // Last: release data, links and the update check.
                AboutSettingsTab(updater: model.updater)
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag("about")
            }
            // Bordered fields: in grouped forms the default style draws
            // text fields without any frame, so they were hard to spot.
            .textFieldStyle(.roundedBorder)
            // The thresholds editors read in the draft's direction and
            // redraw when it changes (spec 030 FR-015).
            .environment(\.displayDirection, draft.displayDirection)

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
            } else if newValue != applied {
                // A headline window clicked in the dropdown while edits are
                // pending: carry it into every state the window keeps, so
                // it is neither a Settings edit nor an undo step, and a
                // later apply keeps it (spec 027 FR-010, research R7).
                applied = applied.keepingHeadlineChoices(of: newValue)
                draft = draft.keepingHeadlineChoices(of: newValue)
                undoTarget = undoTarget?.keepingHeadlineChoices(of: newValue)
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
        // A group left without members stays (spec 009 FR-002). The
        // placement rules of the arrangement compare the candidate with the
        // state the user last saw (spec 008 FR-004a to FR-008, FR-014).
        // The headline windows are the dropdown's: a draft taken before a
        // click there never writes the old choice back (spec 027 FR-010).
        let candidate = draft.settingsCandidate(applied: applied, undoTarget: undoTarget)
            .keepingHeadlineChoices(of: model.configuration)
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
            // A cleared subscription directory may not start sharing the
            // default with another account; one loaded that way stays
            // editable, and an undo may restore it (spec 034 FR-006a).
            try candidate.checkNoNewSharedDefault(comparedTo: [applied] + (undoTarget.map { [$0] } ?? []))
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

/// The General tab: a fixed-width sidebar of pages next to the selected
/// page (spec 034 FR-001, research R1). The selection is remembered in the
/// defaults like the selected tab (FR-003, research R2); every page binds
/// the same draft, so apply, undo and the "Not applied" line work as before
/// (FR-004).
struct GeneralSettingsTab: View {
    @Binding var draft: Configuration
    @AppStorage(GeneralSettingsPage.defaultsKey) private var storedPage = GeneralSettingsPage.appearance.rawValue

    // The version is on the About tab.
    var body: some View {
        HStack(spacing: 0) {
            List(selection: pageBinding) {
                ForEach(GeneralSettingsPage.allCases) { page in
                    // Monochrome icons, the sidebar tint the HIG offers next
                    // to the accent color: the tab bar above stays the only
                    // blue in the window, and the row highlight marks the
                    // page (walkthrough 2026-10-22). The tint is per row.
                    Label(page.title, systemImage: page.systemImage)
                        .listItemTint(.monochrome)
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            // The sidebar material belongs to a full-height sidebar at the
            // window edge (HIG "Sidebars"); nested in a tab it made the only
            // translucent strip of the window (walkthrough 2026-10-22).
            .scrollContentBackground(.hidden)
            .frame(width: 170)
            Divider()
            pageView(GeneralSettingsPage(stored: storedPage))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A click on empty list space selects nothing; the page stays.
    private var pageBinding: Binding<GeneralSettingsPage?> {
        Binding(get: { GeneralSettingsPage(stored: storedPage) },
                set: { if let page = $0 { storedPage = page.rawValue } })
    }

    @ViewBuilder
    private func pageView(_ page: GeneralSettingsPage) -> some View {
        switch page {
        case .refresh: RefreshSettingsPage(draft: $draft)
        case .appearance: AppearanceSettingsPage(draft: $draft)
        case .weeklyWindow: WeeklyWindowSettingsPage(draft: $draft)
        case .notifications: NotificationSettingsPage(draft: $draft)
        case .sources: SourcesSettingsPage(draft: $draft)
        case .startup: StartupSettingsPage(draft: $draft)
        }
    }
}

private struct RefreshSettingsPage: View {
    @Binding var draft: Configuration

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
                // Spec 016 FR-001: on by default, directly below the interval.
                Toggle("Adapt refresh", isOn: $draft.adaptiveRefresh)
                Text("Refresh when the menu opens; check plan limits less often while no agent runs, while you are away or while the Mac saves power (still at least every 30 minutes).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Was the "Display" section (spec 034 FR-002).
private struct AppearanceSettingsPage: View {
    @Binding var draft: Configuration

    var body: some View {
        Form {
            // Spec 030 FR-008: one global direction for every level value,
            // applied through the draft like every other General setting.
            Section("Appearance") {
                Picker("Show usage as", selection: $draft.displayDirection) {
                    Text("Used").tag(DisplayDirection.used)
                    Text("Remaining").tag(DisplayDirection.remaining)
                }
                .pickerStyle(.segmented)
                Text("Remaining counts down from 100% as you use a limit or budget. Thresholds and notifications follow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // The dropdown's theme only; Settings and the menu bar keep
                // following the system. Applied through the draft, so an
                // open dropdown switches without a save (spec 032 FR-002,
                // FR-004, FR-005).
                Picker("Dropdown theme", selection: $draft.dropdownTheme) {
                    Text("Auto").tag(DropdownTheme.auto)
                    Text("Dark").tag(DropdownTheme.dark)
                    Text("Light").tag(DropdownTheme.light)
                }
                .pickerStyle(.segmented)
                Text("Auto follows the system appearance. Settings and the menu bar always do.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WeeklyWindowSettingsPage: View {
    @Binding var draft: Configuration

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        Form {
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
                // What the week counts for, in words without "Unassigned"
                // (walkthrough 2026-10-22); the monthly sentence stays
                // visible regardless of group periods (spec 003 FR-020).
                Text("The week that weekly budgets and the token details in the dropdown (per subscription account, and for usage that matches no account) count over. Aligned with a subscription account, it ends at that account's 7-day reset; the fallback applies until a reset has been fetched. Monthly budgets always run from the 1st to the end of the month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var alignmentBinding: Binding<String> {
        Binding(get: { draft.alignmentAccountId ?? "" },
                set: { draft.alignmentAccountId = $0.isEmpty ? nil : $0 })
    }
}

private struct NotificationSettingsPage: View {
    @Binding var draft: Configuration

    var body: some View {
        Form {
            // Credential notifications (spec 014 FR-012) and free limit
            // reset reminders (spec 033 FR-017).
            Section("Notifications") {
                Toggle("Notify when a sign-in stops working", isOn: $draft.notifySignInProblems)
                Toggle("Notify before a free limit reset expires", isOn: $draft.notifyFreeResetExpiry)
            }
        }
        .formStyle(.grouped)
    }
}

/// The global OpenCode data directories, and where the Claude Code
/// directories and Codex homes went: onto the accounts (spec 034 FR-002,
/// FR-010).
private struct SourcesSettingsPage: View {
    @Binding var draft: Configuration

    var body: some View {
        Form {
            // One OpenCode database holds every provider, so its extra
            // directories stay global (spec 006 FR-003, spec 034 FR-002).
            // `*` entries follow the account lists' rule (spec 035 FR-013).
            DirectoryListSection(title: AccountDirectoryText.openCodeSection,
                                 caption: AccountDirectoryText.openCodeCaption,
                                 prompt: AccountDirectoryText.openCodePrompt,
                                 harness: .openCode,
                                 directories: $draft.openCodeDirectories)
            Section(AccountDirectoryText.sourcesAccountsSection) {
                Text(AccountDirectoryText.sourcesAccountsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// Merges the former "Launch" and "Updates" sections (spec 034 FR-002).
private struct StartupSettingsPage: View {
    @Binding var draft: Configuration

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start at login", isOn: $draft.startAtLogin)
                // The automatic update check, applied through the draft like
                // every other General setting (spec 020 FR-008, FR-009).
                Toggle("Check for updates automatically", isOn: $draft.checksForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}

/// A list of extra directories in the macOS style, for the OpenCode data
/// directories (spec 006 FR-003, spec 035 FR-013) and for an account's
/// additional session directories (spec 035 FR-002): a bordered list with
/// the add and remove buttons below it. Add offers a folder chooser and,
/// for `*` entries, a sheet to type a path; both go through
/// `SessionDirectoryEntry.adding` (trimmed, no blank or duplicate entry).
struct DirectoryListSection: View {
    let title: String
    let caption: String
    let prompt: String
    /// Names the folders "Choose Folder…" asks for; `.openCode` for the
    /// OpenCode list.
    let harness: Harness
    @Binding var directories: [String]
    @State private var selection = Set<Int>()
    @State private var enteringPath = false
    /// The row being edited in place and its text.
    @State private var editing: Int?
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        Section(title) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                List(selection: $selection) {
                    ForEach(Array(directories.enumerated()), id: \.offset) { index, dir in
                        row(index: index, entry: dir).tag(index)
                    }
                }
                // The primary action runs on a double-click or Return, the
                // macOS way to edit a row in place.
                .contextMenu(forSelectionType: Int.self) { rows in
                    if rows.count == 1, let index = rows.first {
                        Button(AccountDirectoryText.editItem) { startEditing(index) }
                    }
                    if !rows.isEmpty {
                        Button("Remove") { remove(rows) }
                    }
                } primaryAction: { rows in
                    if rows.count == 1, let index = rows.first { startEditing(index) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: 96)
                .overlay {
                    if directories.isEmpty {
                        Text(AccountDirectoryText.emptyList).foregroundStyle(.secondary)
                    }
                }
                .onDeleteCommand(perform: removeSelected)
                HStack(spacing: 2) {
                    Menu {
                        Button(AccountDirectoryText.chooseFolderItem, action: chooseFolders)
                        Button(AccountDirectoryText.enterPathItem) { enteringPath = true }
                    } label: {
                        Image(systemName: "plus").frame(width: 20, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Add")
                    Divider().frame(height: 14)
                    Button(action: removeSelected) {
                        Image(systemName: "minus").frame(width: 20, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection.isEmpty)
                    .accessibilityLabel("Remove")
                }
            }
        }
        // Indices go stale when the list changes from outside (undo, a
        // provider switch), so the selection and an edit start over.
        .onChange(of: directories) { _, _ in
            selection = []
            editing = nil
        }
        .sheet(isPresented: $enteringPath) {
            EnterPathSheet(prompt: prompt) { directories = SessionDirectoryEntry.adding($0, to: directories) }
        }
    }

    /// A row shows its entry on one line, or a field while it is edited:
    /// Return or leaving the field applies, Escape cancels.
    @ViewBuilder
    private func row(index: Int, entry: String) -> some View {
        if editing == index {
            TextField("", text: $editText, prompt: Text(prompt))
                .labelsHidden()
                // Plain, as in a Finder rename: the window's rounded border
                // is taller than a row and made the list jump.
                .textFieldStyle(.plain)
                .focused($editFocused)
                // Focus once the field exists; set together with `editing`
                // it would go nowhere.
                .onAppear { editFocused = true }
                .onSubmit(commitEdit)
                .onExitCommand { editing = nil }
                .onChange(of: editFocused) { _, focused in
                    if !focused { commitEdit() }
                }
        } else {
            Text(entry)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry)
        }
    }

    private func startEditing(_ index: Int) {
        guard directories.indices.contains(index) else { return }
        editText = directories[index]
        editing = index
    }

    private func commitEdit() {
        guard let index = editing else { return }
        editing = nil
        directories = SessionDirectoryEntry.replacing(at: index, with: editText, in: directories)
    }

    private func removeSelected() {
        remove(selection)
    }

    private func remove(_ rows: Set<Int>) {
        guard !rows.isEmpty else { return }
        directories.remove(atOffsets: IndexSet(rows))
    }

    /// Folders only, several at once, hidden folders such as `.codex`
    /// shown; one draft change for all of them, so one undo step.
    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = AccountDirectoryText.chooseFolderMessage(for: harness)
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let paths = Paths()
        directories = panel.urls.reduce(directories) { list, url in
            SessionDirectoryEntry.adding(SessionDirectoryEntry.entry(forChosenFolder: url.path, paths: paths), to: list)
        }
    }
}

/// "Enter Path…" of a directory list: a path typed by hand, for entries a
/// folder chooser cannot pick such as `*` entries (spec 035 FR-002).
struct EnterPathSheet: View {
    let prompt: String
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AccountDirectoryText.enterPathTitle).font(.headline)
            TextField("", text: $path, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            Text(AccountDirectoryText.enterPathCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(path)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
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
/// hand-edited config file are kept as they are. The fields read in the
/// display direction from the environment, so the editor redraws at once
/// when it changes; what is stored stays used percent (spec 030 FR-015).
struct ThresholdsEditor: View {
    @Binding var thresholds: [Int]
    /// What 100% means for this entity, used in the explanation.
    let limitDescription: String
    @Environment(\.displayDirection) private var direction

    var body: some View {
        let placeholders = ThresholdDisplay.placeholders(direction: direction)
        LabeledContent("First notification at") {
            percentField(index: 0, placeholder: placeholders.first)
        }
        LabeledContent("Second notification at") {
            percentField(index: 1, placeholder: placeholders.second)
        }
        VStack(alignment: .leading, spacing: 4) {
            // Names no specific marker (spec 012 FR-006); both levels come
            // from the thresholds (spec 030 FR-007).
            Text(ThresholdDisplay.explanation(limitDescription: limitDescription, direction: direction))
            if invalid {
                Text(ThresholdDisplay.validationMessage(direction: direction)).foregroundStyle(.red)
            }
            if let further = ThresholdDisplay.furtherThresholds(thresholds, direction: direction) {
                Text(further)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// A stored value that no entry in the direction can produce: 0 or
    /// below (spec 030 FR-015).
    private var invalid: Bool {
        ThresholdDisplay.hasInvalidStored(thresholds)
    }

    private func percentField(index: Int, placeholder: String) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value(at: index), format: .number.grouping(.never), prompt: Text(placeholder))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text(ThresholdDisplay.fieldSuffix(direction: direction))
            if index < thresholds.count, let caption = ThresholdDisplay.caption(stored: thresholds[index], direction: direction) {
                Text(caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Reads and writes slot 0 or 1 in the direction; an empty field
    /// removes that slot. Entries convert back to used percent.
    private func value(at index: Int) -> Binding<Int?> {
        Binding(
            get: { index < thresholds.count ? ThresholdDisplay.shown(stored: thresholds[index], direction: direction) : nil },
            set: { thresholds = ThresholdDisplay.replacing(thresholds, slot: index, entered: $0, direction: direction) })
    }
}

/// The display direction for views that show thresholds, set once by the
/// Settings window from the draft (spec 030 FR-015).
private struct DisplayDirectionKey: EnvironmentKey {
    static let defaultValue = DisplayDirection.used
}

extension EnvironmentValues {
    var displayDirection: DisplayDirection {
        get { self[DisplayDirectionKey.self] }
        set { self[DisplayDirectionKey.self] = newValue }
    }
}
