import AppKit
import SwiftUI
import UsageCore

struct DropdownView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    private var configuration: Configuration { model.configuration }
    private var snapshot: UsageSnapshot? { model.snapshot }

    @State private var contentHeight: CGFloat = 0
    @State private var panel: NSWindow?

    private static let width: CGFloat = 360
    private static let maxHeight: CGFloat = 640

    var body: some View {
        // The MenuBarExtra window takes its size when it opens and does not
        // follow later content changes, so expanding a Details section left
        // the top and bottom clipped. The content reports its height, the
        // view resizes the panel itself (anchored at the top), and a scroll
        // view with an explicit height takes over past the cap.
        ScrollView(.vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(width: Self.width, height: panelHeight)
        // Always dark and opaque: over a light desktop the translucent panel
        // made the orange and red status lines unreadable.
        .background(Self.panelBackground)
        .environment(\.colorScheme, .dark)
        .background(WindowAccessor(window: $panel))
        .transaction { $0.animation = nil }
        .onChange(of: panelHeight) { _, height in resizePanel(to: height) }
        .onChange(of: panel) { _, window in
            window?.appearance = NSAppearance(named: .darkAqua)
            window?.backgroundColor = NSColor(Self.panelBackground)
        }
    }

    private static let panelBackground = Color(red: 0.12, green: 0.12, blue: 0.13)

    private var panelHeight: CGFloat {
        min(max(contentHeight, 1), Self.maxHeight)
    }

    private func resizePanel(to height: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        let top = frame.maxY
        let newHeight = height + (frame.height - panel.contentRect(forFrameRect: frame).height)
        frame.size.height = newHeight
        frame.origin.y = top - newHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = snapshot?.configError {
                Label("Configuration error: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if configuration.accounts.isEmpty && configuration.groups.isEmpty {
                Text("No accounts configured. Open Settings to add one.")
                    .foregroundStyle(.secondary)
            }

            ForEach(configuration.subscriptionAccounts) { account in
                SubscriptionSection(account: account, entry: snapshot?.subscriptions[account.id], snapshot: snapshot)
            }

            // Codex plans: tokens only until plan limits exist (spec 006 FR-017).
            ForEach(configuration.codexSubscriptionAccounts) { account in
                CodexPlanSection(account: account, entry: snapshot?.planAccounts[account.id])
            }

            ForEach(configuration.groups) { group in
                BudgetSection(icon: group.icon, name: group.name, members: configuration.members(of: group.id),
                              entry: snapshot?.groups[group.id], snapshot: snapshot)
            }

            // Accounts with their own budget, after the groups in
            // accounts-list order, laid out like a group (spec 004 FR-010).
            ForEach(configuration.tokenBasedAccounts.filter { $0.kind.tokenBased?.ownBudget != nil }) { account in
                BudgetSection(icon: account.icon, name: account.displayName, members: [],
                              entry: snapshot?.accountBudgets[account.id], snapshot: snapshot)
            }

            if let unassigned = snapshot?.unassigned, !unassigned.breakdown.isEmpty {
                UnassignedSection(entry: unassigned, snapshot: snapshot)
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 360)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let at = snapshot?.lastSuccessfulRefreshAt {
                    Text("Last refreshed \(at.formatted(date: .abbreviated, time: .shortened))")
                } else if snapshot == nil {
                    Text("Refreshing…")
                } else {
                    Text("No successful refresh yet")
                }
                Spacer()
                if snapshot?.isStale == true {
                    Text("stale").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let errors = snapshot?.sourceErrors, !errors.isEmpty {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                    Text("\(error.sourceName): \(error.message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Refresh now") { model.refreshNow() }
                Button("Open log") { model.openLog() }
                Spacer()
                Button("Settings…") {
                    // A menu bar app is never active on its own; bring the
                    // settings window to the front.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

/// Hands the hosting window to SwiftUI so the dropdown can resize it.
private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window !== nsView.window {
            DispatchQueue.main.async { window = nsView.window }
        }
    }
}

// MARK: - Shared formatting

enum UsageFormat {
    static func usd(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Whole dollars without a currency suffix, for amounts followed by a
    /// budget that carries it: "1.553".
    static func amount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Whole US dollars with the currency: "1.553 US$".
    static func wholeUSD(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// Tokens in whole millions without a suffix: "838", "1.000"; "<1"
    /// for counts that would round to 0, "0" for none.
    static func millions(_ value: Int) -> String {
        guard value > 0 else { return "0" }
        let millions = Double(value) / 1_000_000
        if millions < 0.5 { return "<1" }
        return Int(millions.rounded()).formatted()
    }

    /// A budget in US$ without decimals when it is whole: "300 US$".
    static func budget(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    /// Whole US dollars without a currency suffix for the narrow day
    /// columns: "409", "1.5K"; "<1" for amounts that would round to 0.
    static func compactUSD(_ value: Decimal) -> String {
        if value > 0 && value < Decimal(string: "0.5")! {
            return "<1"
        }
        if value < 1000 {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func tokens(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func resetText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        // Budget periods reset at local midnight; the time adds nothing there.
        if calendar.startOfDay(for: date) == date {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}

// MARK: - Subscription

struct SubscriptionSection: View {
    let account: Account
    let entry: SubscriptionEntry?
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                labelText(account.icon).bold()
                Text(account.displayName)
                Spacer()
                if let percent = entry?.status?.barPercent {
                    Text(PercentFormatter.text(percent)).bold().monospacedDigit()
                }
            }
            if let status = entry?.status {
                WindowRow(title: "5-hour", window: status.fiveHour)
                WindowRow(title: "7-day", window: status.sevenDay)
                ForEach(status.modelLimits, id: \.modelName) { limit in
                    ModelLimitRow(limit: limit)
                }
            }
            stateLine
            if let entry, !entry.breakdown.isEmpty {
                BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly)
            }
        }
    }

    @ViewBuilder
    private var stateLine: some View {
        switch entry?.state {
        case .ok?:
            EmptyView()
        case .stale(let lastGoodAt, let error)?:
            VStack(alignment: .leading, spacing: 2) {
                if let lastGoodAt {
                    Text("Stale, last good value \(lastGoodAt.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("No data yet")
                }
                Text(error).fixedSize(horizontal: false, vertical: true)
                if let retry = snapshot?.nextRetryAt {
                    Text("Retrying at \(retry.formatted(date: .omitted, time: .shortened))")
                } else if let until = snapshot?.endpointBlockedUntil {
                    Text("Rate limited until \(until.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.caption)
            .foregroundStyle(.orange)
        case .notSignedIn?:
            Text("Not signed in (no Claude Code credentials for \(account.kind.subscription?.credentialDirectory ?? "?"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .credentialsExpired?:
            Text("Credentials expired, run Claude Code to refresh them")
                .font(.caption)
                .foregroundStyle(.orange)
        case nil:
            Text(snapshot == nil ? "Refreshing…" : "No data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A model-scoped weekly limit, such as Fable's share of the 7-day limit.
/// Same layout and font as the 5-hour and 7-day rows.
struct ModelLimitRow: View {
    let limit: ModelLimit

    var body: some View {
        let percent = PercentFormatter.rounded(limit.utilizationPercent)
        HStack {
            Text(limit.modelName).frame(width: 60, alignment: .leading)
            Text(PercentFormatter.text(percent))
                .monospacedDigit()
                .foregroundStyle(percent >= 100 ? Color.red : Color.primary)
                .frame(width: 50, alignment: .trailing)
            Text("resets \(UsageFormat.resetText(limit.resetsAt))")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .help(limit.allowancePercentOfWeekly.map { "\(limit.modelName) weekly limit, \($0)% of the 7-day limit" }
              ?? "\(limit.modelName) weekly limit")
    }
}

struct WindowRow: View {
    let title: String
    let window: LimitWindow?

    var body: some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            if let window {
                Text(PercentFormatter.text(PercentFormatter.rounded(window.utilizationPercent)))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
                if let resetsAt = window.resetsAt {
                    Text("resets \(UsageFormat.resetText(resetsAt))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("not started").foregroundStyle(.secondary)
                }
            } else {
                Text("unavailable").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
    }
}

// MARK: - Budget (group or own budget)

/// A budget group, or a token-based account with its own budget (spec 004
/// FR-010): icon and name, "$X of $Y per <period> (P%)", reset time, the
/// members of a group, the incomplete and stale notes, and the breakdown.
struct BudgetSection: View {
    let icon: String
    let name: String
    /// Group members in accounts-list order; empty for an own budget, whose
    /// breakdown is the account's.
    let members: [Account]
    let entry: GroupEntry?
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                labelText(icon).bold()
                Text(name)
                Spacer()
                if let entry {
                    Text(PercentFormatter.text(entry.percent)).bold().monospacedDigit()
                }
            }
            if let entry {
                HStack {
                    // The percent is in the header; this line stays on one
                    // row: "1.552,81 of 300 US$/month   resets Sun 1. Nov".
                    Text("\(UsageFormat.amount(entry.spentUSD)) of \(UsageFormat.budget(entry.budgetUSD))/\(entry.period == .monthly ? "month" : "week")")
                        .monospacedDigit()
                    Spacer()
                    Text("resets \(UsageFormat.resetText(entry.resetAt))")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .lineLimit(1)
                // Every token-based account is listed with its own summary
                // (FR-004) and, when the group has several members, its own
                // breakdown and trend (FR-008). A single member shares the
                // group's breakdown below.
                ForEach(members) { member in
                    if let account = snapshot?.tokenAccounts[member.id] {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                labelText(member.icon)
                                Text(member.displayName)
                                Spacer()
                                // Share of the budget, as in the bar (spec 004 FR-018a).
                                Text(UsageFormat.wholeUSD(account.breakdown.pricedCostUSD)
                                     + (entry.memberPercent(member.id).map { " (\($0)%)" } ?? "")).monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if members.count > 1 {
                                BreakdownView(breakdown: account.breakdown, showsCost: true, period: entry.period)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                if entry.incomplete {
                    Text("incomplete, unpriced: \(entry.breakdown.unpricedModels.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.stale {
                    Text("stale since \(snapshot?.lastSuccessfulRefreshAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "launch")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                BreakdownView(breakdown: entry.breakdown, showsCost: true, period: entry.period)
            } else {
                Text(snapshot == nil ? "Refreshing…" : "No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Codex plan

/// A Codex subscription account: the week's tokens and their breakdown,
/// without percent, reset time or cost (spec 006 FR-017).
struct CodexPlanSection: View {
    let account: Account
    let entry: TokenAccountEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                labelText(account.icon).bold()
                Text(account.displayName)
                Spacer()
                if let entry {
                    Text("\(UsageFormat.tokens(entry.breakdown.totalTokens)) tokens").monospacedDigit()
                } else {
                    Text("…").foregroundStyle(.secondary)
                }
            }
            Text("Tokens this week through the ChatGPT plan; plan limits are not shown yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry?.stale == true {
                Text("stale").font(.caption).foregroundStyle(.orange)
            }
            if let entry, !entry.breakdown.isEmpty {
                BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly)
            }
        }
    }
}

// MARK: - Unassigned

struct UnassignedSection: View {
    let entry: TokenAccountEntry
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Unassigned")
                Spacer()
                Text("\(UsageFormat.tokens(entry.breakdown.totalTokens)) tokens").monospacedDigit()
            }
            Text("Sessions that match no configured account")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.stale {
                Text("stale").font(.caption).foregroundStyle(.orange)
            }
            BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly)
        }
    }
}
