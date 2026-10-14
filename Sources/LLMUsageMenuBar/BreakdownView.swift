import SwiftUI
import UsageCore

/// Collapsible per-model table and per-day trend (FR-008). `showsCost` is
/// false for subscription accounts and Unassigned (tokens only). `period` is
/// the period of the window the breakdown covers (spec 003 FR-013).
struct BreakdownView: View {
    let breakdown: UsageBreakdown
    let showsCost: Bool
    var period: BudgetPeriod = .weekly
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                modelTable
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
                    Text(UsageFormat.tokens(model.inputTokens))
                    Text(UsageFormat.tokens(model.outputTokens))
                    Text(UsageFormat.tokens(model.cacheWriteTokens))
                    Text(UsageFormat.tokens(model.cacheReadTokens))
                    if showsCost { costText(model) }
                }
                .monospacedDigit()
            }
            if breakdown.perModel.count > 1 {
                GridRow {
                    Text("Total").bold().gridColumnAlignment(.leading)
                    Text(UsageFormat.tokens(breakdown.inputTokens))
                    Text(UsageFormat.tokens(breakdown.outputTokens))
                    Text(UsageFormat.tokens(breakdown.cacheWriteTokens))
                    Text(UsageFormat.tokens(breakdown.cacheReadTokens))
                    if showsCost {
                        Text(UsageFormat.usd(breakdown.pricedCostUSD)).bold()
                    }
                }
                .monospacedDigit()
            }
        }
    }

    private func costText(_ model: ModelUsage) -> Text {
        if let cost = model.costUSD {
            return Text(UsageFormat.usd(cost))
        }
        return Text("unpriced").foregroundStyle(Color.orange)
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
        let columns = period == .monthly
            ? "one column per day of the monthly window from the 1st to today (day of the month)"
            : "one column per day of the weekly window (weekday initial)"
        lines.append(showsCost
            ? "Day row: \(columns), with that day's cost in whole US$. Point at a day for the exact amount."
            : "Day row: \(columns), with that day's tokens of all four kinds.")
        lines.append("K, M and B stand for thousand, million and billion.")
        if !showsCost {
            lines.append("Tokens come from the session logs on this Mac only. The percentages above come from Anthropic and cover all devices.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func dayValue(_ day: DayUsage) -> String {
        if showsCost, let cost = day.costUSD {
            return cost == 0 ? "0" : UsageFormat.compactUSD(cost)
        }
        return day.totalTokens == 0 ? "0" : UsageFormat.tokens(day.totalTokens)
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
