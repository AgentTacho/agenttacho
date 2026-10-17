import AppKit
import SwiftUI
import UsageCore

// MARK: - Log tab

/// The newest lines of the diagnostic log, scrolled to the end and reloaded
/// after every refresh. `DiagnosticLog.tail` reads only the end of the file,
/// so this stays cheap even when the log is at its size cap. The log itself
/// can still be opened in Console or shown in Finder.
struct LogSettingsTab: View {
    let model: AppModel

    /// Lines shown; the file can hold many more.
    private static let lineLimit = 500

    @State private var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lines.isEmpty ? "No log entries yet." : "Newest \(lines.count) lines of \(displayPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reload") { reload() }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.log.fileURL])
                }
                .disabled(lines.isEmpty)
                Button("Open in Console") { model.openLog() }
            }
            .controlSize(.small)

            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(8)
                        Color.clear.frame(height: 1).id(Self.endMarker)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .onChange(of: lines) { _, _ in proxy.scrollTo(Self.endMarker, anchor: .bottomLeading) }
                .onAppear { proxy.scrollTo(Self.endMarker, anchor: .bottomLeading) }
            }
        }
        .onAppear { reload() }
        // Every refresh writes its summary to the log.
        .onChange(of: model.snapshot?.generatedAt) { _, _ in reload() }
    }

    private static let endMarker = "log-end"

    private var displayPath: String {
        (model.log.fileURL.path as NSString).abbreviatingWithTildeInPath
    }

    private func reload() {
        lines = model.log.tail(lines: Self.lineLimit)
    }
}
