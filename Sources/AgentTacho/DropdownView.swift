import AppKit
import Combine
import SwiftUI
import UsageCore

struct DropdownView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    /// "Increase contrast" draws the bands stronger (spec 028 FR-006).
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var configuration: Configuration { model.configuration }
    private var snapshot: UsageSnapshot? { model.snapshot }

    /// The measured heights of the scrolling sections and of the pinned
    /// footer (spec 026 FR-010, FR-011).
    @State private var sectionsHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    /// The distance from the panel's top edge to the bottom of its screen's
    /// visible frame, nil while unknown (spec 026 FR-010a).
    @State private var availableHeight: CGFloat?
    @State private var panel: NSWindow?
    /// True while the panel is open: from its first `onAppear` or its
    /// becoming key until it resigns key (spec 025 FR-020).
    @State private var isOpen = false
    /// The reference time of every section and the footer (spec 025
    /// FR-020): set when the panel opens and every 30 s while it is open.
    @State private var now = Date()
    /// True while the system is in dark appearance, for the Auto theme
    /// (spec 032 FR-006, research R1). Read from the app, which never sets
    /// its own appearance, so forcing the panel's appearance does not feed
    /// back into it.
    @State private var systemIsDark = DropdownView.systemAppearanceIsDark(NSApp.effectiveAppearance)

    private static let width: CGFloat = 360
    /// The content's inset from the panel's sides, top and bottom edges.
    private static let inset: CGFloat = 12
    /// The space between a band's edge and its content, top and bottom
    /// (spec 028 FR-004).
    private static let bandPadding: CGFloat = 10

    var body: some View {
        // The MenuBarExtra window takes its size when it opens and does not
        // follow later content changes, so expanding a Details section left
        // the top and bottom clipped. The sections and the footer report
        // their heights, the view resizes the panel itself (anchored at the
        // top), and the sections' scroll view gets an explicit height that
        // takes over past the cap. The footer sits below the scroll view, so
        // it never scrolls away (spec 026 FR-010). The scroll indicator is
        // hidden: a legacy scrollbar takes width once the cap is passed and
        // shifted the content left when Details opened (spec 025 FR-001,
        // walkthrough step 4; spec 026 FR-015).
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                // The bands span the full width, so the sections carry their
                // own horizontal inset; the first content stays 12 pt below
                // the top edge, and the last band meets the footer's
                // (spec 028 FR-004, research R4).
                sections(now: now)
                    .padding(.top, Self.inset - Self.bandPadding)
                    .frame(width: Self.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sectionsHeight = $0 }
            }
            .frame(width: Self.width, height: scrollHeight)
            // The measured height includes the footer band's padding (spec
            // 028 FR-004, FR-007).
            pinnedFooter(now: now)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .frame(width: Self.width, height: panelHeight, alignment: .top)
        // Opaque in every theme: over a light desktop the translucent panel
        // made the orange and red status lines unreadable. The theme picks
        // the light or the dark panel, Auto by the system appearance, and
        // every part of the dropdown follows it at once (spec 032 FR-006,
        // FR-007, FR-012).
        .background(Color(palette.background))
        .environment(\.dropdownColors, colors)
        .environment(\.colorScheme, panelStyle.isDark ? .dark : .light)
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
            applyPanelStyle(to: window)
            measureScreenRoom()
        }
        // A system switch (Auto) or a theme change in Settings reaches an
        // open panel without closing it (spec 032 FR-004, FR-006).
        .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { appearance in
            systemIsDark = Self.systemAppearanceIsDark(appearance)
        }
        .onChange(of: panelStyle) { _, _ in applyPanelStyle(to: panel) }
        // Another display, resolution or Dock size changes the room below
        // the panel's top (spec 026 FR-010a).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            measureScreenRoom()
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
        // A switch while the panel was hidden reaches the window before it
        // is drawn again (spec 032 FR-004, FR-006).
        applyPanelStyle(to: panel)
        measureScreenRoom()
        model.dropdownOpened()
    }

    /// Measures the room from the panel's top edge to the bottom of its
    /// screen's visible frame (Dock and menu bar excluded), on the main
    /// screen when the panel has none, and nil when no screen or panel is
    /// known, which keeps the 640 pt cap (spec 026 FR-010a).
    private func measureScreenRoom() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else {
            availableHeight = nil
            return
        }
        availableHeight = panel.frame.maxY - screen.visibleFrame.minY
    }

    /// The panel the theme resolves to now (spec 032 FR-006).
    private var panelStyle: PanelStyle {
        configuration.dropdownTheme.panelStyle(systemIsDark: systemIsDark)
    }

    /// The colors of the current panel (spec 032 FR-007 to FR-011).
    private var palette: DropdownPalette {
        DropdownPalette.forStyle(panelStyle)
    }

    /// The text colors of the top lines and the footer. The body injects
    /// the same colors for the sections; a view does not see what it injects
    /// into its own body, so they come from the palette here (spec 032
    /// FR-007, FR-012).
    private var colors: DropdownColors {
        DropdownColors.forStyle(panelStyle)
    }

    private static func systemAppearanceIsDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The window's appearance and background follow the panel style, so the
    /// parts AppKit draws (tooltips, focus rings) and the window behind the
    /// content match it (spec 032 FR-006, FR-012, research R1).
    private func applyPanelStyle(to window: NSWindow?) {
        window?.appearance = NSAppearance(named: panelStyle.isDark ? .darkAqua : .aqua)
        window?.backgroundColor = NSColor(Color(palette.background))
    }

    /// The sections' visible height: all of them below the cap, otherwise
    /// what the cap leaves above the footer, but never less than 160 pt
    /// unless the screen room is smaller than footer plus 160 pt (spec 026
    /// FR-010a, FR-011, `FooterLayout`).
    private var scrollHeight: CGFloat {
        let available = availableHeight.map(Double.init)
        return CGFloat(FooterLayout.sectionsHeight(content: sectionsHeight, footer: footerHeight,
                                                   cap: FooterLayout.cap(available: available),
                                                   room: FooterLayout.room(available: available)))
    }

    /// Sections plus footer: exactly their height below the cap, so there
    /// is no empty space (spec 026 FR-010).
    private var panelHeight: CGFloat {
        max(scrollHeight + footerHeight, 1)
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
            case .subscription(let settings):
                let entry = snapshot?.subscriptions[account.id]
                SubscriptionSection(account: account, entry: entry, snapshot: snapshot, times: times,
                                    direction: configuration.displayDirection,
                                    shotIndex: shotClaudeAccountIds.firstIndex(of: account.id),
                                    headline: HeadlineWindow.claude(accountId: account.id, status: entry?.status,
                                                                    choice: settings.headlineWindow, now: snapshot?.generatedAt ?? now),
                                    onSelect: { model.setHeadline(accountId: account.id, choice: $0) })
            case .codexSubscription(let settings):
                let limits = snapshot?.codexLimits[account.id]
                CodexPlanSection(account: account, entry: snapshot?.codexPlanTokens[account.id],
                                 limits: limits, now: snapshot?.generatedAt, snapshot: snapshot, times: times,
                                 direction: configuration.displayDirection,
                                 headline: limits.flatMap { limits in
                                     snapshot.flatMap { HeadlineWindow.codex(accountId: account.id, entry: limits,
                                                                             choice: settings.headlineWindow, now: $0.generatedAt) }
                                 },
                                 onSelect: { model.setHeadline(accountId: account.id, choice: $0) })
            case .tokenBased:
                BudgetSection(ownerId: account.id, icon: account.icon, name: account.displayName, isGroup: false, members: [],
                              entry: snapshot?.accountBudgets[account.id],
                              thresholds: account.kind.tokenBased?.ownBudget?.thresholds ?? [],
                              direction: configuration.displayDirection, snapshot: snapshot, times: times,
                              isShotTarget: shotOwner.map { $0.kind == .account && $0.id == account.id } ?? false)
            }
        case .group(let group, let members):
            BudgetSection(ownerId: group.id, icon: group.icon, name: group.name, isGroup: true, members: members,
                          entry: snapshot?.groups[group.id], thresholds: group.thresholds,
                          direction: configuration.displayDirection, snapshot: snapshot, times: times,
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

    /// The Claude subscription accounts whose sections the screenshot
    /// capture crops, first and second (spec 031 FR-010a).
    private var shotClaudeAccountIds: [String] {
        BarLayout.shotClaudeAccountIds(configuration: configuration)
    }

    /// The sections above the pinned footer, the part that scrolls past the
    /// height cap (spec 026 FR-010). No dividers: each section sits on a
    /// full-width band, plain or tinted in turn from `SectionBands`, with
    /// the content inset inside it (spec 028 FR-001 to FR-004).
    private func sections(now: Date) -> some View {
        let entries = configuration.arrangedEntries
        let showsUnassigned = SectionBands.showsUnassigned(snapshot)
        let stripes = SectionBands.stripes(arrangedCount: entries.count, unassignedShown: showsUnassigned)
        return VStack(alignment: .leading, spacing: 0) {
            // The error lines and "No accounts configured" are not sections:
            // no band, and the first section stays plain (spec 028 Edge
            // Cases, FR-003).
            if hasTopLines {
                VStack(alignment: .leading, spacing: 10) {
                    #if AGENTTACHO_DEMO
                    // A scenario that could not be played (spec 024 FR-013).
                    if let error = model.demoScenarioError {
                        Label("Demo scenario error: \(error)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(colors.critical)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    #endif
                    if let error = snapshot?.configError {
                        Label("Configuration error: \(error)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(colors.critical)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Groups can be empty since spec 009, so only accounts count.
                    if configuration.accounts.isEmpty {
                        Text("No accounts configured. Open Settings to add one.")
                            .foregroundStyle(colors.secondary)
                    }
                }
                .padding(.horizontal, Self.inset)
                .padding(.top, Self.bandPadding)
                // A following band brings its own top padding, so the lines
                // keep the 10 pt they had above the first section; without
                // sections the footer band follows (spec 028 SC-003).
                .padding(.bottom, entries.isEmpty && !showsUnassigned ? Self.bandPadding : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // One section per entry in arrangement order, shown in bar or
            // not; group members in member order (spec 008 FR-003).
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, arranged in
                band(stripes[index]) {
                    section(for: arranged, now: now)
                }
            }

            // Unassigned stays the last section and takes the next stripe
            // (spec 008 FR-003, spec 028 FR-002).
            if showsUnassigned, let unassigned = snapshot?.unassigned, let stripe = stripes.last {
                band(stripe) {
                    UnassignedSection(entry: unassigned, snapshot: snapshot)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// True when a configuration or demo scenario error or "No accounts
    /// configured" shows above the sections, the lines that are not sections
    /// (spec 028 FR-003). Keep in step with the top lines in `sections`.
    private var hasTopLines: Bool {
        #if AGENTTACHO_DEMO
        if model.demoScenarioError != nil { return true }
        #endif
        return snapshot?.configError != nil || configuration.accounts.isEmpty
    }

    /// One section on its band: the content inset 12 pt from the sides and
    /// `bandPadding` from the top and bottom, the fill a flat, full-width
    /// rectangle with hard edges (spec 028 FR-004, FR-004a, FR-005). A
    /// background adds no accessibility element (FR-009a).
    private func band(_ style: BandStyle, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, Self.inset)
            .padding(.vertical, Self.bandPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bandFill(style))
    }

    /// The fill of a band: the panel's foreground color at the style's
    /// strength, stronger with "Increase contrast" (spec 028 FR-005,
    /// FR-006). The one place a `BandStyle` becomes a color. `Color.primary`
    /// is the label color of the panel's scheme, whose RGB is
    /// `DropdownPalette.foreground` (spec 032 FR-011).
    private func bandFill(_ style: BandStyle) -> Color {
        Color.primary.opacity(style.opacity(increasedContrast: colorSchemeContrast == .increased))
    }

    /// The pinned footer below the sections, on its own band without a
    /// divider (spec 028 FR-001, FR-004, FR-007): the footer's lines with a
    /// top padding inside the band like a section's, the 12 pt inset to the
    /// sides and the bottom edge, and the band across the full width down to
    /// the panel's bottom edge. It stays pinned because `body` places it
    /// below the scroll view, outside it (FR-008).
    private func pinnedFooter(now: Date) -> some View {
        footer(now: now)
            .padding(.top, Self.bandPadding)
            .padding(.horizontal, Self.inset)
            .padding(.bottom, Self.inset)
            .frame(width: Self.width, alignment: .leading)
            .background(bandFill(.footer))
    }

    /// The footer in a fixed order (spec 025 FR-023 to FR-028, spec 026
    /// FR-011 to FR-014, contracts/dropdown-ui.md "Footer"): at most 3
    /// source error lines, the quiet update line, then the status row. There
    /// is no gear menu: About and "Check for Updates…" live in Settings >
    /// About (FR-028, spec 020), so the dropdown never starts an update
    /// check and its transient result never reaches the line (FR-026).
    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // One line each, truncated with the full text as tooltip; more
            // than 3 errors end in "+N more" (spec 026 FR-011).
            ForEach(Array(FooterErrors.visible(snapshot?.sourceErrors ?? []).enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.caption)
                    .foregroundStyle(colors.critical)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(line.tooltip)
            }
            // The quiet update line (spec 013 FR-009, FR-010).
            if let line = model.updater.display.lineState {
                UpdateLine(updater: model.updater, state: line)
            }
            statusRow(now: now)
        }
    }

    /// The status row (spec 026 FR-012, FR-014): the refresh icon, "Last
    /// refreshed 16:54" with the "stale" marker (spec 025 FR-024), then on
    /// the right Settings and Quit, as icons with a tooltip and an
    /// accessibility label each; ⌘, and ⌘Q work while the dropdown is
    /// open (spec 025 FR-027). The capture opens Settings through the
    /// Settings button (spec 024 FR-019, spec 025 FR-035).
    private func statusRow(now: Date) -> some View {
        HStack(spacing: 10) {
            iconButton("arrow.clockwise", label: "Refresh now", identifier: "agenttacho.refreshButton") {
                model.refreshNow()
            }
            statusText(now: now)
            Spacer(minLength: 0)
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

    /// "Last refreshed" on one line, truncated when the row is too narrow,
    /// never wrapping (spec 026 FR-013). The first variant that fits shows
    /// the text whole; otherwise the truncated one carries the full text in
    /// its tooltip. While a pace is slower than its base, the pace line text
    /// of spec 019 joins the tooltip and stays the accessibility value
    /// (spec 025 FR-025). The tooltip text comes from `FooterText`.
    private func statusText(now: Date) -> some View {
        let paceText = FooterText.paceTooltip(model.paceStatus, now: now, calendar: .autoupdatingCurrent)
        let status = FooterText.lastRefreshed(at: snapshot?.lastSuccessfulRefreshAt, hasSnapshot: snapshot != nil,
                                              isPreliminary: snapshot?.isPreliminary == true, now: now,
                                              calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
        return HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                statusLabel(status, isTruncated: false, paceText: paceText)
                    .fixedSize()
                statusLabel(status, isTruncated: true, paceText: paceText)
            }
            if snapshot?.isStale == true {
                Text("stale")
                    .foregroundStyle(colors.warning)
                    .fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(colors.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(paceText ?? "")
    }

    private func statusLabel(_ status: String, isTruncated: Bool, paceText: String?) -> some View {
        Text(status)
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(Rectangle())
            .optionalHelp(FooterText.statusTooltip(statusText: status, isTruncated: isTruncated, paceText: paceText))
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
        // The dropdown closes first, so it never overlaps the Settings
        // window (spec 026 FR-012a).
        panel?.close()
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
        CompactFormat.millions(value, locale: .autoupdatingCurrent)
    }

    /// A budget in US$ without decimals when it is whole: "300 US$".
    static func budget(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    /// Whole US dollars without a currency suffix for the narrow day
    /// columns: "409", "1.5K"; "<1" for amounts that would round to 0.
    static func compactUSD(_ value: Decimal) -> String {
        CompactFormat.usd(value, locale: .autoupdatingCurrent)
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
    /// Used or remaining, for the percents and the bars (spec 030 FR-009).
    let direction: DisplayDirection
    /// The account's place among the Claude sections the capture crops
    /// (`BarLayout.shotClaudeAccountIds`), nil for none: 0 marks the
    /// section and its details for the `glance` and `same-provider` shots,
    /// 1 the section for `same-provider` (spec 031 FR-010a).
    var shotIndex: Int? = nil
    /// The window the header and the bar entry follow; its row carries the
    /// `●` (spec 027 FR-002, FR-008).
    let headline: ResolvedHeadline
    /// Stores the choice of a clicked window row (spec 027 FR-001).
    let onSelect: (HeadlineChoice?) -> Void

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
        RowBar.make(usedPercent: usedPercent, limitReached: false, thresholds: thresholds, direction: direction,
                    reading: snapshot?.paceReading(for: .claude(account.id, window)))
    }

    /// The account's thresholds, for the row and header levels (spec 030
    /// FR-005).
    private var thresholds: [Int] {
        account.kind.subscription?.thresholds ?? []
    }

    /// The section's identifier for the capture (spec 031 FR-010a).
    private var sectionIdentifier: String? {
        switch shotIndex {
        case 0?: return "agenttacho.claudeSection"
        case 1?: return "agenttacho.claudeSection2"
        default: return nil
        }
    }

    var body: some View {
        // The whole section, header to details, is the `glance` shot; the
        // first two stacked are the `same-provider` shot (spec 031 FR-008,
        // FR-009, FR-012a).
        VStack(alignment: .leading, spacing: 4) {
            // The plan with its windows.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    labelText(account.icon).bold()
                    Text(account.displayName)
                    Spacer()
                    // The header's level is the bar entry's, cross-window
                    // rules included (spec 030 FR-005).
                    HeadlineHeaderText(header: snapshot.flatMap {
                        HeadlineWindow.claudeHeader(headline, entry: entry, thresholds: thresholds, direction: direction,
                                                    now: $0.generatedAt)
                    })
                }
                if let status {
                    // Windows whose reset passed show 0% without a reset
                    // text (spec 010 FR-016); a window that never started
                    // reads "not started" (spec 025 FR-008).
                    // A click on a row makes it the headline window; the
                    // `●` follows the resolved headline, so a click on its
                    // row after a fallback clears the choice (spec 027
                    // FR-001, FR-002, US3 scenario 3).
                    WindowRow(title: "5-hour", window: status.fiveHour,
                              fetchedWithReset: entry?.status?.fiveHour?.resetsAt != nil,
                              bar: status.fiveHour.map { bar($0.utilizationPercent, .fiveHour) }, times: times, direction: direction,
                              isHeadline: headline.claudeWindow == .fiveHour, isDefaultWindow: headline.isDefault,
                              onSelect: { onSelect(HeadlineWindow.choice(forClaude: .fiveHour)) })
                    // The `glance` shot shows this row with its note (spec 025
                    // FR-035, spec 031 FR-006).
                    WindowRow(title: "7-day", window: status.sevenDay,
                              fetchedWithReset: entry?.status?.sevenDay?.resetsAt != nil,
                              bar: status.sevenDay.map { bar($0.utilizationPercent, .sevenDay) }, times: times, direction: direction,
                              isHeadline: headline.claudeWindow == .sevenDay, isDefaultWindow: headline.isDefault,
                              onSelect: { onSelect(HeadlineWindow.choice(forClaude: .sevenDay)) })
                    ForEach(status.modelLimits, id: \.modelName) { limit in
                        ModelLimitRow(limit: limit, bar: bar(limit.utilizationPercent, .model(limit.modelName)), times: times,
                                      direction: direction,
                                      isHeadline: headline.claudeWindow == .model(limit.modelName),
                                      isDefaultWindow: headline.isDefault,
                                      onSelect: { onSelect(HeadlineWindow.choice(forClaude: .model(limit.modelName))) })
                    }
                }
            }
            stateLine
            if let entry, !entry.breakdown.isEmpty {
                BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly,
                              shotIdentifier: shotIndex == 0 ? "agenttacho.claudeDetails" : nil)
            }
        }
        .shotContainer(sectionIdentifier)
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
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    let notes: [SectionNote]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    Text(note.text)
                        .foregroundStyle(note.style.color(colors))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
        }
    }
}

extension NoteStyle {
    /// The note's text color on the current panel (spec 032 FR-007).
    func color(_ colors: DropdownColors) -> AnyShapeStyle {
        switch self {
        case .neutral: colors.secondary
        case .warning: colors.warning
        case .alert: colors.critical
        }
    }
}

/// The level colors of a dropdown percent (spec 030 FR-005): orange and
/// red, primary otherwise, in the current panel's text colors (spec 032
/// FR-007, FR-009).
extension PercentTone {
    func color(_ colors: DropdownColors) -> AnyShapeStyle {
        switch self {
        case .primary: colors.primary
        case .warning: colors.warning
        case .critical: colors.critical
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
    let direction: DisplayDirection
    /// The headline marker and click of spec 027 (see `LimitRowLayout`).
    var isHeadline: Bool? = nil
    var isDefaultWindow = false
    var onSelect: (() -> Void)? = nil

    var body: some View {
        LimitRowLayout(name: limit.modelName,
                       nameHelp: limit.allowancePercentOfWeekly.map { "\(limit.modelName) weekly limit, \($0)% of the 7-day limit" }
                           ?? "\(limit.modelName) weekly limit",
                       percent: PercentFormatter.rounded(limit.utilizationPercent), bar: bar,
                       resetsAt: limit.resetsAt, observedWithReset: true, times: times, direction: direction,
                       isHeadline: isHeadline, isDefaultWindow: isDefaultWindow, onSelect: onSelect)
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
    let direction: DisplayDirection
    /// The headline marker and click of spec 027 (see `LimitRowLayout`).
    var isHeadline: Bool? = nil
    var isDefaultWindow = false
    var onSelect: (() -> Void)? = nil

    var body: some View {
        LimitRowLayout(name: title, percent: window.map { PercentFormatter.rounded($0.utilizationPercent) }, bar: bar,
                       resetsAt: window?.resetsAt, observedWithReset: fetchedWithReset, times: times, direction: direction,
                       isHeadline: isHeadline, isDefaultWindow: isDefaultWindow, onSelect: onSelect)
    }
}

/// One limit window in layout B (spec 025 FR-001 to FR-008,
/// contracts/dropdown-ui.md): name, percent and reset text on one line, the
/// bar below, and the orange note only when the row calls for attention. The
/// percent is orange at the warning level and red at the critical level of
/// the row's thresholds (FR-007, amended by spec 030 FR-005). The reset text shows
/// the other time form as its tooltip (FR-019); the bar has no tooltip
/// (FR-005). The row is one accessibility element naming the window, the
/// percent, the reset text and the pace summary (FR-006). The reset text,
/// its tooltip and the label come from `RowText` in UsageCore.
///
/// In a Claude or Codex subscription section the row is also the headline
/// switch (spec 027 FR-001 to FR-003, research R8): a 12 pt marker slot at
/// the leading edge with `●` on the headline row (dimmed on the default
/// window, `HeadlineMarker`), a click anywhere on the
/// row (tooltips keep working), a hover highlight with `○` on the other
/// rows, and the accessibility action "Show in menu bar". Budget rows pass
/// no `isHeadline` and get none of it. The hover highlight is the row's own
/// background, drawn above the section's band, so a hovered row on a tinted
/// band still differs from it by the highlight's strength (spec 028 FR-009).
struct LimitRowLayout: View {
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
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
    /// The percent reads as used or remaining (spec 030 FR-009).
    let direction: DisplayDirection
    /// True on the account's headline row, false on its other window rows,
    /// nil outside a subscription section (no marker slot).
    var isHeadline: Bool? = nil
    /// True when the account's headline is its default window, which dims
    /// the headline row's `●` (spec 027 FR-002, amendment 2026-10-19).
    var isDefaultWindow = false
    /// Called on a click on the row; the headline row forwards it too, so a
    /// click on the default row after a fallback clears the choice.
    var onSelect: (() -> Void)? = nil

    @State private var isHovered = false

    private static let markerWidth: CGFloat = 12

    /// Only rows a click would change show the hover state (FR-002).
    private var showsHover: Bool { isHovered && isHeadline == false }

    private var text: RowText {
        RowText.window(name: name, percent: percent, direction: direction, resetsAt: resetsAt, observedWithReset: observedWithReset,
                       limitReached: limitReached, bar: bar, times: times, isHeadline: isHeadline == true)
    }

    var body: some View {
        let text = self.text
        let indent = isHeadline != nil ? Self.markerWidth : 0
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let isHeadline {
                    let marker = HeadlineMarker.of(isHeadline: isHeadline, isDefault: isDefaultWindow, isHovered: showsHover)
                    Text(marker.symbol)
                        .font(.caption2)
                        .foregroundStyle(marker.isDimmed ? colors.secondary : colors.primary)
                        .frame(width: Self.markerWidth, alignment: .leading)
                }
                nameAndBar(text)
            }
            .background {
                if showsHover {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(DropdownPalette.hoverOpacity))
                        .padding(.horizontal, -4)
                        .padding(.vertical, -2)
                }
            }
            Group {
                PaceNoteText(note: bar?.note, times: times)
                if limitReached {
                    Text("Limit reached").font(.caption).foregroundStyle(colors.critical)
                }
            }
            .padding(.leading, indent)
        }
        .contentShape(Rectangle())
        .headlineSwitch(enabled: isHeadline != nil, isHovered: $isHovered) { onSelect?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
        .headlineAccessibility(enabled: isHeadline != nil, isSelected: isHeadline == true) { onSelect?() }
    }

    /// Name, percent and reset text on one line, the bar below (spec 025
    /// FR-001 to FR-005).
    private func nameAndBar(_ text: RowText) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .frame(width: 60, alignment: .leading)
                    .optionalHelp(nameHelp)
                if let percent {
                    Text(DirectedPercent(usedPercent: percent, direction: direction).text)
                        .monospacedDigit()
                        .foregroundStyle((bar?.percentTone ?? .primary).color(colors))
                        .frame(width: 50, alignment: .trailing)
                    Spacer()
                    if let reset = text.reset {
                        Text(reset)
                            .foregroundStyle(colors.secondary)
                            .optionalHelp(text.resetTooltip)
                    }
                } else {
                    Text("unavailable").foregroundStyle(colors.secondary)
                    Spacer()
                }
            }
            .font(.callout)
            .lineLimit(1)
            if percent != nil, let bar {
                RowBarView(bar: bar)
            }
        }
    }
}

extension View {
    /// The click and hover of a window row (spec 027 FR-001, FR-002);
    /// unchanged when `enabled` is false. The pointer stays the arrow.
    @ViewBuilder
    func headlineSwitch(enabled: Bool, isHovered: Binding<Bool>, action: @escaping () -> Void) -> some View {
        if enabled {
            onTapGesture(perform: action)
                .onHover { isHovered.wrappedValue = $0 }
        } else {
            self
        }
    }

    /// The accessibility action "Show in menu bar" of a window row and the
    /// selected state of the headline row (spec 027 FR-003); unchanged when
    /// `enabled` is false.
    @ViewBuilder
    func headlineAccessibility(enabled: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityAction(named: "Show in menu bar", action)
        } else {
            self
        }
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
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
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
    /// The budget's thresholds, for the header percent and the bar (spec
    /// 030 FR-005, FR-006).
    let thresholds: [Int]
    /// Used or remaining, for the percent, the bar and the amount line
    /// (spec 030 FR-009, FR-012).
    let direction: DisplayDirection
    let snapshot: UsageSnapshot?
    /// The section's reset and run-out times (spec 025 FR-016).
    let times: TimeText
    /// The budget the screenshot capture crops: its row and details carry
    /// the capture's identifiers (spec 024 FR-019).
    var isShotTarget = false

    /// The budget's bar from its pace reading at the snapshot time; never
    /// for member lines (spec 011 FR-008, FR-011). Its level, from the
    /// header's rounded percent and the thresholds, also colors the header
    /// percent (spec 025 FR-003, FR-009, spec 030 FR-005, FR-006).
    private func bar(_ entry: GroupEntry) -> RowBar {
        RowBar.budget(entry, thresholds: thresholds, direction: direction,
                      reading: snapshot?.paceReading(for: isGroup ? .group(ownerId) : .accountBudget(ownerId)))
    }

    private var isEmptyGroup: Bool { isGroup && members.isEmpty }

    /// The group's member lines and member tables (spec 026 FR-002, FR-003,
    /// FR-007); nothing for an own budget, which passes no members.
    private var memberDisplay: MemberDisplay {
        MemberDisplay.make(memberIds: members.map(\.id), usage: snapshot?.tokenAccounts ?? [:])
    }

    private func member(_ id: String) -> Account? {
        members.first { $0.id == id }
    }

    /// The members' tables behind "Show account details", each with the member's
    /// own breakdown for the group's period (spec 026 FR-003, Assumptions).
    private func memberTables(_ display: MemberDisplay) -> [MemberTable] {
        display.tables.compactMap { id in
            guard let member = member(id), let account = snapshot?.tokenAccounts[id] else { return nil }
            return MemberTable(id: id, icon: member.icon, name: member.displayName,
                               breakdown: account.breakdown, incomplete: account.incomplete)
        }
    }

    /// The incomplete-prices and stale notes of the budget (spec 025 FR-029).
    private func notes(_ entry: GroupEntry) -> [SectionNote] {
        var notes: [SectionNote] = []
        if entry.incomplete { notes.append(.budgetIncomplete(unpricedModels: entry.breakdown.unpricedModels)) }
        if entry.stale { notes.append(.budgetStale(since: snapshot?.lastSuccessfulRefreshAt, dates: .current)) }
        return notes
    }

    var body: some View {
        // One bar per render: its pace reading is the costly part, and the
        // header percent and the bar row share its level.
        let budgetBar = entry.map(bar)
        VStack(alignment: .leading, spacing: 4) {
            // Header and amount line, the `budget` shot (spec 024 FR-019).
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    labelText(icon).bold()
                    Text(name)
                    Spacer()
                    if let entry, let budgetBar {
                        let percent = DirectedPercent(usedPercent: entry.percent, direction: direction)
                        Text(percent.text).bold().monospacedDigit()
                            .foregroundStyle(budgetBar.percentTone.color(colors))
                            .accessibilityLabel(percent.accessibilityText(.budget))
                    }
                }
                if let entry, let budgetBar {
                    BudgetBarRow(name: name, entry: entry, bar: budgetBar, times: times, direction: direction)
                }
            }
            .shotContainer(isShotTarget ? "agenttacho.budgetRow" : nil)
            if let entry {
                if isEmptyGroup {
                    SectionNotesView(notes: [.emptyGroup])
                }
                // With two or more members each member with usage has its
                // summary line (spec 004 FR-018a); a single member's line
                // would repeat the group's amount (spec 025 FR-010). Member
                // lines have no Details of their own: their tables sit in
                // the group's Details behind "Show account details" (spec 026
                // FR-001 to FR-003). The rule is `MemberDisplay` (FR-007).
                let display = memberDisplay
                ForEach(display.lines, id: \.self) { id in
                    if let member = member(id), let account = snapshot?.tokenAccounts[id] {
                        HStack {
                            labelText(member.icon)
                            Text(member.displayName)
                            Spacer()
                            // Share of the budget, as in the bar (spec 004 FR-018a).
                            Text(UsageFormat.wholeUSD(account.breakdown.pricedCostUSD)
                                 + (entry.memberPercent(id).map { " (\($0)%)" } ?? "")).monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(colors.secondary)
                    }
                }
                SectionNotesView(notes: notes(entry))
                if !isEmptyGroup {
                    BreakdownView(breakdown: entry.breakdown, showsCost: true, period: entry.period,
                                  shotIdentifier: isShotTarget ? "agenttacho.details" : nil,
                                  incomplete: entry.incomplete,
                                  memberTables: memberTables(display))
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
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    let name: String
    let entry: GroupEntry
    let bar: RowBar
    let times: TimeText
    let direction: DisplayDirection

    /// "1,596 of 300 US$/month", or "60 left of 100 US$/week" and "15 over
    /// 100 US$/week" in direction remaining (spec 030 FR-012).
    private var amountText: String {
        BudgetAmountLine.make(spent: entry.spentUSD, budget: entry.budgetUSD, roundedPercent: entry.percent, direction: direction)
            .text(amount: UsageFormat.amount, budget: UsageFormat.budget(entry.budgetUSD),
                  period: entry.period == .monthly ? "month" : "week")
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
                        .foregroundStyle(colors.secondary)
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
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    let note: PaceNote?
    let times: TimeText

    var body: some View {
        if let note {
            Text(note.text(times: times))
                .font(.caption)
                .foregroundStyle(colors.warning)
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
/// week" lines are gone (spec 025 FR-013); the week's total is the Σ column
/// of the Details' day row (spec 026 FR-008, FR-009).
struct CodexPlanSection: View {
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    let account: Account
    let entry: TokenAccountEntry?
    let limits: CodexLimitsEntry?
    /// The snapshot's time, so reset windows show 0% (FR-010).
    let now: Date?
    /// For the windows' pace readings (spec 025 FR-030).
    let snapshot: UsageSnapshot?
    /// The section's reset and run-out times (spec 025 FR-016).
    let times: TimeText
    /// Used or remaining, for the percents and the bars (spec 030 FR-009).
    let direction: DisplayDirection
    /// The window the header and the bar entry follow, nil without windows;
    /// its row carries the `●` (spec 027 FR-002, FR-008).
    let headline: ResolvedHeadline?
    /// Stores the choice of a clicked window row (spec 027 FR-001).
    let onSelect: (HeadlineChoice?) -> Void

    /// The plan's thresholds, for the row and header levels (spec 030
    /// FR-005).
    private var thresholds: [Int] {
        account.kind.codexSubscription?.thresholds ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                labelText(account.icon).bold()
                Text(account.displayName)
                Spacer()
                // The header's level is the bar entry's, any reached limit
                // included (spec 030 FR-005).
                if let limits, let now, let header = HeadlineWindow.codexHeader(headline, entry: limits, thresholds: thresholds,
                                                                                          direction: direction, now: now) {
                    HeadlineHeaderText(header: header)
                } else if limits == nil {
                    Text("…").foregroundStyle(colors.secondary)
                }
            }
            if let limits, let now {
                // Each window's bar from its pace reading at the observation
                // time (spec 011 FR-002, spec 025 FR-030). A click on a row
                // makes it the headline window (spec 027 FR-001).
                let windows = limits.windows(now: now)
                let headlineIndex = headline.flatMap { HeadlineWindow.codexHeadlineIndex($0, windows: windows) }
                ForEach(Array(windows.enumerated()), id: \.element.name) { index, window in
                    CodexWindowRow(window: window,
                                   fetchedWithReset: limits.observedWithReset(window.name),
                                   bar: RowBar.make(usedPercent: window.usedPercent, limitReached: window.limitReached,
                                                    thresholds: thresholds, direction: direction,
                                                    reading: snapshot?.paceReading(for: .codex(account.id, window.name))),
                                   times: times, direction: direction,
                                   isHeadline: index == headlineIndex, isDefaultWindow: headline?.isDefault ?? true,
                                   onSelect: { onSelect(HeadlineWindow.choice(forCodex: window.name, entry: limits, now: now)) })
                }
                stateLine(limits)
            }
            if entry?.stale == true {
                SectionNotesView(notes: [.staleMarker])
            }
            if let entry, !entry.breakdown.isEmpty {
                BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly)
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
    let direction: DisplayDirection
    /// The headline marker and click of spec 027 (see `LimitRowLayout`).
    var isHeadline: Bool? = nil
    var isDefaultWindow = false
    var onSelect: (() -> Void)? = nil

    var body: some View {
        LimitRowLayout(name: window.name, percent: PercentFormatter.rounded(window.usedPercent), bar: bar,
                       resetsAt: window.resetsAt, observedWithReset: fetchedWithReset,
                       limitReached: window.limitReached, times: times, direction: direction,
                       isHeadline: isHeadline, isDefaultWindow: isDefaultWindow, onSelect: onSelect)
    }
}

/// The headline part of a subscription section header (spec 027 FR-008,
/// clarification): the tag in the secondary color and regular weight
/// directly before the bold percent; only the bold percent for the default
/// window, as before. The bold percent takes the level color (spec 030
/// FR-005).
struct HeadlineHeaderText: View {
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    let header: HeadlineHeader?

    var body: some View {
        if let header {
            HStack(spacing: 4) {
                if let tag = header.tag {
                    Text(tag).foregroundStyle(colors.secondary)
                }
                Text(header.value).bold().monospacedDigit()
                    .foregroundStyle(header.percentTone.color(colors))
                    // "30% left" in direction remaining (spec 030 FR-009).
                    .accessibilityLabel(header.accessibilityValue)
            }
        }
    }
}

// MARK: - Unassigned

struct UnassignedSection: View {
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
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
                .foregroundStyle(colors.secondary)
            if entry.stale {
                SectionNotesView(notes: [.staleMarker])
            }
            BreakdownView(breakdown: entry.breakdown, showsCost: false, period: .weekly)
        }
    }
}
