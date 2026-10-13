import SwiftUI
import UsageCore

/// Collapsible per-model table and per-day trend (FR-008). `showsCost` is
/// false for subscription accounts and Unassigned (tokens only).
struct BreakdownView: View {
    let breakdown: UsageBreakdown
    let showsCost: Bool
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

    /// One compact column per day of the window: weekday initial on top,
    /// spend (or tokens) below. Days without usage show 0.
    private var dayTrend: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(breakdown.perDay) { day in
                VStack(spacing: 1) {
                    Text(day.day.formatted(.dateTime.weekday(.narrow)))
                        .foregroundStyle(.secondary)
                    Text(dayValue(day))
                        .monospacedDigit()
                }
                .frame(minWidth: 34)
            }
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
        lines.append(showsCost
            ? "Day row: one column per day of the weekly window (weekday initial), with that day's cost."
            : "Day row: one column per day of the weekly window (weekday initial), with that day's tokens of all four kinds.")
        lines.append("K, M and B stand for thousand, million and billion.")
        if !showsCost {
            lines.append("Tokens come from the session logs on this Mac only. The percentages above come from Anthropic and cover all devices.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func dayValue(_ day: DayUsage) -> String {
        if showsCost, let cost = day.costUSD {
            return cost == 0 ? "0" : UsageFormat.usd(cost)
        }
        return day.totalTokens == 0 ? "0" : UsageFormat.tokens(day.totalTokens)
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
