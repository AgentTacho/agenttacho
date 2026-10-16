import AppKit
import Combine
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
        // The MenuBarExtra keeps its content alive between openings, so
        // `onAppear` fires only on the first one; every later opening makes
        // the panel key (spec 016 FR-012, research R9). A double call on the
        // first opening starts one refresh only.
        .onAppear { model.dropdownOpened() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let panel, note.object as? NSWindow === panel { model.dropdownOpened() }
        }
        .onChange(of: panelHeight) { _, height in resizePanel(to: height) }
        .onChange(of: panel) { _, window in
            window?.appearance = NSAppearance(named: .darkAqua)
            window?.backgroundColor = NSColor(Self.panelBackground)
        }
        // The dropdown closed: a manual check's result leaves the update
        // line (spec 013 FR-003). onDisappear is unreliable for the menu bar
        // window, so the hosting window's key state is watched.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if let panel, (note.object as? NSWindow) === panel {
                model.updater.dismissTransient()
            }
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

    /// The section of one arranged entry: a Claude subscription, a Codex plan
    /// with its limits and the week's tokens (spec 007 FR-011, FR-013), or a
    /// budget laid out like a group, for a group with its members or an
    /// account with its own budget (spec 004 FR-010).
    @ViewBuilder
    private func section(for arranged: ArrangedEntry) -> some View {
        switch arranged {
        case .account(let account):
            switch account.kind {
            case .subscription:
                SubscriptionSection(account: account, entry: snapshot?.subscriptions[account.id], snapshot: snapshot)
            case .codexSubscription:
                CodexPlanSection(account: account, entry: snapshot?.codexPlanTokens[account.id],
                                 limits: snapshot?.codexLimits[account.id], now: snapshot?.generatedAt, snapshot: snapshot)
            case .tokenBased:
                BudgetSection(ownerId: account.id, icon: account.icon, name: account.displayName, isGroup: false, members: [],
                              entry: snapshot?.accountBudgets[account.id], snapshot: snapshot)
            }
        case .group(let group, let members):
            BudgetSection(ownerId: group.id, icon: group.icon, name: group.name, isGroup: true, members: members,
                          entry: snapshot?.groups[group.id], snapshot: snapshot)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = snapshot?.configError {
                Label("Configuration error: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Groups can be empty since spec 009, so only accounts count.
            if configuration.accounts.isEmpty {
                Text("No accounts configured. Open Settings to add one.")
                    .foregroundStyle(.secondary)
            }

            // One section per entry in arrangement order, shown in bar or
            // not; group members in member order (spec 008 FR-003).
            ForEach(configuration.arrangedEntries) { arranged in
                section(for: arranged)
            }

            // Unassigned stays the last section (spec 008 FR-003).
            if let unassigned = snapshot?.unassigned, !unassigned.breakdown.isEmpty {
                UnassignedSection(entry: unassigned, snapshot: snapshot)
            }

            Divider()
            // The quiet update line, above the footer (spec 013 FR-009, FR-010).
            if let line = model.updater.display.lineState {
                UpdateLine(updater: model.updater, state: line)
            }
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
                } else if snapshot == nil || snapshot?.isPreliminary == true {
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

            // One line while a pace is slower than the base (spec 016 FR-016).
            if let pace = model.paceStatus {
                Text(pace.text(now: Date(), calendar: .autoupdatingCurrent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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
                Spacer()
                appMenu
            }
            .controlSize(.small)
            // Menu items show their shortcuts but only fire while the menu is
            // open; these keep ⌘, and ⌘Q working in the open dropdown.
            .background {
                Group {
                    Button("Settings…") { showSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                    Button("Quit AgentMeter") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q", modifiers: .command)
                }
                .hidden()
                .accessibilityHidden(true)
            }
        }
    }

    /// The app-level items in the order of a standard macOS app menu (About,
    /// Settings, Quit; Apple HIG, The menu bar), behind one gear button so
    /// the footer keeps the data action apart from the app actions.
    private var appMenu: some View {
        Menu {
            Button("About AgentMeter") { showSettings(pane: "about") }
            // Runs regardless of the automatic check setting (spec 013 FR-003).
            Button("Check for Updates\u{2026}") { model.updater.checkNow(from: .dropdown) }
                .disabled(model.updater.display.state.isInstallRunning)
            Divider()
            Button("Settings…") { showSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit AgentMeter") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("About, Check for Updates, Settings and Quit")
        .accessibilityLabel("AgentMeter menu")
    }

    /// Opens Settings, optionally on a given tab (Settings remembers its tab
    /// in "settingsPane"). A menu bar app is never active on its own, so the
    /// window is brought to the front.
    private func showSettings(pane: String? = nil) {
        if let pane { UserDefaults.standard.set(pane, forKey: "settingsPane") }
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
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
        // Budget periods reset at local midnight; the time adds nothing there.
        if !calendar.isDateInToday(date), calendar.startOfDay(for: date) == date {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return runOutText(date)
    }

    /// A run-out time (spec 011 FR-009): the time only when it is today,
    /// otherwise weekday, day, month and time. Unlike `resetText` the time
    /// is kept at local midnight.
    static func runOutText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}

/// The pace meter at the end of a window or budget row (spec 011 FR-008,
/// FR-010): a tick for even use, a bar left of it when behind and right of it
/// when ahead, the pace text as tooltip and accessibility label;
/// nothing without a pace, orange with a run-out or a fast burn, secondary
/// otherwise. A fast burn names itself and its run-out in the text, whatever
/// the bar marker toggle says (spec 017 FR-012).
struct PaceMeter: View {
    let pace: Pace?
    /// The row's burn rate (spec 017 FR-012); nil without one.
    var burn: BurnRate? = nil

    static let width: CGFloat = 44

    var body: some View {
        if let pace {
            let color: Color = pace.usesAttentionColor(burn: burn) ? .orange : .secondary
            let half = Self.width / 2
            let length = half * abs(pace.meterOffset)
            let text = pace.summary(runOutText: UsageFormat.runOutText, fastRunOut: burn?.fastRunOut)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(width: Self.width, height: 3)
                Capsule().fill(color).frame(width: length, height: 3)
                    .offset(x: pace.meterOffset >= 0 ? half : half - length)
                Rectangle().fill(color).frame(width: 1.5, height: 10).offset(x: half - 0.75)
            }
            .frame(width: Self.width, height: 10)
            // The whole meter area, not only the drawn bar and tick,
            // shows the tooltip.
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .help(text)
            .accessibilityElement()
            .accessibilityLabel(text)
        }
    }
}

// MARK: - Subscription

struct SubscriptionSection: View {
    let account: Account
    let entry: SubscriptionEntry?
    let snapshot: UsageSnapshot?

    /// The status as shown at the snapshot's time: reset windows show 0%
    /// without a reset time (spec 010 FR-016).
    private var status: SubscriptionStatus? {
        guard let status = entry?.status else { return nil }
        return snapshot.map { status.effective(now: $0.generatedAt) } ?? status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                labelText(account.icon).bold()
                Text(account.displayName)
                Spacer()
                if let percent = status?.barPercent {
                    Text(PercentFormatter.text(percent)).bold().monospacedDigit()
                }
            }
            if let status {
                // Windows whose reset passed show 0% (spec 010 FR-016). Paces
                // at the fetch time; the snapshot time only rules out windows
                // that have reset since (spec 011 FR-002, FR-007).
                let now = snapshot?.generatedAt
                WindowRow(title: "5-hour", window: status.fiveHour, pace: now.flatMap { status.fiveHourPace(now: $0) },
                          burn: snapshot?.burnRate(for: .claude(account.id, .fiveHour)))
                WindowRow(title: "7-day", window: status.sevenDay, pace: now.flatMap { status.sevenDayPace(now: $0) },
                          burn: snapshot?.burnRate(for: .claude(account.id, .sevenDay)))
                ForEach(status.modelLimits, id: \.modelName) { limit in
                    ModelLimitRow(limit: limit, pace: now.flatMap { status.pace(of: limit, now: $0) },
                                  burn: snapshot?.burnRate(for: .claude(account.id, .model(limit.modelName))))
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
        case .retrying(_, let error, let retryAt)?:
            // Neutral grace note, not the stale style (spec 010 FR-005).
            Text("\(GraceNote.reason(claudeError: error)), retrying at \(retryAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .signInRejected(let lastGoodAt)?:
            // Attention style, distinct from the orange stale note (spec 010 FR-010).
            VStack(alignment: .leading, spacing: 2) {
                Text(SignInRejectedNote.text(credentialDirectory: account.kind.subscription?.credentialDirectory ?? Paths.defaultClaudeDirectory))
                    .fixedSize(horizontal: false, vertical: true)
                if let lastGoodAt {
                    Text("Last good value \(lastGoodAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .font(.caption)
            .foregroundStyle(.red)
        case nil:
            Text(snapshot == nil || snapshot?.isPreliminary == true ? "Refreshing…" : "No data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A model-scoped weekly limit, such as Fable's share of the 7-day limit.
/// Same layout and font as the 5-hour and 7-day rows.
struct ModelLimitRow: View {
    let limit: ModelLimit
    /// Shown at the end of the row (spec 011 FR-008).
    var pace: Pace?
    /// The limit's burn rate for the meter text (spec 017 FR-012).
    var burn: BurnRate?

    var body: some View {
        let percent = PercentFormatter.rounded(limit.utilizationPercent)
        HStack {
            // The limit's tooltip covers the text only, so the pace meter
            // keeps its own (spec 011 FR-008).
            HStack {
                Text(limit.modelName).frame(width: 60, alignment: .leading)
                Text(PercentFormatter.text(percent))
                    .monospacedDigit()
                    .foregroundStyle(percent >= 100 ? Color.red : Color.primary)
                    .frame(width: 50, alignment: .trailing)
                // No reset time once the reset passed (spec 010 FR-016).
                if let resetsAt = limit.resetsAt {
                    Text("resets \(UsageFormat.resetText(resetsAt))")
                        .foregroundStyle(.secondary)
                }
            }
            .help(limit.allowancePercentOfWeekly.map { "\(limit.modelName) weekly limit, \($0)% of the 7-day limit" }
                  ?? "\(limit.modelName) weekly limit")
            Spacer()
            PaceMeter(pace: pace, burn: burn)
        }
        .font(.callout)
    }
}

struct WindowRow: View {
    let title: String
    let window: LimitWindow?
    /// Shown at the end of the row (spec 011 FR-008).
    var pace: Pace?
    /// The window's burn rate for the meter text (spec 017 FR-012).
    var burn: BurnRate?

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
            PaceMeter(pace: pace, burn: burn)
        }
        .font(.callout)
    }
}

// MARK: - Budget (group or own budget)

/// A budget group, or a token-based account with its own budget (spec 004
/// FR-010): icon and name, "$X of $Y per <period> (P%)", reset time, the
/// members of a group, the incomplete and stale notes, and the breakdown.
/// A group without members keeps the header and shows a note instead of
/// members, breakdown and trend (spec 009 FR-005).
struct BudgetSection: View {
    /// The group id, or the account id of an own budget: the key of the
    /// budget's burn rate (spec 017 FR-012).
    let ownerId: String
    let icon: String
    let name: String
    /// True for a budget group. An own budget also passes no members, so
    /// only this tells an empty group apart from it (spec 009 FR-005).
    let isGroup: Bool
    /// Group members in member order (spec 008 FR-003); empty for an own
    /// budget, whose breakdown is the account's, and for an empty group.
    let members: [Account]
    let entry: GroupEntry?
    let snapshot: UsageSnapshot?

    private var isEmptyGroup: Bool { isGroup && members.isEmpty }

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
                    // The budget's pace at the snapshot time; never for
                    // member lines (spec 011 FR-008, FR-011).
                    PaceMeter(pace: snapshot.flatMap { entry.pace(now: $0.generatedAt) },
                              burn: snapshot?.burnRate(for: isGroup ? .group(ownerId) : .accountBudget(ownerId)))
                }
                .font(.callout)
                .lineLimit(1)
                if isEmptyGroup {
                    Text("No accounts in this group yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                if !isEmptyGroup {
                    BreakdownView(breakdown: entry.breakdown, showsCost: true, period: entry.period)
                }
            } else {
                // The early result from saved values has no budgets yet (spec 010 FR-015).
                Text(snapshot == nil || snapshot?.isPreliminary == true ? "Refreshing…" : "No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Codex plan

/// A Codex subscription account (spec 007 FR-011, FR-013): the percent of
/// the longest window in the header, every plan window with its percent,
/// reset time and limit-reached note, the plan type, where the values come
/// from, then the week's tokens and their breakdown (spec 006 FR-017).
struct CodexPlanSection: View {
    let account: Account
    let entry: TokenAccountEntry?
    let limits: CodexLimitsEntry?
    /// The snapshot's time, so reset windows show 0% (FR-010).
    let now: Date?
    /// For the windows' burn rates (spec 017 FR-012).
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                labelText(account.icon).bold()
                Text(account.displayName)
                Spacer()
                if let limits, let now, let percent = limits.barPercent(now: now) {
                    Text(PercentFormatter.text(percent)).bold().monospacedDigit()
                } else if limits == nil {
                    Text("…").foregroundStyle(.secondary)
                }
            }
            if let limits, let now {
                // Each window's pace at the observation time (spec 011 FR-002).
                ForEach(limits.windows(now: now), id: \.name) { window in
                    CodexWindowRow(window: window, pace: limits.pace(of: window, now: now),
                                   burn: snapshot?.burnRate(for: .codex(account.id, window.name)))
                }
                if let plan = CodexLimitsEntry.planDisplayName(limits.observation?.planType) {
                    Text("ChatGPT \(plan) plan").font(.caption).foregroundStyle(.secondary)
                }
                stateLine(limits)
            }
            HStack {
                Text("Tokens this week")
                Spacer()
                if let entry {
                    Text("\(UsageFormat.tokens(entry.breakdown.totalTokens)) tokens").monospacedDigit()
                } else {
                    Text("…")
                }
            }
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

    /// Live values need no note; stale values name their time and reason,
    /// local-only values and a newer snapshot between fetches their time
    /// (not a failure, FR-006).
    @ViewBuilder
    private func stateLine(_ limits: CodexLimitsEntry) -> some View {
        let observed = limits.observation.map { $0.observedAt.formatted(date: .abbreviated, time: .shortened) } ?? "?"
        switch limits.state {
        case .live:
            EmptyView()
        case .newerSnapshot:
            Text("As of \(observed)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .stale(let reason):
            // A rejected sign-in uses the attention style (spec 010 FR-012).
            Text("Stale, as of \(observed): \(reason)")
                .font(.caption)
                .foregroundStyle(limits.signInRejected ? .red : .orange)
                .fixedSize(horizontal: false, vertical: true)
        case .localOnly:
            Text("Local data, as of \(observed)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(limits.signInRejected ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .retrying(let reason, let retryAt):
            // Neutral grace note, not the stale style (spec 010 FR-005).
            Text("\(GraceNote.reason(codexReason: reason)), retrying at \(retryAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One Codex plan window: its name, percent and reset time, and a "Limit
/// reached" note. A window without a reset time (reset since the
/// observation, FR-010) shows no reset text.
struct CodexWindowRow: View {
    let window: CodexLimitWindow
    /// Shown at the end of the row (spec 011 FR-008).
    var pace: Pace?
    /// The window's burn rate for the meter text (spec 017 FR-012).
    var burn: BurnRate?

    var body: some View {
        let percent = PercentFormatter.rounded(window.usedPercent)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(window.name).frame(width: 60, alignment: .leading)
                Text(PercentFormatter.text(percent))
                    .monospacedDigit()
                    .foregroundStyle(percent >= 100 || window.limitReached ? Color.red : Color.primary)
                    .frame(width: 50, alignment: .trailing)
                if let resetsAt = window.resetsAt {
                    Text("resets \(UsageFormat.resetText(resetsAt))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PaceMeter(pace: pace, burn: burn)
            }
            .font(.callout)
            if window.limitReached {
                Text("Limit reached").font(.caption).foregroundStyle(.red)
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
