import SwiftUI
import UsageCore

/// Window for choosing a Font Awesome icon: a search field over name, label
/// and search terms, and a grid of matching icons. A click selects and
/// closes; Escape cancels. There is no "no icon" choice, since every entry
/// has exactly one icon (spec 004 FR-002).
struct IconPickerSheet: View {
    @Binding var selection: String?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [IconEntry] {
        IconCatalog.shared.search(query)
    }

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 6)]

    var body: some View {
        let results = self.results
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("", text: $query, prompt: Text("Search icons, for example claude, cloud, robot"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
            }
            Text(results.count == 1 ? "1 icon" : "\(results.count) icons")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(results) { entry in
                        IconCell(entry: entry, selected: entry.ref.description == selection)
                            .onTapGesture {
                                selection = entry.ref.description
                                dismiss()
                            }
                    }
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if results.isEmpty {
                    Text("No icon matches \"\(query)\".").foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Font Awesome Free \(IconCatalog.shared.version), CC BY 4.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 560, height: 480)
        .onAppear { searchFocused = true }
    }
}

private struct IconCell: View {
    let entry: IconEntry
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            IconGlyph(entry: entry, size: 22)
                .frame(height: 28)
            Text(entry.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            if entry.style != .solid {
                Text(entry.style.rawValue)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.08)))
        .contentShape(Rectangle())
        .help("\(entry.label) (\(entry.ref))")
    }
}
