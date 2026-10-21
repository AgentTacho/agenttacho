import SwiftUI
import UsageCore

/// What the import sheet was opened for: a provider import that still has
/// to be fetched, or a CSV file that was already read (successfully or not).
struct PriceImportRequest: Identifiable {
    enum Kind {
        case provider(ImportKind)
        case csv(Result<(ProposedImport, PriceDiff), Error>)
    }

    let id = UUID()
    let kind: Kind
    /// The manual overrides shown on the Prices tab when the import was
    /// chosen; the preview and the apply log compare against them.
    let overrides: [PriceEntry]

    var title: String {
        switch kind {
        case .provider(let importKind): return "\(importKind.displayName) prices from LiteLLM"
        case .csv: return "Prices from CSV file"
        }
    }
}

/// Preview of a proposed import before any price changes (FR-020 to
/// FR-022, contracts/prices-tab-ui.md). Provider imports start in the
/// loading state; errors replace the preview with the reason (FR-024).
struct PriceImportSheet: View {
    let model: AppModel
    let request: PriceImportRequest

    private enum Phase {
        case loading
        case preview(ProposedImport, PriceDiff)
        case failed(String)
    }

    @State private var phase: Phase
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, request: PriceImportRequest) {
        self.model = model
        self.request = request
        switch request.kind {
        case .provider:
            _phase = State(initialValue: .loading)
        case .csv(.success(let (proposal, diff))):
            _phase = State(initialValue: .preview(proposal, diff))
        case .csv(.failure(let error)):
            _phase = State(initialValue: .failed(String(describing: error)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The top of the prices strip (spec 031 FR-011a).
            Text(request.title).font(.headline)
                .shotIdentifier("agenttacho.priceImportTitle")
            content
            Divider()
            buttons
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .task { await start() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Downloading the LiteLLM price list…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Label("No prices were changed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(reason)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .preview(let proposal, let diff):
            PriceImportPreview(proposal: proposal, diff: diff)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            switch phase {
            case .failed:
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .loading:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            case .preview(let proposal, let diff):
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply(proposal, diff) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(applyDisabled(proposal, diff))
            }
        }
    }

    /// Nothing to apply: no new, changed or removed models and the same
    /// prices as the stored batch of that kind (contracts/prices-tab-ui.md).
    private func applyDisabled(_ proposal: ProposedImport, _ diff: PriceDiff) -> Bool {
        diff.isEmpty && proposal.matches(model.importedPrices.batch(for: proposal.batch.kind))
    }

    /// Provider imports are fetched once when the sheet appears; a CSV file
    /// was already read before the sheet opened.
    private func start() async {
        guard case .provider(let kind) = request.kind, case .loading = phase else { return }
        do {
            let (proposal, diff) = try await model.previewProviderImport(kind, overrides: request.overrides)
            phase = .preview(proposal, diff)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Saving is synchronous and quick; the sheet closes on success and
    /// shows the reason on failure.
    private func apply(_ proposal: ProposedImport, _ diff: PriceDiff) {
        do {
            try model.applyImport(proposal, overrides: request.overrides)
            dismiss()
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}

/// The diff of a proposed import: summary and one section per category.
struct PriceImportPreview: View {
    let proposal: ProposedImport
    let diff: PriceDiff
    /// Every skipped row as "Line N: reason", 200 lines per chunk, built
    /// once. One lazily laid out Text per chunk keeps a large file from
    /// creating a view per line or one huge Text (FR-017, FR-020c).
    private let skippedChunks: [String]

    init(proposal: ProposedImport, diff: PriceDiff) {
        self.proposal = proposal
        self.diff = diff
        let lines = proposal.skippedRows.map { "Line \($0.line): \($0.reason)" }
        skippedChunks = stride(from: 0, to: lines.count, by: 200).map {
            lines[$0..<min($0 + 200, lines.count)].joined(separator: "\n")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The prices strip runs from the title over the summary to the
            // end of the Changed section (spec 031 FR-011a).
            Text(summary).font(.callout.bold())
                .shotIdentifier("agenttacho.priceImportSummary")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !diff.changed.isEmpty {
                        section("Changed") {
                            ForEach(diff.changed) { change in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.model).monospaced()
                                    ForEach(change.changedFields, id: \.self) { field in
                                        HStack(spacing: 4) {
                                            Text(field.displayName).frame(width: 80, alignment: .leading)
                                            Text(PriceFormat.value(change.before[keyPath: field.keyPath]))
                                                .foregroundStyle(.secondary)
                                            Text("→")
                                            Text(PriceFormat.value(change.after[keyPath: field.keyPath]))
                                                .bold()
                                                .foregroundStyle(Color.accentColor)
                                            if isDerived(change.model, field) { DerivedMarker() }
                                        }
                                        .font(.caption)
                                        .padding(.leading, 12)
                                    }
                                }
                            }
                        }
                        .shotContainer("agenttacho.priceImportChanged")
                    }
                    if !diff.removed.isEmpty {
                        section("Removed") {
                            ForEach(diff.removed) { removal in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(removal.model).monospaced()
                                    Group {
                                        if let fallback = removal.fallback {
                                            Text("falls back to \(PriceFormat.prices(fallback)) (\(PriceFormat.source(fallback.source)))")
                                        } else {
                                            Text("unpriced").foregroundStyle(.red)
                                        }
                                    }
                                    .font(.caption)
                                    .padding(.leading, 12)
                                }
                            }
                        }
                    }
                    if !diff.shadowed.isEmpty {
                        section("Shadowed") {
                            ForEach(diff.shadowed) { shadow in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shadow.model).monospaced()
                                    VStack(alignment: .leading, spacing: 2) {
                                        priceFields(shadow.proposed)
                                        Text(PriceFormat.winnerText(shadow.winner))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 12)
                                }
                            }
                        }
                    }
                    if !diff.newModels.isEmpty {
                        section("New") {
                            ForEach(diff.newUsed) { entry in newRow(entry) }
                            if !diff.newOther.isEmpty {
                                DisclosureGroup("\(diff.newOther.count) more new models") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(diff.newOther) { entry in newRow(entry) }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    if !skippedChunks.isEmpty {
                        // Header and chunks are direct children of the lazy
                        // stack; the negative padding closes the stack spacing.
                        Text("Skipped rows").font(.subheadline.bold())
                        ForEach(skippedChunks.indices, id: \.self) { index in
                            Text(skippedChunks[index])
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                                .padding(.top, index == 0 ? -8 : -14)
                        }
                    }
                    if diff.unchangedCount > 0 {
                        Text("\(diff.unchangedCount) unchanged models")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The diff summary plus, for CSV, the number of skipped rows.
    private var summary: String {
        let skipped = proposal.skippedRows.count
        return skipped == 0 ? diff.summary : "\(diff.summary), \(skipped) skipped"
    }

    private func isDerived(_ model: String, _ field: PriceField) -> Bool {
        proposal.derived[model]?.contains(field) ?? false
    }

    private func newRow(_ entry: PriceEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.model).monospaced()
            priceFields(entry)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        }
    }

    /// All five prices of an entry, derived CSV values marked (FR-015).
    private func priceFields(_ entry: PriceEntry) -> some View {
        HStack(spacing: 8) {
            ForEach(PriceField.allCases, id: \.self) { field in
                HStack(spacing: 2) {
                    Text("\(field.displayName) \(PriceFormat.value(entry[keyPath: field.keyPath]))")
                    if isDerived(entry.model, field) { DerivedMarker() }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }
}

/// Marks a CSV value derived from the input price (FR-015).
struct DerivedMarker: View {
    var body: some View {
        Text("derived")
            .font(.caption2)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2)))
    }
}

/// Text for prices and sources shared by the Prices tab and the import sheet.
enum PriceFormat {
    static func value(_ value: Decimal) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
    }

    static func prices(_ entry: PriceEntry) -> String {
        PriceField.allCases.map { "\($0.displayName.lowercased()) \(value(entry[keyPath: $0.keyPath]))" }.joined(separator: ", ")
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Built-in", "LiteLLM <date>", "CSV <file name>" or "Manual" (FR-029).
    static func source(_ source: PriceSource) -> String {
        switch source {
        case .builtIn: return "Built-in"
        case .override: return "Manual"
        case .imported(let provenance):
            return provenance.kind == .csv ? "CSV \(provenance.origin)" : "LiteLLM \(date(provenance.importedAt))"
        }
    }

    /// "Anthropic prices from LiteLLM, imported today" or "CSV prices from
    /// prices.csv, imported 3 days ago" (FR-031).
    static func status(_ batch: PriceBatch, now: Date = Date(), calendar: Calendar = .current) -> String {
        let from = batch.kind == .csv ? batch.origin : "LiteLLM"
        return "\(batch.kind.displayName) prices from \(from), imported \(age(batch.importedAt, now: now, calendar: calendar))"
    }

    /// Day granularity: "today", "yesterday", "N days ago".
    static func age(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// The source that keeps winning over a shadowed import (FR-020a).
    static func winnerText(_ winner: PriceSource) -> String {
        switch winner {
        case .override: return "your override stays in effect"
        case .imported(let provenance) where provenance.kind == .csv: return "the CSV price stays in effect"
        case .imported(let provenance): return "the \(provenance.kind.displayName) import stays in effect"
        case .builtIn: return "the built-in price stays in effect"
        }
    }
}
