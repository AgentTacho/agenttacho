import AppKit
import SwiftUI
import UsageCore

// MARK: - About tab

/// What build is running and where it comes from: the monochrome app icon,
/// the release data stamped by build-app.sh (version, commit, build date,
/// signing), the changes since the previous release from the bundled
/// changes.json, a short note on the credentials it reads, and links to the
/// GitHub repository, issues and sponsor page.
/// A build without the stamped data (`swift run`) shows only what it has.
struct AboutSettingsTab: View {
    private static let info = AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
    private static let changes = ReleaseChanges(
        data: Bundle.main.url(forResource: "changes", withExtension: "json").flatMap { try? Data(contentsOf: $0) })
    /// "What's new" lists at most this many changes; the release notes on
    /// GitHub have the rest.
    private static let changeLimit = 8

    /// The template-image icon (Resources/icons/mono), copied into the bundle
    /// by build-app.sh when it exists.
    @MainActor private static let monoIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AgentMeter-mono", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    hero
                    Text("AgentMeter")
                        .font(.title.weight(.semibold))
                    Text("Every agent, every plan, one menu bar")
                        .foregroundStyle(.secondary)
                }
                releaseGrid
                whatsNew
                credentials
                linkRow
                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity)
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
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
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

    private var whatsNew: some View {
        let groups = Self.changes.groups(limit: Self.changeLimit)
        return VStack(alignment: .leading, spacing: 8) {
            if !groups.isEmpty {
                Text("What's new in \(Self.info.version ?? "this build")")
                    .font(.headline)
                ForEach(groups, id: \.kind) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        // A heading only helps when there is more than one kind.
                        if groups.count > 1 {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.entries, id: \.hash) { change in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•")
                                changeText(change)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            Link("Release notes on GitHub", destination: AppLinks.releasePage(for: Self.info.releaseTag))
                .frame(maxWidth: .infinity, alignment: groups.isEmpty ? .center : .leading)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    /// The capitalized subject, then the scope in a lighter tone.
    private func changeText(_ change: ReleaseChange) -> Text {
        let sentence = Text(change.sentence)
        guard let scope = change.scope else { return sentence }
        return sentence + Text("  \(scope)").font(.caption).foregroundStyle(.tertiary)
    }

    /// A short, honest summary of the credential access; the README's
    /// security statement has the details.
    private var credentials: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .frame(maxWidth: 520, alignment: .leading)
    }

    private static let credentialFacts = [
        "Reads the Claude Code login from the keychain and the Codex sign-in from auth.json, only to ask Anthropic and ChatGPT for your usage.",
        "Sends each token only to that one usage address, keeps it in memory for one request, and never refreshes or changes a login.",
        "Runs without the macOS sandbox, with your user account's access. Any program you run could read these tokens the same way.",
    ]

    private var linkRow: some View {
        HStack(spacing: 20) {
            Link("GitHub", destination: AppLinks.repository)
            Link("Report an issue", destination: AppLinks.newIssue)
            Link("♥ Sponsor AgentMeter", destination: AppLinks.sponsor)
        }
    }

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
    /// the name linking to the author's GitHub profile.
    private static let credit: AttributedString = {
        var name = AttributedString("Roland Huß")
        name.link = AppLinks.author
        var credit = AttributedString("Built by ")
        credit.append(name)
        credit.append(AttributedString(" and a team of agents who know their limits."))
        return credit
    }()
}
