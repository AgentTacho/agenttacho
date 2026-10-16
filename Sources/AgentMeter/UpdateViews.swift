import SwiftUI
import UsageCore

/// The quiet update line at the bottom of the dropdown (spec 013 FR-009,
/// FR-010, FR-018; contracts/update-ui.md): secondary text, the state's
/// `lineText` (a Download or Try again reason after a middle dot, kept to one
/// line and truncated with the full text as tooltip), then the state's
/// buttons.
struct UpdateLine: View {
    let updater: Updater
    let state: UpdateState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            UpdateStatusText(text: state.lineText, truncates: state.reason != nil)
            Spacer(minLength: 4)
            UpdateButtons(updater: updater, state: state)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }
}

/// A state's text as `UpdateState` words it (`lineText` or
/// `settingsText`). With `truncates` it stays one line with the full text as
/// tooltip; otherwise it wraps.
struct UpdateStatusText: View {
    let text: String
    let truncates: Bool

    var body: some View {
        if truncates {
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
        } else {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The buttons of a state (contracts/update-ui.md): the installation's action
/// (or "Try again") and "Release notes" for an available update, "Release
/// notes" after the Homebrew command was copied, "Cancel" while downloading
/// and verifying, none while installing, and "Release page" after a failed
/// install from the previous run. Install appears only in the available
/// state, so a running install cannot be started twice (FR-018).
struct UpdateButtons: View {
    let updater: Updater
    let state: UpdateState

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .available(let release, let action):
                Button(Self.title(of: action)) { updater.perform(action, release: release) }
                Button("Release notes") { updater.openReleasePage(release) }
            case .commandCopied(let release):
                Button("Release notes") { updater.openReleasePage(release) }
            case .downloading, .verifying:
                // Stops the install before anything is replaced (FR-018).
                Button("Cancel") { updater.cancelInstall() }
            case .installFailed:
                // A failure reported by the previous run offers the release
                // page (FR-019).
                Button("Release page") { updater.openLatestReleasePage() }
            default:
                EmptyView()
            }
        }
        .buttonStyle(.link)
        .fixedSize()
    }

    /// "Install", "Upgrade with Homebrew", "Download" (FR-012) or "Try
    /// again" after a failure that may pass on a second try (US2 scenario 4).
    static func title(of action: UpdateAction) -> String {
        switch action {
        case .install: return "Install"
        case .retry: return "Try again"
        case .homebrew: return "Upgrade with Homebrew"
        case .download: return "Download"
        }
    }
}
