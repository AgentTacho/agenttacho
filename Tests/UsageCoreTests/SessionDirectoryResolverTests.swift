import Foundation
import Testing
@testable import UsageCore

/// spec 035 FR-005, FR-008, FR-012, research R4, contracts/directory-resolution.md
/// "Resolution order": the directories one refresh reads per harness.
@Suite struct SessionDirectoryResolverTests {
    static let home = "/Users/tester"
    static let paths = Paths(home: URL(fileURLWithPath: home))
    typealias Make = AdditionalSessionDirectoryTests

    static func resolve(_ harness: Harness, _ accounts: [Account], _ fs: InMemoryDirectoryFileSystem) -> SessionDirectoryResolution {
        SessionDirectoryResolver(paths: paths, fileSystem: fs).resolve(harness, configuration: Make.config(accounts))
    }

    static func listed(_ resolution: SessionDirectoryResolution) -> [String] {
        resolution.directories.map(\.path)
    }

    @Test func mainsFirstThenEntriesInAccountsAndListOrder() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem(folders: [h + "/agent-sessions/openshell/beta/claude", h + "/agent-sessions/openshell/alpha/claude"])
        let resolution = Self.resolve(.claudeCode, [
            Make.claude("max", "~/.claude", extra: ["~/agent-sessions/openshell/*/claude", "~/.claude-lab"]),
            Make.token("vertex", .vertex, "~/profiles/acme/claude", extra: ["~/.claude-vertex"]),
        ], fs)
        #expect(Self.listed(resolution) == [h + "/.claude", h + "/profiles/acme/claude",
                                            h + "/agent-sessions/openshell/alpha/claude", h + "/agent-sessions/openshell/beta/claude",
                                            h + "/.claude-lab", h + "/.claude-vertex"])
        #expect(resolution.directories.map(\.origin) == [
            .main, .main,
            .wildcard(entry: "~/agent-sessions/openshell/*/claude"), .wildcard(entry: "~/agent-sessions/openshell/*/claude"),
            .literal(entry: "~/.claude-lab"), .literal(entry: "~/.claude-vertex"),
        ])
        #expect(resolution.directories.map(\.isMain) == [true, true, false, false, false, false])
    }

    /// One directory reached as a main directory, a literal entry, a
    /// wildcard match and through another account is listed once, with the
    /// first spelling and origin (SC-003).
    @Test func dedupeByCanonicalPathKeepsTheFirstRoute() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem(folders: [h + "/.claude-lab", h + "/box/alpha"])
        fs.addSymlink(h + "/link-lab", to: h + "/.claude-lab")
        let resolution = Self.resolve(.claudeCode, [
            Make.claude("max", "~/.claude-lab", extra: [h + "/.claude-lab/", "~/link-lab", "~/.claude-*", "~/box/*"]),
            Make.claude("pro", "~/.claude-pro", extra: ["~/box/alpha", "~/.claude-lab"]),
        ], fs)
        #expect(Self.listed(resolution) == [h + "/.claude-lab", h + "/.claude-pro", h + "/box/alpha"])
        #expect(resolution.directories.map(\.origin) == [.main, .main, .wildcard(entry: "~/box/*")])
        #expect(resolution.directories.map(\.canonical) == [h + "/.claude-lab", h + "/.claude-pro", h + "/box/alpha"])
    }

    /// Each subscription account's own literal and matched directories,
    /// canonical, even when first reached another way; token-based accounts
    /// never reach the tie-breaker.
    @Test func additionalByAccountHoldsEverySubscriptionClaim() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem(folders: [h + "/box/alpha", h + "/box/beta"])
        fs.addSymlink(h + "/link", to: h + "/box/beta")
        let claude = Self.resolve(.claudeCode, [
            Make.claude("max", "~/.claude", extra: ["~/box/*", "~/.claude-pro"]),
            Make.claude("pro", "~/.claude-pro", extra: ["~/link"]),
            Make.token("vertex", .vertex, extra: ["~/.claude-vertex"]),
        ], fs)
        #expect(claude.additionalByAccount == [
            "max": [h + "/box/alpha", h + "/box/beta", h + "/.claude-pro"],
            "pro": [h + "/box/beta"],
        ])
        let codex = Self.resolve(.codex, [
            Make.codex("plus", "~/.codex-lab", extra: ["~/.codex"]),
            Make.token("openai", .openai, extra: ["~/.codex-api"]),
        ], fs)
        #expect(codex.additionalByAccount == ["plus": [h + "/.codex"]])
    }

    /// One report per distinct entry text, in first-seen order, even when
    /// two accounts list it; the entry is expanded once.
    @Test func oneReportPerEntryText() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem(folders: [h + "/box/alpha", h + "/sandboxes/one"])
        fs.makeUnreadable(h + "/sandboxes")
        let shared = "~/box/*"
        let before = fs.listingCount
        let resolution = Self.resolve(.claudeCode, [
            Make.claude("max", extra: [shared, "~/sandboxes/*", "~/none/*"]),
            Make.claude("pro", "~/.claude-pro", extra: [shared]),
        ], fs)
        #expect(resolution.wildcards == [
            WildcardReport(entry: shared, matched: 1, read: 1, listingErrors: []),
            WildcardReport(entry: "~/sandboxes/*", matched: 0, read: 0, listingErrors: [WildcardListingError(path: h + "/sandboxes", reason: "not readable")]),
            WildcardReport(entry: "~/none/*", matched: 0, read: 0, listingErrors: []),
        ])
        #expect(fs.listingCount - before == 3)
        #expect(resolution.additionalByAccount["pro"] == [h + "/box/alpha"])
    }

    /// The home folder and `/` are never a Claude Code directory and never
    /// an additional Codex home; a Codex main home keeps today's behavior.
    @Test func homeAndRootAreSkipped() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem(folders: [h])
        let claude = Self.resolve(.claudeCode, [
            Make.claude("max", "~/", extra: ["~", "/"]),
            Make.token("vertex", .vertex, "/", extra: [h + "/"]),
        ], fs)
        #expect(claude.directories.isEmpty)
        #expect(claude.additionalByAccount.isEmpty)
        let codex = Self.resolve(.codex, [Make.codex("plus", "~/", extra: ["~", "/"])], fs)
        #expect(Self.listed(codex) == [h])
        #expect(codex.directories.map(\.origin) == [.main])
    }

    @Test func harnessFiltering() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem()
        let accounts = [
            Make.claude("max", extra: ["~/.claude-lab"]),
            Make.token("vertex", .vertex, extra: ["~/.claude-vertex"]),
            Make.codex("plus", extra: ["~/.codex-lab"]),
            Make.token("openai", .openai, extra: ["~/.codex-api"]),
        ]
        #expect(Self.listed(Self.resolve(.claudeCode, accounts, fs)) == [h + "/.claude", h + "/.claude-lab", h + "/.claude-vertex"])
        #expect(Self.listed(Self.resolve(.codex, accounts, fs)) == [h + "/.codex", h + "/.codex-lab", h + "/.codex-api"])
        #expect(Self.resolve(.openCode, accounts, fs).directories.isEmpty)
    }

    /// The example of contracts/directory-resolution.md.
    @Test func contractExample() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem(folders: [h + "/.claude", h + "/.claude-lab", h + "/agent-sessions/openshell/alpha/claude"])
        let resolution = Self.resolve(.claudeCode, [
            Make.claude("max", "", extra: ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"]),
            Make.token("vertex", .vertex, "~/.claude-lab"),
        ], fs)
        #expect(Self.listed(resolution) == [h + "/.claude", h + "/.claude-lab", h + "/agent-sessions/openshell/alpha/claude"])
        #expect(resolution.directories.map(\.origin) == [.main, .main, .wildcard(entry: "~/agent-sessions/openshell/*/claude")])
        #expect(resolution.additionalByAccount == ["max": [h + "/.claude-lab", h + "/agent-sessions/openshell/alpha/claude"]])
        #expect(resolution.wildcards == [WildcardReport(entry: "~/agent-sessions/openshell/*/claude", matched: 1, read: 1, listingErrors: [])])
    }

    /// Matches are evaluated anew on every call (SC-002).
    @Test func foldersAddedAndRemovedBetweenCalls() {
        let h = Self.home
        let base = h + "/agent-sessions/openshell"
        let fs = InMemoryDirectoryFileSystem(folders: [base + "/alpha/claude", base + "/beta/claude"])
        let accounts = [Make.claude("max", extra: ["~/agent-sessions/openshell/*/claude"])]
        let resolver = SessionDirectoryResolver(paths: Self.paths, fileSystem: fs)
        let config = Make.config(accounts)
        #expect(resolver.resolve(.claudeCode, configuration: config).directories.count == 3)
        fs.addFolder(base + "/gamma/claude")
        #expect(Self.listed(resolver.resolve(.claudeCode, configuration: config)).suffix(3)
                == [base + "/alpha/claude", base + "/beta/claude", base + "/gamma/claude"])
        fs.remove(base + "/beta")
        #expect(Self.listed(resolver.resolve(.claudeCode, configuration: config)).suffix(2)
                == [base + "/alpha/claude", base + "/gamma/claude"])
    }

    /// A `*` in a main directory field stays an ordinary character.
    @Test func starInAMainDirectoryIsNotExpanded() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem(folders: [h + "/box/alpha"])
        let claude = Self.resolve(.claudeCode, [Make.claude("max", "~/box/*"), Make.token("vertex", .vertex, "~/box/*")], fs)
        #expect(Self.listed(claude) == [h + "/box/*"])
        #expect(claude.wildcards.isEmpty)
        let codex = Self.resolve(.codex, [Make.codex("plus", "~/box/*")], fs)
        #expect(Self.listed(codex) == [h + "/box/*"])
    }

    /// Without entries the resolution is exactly the main directories of
    /// spec 034.
    @Test func withoutEntriesOnlyMains() {
        let h = Self.home
        let fs = InMemoryDirectoryFileSystem()
        let accounts = [Make.claude("max", "~/.claude-personal"), Make.token("vertex", .vertex), Make.claude("pro", "~/.claude-personal/"),
                        Make.codex("plus", "~/.codex-lab"), Make.token("openai", .openai, "~/.codex-lab")]
        let claude = Self.resolve(.claudeCode, accounts, fs)
        #expect(Self.listed(claude) == [h + "/.claude-personal", h + "/.claude"])
        #expect(claude.additionalByAccount.isEmpty)
        #expect(claude.wildcards.isEmpty)
        #expect(Self.listed(Self.resolve(.codex, accounts, fs)) == [h + "/.codex-lab"])
    }
}
