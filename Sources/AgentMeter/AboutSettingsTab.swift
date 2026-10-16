import AppKit
import SwiftUI
import UsageCore

// MARK: - About tab

/// What build is running and where it comes from: the monochrome app icon,
/// the release data stamped by build-app.sh (version, commit, build date,
/// signing), the changes since the previous release from the bundled
/// changes.json, a short note on the credentials it reads (in a popover), and
/// links to the GitHub repository, issues and sponsor page. Laid out to fit
/// the Settings window without scrolling. A build without the stamped data
/// (`swift run`) shows only what it has.
struct AboutSettingsTab: View {
    private static let info = AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
    private static let changes = ReleaseChanges(
        data: Bundle.main.url(forResource: "changes", withExtension: "json").flatMap { try? Data(contentsOf: $0) })
    /// "What's new" lists at most this many changes, features first; the
    /// release notes on GitHub have the rest.
    private static let changeLimit = 5

    /// The template-image icon (Resources/icons/mono), copied into the bundle
    /// by build-app.sh when it exists.
    @MainActor private static let monoIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AgentMeter-mono", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }()

    /// The update check and its state (spec 013 FR-011).
    let updater: Updater
    /// The Settings draft, for "Check for updates automatically", applied
    /// like every other Settings change (spec 013 FR-002).
    @Binding var draft: Configuration

    @State private var showingCredentials = false

    var body: some View {
        // At least the visible height, so the content sits vertically centered
        // and only scrolls when the window is too small.
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    updates
                    whatsNew
                    linkRow
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    /// Icon on top, then name, tagline and release data, all centered.
    private var header: some View {
        VStack(spacing: 10) {
            hero
            VStack(spacing: 2) {
                Text("AgentMeter")
                    .font(.title.weight(.semibold))
                Text("Every agent, every plan, one menu bar")
                    .foregroundStyle(.secondary)
            }
            releaseGrid
        }
    }

    @ViewBuilder private var hero: some View {
        if let mono = Self.monoIcon {
            // Template rendering follows light and dark mode.
            Image(nsImage: mono)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        } else {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        }
    }

    private var releaseGrid: some View {
        let info = Self.info
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 2) {
            row("Version") { Text(info.versionText) }
            if let commit = info.commit, let short = info.shortCommit {
                row("Commit") {
                    Link(short, destination: AppLinks.commit(commit))
                        .font(.body.monospaced())
                        .help(commit)
                }
            }
            if let built = info.buildDate {
                row("Built") { Text(built.formatted(date: .long, time: .shortened)) }
            }
            if let signing = info.signing {
                row("Signing") { Text(signing.text) }
            }
        }
        .textSelection(.enabled)
    }

    private func row<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value()
        }
    }

    /// The Updates group (spec 013 FR-002, FR-003, FR-011;
    /// contracts/update-ui.md): the state with its action and release notes,
    /// a known update kept next to a failed manual check (FR-007a), and the
    /// "Check for Updates…" button.
    private var updates: some View {
        let display = updater.display
        let state = display.state
        return VStack(spacing: 6) {
            Text("Updates")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                UpdateStatusText(text: state.settingsText(formatTime: { $0.formatted(date: .omitted, time: .shortened) }),
                                 truncates: false)
                UpdateButtons(updater: updater, state: state)
            }
            if let known = display.settingsKnownUpdate {
                let available = UpdateState.available(known.release, known.action)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    UpdateStatusText(text: available.lineText, truncates: false)
                    UpdateButtons(updater: updater, state: available)
                }
            }
            HStack(spacing: 16) {
                // Its result shows here, not on the dropdown line (FR-003).
                Button("Check for Updates\u{2026}") { updater.checkNow(from: .settings) }
                    .disabled(state.isInstallRunning)
                Toggle("Check for updates automatically", isOn: $draft.checksForUpdates)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 520)
    }

    /// One short list, features before fixes, without group headings or
    /// scopes; the release notes have the full, grouped list.
    private var whatsNew: some View {
        let entries = Self.changes.groups(limit: Self.changeLimit).flatMap(\.entries)
        return VStack(alignment: .leading, spacing: 6) {
            if !entries.isEmpty {
                Text("What's new in \(Self.info.version ?? "this build")")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entries, id: \.hash) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(change.sentence)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Link("Release notes on GitHub", destination: AppLinks.releasePage(for: Self.info.releaseTag))
                .frame(maxWidth: .infinity, alignment: entries.isEmpty ? .center : .leading)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    /// Links with Font Awesome icons, separated by small bullets.
    private var linkRow: some View {
        HStack(spacing: 10) {
            Link(destination: AppLinks.repository) { iconText("brands:github", "GitHub") }
            separator
            Link(destination: AppLinks.newIssue) { iconText("solid:bug", "Report an issue") }
            separator
            Link(destination: AppLinks.sponsor) { iconText("solid:heart", "Sponsor AgentMeter") }
            separator
            Button {
                showingCredentials.toggle()
            } label: {
                iconText("solid:shield-halved", "Your credentials")
            }
            .buttonStyle(.link)
            .popover(isPresented: $showingCredentials, arrowEdge: .bottom) {
                credentials
            }
        }
    }

    private func iconText(_ icon: String, _ title: String) -> Text {
        labelText(icon) + Text(" \(title)")
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// A short, honest summary of the credential access; the README's
    /// security statement has the details.
    private var credentials: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your credentials")
                .font(.headline)
            ForEach(Self.credentialFacts, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(fact)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Link("How AgentMeter handles your credentials", destination: AppLinks.securityStatement)
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }

    private static let credentialFacts = [
        "Reads the Claude Code login from the keychain and the Codex sign-in from auth.json, only to ask Anthropic and ChatGPT for your usage.",
        "Sends each token only to that one usage address, keeps it in memory for one request, and never refreshes or changes a login.",
        "Runs without the macOS sandbox, with your user account's access. Any program you run could read these tokens the same way.",
    ]

    private var footer: some View {
        VStack(spacing: 4) {
            Text(Self.credit)
            Text("Apache License 2.0 · icons from Font Awesome Free (CC BY 4.0)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    /// "Built by Roland Huß and a team of agents who know their limits.", with
    /// the name linking to the author's homepage.
    private static let credit: AttributedString = {
        var name = AttributedString("Roland Huß")
        name.link = AppLinks.author
        var credit = AttributedString("Built by ")
        credit.append(name)
        credit.append(AttributedString(" and a team of agents who know their limits."))
        return credit
    }()
}
