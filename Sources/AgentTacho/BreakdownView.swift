import SwiftUI
import UsageCore

/// Which table the expanded Details section shows; one choice for all
/// sections, remembered across launches.
enum DetailsMode: String, CaseIterable, Identifiable {
    case models, projects, harnesses

    var id: Self { self }
    var title: String {
        switch self {
        case .models: return "Models"
        case .projects: return "Projects"
        case .harnesses: return "Harnesses"
        }
    }
}

/// A budget group member's tables behind "Show account details" (spec 026 FR-003):
/// the member's own breakdown for the group's period (spec 004 FR-018a).
struct MemberTable: Identifiable {
    let id: String
    let icon: String
    let name: String
    let breakdown: UsageBreakdown
    /// The member's incomplete prices, for its Σ tooltip (spec 026 FR-009).
    let incomplete: Bool
}

/// Collapsible per-model table and per-day trend (FR-008). `showsCost` is
/// false for subscription accounts and Unassigned (tokens only). `period` is
/// the period of the window the breakdown covers (spec 003 FR-013). A budget
/// group passes its members' tables, which the Details reveal below the
/// group's own behind "Show account details" (spec 026 FR-003 to FR-005).
struct BreakdownView: View {
    let breakdown: UsageBreakdown
    let showsCost: Bool
    var period: BudgetPeriod = .weekly
    /// The capture's identifier for this breakdown, nil for none: the shot
    /// budget's (`agenttacho.details`, the `harnesses` shot, spec 024
    /// FR-019) or the first Claude Max account's (`agenttacho.claudeDetails`,
    /// the `glance` shot, spec 031 FR-010a).
    var shotIdentifier: String? = nil
    /// True for a budget with unpriced usage (its incomplete note): the Σ
    /// tooltip adds "incomplete: some usage is unpriced"; false for
    /// subscriptions and Unassigned (spec 026 FR-009).
    var incomplete = false
    /// The members' tables of a budget group with two or more members with
    /// usage, in member order; empty otherwise (`MemberDisplay.tables`).
    var memberTables: [MemberTable] = []
    @State private var expanded = false
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    @AppStorage("detailsMode") private var mode: DetailsMode = .models
    /// Whether the member tables are shown: one choice for all groups,
    /// remembered across openings and launches like the view picker
    /// (spec 026 FR-004).
    @AppStorage("showsMemberTables") private var showsMemberTables = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // The view picker comes first; the week's total is the day
            // row's Σ column, not a line of its own (spec 026 FR-008).
            VStack(alignment: .leading, spacing: 6) {
                Picker("View", selection: $mode) {
                    ForEach(DetailsMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                BreakdownTables(breakdown: breakdown, showsCost: showsCost, period: period, mode: mode, incomplete: incomplete)
                if !memberTables.isEmpty {
                    memberSection
                }
            }
            .padding(.top, 4)
            // Left-aligned at full width, so the picker and the tables keep
            // their place when the view or the member tables change (spec 026
            // FR-005a, walkthrough step 3).
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .shotContainer(shotIdentifier)
    }

    /// "Show account details" / "Hide account details" after the group's day row, and when
    /// shown each member under its name with its tables for the selected
    /// view and its day row, without a leading indent of its own (spec 026
    /// FR-003, FR-005, FR-009a).
    @ViewBuilder
    private var memberSection: some View {
        Button(showsMemberTables ? "Hide account details" : "Show account details") {
            showsMemberTables.toggle()
        }
        .buttonStyle(DropdownLinkButtonStyle(color: colors.link))
        .font(.caption)
        if showsMemberTables {
            ForEach(memberTables) { member in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        labelText(member.icon)
                        Text(member.name)
                    }
                    .foregroundStyle(colors.secondary)
                    BreakdownTables(breakdown: member.breakdown, showsCost: showsCost, period: period, mode: mode,
                                    incomplete: member.incomplete)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Column legend shown by the (i) icon.
    private var explanation: String {
        var lines: [String]
        switch mode {
        case .models: lines = modelLegend
        case .projects: lines = projectLegend
        case .harnesses: lines = harnessLegend
        }
        let columns = period == .monthly
            ? "one column per day of the monthly window from the 1st to today (day of the month)"
            : "one column per day of the weekly window (weekday initial)"
        lines.append(showsCost
            ? "Day row: \(columns), with that day's cost in whole US$. Point at a day for the exact amount."
            : "Day row: \(columns), with that day's tokens of all four kinds. Point at a day for the exact count.")
        // The Σ column replaces the "This week" line (spec 026 FR-008, FR-009).
        lines.append(showsCost
            ? "\u{03A3}: the sum of all shown days, after the last day, in the same format. Point at it for the exact total."
            : "\u{03A3}: the sum of all days in the row, the week's tokens on this Mac. Point at it for the exact total.")
        lines.append(showsCost
            ? "K, M and B stand for thousand, million and billion."
            : "All token counts are in millions, rounded to whole numbers. \"<1\" means less than half a million.")
        if !showsCost {
            lines.append("Tokens come from the session logs and harness data on this Mac only. The percentages above come from the provider and cover all devices.")
        }
        return lines.joined(separator: "\n\n")
    }

    private var modelLegend: [String] {
        var lines = [
            "Model: the model id as recorded by the harness (Claude Code, Codex or OpenCode), without a snapshot or @ suffix.",
            "In: input tokens sent to the model that did not come from the prompt cache.",
            "Out: output tokens the model generated, including reasoning. Point at a value to see the reasoning part.",
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
            "Project: the git repository the session ran in. Subdirectories and git worktrees count toward their repository; folders outside a repository count on their own. Point at a name for the full path.",
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

    private var harnessLegend: [String] {
        var lines = [
            "Harness: the coding agent that recorded the usage: Claude Code, Codex or OpenCode.",
            "Tokens: input, output and both cache kinds together.",
        ]
        if showsCost {
            lines.append("Cost: US$ from the price table, never the harness's own estimate. \"unpriced\" means a model used through that harness has no price.")
        }
        return lines
    }
}

/// The table for the selected view and the day row of one breakdown, shared
/// by a section's own Details and the member tables of a budget group
/// (spec 026 FR-003, FR-005).
private struct BreakdownTables: View {
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    let breakdown: UsageBreakdown
    let showsCost: Bool
    let period: BudgetPeriod
    let mode: DetailsMode
    /// The breakdown has unpriced usage; Σ's tooltip says so (spec 026 FR-009).
    let incomplete: Bool

    var body: some View {
        switch mode {
        case .models: modelTable
        case .projects: projectTable
        case .harnesses: harnessTable
        }
        if !breakdown.perDay.isEmpty {
            dayTrend
        }
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
            .foregroundStyle(colors.secondary)
            ForEach(breakdown.perModel) { model in
                GridRow {
                    Text(model.model).lineLimit(1).gridColumnAlignment(.leading)
                    Text(tokenText(model.inputTokens))
                    Text(tokenText(model.outputTokens))
                        .help(model.reasoningTokens > 0 ? "of which reasoning \(model.reasoningTokens.formatted())" : "")
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
        return Text("unpriced").foregroundStyle(colors.warning)
    }

    /// Top 5 projects plus Other; no Total row, the section header has it.
    @ViewBuilder
    private var projectTable: some View {
        let ranking = breakdown.topProjects(byCost: showsCost)
        let showsShare = ranking.top.first?.sharePercent != nil
        if ranking.top.isEmpty {
            Text("No usage in this window").foregroundStyle(colors.secondary)
        } else {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("Project").gridColumnAlignment(.leading)
                    Text("Tokens")
                    if showsCost { Text("Cost") }
                    if showsShare { Text("Share") }
                }
                .foregroundStyle(colors.secondary)
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
                    .foregroundStyle(colors.secondary)
                }
            }
        }
    }

    /// One row per harness: tokens and, in priced breakdowns, cost (spec 006
    /// FR-021). Sorted by the aggregator: cost, then tokens.
    @ViewBuilder
    private var harnessTable: some View {
        if breakdown.perHarness.isEmpty {
            Text("No usage in this window").foregroundStyle(colors.secondary)
        } else {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("Harness").gridColumnAlignment(.leading)
                    Text("Tokens")
                    if showsCost { Text("Cost") }
                }
                .foregroundStyle(colors.secondary)
                ForEach(breakdown.perHarness) { row in
                    GridRow {
                        Text(row.harness.displayName).gridColumnAlignment(.leading)
                        Text(tokenText(row.totalTokens))
                        if showsCost { costText(row.costUSD) }
                    }
                    .monospacedDigit()
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

    /// Minimum width of a day column and the Σ column, and of the header
    /// column in front: a weekly row of 8 days plus Σ with its header (26 pt
    /// + 9 x 28 pt + 9 x 4 pt spacing, 314 pt) fits the Details' width (spec
    /// 026 FR-009a, FR-009b).
    private static let dayColumnWidth: CGFloat = 28
    private static let dayHeaderWidth: CGFloat = 26

    /// One compact column per day of the window: weekday initial (weekly) or
    /// day of the month (monthly) on top, spend (or tokens) below. Days
    /// without usage show 0. Monthly rows wrap after 7 columns; a weekly
    /// window (7 or 8 local days) stays on one row (spec 003 FR-013). The
    /// last row ends with Σ, the sum of all shown days, with its exact value
    /// as tooltip (spec 026 FR-009). Rows and sum come from `DayRowLayout`
    /// and `DayRowTotal`.
    private var dayTrend: some View {
        let days = breakdown.perDay
        let monthly = period == .monthly
        let rows = DayRowLayout.rows(dayCount: days.count, monthly: monthly)
        let sumRow = DayRowLayout.sumRowIndex(dayCount: days.count, monthly: monthly)
        let total = DayRowTotal.make(days: days, showsCost: showsCost, incomplete: incomplete, locale: .autoupdatingCurrent)
        let header = DayRowHeader.make(showsCost: showsCost)
        return Grid(alignment: .top, horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    // "Day" over the unit in front of every row, so wrapped
                    // monthly rows stay aligned (spec 026 FR-009b).
                    VStack(alignment: .leading, spacing: 1) {
                        Text(header.top)
                        Text(header.bottom)
                    }
                    .foregroundStyle(colors.secondary)
                    .frame(minWidth: Self.dayHeaderWidth, alignment: .leading)
                    .help(header.tooltip)
                    ForEach(days[rows[index]]) { day in
                        VStack(spacing: 1) {
                            Text(dayLabel(day))
                                .foregroundStyle(colors.secondary)
                            Text(dayValue(day))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .frame(minWidth: Self.dayColumnWidth)
                        .help(dayHelp(day))
                    }
                    if index == sumRow {
                        VStack(spacing: 1) {
                            Text("\u{03A3}")
                                .foregroundStyle(colors.secondary)
                            Text(total.text)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .frame(minWidth: Self.dayColumnWidth)
                        .help(total.tooltip)
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

    private func dayValue(_ day: DayUsage) -> String {
        if showsCost, let cost = day.costUSD {
            return cost == 0 ? "0" : UsageFormat.compactUSD(cost)
        }
        return day.totalTokens == 0 ? "0" : tokenText(day.totalTokens)
    }

    /// Exact value shown on hover, since the cell rounds.
    /// The day's date with its cost or its tokens in millions (spec 026
    /// FR-009c).
    private func dayHelp(_ day: DayUsage) -> String {
        DayRowHeader.dayTooltip(day, showsCost: showsCost, locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent)
    }
}

/// An (i) icon that shows an explanation in a popover while the pointer is
/// over it.
struct InfoHover: View {
    let text: String
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    @State private var shown = false

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(colors.secondary)
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
