import Foundation
import Testing
@testable import UsageCore

/// spec 035 FR-002, FR-006, research R2, contracts/configuration.md "Entry
/// rules": which entries of an additional session directory list or of the
/// OpenCode list are refused, without touching the file system.
@Suite struct SessionDirectoryEntryTests {
    static let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))

    static func refusal(_ entry: String, _ list: SessionDirectoryList = .account) -> SessionDirectoryRefusal? {
        SessionDirectoryEntry.refusal(of: entry, in: list, paths: paths)
    }

    @Test func reasonTexts() {
        #expect(SessionDirectoryRefusal.relative.reason == "it must start with ~/ or /")
        #expect(SessionDirectoryRefusal.doubleStar.reason == "** is not supported, * covers one folder level")
        #expect(SessionDirectoryRefusal.homeOrRoot.reason == "the home folder or / is not a session directory")
        #expect(SessionDirectoryRefusal.bareStarAtTop.reason == "* may not stand for a whole folder directly under the home folder or /")
    }

    @Test(arguments: ["~/.claude-lab", "~/.claude-*", "~/agent-sessions/openshell/*/claude", "/Volumes/archive/*/codex",
                      "~/agent-sessions/openshell/sandbox-*/opencode", "  ~/.codex-lab\n", "/Users/tester/.claude-lab",
                      "~/agent-sessions/?[x]{y}/claude", "/Users/*", "~/x/*"])
    func acceptedEntries(entry: String) {
        #expect(Self.refusal(entry) == nil)
        #expect(Self.refusal(entry, .openCode) == nil)
    }

    @Test(arguments: ["agent-sessions/*/claude", "~name/x", "agent-sessions/**/x", ".claude-lab", "./x", ""])
    func relativeEntriesAreRefusedInAccountLists(entry: String) {
        #expect(Self.refusal(entry) == .relative)
    }

    /// The OpenCode list keeps literal relative entries (as today) and
    /// refuses a relative entry with `*`.
    @Test func openCodeRefusesOnlyRelativeWildcards() {
        #expect(Self.refusal("opencode-lab", .openCode) == nil)
        #expect(Self.refusal("~name/x", .openCode) == nil)
        #expect(Self.refusal("agent-sessions/*/opencode", .openCode) == .relative)
        #expect(Self.refusal("agent-sessions/**/opencode", .openCode) == .relative)
    }

    @Test(arguments: ["~/agent-sessions/**/claude", "/**", "~/a/**"])
    func doubleStarIsRefused(entry: String) {
        #expect(Self.refusal(entry) == .doubleStar)
        #expect(Self.refusal(entry, .openCode) == .doubleStar)
    }

    @Test(arguments: ["~", "~/", "/", "/Users/tester", "/Users/tester/", "~/x/..", "~/.", "/Users/../", "//", "~//", "/Users/tester/.", "~/./"])
    func homeOrRootIsRefused(entry: String) {
        #expect(Self.refusal(entry) == .homeOrRoot)
        #expect(Self.refusal(entry, .openCode) == .homeOrRoot)
    }

    @Test(arguments: ["~/*/claude", "/*", "~/*", "/Users/tester/*/codex", "~/x/../*/claude", "/*/x",
                      "~/./*", "~//*/claude", "/./*", "/Users/tester/./*/codex"])
    func bareStarAtTopIsRefused(entry: String) {
        #expect(Self.refusal(entry) == .bareStarAtTop)
        #expect(Self.refusal(entry, .openCode) == .bareStarAtTop)
    }

    /// The Add button: trims whitespace and newlines, ignores blank input and
    /// an entry already in the list (spec 035 FR-002).
    @Test func addingTrimsAndIgnoresBlanksAndDuplicates() {
        #expect(SessionDirectoryEntry.adding(" ~/.claude-lab\n", to: []) == ["~/.claude-lab"])
        #expect(SessionDirectoryEntry.adding("~/.claude-lab", to: ["~/.claude-lab"]) == ["~/.claude-lab"])
        #expect(SessionDirectoryEntry.adding("  ~/.claude-lab ", to: ["~/.claude-lab"]) == ["~/.claude-lab"])
        #expect(SessionDirectoryEntry.adding(" \n\t", to: ["~/.claude-lab"]) == ["~/.claude-lab"])
        #expect(SessionDirectoryEntry.adding("~/agent-sessions/openshell/*/claude", to: ["~/.claude-lab"])
                == ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"])
        // A refused entry is still added, so the draft names it (research R11).
        #expect(SessionDirectoryEntry.adding("~/*/claude", to: []) == ["~/*/claude"])
    }

    /// Editing a row in place: trimmed like an added entry; blank text, the
    /// unchanged entry or another entry's text leaves the list as it is
    /// (spec 035 FR-002).
    @Test func replacingAnEntry() {
        let list = ["~/.codex-lab", "~/agent-sessions/openshell/*/codex"]
        #expect(SessionDirectoryEntry.replacing(at: 0, with: " ~/.codex-work\n", in: list)
                == ["~/.codex-work", "~/agent-sessions/openshell/*/codex"])
        #expect(SessionDirectoryEntry.replacing(at: 1, with: " \t", in: list) == list)
        #expect(SessionDirectoryEntry.replacing(at: 1, with: "~/.codex-lab", in: list) == list)
        #expect(SessionDirectoryEntry.replacing(at: 0, with: " ~/.codex-lab", in: list) == list)
        #expect(SessionDirectoryEntry.replacing(at: 2, with: "~/x", in: list) == list)
        #expect(SessionDirectoryEntry.replacing(at: -1, with: "~/x", in: list) == list)
        // A refused entry is still written, so the draft names it.
        #expect(SessionDirectoryEntry.replacing(at: 0, with: "~/*", in: list) == ["~/*", "~/agent-sessions/openshell/*/codex"])
    }

    /// Choose Folder…: a chosen folder is written with `~` for the home
    /// folder, so the entry reads like the typed ones (spec 035 FR-002).
    @Test func chosenFolderEntry() {
        func entry(_ path: String) -> String { SessionDirectoryEntry.entry(forChosenFolder: path, paths: Self.paths) }
        #expect(entry("/Users/tester/.codex-lab") == "~/.codex-lab")
        #expect(entry("/Users/tester/agent-sessions/openshell/box-a/codex/") == "~/agent-sessions/openshell/box-a/codex")
        #expect(entry("/Users/tester") == "~")
        #expect(entry("/Volumes/archive/codex") == "/Volumes/archive/codex")
        // A sibling whose name starts with the home folder's name stays absolute.
        #expect(entry("/Users/tester2/.codex") == "/Users/tester2/.codex")
        #expect(entry("/") == "/")
    }

    /// Expansion and standardization are string work only.
    @Test func normalizedPath() {
        #expect(SessionDirectoryEntry.normalized("~/a/./b/../c/", paths: Self.paths) == "/Users/tester/a/c")
        #expect(SessionDirectoryEntry.normalized("~", paths: Self.paths) == "/Users/tester")
        #expect(SessionDirectoryEntry.normalized("/../..", paths: Self.paths) == "/")
        #expect(SessionDirectoryEntry.normalized("//x//y", paths: Self.paths) == "/x/y")
    }
}
