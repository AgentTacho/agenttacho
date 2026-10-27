import Foundation
import Testing
@testable import UsageCore

/// spec 037 FR-001, FR-002, FR-004, SC-004, research R1, R2: the profile
/// named by a session file's `api-request-shape` lines.
@Suite struct SessionProfileTests {
    static let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    static let marker = "SECRET-PROMPT-MARKER-4711"

    /// A line shaped like Claude Code's: the system prompt names the
    /// auto-memory folder below `dir`.
    static func shapeLine(_ dirs: [String], extra: String = "") -> String {
        let memory = dirs.map { "You have a persistent file-based memory at `\($0)/projects/-Users-tester-proj/memory/`." }
            .joined(separator: " ")
        return #"{"type":"api-request-shape","sessionId":"s-1","shape":{"system":[{"type":"text","text":"You are a coding agent. \#(memory) \#(extra) \#(marker)"}]}}"#
    }

    static func candidates(_ entries: [SessionProfile.Entry]) -> SessionProfile.Candidates {
        SessionProfile.Candidates(entries: entries, paths: paths)
    }

    static let three = candidates([
        .init(accountId: "personal", path: "~/agent-profiles/personal/claude", rank: .main),
        .init(accountId: "work", path: "~/agent-profiles/work/claude", rank: .main),
        .init(accountId: "lab", path: "~/agent-profiles/lab/claude", rank: .main),
    ])

    @Test func lineWithoutShapeTypeIsNoShapeLine() {
        let assistant = #"{"type":"assistant","message":{"content":"/Users/tester/agent-profiles/work/claude/projects/x"}}"#
        #expect(SessionProfile.detect(line: assistant, candidates: Self.three) == .notShape)
        #expect(SessionProfile.detect(line: "", candidates: Self.three) == .notShape)
    }

    @Test func shapeLineNamingOneCandidate() {
        let line = Self.shapeLine(["/Users/tester/agent-profiles/work/claude"])
        #expect(SessionProfile.detect(line: line, candidates: Self.three) == .named("/Users/tester/agent-profiles/work/claude"))
        // The spaced JSON spelling counts too.
        let spaced = line.replacingOccurrences(of: #""type":"api-request-shape""#, with: #""type": "api-request-shape""#)
        #expect(SessionProfile.detect(line: spaced, candidates: Self.three) == .named("/Users/tester/agent-profiles/work/claude"))
    }

    @Test func shapeLineNamingNoCandidate() {
        let line = Self.shapeLine(["/sandbox/.claude"])
        #expect(SessionProfile.detect(line: line, candidates: Self.three) == SessionProfile.Detection.none)
        // A path without `/projects/` after it does not count.
        let bare = Self.shapeLine([], extra: "Your directory is /Users/tester/agent-profiles/work/claude.")
        #expect(SessionProfile.detect(line: bare, candidates: Self.three) == SessionProfile.Detection.none)
        #expect(SessionProfile.detect(line: line, candidates: Self.candidates([])) == SessionProfile.Detection.none)
    }

    /// FR-001: a line that names two configured directories is skipped.
    @Test func shapeLineNamingTwoCandidatesIsAmbiguous() {
        let line = Self.shapeLine(["/Users/tester/agent-profiles/work/claude", "/Users/tester/agent-profiles/lab/claude"])
        #expect(SessionProfile.detect(line: line, candidates: Self.three) == .ambiguous)
        // The same directory named twice is still one.
        let twice = Self.shapeLine(["/Users/tester/agent-profiles/lab/claude", "/Users/tester/agent-profiles/lab/claude"])
        #expect(SessionProfile.detect(line: twice, candidates: Self.three) == .named("/Users/tester/agent-profiles/lab/claude"))
    }

    /// FR-002: `~` in Settings matches the absolute path in the file, and an
    /// empty main directory field is `~/.claude`.
    @Test func tildeMatchesTheAbsolutePath() {
        let candidates = Self.candidates([.init(accountId: "max", path: "~/.claude", rank: .main)])
        let line = Self.shapeLine(["/Users/tester/.claude"])
        #expect(SessionProfile.detect(line: line, candidates: candidates) == .named("/Users/tester/.claude"))
        let slash = Self.candidates([.init(accountId: "max", path: "~/.claude/", rank: .main)])
        #expect(SessionProfile.detect(line: line, candidates: slash) == .named("/Users/tester/.claude"))
    }

    /// FR-002: a configuration directory reached through a symlinked parent
    /// matches the resolved path the session file names, and the plain
    /// spelling still matches; a shared `projects` link is never resolved.
    @Test func symlinkedParentMatches() throws {
        let root = try makeTempDirectory("profile-symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("claude"), withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let shared = root.appendingPathComponent("shared-projects")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: real.appendingPathComponent("claude/projects"), withDestinationURL: shared)

        let configured = link.path + "/claude"
        let candidates = Self.candidates([.init(accountId: "work", path: configured, rank: .main)])
        let canonical = Attributor.canonical(configured)
        #expect(canonical.hasSuffix("/real/claude"))
        let resolvedLine = Self.shapeLine([canonical])
        #expect(SessionProfile.detect(line: resolvedLine, candidates: candidates) == .named(canonical))
        let linkLine = Self.shapeLine([configured])
        #expect(SessionProfile.detect(line: linkLine, candidates: candidates) == .named(canonical))
        // A second profile whose `projects` links to the same shared folder
        // stays apart: each line names exactly its own profile.
        let other = root.appendingPathComponent("other/claude")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: other.appendingPathComponent("projects"), withDestinationURL: shared)
        let both = Self.candidates([.init(accountId: "work", path: configured, rank: .main),
                                    .init(accountId: "other", path: other.path, rank: .main)])
        let otherCanonical = Attributor.canonical(other.path)
        #expect(SessionProfile.detect(line: linkLine, candidates: both) == .named(canonical))
        #expect(SessionProfile.detect(line: Self.shapeLine([other.path]), candidates: both) == .named(otherCanonical))
        #expect(both.directories == [canonical, otherCanonical])
    }

    /// FR-002, Codex review: every listed spelling of an additional
    /// directory is searched, also when two entries are aliases of one
    /// folder and the resolver reads it once; the home folder and `/` are
    /// never a candidate.
    @Test func everyAliasOfAnAdditionalDirectoryIsSearched() throws {
        let root = try makeTempDirectory("profile-alias")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real/claude")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let aliasA = root.appendingPathComponent("alias-a")
        let aliasB = root.appendingPathComponent("alias-b")
        try FileManager.default.createSymbolicLink(at: aliasA, withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: aliasB, withDestinationURL: real)
        let paths = Paths(home: root)
        let config = Configuration(accounts: [
            Account(id: "home", displayName: "Home", kind: .subscription(SubscriptionSettings(credentialDirectory: "~"))),
            Account(id: "lab", displayName: "Lab",
                    kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), matchRule: MatchRule.none,
                                                         sessionDirectory: "~/lab/claude",
                                                         additionalSessionDirectories: [aliasA.path, aliasB.path]))),
        ], groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
        let resolution = SessionDirectoryResolver(paths: paths).resolve(.claudeCode, configuration: config)
        let profiles = SessionLogSource.profileCandidates(configuration: config, resolution: resolution, paths: paths)
        let canonical = Attributor.canonical(real.path)
        #expect(SessionProfile.detect(line: Self.shapeLine([aliasB.path]), candidates: profiles) == .named(canonical))
        #expect(SessionProfile.detect(line: Self.shapeLine([aliasA.path]), candidates: profiles) == .named(canonical))
        #expect(!profiles.directories.contains(Attributor.canonical(root.path)))
        #expect(!profiles.directories.contains("/"))
    }

    /// Plan review finding 12: a configured path inside a longer path does
    /// not match without a path boundary before it.
    @Test func longerPathDoesNotMatch() {
        let candidates = Self.candidates([.init(accountId: "max", path: "~/.claude", rank: .main)])
        let line = Self.shapeLine(["/var/sandbox/Users/tester/.claude"])
        #expect(SessionProfile.detect(line: line, candidates: candidates) == SessionProfile.Detection.none)
        let prefixed = Self.shapeLine(["/Users/tester/x.claude"])
        #expect(SessionProfile.detect(line: prefixed, candidates: Self.candidates([.init(accountId: "x", path: "~/.claude", rank: .main)]))
                == SessionProfile.Detection.none)
        // Quote, whitespace, parenthesis and an escaped newline are boundaries.
        for lead in ["\"", " ", "(", "\\n", "'"] {
            let text = #"{"type":"api-request-shape","shape":{"system":[{"text":"memory:\#(lead)/Users/tester/.claude/projects/p/memory/"}]}}"#
            #expect(SessionProfile.detect(line: text, candidates: candidates) == .named("/Users/tester/.claude"), "lead \(lead)")
        }
        let start = "/Users/tester/.claude/projects/ \"type\":\"api-request-shape\""
        #expect(SessionProfile.detect(line: start, candidates: candidates) == .named("/Users/tester/.claude"))
    }

    /// Plan review finding 11: the key names each directory's claimants and
    /// rank, so a directory that moves between accounts or ranks changes it.
    @Test func keyFollowsClaimantsAndRanks() {
        let base = Self.candidates([.init(accountId: "max", path: "~/.claude", rank: .main),
                                    .init(accountId: "work", path: "~/agent-profiles/work/claude", rank: .main),
                                    .init(accountId: "max", path: "~/.claude-lab", rank: .additional)])
        let same = Self.candidates([.init(accountId: "max", path: "~/.claude-lab", rank: .additional),
                                    .init(accountId: "work", path: "~/agent-profiles/work/claude", rank: .main),
                                    .init(accountId: "max", path: "~/.claude/", rank: .main)])
        #expect(base.key == same.key)
        let moved = Self.candidates([.init(accountId: "max", path: "~/.claude", rank: .main),
                                     .init(accountId: "work", path: "~/agent-profiles/work/claude", rank: .main),
                                     .init(accountId: "work", path: "~/.claude-lab", rank: .additional)])
        #expect(base.key != moved.key)
        let promoted = Self.candidates([.init(accountId: "max", path: "~/.claude", rank: .main),
                                        .init(accountId: "work", path: "~/agent-profiles/work/claude", rank: .main),
                                        .init(accountId: "max", path: "~/.claude-lab", rank: .main)])
        #expect(base.key != promoted.key)
        #expect(base.directories == ["/Users/tester/.claude", "/Users/tester/agent-profiles/work/claude", "/Users/tester/.claude-lab"])
        #expect(base.claimKey(forDirectory: "/Users/tester/.claude-lab") != moved.claimKey(forDirectory: "/Users/tester/.claude-lab"))
        #expect(base.claimKey(forDirectory: "/Users/tester/.claude") == moved.claimKey(forDirectory: "/Users/tester/.claude"))
        #expect(base.claimKey(forDirectory: "/Users/tester/elsewhere") == nil)
    }

    /// FR-004, SC-004: nothing of the line but the matched directory leaves
    /// the detection.
    @Test func onlyTheDirectoryLeavesTheLine() {
        let line = Self.shapeLine(["/Users/tester/agent-profiles/work/claude"])
        #expect(line.contains(Self.marker))
        let detection = SessionProfile.detect(line: line, candidates: Self.three)
        #expect(!String(describing: detection).contains(Self.marker))
        #expect(!String(reflecting: detection).contains(Self.marker))
        #expect(!String(reflecting: Self.three).contains(Self.marker))
    }
}
