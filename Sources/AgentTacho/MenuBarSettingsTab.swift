import SwiftUI
import UsageCore

// MARK: - Menu Bar tab

/// The order of the bar and the dropdown (spec 008 FR-009 to FR-014,
/// contracts/menu-bar-tab.md): a live preview of the bar, the level display
/// settings (spec 012 FR-004, FR-012), then every entry with its members
/// indented below it. Rows reorder by drag or with Move
/// Up/Move Down; all order logic lives in `ArrangementEditor`. Changes go to
/// the draft and are applied and undone like every other settings change.
struct MenuBarSettingsTab: View {
    @Binding var draft: Configuration
    let model: AppModel
    /// The selected row's id; ids are stable, so a moved row stays selected.
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
            levelSettings
            // The preview follows the toggle through `BarLayout.segments`;
            // the dropdown's bars and notes stay (spec 011 FR-014, spec 025). The toggle
            // covers both markers (spec 017 FR-010).
            Toggle("Show ↗ or ↑ when an entry will run out before it resets", isOn: $draft.showsRunOutMarker)
            let rows = ArrangementEditor.rows(draft)
            if rows.isEmpty {
                Text("No accounts configured. Add one in the Accounts tab.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(rows) { row in
                        rowView(row).tag(row.id)
                    }
                    .onMove { source, destination in
                        // A rejected drop (out of a group, into a member
                        // block) changes nothing (FR-010).
                        if let moved = ArrangementEditor.move(draft, from: source, to: destination) {
                            draft.arrangement = moved
                        }
                    }
                }
                moveButtons(rows)
            }
        }
    }

    // MARK: Preview

    /// The bar built by the same rules and renderer as the real one, from
    /// the draft's order and visibility and the latest values (FR-013).
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer(minLength: 0)
                BarLabelView(items: BarLayout.segments(snapshot: model.snapshot, configuration: draft),
                             display: draft.levelDisplay, preview: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .clipShape(Capsule())
        }
    }

    // MARK: Level settings

    /// How the bar shows levels (spec 012 FR-004,
    /// contracts/menu-bar-tab-level-settings.md). Changes go to the draft
    /// like every other setting and never trigger a refresh.
    private var levelSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Level color", selection: $draft.levelColor) {
                Text("Text").tag(LevelColorStyle.text)
                Text("Pill").tag(LevelColorStyle.pill)
                Text("Off").tag(LevelColorStyle.off)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            // FR-004: the glyphs, alone or together with color (drawn per FR-010).
            Toggle("Mark levels with ⚠ / ‼", isOn: $draft.showLevelSymbols)
                .toggleStyle(.checkbox)
            // FR-012: Off without symbols is valid but hides levels.
            if draft.levelDisplay.hidesLevels {
                Text("Levels will not appear in the menu bar. Notifications and the dropdown still show them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: ArrangementRow) -> some View {
        let info = info(for: row)
        HStack {
            // The same setting as the editor toggles (FR-012).
            Toggle("Show in bar", isOn: shownInBar(row))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Show \(info.name) in bar")
                .help("Show in bar")
            labelText(info.icon).bold().frame(width: 28, alignment: .leading)
            VStack(alignment: .leading) {
                Text(info.name)
                Text(info.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        // Hidden entries keep their place, in secondary color (contract).
        .foregroundStyle(draft.isShownInBar(row) ? .primary : .secondary)
        .padding(.leading, row.isMember ? 24 : 0)
    }

    private struct RowInfo {
        let icon: String
        let name: String
        let caption: String
    }

    /// Icon, name and kind caption of a row (FR-009).
    private func info(for row: ArrangementRow) -> RowInfo {
        switch row {
        case .entry(let ref) where ref.kind == .group:
            let group = draft.group(id: ref.id)
            return RowInfo(icon: group?.icon ?? IconDefaults.group, name: group?.name ?? ref.id, caption: "Budget group")
        case .entry(let ref):
            let account = draft.account(id: ref.id)
            let caption: String
            switch account?.kind {
            case .subscription?: caption = "Subscription"
            case .codexSubscription?: caption = "Codex plan"
            case .tokenBased?, nil: caption = "Own budget"
            }
            return RowInfo(icon: account?.icon ?? "", name: account?.displayName ?? ref.id, caption: caption)
        case .member(_, let accountId):
            let account = draft.account(id: accountId)
            return RowInfo(icon: account?.icon ?? "", name: account?.displayName ?? accountId, caption: "Member share")
        }
    }

    /// The row's "Show in bar" setting, read and written through the draft
    /// so the editors and the preview follow at once (FR-012, FR-013).
    private func shownInBar(_ row: ArrangementRow) -> Binding<Bool> {
        Binding(
            get: { draft.isShownInBar(row) },
            set: { draft = draft.settingShownInBar(row, $0) }
        )
    }

    // MARK: Move Up / Move Down

    /// The pointer-free alternative to dragging (FR-010a): one position
    /// within the selected row's level, Option-Command-Up and -Down.
    private func moveButtons(_ rows: [ArrangementRow]) -> some View {
        let selected = rows.first { $0.id == selection }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Move Up") {
                    if let selected, let moved = ArrangementEditor.moveUp(draft, row: selected) {
                        draft.arrangement = moved
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
                .disabled(!ArrangementEditor.canMoveUp(draft, row: selected))
                Button("Move Down") {
                    if let selected, let moved = ArrangementEditor.moveDown(draft, row: selected) {
                        draft.arrangement = moved
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
                .disabled(!ArrangementEditor.canMoveDown(draft, row: selected))
            }
            Text("Drag to reorder. Members stay inside their group. The dropdown uses the same order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension ArrangementRow {
    var isMember: Bool {
        if case .member = self { return true }
        return false
    }
}
