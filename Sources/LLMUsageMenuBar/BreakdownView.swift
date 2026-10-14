import SwiftUI
import UsageCore

/// Which table the expanded Details section shows; one choice for all
/// sections, remembered across launches.
enum DetailsMode: String, CaseIterable, Identifiable {
    case models, projects

    var id: Self { self }
    var title: String { self == .models ? "Models" : "Projects" }
}

/// Collapsible per-model table and per-day trend (FR-008). `showsCost` is
/// false for subscription accounts and Unassigned (tokens only). `period` is
/// the period of the window the breakdown covers (spec 003 FR-013).
struct BreakdownView: View {
    let breakdown: UsageBreakdown
    let showsCost: Bool
    var period: BudgetPeriod = .weekly
    @State private var expanded = false
    @AppStorage("detailsMode") private var mode: DetailsMode = .models

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("View", selection: $mode) {
                    ForEach(DetailsMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                switch mode {
                case .models: modelTable
                case .projects: projectTable
                }
                if !breakdown.perDay.isEmpty {
                    dayTrend
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text("Details")
                if expanded {
                    InfoHover(text: explanation)
                }
            }
        }
        .font(.caption)
        // Expand without animation: the MenuBarExtra window resizes to the
        // final content size in one step instead of clipping mid-animation.
        .animation(nil, value: expanded)
    }

    private var modelTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
                Text("Model").gridColumnAlignment(.leading)
                Text("In")
                Text("Out")
                Text("Cache w")
                Text("Cache r")
                if showsCost { Text("Cost") }
            }
            .foregroundStyle(.secondary)
            ForEach(breakdown.perModel) { model in
                GridRow {
                    Text(model.model).lineLimit(1).gridColumnAlignment(.leading)
                    Text(tokenText(model.inputTokens))
                    Text(tokenText(model.outputTokens))
                    Text(tokenText(model.cacheWriteTokens))
                    Text(tokenText(model.cacheReadTokens))
                    if showsCost { costText(model.costUSD) }
                }
                .monospacedDigit()
            }
            if breakdown.perModel.count > 1 {
                GridRow {
                    Text("Total").bold().gridColumnAlignment(.leading)
                    Text(tokenText(breakdown.inputTokens))
                    Text(tokenText(breakdown.outputTokens))
                    Text(tokenText(breakdown.cacheWriteTokens))
                    Text(tokenText(breakdown.cacheReadTokens))
                    if showsCost {
                        Text(UsageFormat.usd(breakdown.pricedCostUSD)).bold()
                    }
                }
                .monospacedDigit()
            }
        }
    }

    private func costText(_ cost: Decimal?) -> Text {
        if let cost {
            return Text(UsageFormat.usd(cost))
        }
        return Text("unpriced").foregroundStyle(Color.orange)
    }

    /// Top 5 projects plus Other; no Total row, the section header has it.
    @ViewBuilder
    private var projectTable: some View {
        let ranking = breakdown.topProjects(byCost: showsCost)
        let showsShare = ranking.top.first?.sharePercent != nil
        if ranking.top.isEmpty {
            Text("No usage in this window").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("Project").gridColumnAlignment(.leading)
                    Text("Tokens")
                    if showsCost { Text("Cost") }
                    if showsShare { Text("Share") }
                }
                .foregroundStyle(.secondary)
                ForEach(ranking.top) { row in
                    GridRow {
                        Text(row.usage.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 160, alignment: .leading)
                            .help(row.usage.project?.rootPath ?? "")
                            .gridColumnAlignment(.leading)
                        Text(tokenText(row.usage.totalTokens))
                        if showsCost { costText(row.usage.costUSD) }
                        if showsShare { Text(shareText(row.sharePercent)) }
                    }
                    .monospacedDigit()
                }
                if let other = ranking.other {
                    GridRow {
                        Text("Other (\(other.count))").gridColumnAlignment(.leading)
                        Text(tokenText(other.totalTokens))
                        if showsCost { costText(other.costUSD) }
                        if showsShare { Text(shareText(other.sharePercent)) }
                    }
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Token-only breakdowns (subscription accounts, Unassigned) show whole
    /// millions without a suffix; priced ones keep the compact K/M/B form.
    private func tokenText(_ value: Int) -> String {
        showsCost ? UsageFormat.tokens(value) : UsageFormat.millions(value)
    }

    private func shareText(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? ""
    }

    /// Columns per row of a monthly day trend; a 31-day month wraps into at
    /// most 5 rows and stays within the dropdown width (spec 003 SC-006,
    /// research R6).
    private static let monthlyDaysPerRow = 7

    /// One compact column per day of the window: weekday initial (weekly) or
    /// day of the month (monthly) on top, spend (or tokens) below. Days
    /// without usage show 0. Monthly rows wrap after 7 columns; a weekly
    /// window (7 or 8 local days) stays on one row as before.
    private var dayTrend: some View {
        let days = breakdown.perDay
        let perRow = period == .monthly ? Self.monthlyDaysPerRow : max(days.count, 1)
        let rows = stride(from: 0, to: days.count, by: perRow).map {
            Array(days[$0..<min($0 + perRow, days.count)])
        }
        return Grid(alignment: .top, horizontalSpacing: 6, verticalSpacing: 4) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { day in
                        VStack(spacing: 1) {
                            Text(dayLabel(day))
                                .foregroundStyle(.secondary)
                            Text(dayValue(day))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .frame(minWidth: 34)
                        .help(dayHelp(day))
                    }
                }
            }
        }
    }

    private func dayLabel(_ day: DayUsage) -> String {
        switch period {
        case .weekly: return day.day.formatted(.dateTime.weekday(.narrow))
        case .monthly: return day.day.formatted(.dateTime.day())
        }
    }

    /// Column legend shown by the (i) icon.
    private var explanation: String {
        var lines = mode == .models ? modelLegend : projectLegend
        let columns = period == .monthly
            ? "one column per day of the monthly window from the 1st to today (day of the month)"
            : "one column per day of the weekly window (weekday initial)"
        lines.append(showsCost
            ? "Day row: \(columns), with that day's cost in whole US$. Point at a day for the exact amount."
            : "Day row: \(columns), with that day's tokens of all four kinds. Point at a day for the exact count.")
        lines.append(showsCost
            ? "K, M and B stand for thousand, million and billion."
            : "All token counts are in millions, rounded to whole numbers. \"<1\" means less than half a million.")
        if !showsCost {
            lines.append("Tokens come from the session logs on this Mac only. The percentages above come from Anthropic and cover all devices.")
        }
        return lines.joined(separator: "\n\n")
    }

    private var modelLegend: [String] {
        var lines = [
            "Model: the model id as recorded in the Claude Code session logs.",
            "In: input tokens sent to the model that did not come from the prompt cache.",
            "Out: output tokens the model generated.",
            "Cache w: input tokens written to the prompt cache (5-minute and 1-hour entries), billed above the normal input price.",
            "Cache r: input tokens served from the prompt cache, billed at a small fraction of the input price.",
        ]
        if showsCost {
            lines.append("Cost: US$ from the built-in price table or your overrides on the Prices tab. \"unpriced\" means the model has no price, so the total is incomplete.")
        }
        lines.append("Total: the sum over all models, shown when there is more than one.")
        return lines
    }

    private var projectLegend: [String] {
        var lines = [
            "Project: the git repository the Claude Code session ran in. Subdirectories and git worktrees count toward their repository; folders outside a repository count on their own. Point at a name for the full path.",
            "Unknown: log lines that do not record a working directory.",
            "Tokens: input, output and both cache kinds together.",
        ]
        if showsCost {
            lines.append("Cost: US$ from the price table. \"unpriced\" means a model used in the project has no price.")
            lines.append("Share: part of this section's priced cost.")
        } else {
            lines.append("Share: part of this section's tokens.")
        }
        lines.append("Other: the projects beyond the top 5, added up.")
        return lines
    }

    private func dayValue(_ day: DayUsage) -> String {
        if showsCost, let cost = day.costUSD {
            return cost == 0 ? "0" : UsageFormat.compactUSD(cost)
        }
        return day.totalTokens == 0 ? "0" : tokenText(day.totalTokens)
    }

    /// Exact value shown on hover, since the cell rounds.
    private func dayHelp(_ day: DayUsage) -> String {
        let date = day.day.formatted(date: .abbreviated, time: .omitted)
        if showsCost, let cost = day.costUSD {
            return "\(date): \(UsageFormat.usd(cost))"
        }
        return "\(date): \(day.totalTokens.formatted()) tokens"
    }
}

/// An (i) icon that shows an explanation in a popover while the pointer is
/// over it.
struct InfoHover: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { shown = $0 }
            .popover(isPresented: $shown, arrowEdge: .trailing) {
                Text(text)
                    .font(.callout)
                    .frame(width: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
            .accessibilityLabel("Column explanation")
            .accessibilityHint(text)
    }
}
