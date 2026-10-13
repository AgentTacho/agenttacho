import SwiftUI
import UsageCore

/// Collapsible per-model table and per-day trend (FR-008). `showsCost` is
/// false for subscription accounts and Unassigned (tokens only).
struct BreakdownView: View {
    let breakdown: UsageBreakdown
    let showsCost: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("Details", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                modelTable
                if !breakdown.perDay.isEmpty {
                    dayTrend
                }
            }
            .padding(.top, 4)
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

    private func dayValue(_ day: DayUsage) -> String {
        if showsCost, let cost = day.costUSD {
            return cost == 0 ? "0" : UsageFormat.usd(cost)
        }
        return day.totalTokens == 0 ? "0" : UsageFormat.tokens(day.totalTokens)
    }
}
