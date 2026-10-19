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
    /// True while the panel is open: from its first `onAppear` or its
    /// becoming key until it resigns key (spec 025 FR-020).
    @State private var isOpen = false
    /// The reference time of every section and the footer (spec 025
    /// FR-020): set when the panel opens and every 30 s while it is open.
    @State private var now = Date()

    private static let width: CGFloat = 360
    private static let maxHeight: CGFloat = 640

    var body: some View {
        // The MenuBarExtra window takes its size when it opens and does not
        // follow later content changes, so expanding a Details section left
        // the top and bottom clipped. The content reports its height, the
        // view resizes the panel itself (anchored at the top), and a scroll
        // view with an explicit height takes over past the cap. Its scroll
        // indicator is hidden: a legacy scrollbar takes width once the cap is
        // passed and shifted the content left when Details opened (spec 025
        // FR-001, walkthrough step 4).
        ScrollView(.vertical, showsIndicators: false) {
            content(now: now)
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
        .onAppear { opened() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let panel, note.object as? NSWindow === panel { opened() }
        }
        // Relative times count down and absolute times switch form at a day
        // change while the dropdown stays open, without a refresh (spec 025
        // FR-020, research R8). The panel's content stays alive while it is
        // hidden, so the 30 s updates run only while it is open: closing
        // cancels this task, and opening sets `now` at once and starts it
        // again.
        .task(id: isOpen) {
            guard isOpen else { return }
            while true {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                now = Date()
            }
        }
        .onChange(of: panelHeight) { _, height in resizePanel(to: height) }
        .onChange(of: panel) { _, window in
            window?.appearance = NSAppearance(named: .darkAqua)
            window?.backgroundColor = NSColor(Self.panelBackground)
        }
        // The dropdown closed: a failed install reported by the previous run
        // leaves the update line (spec 013); the dropdown starts no check of
        // its own since spec 025 FR-028. onDisappear is unreliable for the
        // menu bar window, so the hosting window's key state is watched.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if let panel, (note.object as? NSWindow) === panel {
                isOpen = false
                model.updater.dismissTransient()
            }
        }
    }

    /// The panel opened: times are current at once, the 30 s updates start
    /// (spec 025 FR-020), and the model hears of the opening (spec 016
    /// FR-012).
    private func opened() {
        now = Date()
        isOpen = true
        model.dropdownOpened()
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
    private func section(for arranged: ArrangedEntry, now: Date) -> some View {
        let times = times(for: arranged, now: now)
        switch arranged {
        case .account(let account):
            switch account.kind {
            case .subscription:
                SubscriptionSection(account: account, entry: snapshot?.subscriptions[account.id], snapshot: snapshot, times: times)
            case .codexSubscription:
                CodexPlanSection(account: account, entry: snapshot?.codexPlanTokens[account.id],
                                 limits: snapshot?.codexLimits[account.id], now: snapshot?.generatedAt, snapshot: snapshot, times: times)
            case .tokenBased:
                BudgetSection(ownerId: account.id, icon: account.icon, name: account.displayName, isGroup: false, members: [],
                              entry: snapshot?.accountBudgets[account.id], snapshot: snapshot, times: times,
                              isShotTarget: shotOwner.map { $0.kind == .account && $0.id == account.id } ?? false)
            }
        case .group(let group, let members):
            BudgetSection(ownerId: group.id, icon: group.icon, name: group.name, isGroup: true, members: members,
                          entry: snapshot?.groups[group.id], snapshot: snapshot, times: times,
                          isShotTarget: shotOwner.map { $0.kind == .group && $0.id == group.id } ?? false)
        }
    }

    /// The reset and run-out times of a section in its own time format, the
    /// account's or the group's, at the reference time `now` (spec 025
    /// FR-016, FR-020). Tooltips show the other form (FR-019).
    private func times(for arranged: ArrangedEntry, now: Date) -> TimeText {
        TimeText(format: configuration.timeFormat(for: arranged), now: now,
                 calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
    }

    /// The budget whose row and details the screenshot capture crops
    /// (spec 024 FR-019).
    private var shotOwner: BudgetOwner? {
        BarLayout.shotBudgetOwner(snapshot: snapshot, configuration: configuration)
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            #if AGENTTACHO_DEMO
            // A scenario that could not be played (spec 024 FR-013).
            if let error = model.demoScenarioError {
                Label("Demo scenario error: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
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
            // not; group members in member order (spec 008 FR-003). A
            // divider separates each pair of sections, none above the first
            // (spec 025 FR-011).
            let entries = configuration.arrangedEntries
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, arranged in
                if index > 0 {
                    Divider()
                }
                section(for: arranged, now: now)
            }

            // Unassigned stays the last section (spec 008 FR-003).
            if let unassigned = snapshot?.unassigned, !unassigned.breakdown.isEmpty {
                if !entries.isEmpty {
                    Divider()
                }
                UnassignedSection(entry: unassigned, snapshot: snapshot)
            }

            // One divider before the footer (FR-011).
            Divider()
            footer(now: now)
        }
        .padding(12)
        .frame(width: 360)
    }

    /// The footer in a fixed order (spec 025 FR-023 to FR-028,
    /// contracts/dropdown-ui.md "Footer"): source errors, the quiet update
    /// line, "Last refreshed" as the last text line, then the icon row. There
    /// is no gear menu: About and "Check for Updates…" live in Settings >
    /// About (FR-028, spec 020), so the dropdown never starts an update
    /// check and its transient result never reaches the line (FR-026).
    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errors = snapshot?.sourceErrors, !errors.isEmpty {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                    Text("\(error.sourceName): \(error.message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The quiet update line (spec 013 FR-009, FR-010).
            if let line = model.updater.display.lineState {
                UpdateLine(updater: model.updater, state: line)
            }
            lastRefreshedLine(now: now)
            iconRow
        }
    }

    /// "Last refreshed 16:54" with the "stale" marker (FR-024). While a pace
    /// is slower than its base, the pace line text of spec 019 is its
    /// tooltip and accessibility value instead of a line of its own (FR-025).
    private func lastRefreshedLine(now: Date) -> some View {
        let paceText = FooterText.paceTooltip(model.paceStatus, now: now, calendar: .autoupdatingCurrent)
        return HStack {
            Text(FooterText.lastRefreshed(at: snapshot?.lastSuccessfulRefreshAt, hasSnapshot: snapshot != nil,
                                          isPreliminary: snapshot?.isPreliminary == true, now: now,
                                          calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent))
            Spacer()
            if snapshot?.isStale == true {
                Text("stale").foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .optionalHelp(paceText)
        .accessibilityElement(children: .combine)
        .accessibilityValue(paceText ?? "")
    }

    /// Refresh on the left, Settings and Quit on the right, as icons with a
    /// tooltip and an accessibility label each; ⌘, and ⌘Q work while the
    /// dropdown is open (FR-027). The capture opens Settings through the
    /// Settings button (spec 024 FR-019, spec 025 FR-035).
    private var iconRow: some View {
        HStack(spacing: 10) {
            iconButton("arrow.clockwise", label: "Refresh now", identifier: "agenttacho.refreshButton") {
                model.refreshNow()
            }
            Spacer()
            iconButton("gearshape", label: "Settings\u{2026}", identifier: "agenttacho.settingsButton") {
                showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            iconButton("power", label: "Quit AgentTacho", identifier: "agenttacho.quitButton") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func iconButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Opens Settings. A menu bar app is never active on its own, so the
    /// window is brought to the front.
    private func showSettings() {
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
}

extension View {
    /// An accessibility identifier the screenshot capture finds the view by
    /// (spec 024 FR-019); nothing when nil. Invisible in every build.
    @ViewBuilder
    func shotIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    /// The view as one accessibility container with an identifier, so the
    /// capture can read its frame (spec 024 FR-019); unchanged when nil.
    @ViewBuilder
    func shotContainer(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

// MARK: - Subscription

struct SubscriptionSection: View {
    let account: Account
    let entry: SubscriptionEntry?
    let snapshot: UsageSnapshot?
    /// The section's reset and run-out times (spec 025 FR-016).
    let times: TimeText

    /// The status as shown at the snapshot's time: reset windows show 0%
    /// without a reset time (spec 010 FR-016).
    private var status: SubscriptionStatus? {
        guard let status = entry?.status else { return nil }
        return snapshot.map { status.effective(now: $0.generatedAt) } ?? status
    }

    /// The bar of one window from its pace reading, the one value its tick,
    /// note and color come from (spec 025 FR-030). Paces are at the fetch
    /// time; the snapshot time only rules out windows that have reset since
    /// (spec 011 FR-002, FR-007).
    private func bar(_ usedPercent: Double, _ window: ClaudeWindow) -> RowBar {
        RowBar.make(usedPercent: usedPercent, limitReached: false,
                    reading: snapshot?.paceReading(for: .claude(account.id, window)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The plan with its windows, the `plan-limits` shot (spec 024 FR-019).
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    labelText(account.icon).bold()
                    Text(account.displayName)
                    Spacer()
                    if let percent = status?.barPercent {
                        Text(PercentFormatter.text(percent)).bold().monospacedDigit()
                    }
                }
                if let status {
                    // Windows whose reset passed show 0% without a reset
                    // text (spec 010 FR-016); a window that never started
                    // reads "not started" (spec 025 FR-008).
                    WindowRow(title: "5-hour", window: status.fiveHour,
                              fetchedWithReset: entry?.status?.fiveHour?.resetsAt != nil,
                              bar: status.fiveHour.map { bar($0.utilizationPercent, .fiveHour) }, times: times)
                    // The `pace` shot crops this row with its note (spec 025 FR-035).
                    WindowRow(title: "7-day", window: status.sevenDay,
                              fetchedWithReset: entry?.status?.sevenDay?.resetsAt != nil,
                              bar: status.sevenDay.map { bar($0.utilizationPercent, .sevenDay) }, times: times,
                              identifier: "agenttacho.paceRow")
                    ForEach(status.modelLimits, id: \.modelName) { limit in
                        ModelLimitRow(limit: limit, bar: bar(limit.utilizationPercent, .model(limit.modelName)), times: times)
                    }
                }
            }
            .shotContainer("agenttacho.claudePlan")
            stateLine
            if let entry, !entry.breakdown.isEmpty {
                BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly,
                              totalLine: DetailsTotal.weekly(tokens: entry.breakdown.totalTokens, locale: .autoupdatingCurrent))
            }
        }
    }

    /// The section's notes with their styles from UsageCore (spec 025
    /// FR-015, FR-029).
    private var stateLine: some View {
        SectionNotesView(notes: SectionNote.claude(
            state: entry?.state,
            credentialDirectory: account.kind.subscription?.credentialDirectory ?? Paths.defaultClaudeDirectory,
            isPreliminary: snapshot == nil || snapshot?.isPreliminary == true,
            nextRetryAt: snapshot?.nextRetryAt, endpointBlockedUntil: snapshot?.endpointBlockedUntil,
            dates: .current))
    }
}

/// Section notes in their style: neutral in the secondary color, warning in
/// orange, alert in red, wrapping instead of truncating (spec 025 FR-015,
/// FR-029). The texts and styles come from `SectionNote`.
struct SectionNotesView: View {
    let notes: [SectionNote]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    Text(note.text)
                        .foregroundStyle(note.style.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
        }
    }
}

extension NoteStyle {
    var color: Color {
        switch self {
        case .neutral: Color.secondary
        case .warning: Color.orange
        case .alert: Color.red
        }
    }
}

extension NoteDates {
    /// The user's locale and time zone.
    static var current: NoteDates {
        NoteDates(locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent)
    }
}

/// A model-scoped weekly limit, such as Fable's share of the 7-day limit,
/// in the layout of the 5-hour and 7-day rows. Model limits are only
/// reported with a reset time, so one without it has reset since and shows
/// no reset text (spec 010 FR-016). The limit's tooltip covers its name
/// only, so the reset time keeps its own (spec 025 FR-019a).
struct ModelLimitRow: View {
    let limit: ModelLimit
    let bar: RowBar
    let times: TimeText

    var body: some View {
        LimitRowLayout(name: limit.modelName,
                       nameHelp: limit.allowancePercentOfWeekly.map { "\(limit.modelName) weekly limit, \($0)% of the 7-day limit" }
                           ?? "\(limit.modelName) weekly limit",
                       percent: PercentFormatter.rounded(limit.utilizationPercent), bar: bar,
                       resetsAt: limit.resetsAt, observedWithReset: true, times: times)
    }
}

/// A Claude 5-hour or 7-day window: "unavailable" without a window, "not
/// started" without a reset time, no reset text once the reset passed
/// (spec 010 FR-016, spec 025 FR-008).
struct WindowRow: View {
    let title: String
    /// The window as shown at the snapshot time; nil when unavailable.
    let window: LimitWindow?
    /// True when the fetched window has a reset time: a shown window without
    /// one has reset since the fetch (spec 010 FR-016) and is not "not started".
    var fetchedWithReset = false
    let bar: RowBar?
    let times: TimeText
    /// The row's identifier for the screenshot capture (spec 024 FR-019).
    var identifier: String? = nil

    var body: some View {
        LimitRowLayout(name: title, percent: window.map { PercentFormatter.rounded($0.utilizationPercent) }, bar: bar,
                       resetsAt: window?.resetsAt, observedWithReset: fetchedWithReset, times: times,
                       identifier: identifier)
    }
}

/// One limit window in layout B (spec 025 FR-001 to FR-008,
/// contracts/dropdown-ui.md): name, percent and reset text on one line, the
/// bar below, and the orange note only when the row calls for attention. The
/// percent is red over the limit in every row (FR-007). The reset text shows
/// the other time form as its tooltip (FR-019); the bar has no tooltip
/// (FR-005). The row is one accessibility element naming the window, the
/// percent, the reset text and the pace summary (FR-006). The reset text,
/// its tooltip and the label come from `RowText` in UsageCore.
struct LimitRowLayout: View {
    let name: String
    /// The tooltip of the name only (FR-019a).
    var nameHelp: String? = nil
    /// The rounded percent; nil for an unavailable window, which shows no bar.
    let percent: Int?
    let bar: RowBar?
    let resetsAt: Date?
    /// False for a window observed without a reset time, which reads "not
    /// started"; true when a missing reset time means the window has reset
    /// since the observation, which shows no reset text (FR-008).
    let observedWithReset: Bool
    /// A reached Codex limit keeps its "Limit reached" text (FR-007).
    var limitReached = false
    let times: TimeText
    var identifier: String? = nil

    private var isOverLimit: Bool { bar?.tone == .overLimit }

    private var text: RowText {
        RowText.window(name: name, percent: percent, resetsAt: resetsAt, observedWithReset: observedWithReset,
                       limitReached: limitReached, bar: bar, times: times)
    }

    var body: some View {
        let text = self.text
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .frame(width: 60, alignment: .leading)
                    .optionalHelp(nameHelp)
                if let percent {
                    Text(PercentFormatter.text(percent))
                        .monospacedDigit()
                        .foregroundStyle(isOverLimit ? Color.red : Color.primary)
                        .frame(width: 50, alignment: .trailing)
                    Spacer()
                    if let reset = text.reset {
                        Text(reset)
                            .foregroundStyle(.secondary)
                            .optionalHelp(text.resetTooltip)
                    }
                } else {
                    Text("unavailable").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .font(.callout)
            .lineLimit(1)
            if percent != nil, let bar {
                RowBarView(bar: bar)
            }
            PaceNoteText(note: bar?.note, times: times)
            if limitReached {
                Text("Limit reached").font(.caption).foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
        .shotIdentifier(identifier)
    }
}

extension View {
    /// A tooltip when `text` is set; unchanged otherwise.
    @ViewBuilder
    func optionalHelp(_ text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}

// MARK: - Budget (group or own budget)

/// A budget group, or a token-based account with its own budget (spec 004
/// FR-010): icon, name and percent, the amount line with the reset time, the
/// bar with the budget's pace tick and note (spec 025 FR-009), the members
/// of a group, the incomplete and stale notes, and the breakdown. A group
/// without members keeps the header and shows a note instead of members,
/// breakdown and trend (spec 009 FR-005).
struct BudgetSection: View {
    /// The group id, or the account id of an own budget: the key of the
    /// budget's pace reading (spec 025 FR-030).
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
    /// The section's reset and run-out times (spec 025 FR-016).
    let times: TimeText
    /// The budget the screenshot capture crops: its row and details carry
    /// the capture's identifiers (spec 024 FR-019).
    var isShotTarget = false

    private var isEmptyGroup: Bool { isGroup && members.isEmpty }

    /// The incomplete-prices and stale notes of the budget (spec 025 FR-029).
    private func notes(_ entry: GroupEntry) -> [SectionNote] {
        var notes: [SectionNote] = []
        if entry.incomplete { notes.append(.budgetIncomplete(unpricedModels: entry.breakdown.unpricedModels)) }
        if entry.stale { notes.append(.budgetStale(since: snapshot?.lastSuccessfulRefreshAt, dates: .current)) }
        return notes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header and amount line, the `budget` shot (spec 024 FR-019).
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
                    // The budget's pace at the snapshot time; never for
                    // member lines (spec 011 FR-008, FR-011). The bar is red
                    // exactly when the header's percent is 100 or more
                    // (spec 025 FR-003, FR-009).
                    BudgetBarRow(name: name, entry: entry,
                                 bar: RowBar.budget(entry, reading: snapshot?.paceReading(for: isGroup ? .group(ownerId) : .accountBudget(ownerId))),
                                 times: times)
                }
            }
            .shotContainer(isShotTarget ? "agenttacho.budgetRow" : nil)
            if let entry {
                if isEmptyGroup {
                    SectionNotesView(notes: [.emptyGroup])
                }
                // With two or more members every token-based account is
                // listed with its own summary (spec 004 FR-004) and its own
                // breakdown and trend (FR-008). A single member's line would
                // repeat the group's amount, so it is left out and the
                // member shares the group's breakdown below (spec 025 FR-010).
                if members.count >= 2 {
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
                                BreakdownView(breakdown: account.breakdown, showsCost: true, period: entry.period)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                SectionNotesView(notes: notes(entry))
                if !isEmptyGroup {
                    BreakdownView(breakdown: entry.breakdown, showsCost: true, period: entry.period, isShotTarget: isShotTarget)
                }
            } else {
                // The early result from saved values has no budgets yet (spec 010 FR-015).
                SectionNotesView(notes: [.noData(isPreliminary: snapshot == nil || snapshot?.isPreliminary == true)])
            }
        }
    }
}

/// A budget's amount line with the reset time right-aligned, its bar with
/// the spend share and the pace tick, and the orange note on attention
/// (spec 025 FR-009, contracts/dropdown-ui.md "Budget section"). One
/// accessibility element naming the budget, the amount, the reset time and
/// the pace summary (FR-006).
struct BudgetBarRow: View {
    let name: String
    let entry: GroupEntry
    let bar: RowBar
    let times: TimeText

    /// "1,596 of 300 US$/month".
    private var amountText: String {
        "\(UsageFormat.amount(entry.spentUSD)) of \(UsageFormat.budget(entry.budgetUSD))/\(entry.period == .monthly ? "month" : "week")"
    }

    var body: some View {
        let amount = amountText
        let text = RowText.budget(name: name, amount: amount, resetsAt: entry.resetAt, bar: bar, times: times)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                // The percent is in the header; this line stays on one row.
                Text(amount).monospacedDigit()
                Spacer()
                if let reset = text.reset {
                    Text(reset)
                        .foregroundStyle(.secondary)
                        .optionalHelp(text.resetTooltip)
                }
            }
            .font(.callout)
            .lineLimit(1)
            RowBarView(bar: bar)
            PaceNoteText(note: bar.note, times: times)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }
}

/// The orange note under a bar that calls for attention, with its run-out
/// in the other time form as tooltip (spec 025 FR-004, FR-019); nothing
/// without a note.
struct PaceNoteText: View {
    let note: PaceNote?
    let times: TimeText

    var body: some View {
        if let note {
            Text(note.text(times: times))
                .font(.caption)
                .foregroundStyle(.orange)
                .help(note.tooltip(times: times))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Codex plan

/// A Codex subscription account (spec 007 FR-011, FR-013): the percent of
/// the longest window in the header, every plan window with its percent, reset time, bar and
/// limit-reached note, where the values come from, then the breakdown of
/// the week's tokens (spec 006 FR-017). The plan type and "Tokens this
/// week" lines are gone; the total heads the Details (spec 025 FR-013,
/// FR-014).
struct CodexPlanSection: View {
    let account: Account
    let entry: TokenAccountEntry?
    let limits: CodexLimitsEntry?
    /// The snapshot's time, so reset windows show 0% (FR-010).
    let now: Date?
    /// For the windows' pace readings (spec 025 FR-030).
    let snapshot: UsageSnapshot?
    /// The section's reset and run-out times (spec 025 FR-016).
    let times: TimeText

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
                // Each window's bar from its pace reading at the observation
                // time (spec 011 FR-002, spec 025 FR-030).
                ForEach(limits.windows(now: now), id: \.name) { window in
                    CodexWindowRow(window: window,
                                   fetchedWithReset: limits.observedWithReset(window.name),
                                   bar: RowBar.make(usedPercent: window.usedPercent, limitReached: window.limitReached,
                                                    reading: snapshot?.paceReading(for: .codex(account.id, window.name))),
                                   times: times)
                }
                stateLine(limits)
            }
            if entry?.stale == true {
                SectionNotesView(notes: [.staleMarker])
            }
            if let entry, !entry.breakdown.isEmpty {
                BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly,
                              totalLine: DetailsTotal.weekly(tokens: entry.breakdown.totalTokens, locale: .autoupdatingCurrent))
            }
        }
    }

    /// Live values need no note; stale values name their time and reason,
    /// local-only values and a newer snapshot between fetches their time
    /// (not a failure, spec 007 FR-006). Text and style come from
    /// `SectionNote` (spec 025 FR-029).
    private func stateLine(_ limits: CodexLimitsEntry) -> some View {
        SectionNotesView(notes: SectionNote.codex(limits, dates: .current).map { [$0] } ?? [])
    }
}

/// One Codex plan window: its name, percent and reset time, its bar, and a
/// "Limit reached" note (spec 007 FR-012, spec 025 FR-007). A window that
/// reset since the observation (spec 007 FR-010) shows no reset text; one
/// reported without a reset time reads "not started" (spec 025 FR-008).
struct CodexWindowRow: View {
    /// The effective window at the snapshot time.
    let window: CodexLimitWindow
    /// True when the observed window has a reset time: an effective window
    /// without one has reset since the observation.
    var fetchedWithReset = false
    let bar: RowBar
    let times: TimeText

    var body: some View {
        LimitRowLayout(name: window.name, percent: PercentFormatter.rounded(window.usedPercent), bar: bar,
                       resetsAt: window.resetsAt, observedWithReset: fetchedWithReset,
                       limitReached: window.limitReached, times: times)
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
                SectionNotesView(notes: [.staleMarker])
            }
            BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly)
        }
    }
}
