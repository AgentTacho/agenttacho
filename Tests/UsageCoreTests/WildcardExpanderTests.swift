import Foundation
import Testing
@testable import UsageCore

/// spec 035 FR-004, FR-005, FR-006, research R3, contracts/directory-resolution.md
/// "Wildcard expansion": which folders an entry with `*` names.
@Suite struct WildcardPatternTests {
    @Test func starMatchesAnyRunWithinOneName() {
        #expect(WildcardPattern.matches(name: "alpha", component: "*"))
        #expect(WildcardPattern.matches(name: ".claude-lab", component: ".claude-*"))
        #expect(WildcardPattern.matches(name: ".claude-", component: ".claude-*"))
        #expect(!WildcardPattern.matches(name: ".claude", component: ".claude-*"))
        #expect(WildcardPattern.matches(name: "sandbox-a", component: "sandbox-*"))
        #expect(WildcardPattern.matches(name: "a-sandbox-b-x", component: "*sandbox*x"))
        #expect(WildcardPattern.matches(name: "ab", component: "a*b"))
        #expect(!WildcardPattern.matches(name: "aXb", component: "a*bb"))
        #expect(WildcardPattern.matches(name: "abab", component: "a*b*b"))
        #expect(!WildcardPattern.matches(name: "aba", component: "a*b*b"))
        #expect(WildcardPattern.matches(name: "lab", component: "lab"))
        #expect(!WildcardPattern.matches(name: "lab2", component: "lab"))
    }

    /// A component that starts with `*` never matches a dot name.
    @Test func leadingStarSkipsDotNames() {
        #expect(!WildcardPattern.matches(name: ".cache", component: "*"))
        #expect(!WildcardPattern.matches(name: ".claude-lab", component: "*-lab"))
        #expect(WildcardPattern.matches(name: ".claude-lab", component: ".*"))
    }

    /// Only `*` is special.
    @Test func otherGlobCharactersAreLiteral() {
        #expect(WildcardPattern.matches(name: "a?[b]{c}", component: "a?[b]{c}"))
        #expect(!WildcardPattern.matches(name: "ax", component: "a?"))
        #expect(!WildcardPattern.matches(name: "ab", component: "a[b]"))
        #expect(WildcardPattern.matches(name: "a?x", component: "a?*"))
    }
}

@Suite struct WildcardExpanderTests {
    static let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    let home = "/Users/tester"
    var openshell: String { home + "/agent-sessions/openshell" }

    static func expand(_ entry: String, _ fs: InMemoryDirectoryFileSystem) -> WildcardExpansion {
        WildcardExpander(paths: paths, fileSystem: fs).expand(entry)
    }

    /// The first row of the contract table: one level, no dot names, no
    /// files.
    @Test func sandboxFoldersMatchOneLevel() {
        let fs = InMemoryDirectoryFileSystem(folders: [openshell + "/alpha/claude", openshell + "/beta/claude",
                                                       openshell + "/.cache/claude", openshell + "/team/alpha/claude"])
        fs.addFile(openshell + "/gamma/claude.txt")
        fs.addFile(openshell + "/delta")
        let expansion = Self.expand("~/agent-sessions/openshell/*/claude", fs)
        #expect(expansion.paths == [openshell + "/alpha/claude", openshell + "/beta/claude"])
        #expect(expansion.matched == 2)
        #expect(expansion.listingErrors.isEmpty)
        #expect(!expansion.isCapped)
        #expect(expansion.entry == "~/agent-sessions/openshell/*/claude")
    }

    @Test func partialNames() {
        let fs = InMemoryDirectoryFileSystem(folders: [home + "/.claude-lab", home + "/.claude-personal", home + "/.claude",
                                                       home + "/sandbox-a", home + "/sandbox-b/x"])
        fs.addFile(home + "/.claude-notes")
        #expect(Self.expand("~/.claude-*", fs).paths == [home + "/.claude-lab", home + "/.claude-personal"])
        #expect(Self.expand("~/sandbox-*/x", fs).paths == [home + "/sandbox-b/x"])
    }

    /// A symlink to a folder matches, with the spelling under the entry.
    @Test func symlinkToAFolderMatches() {
        let fs = InMemoryDirectoryFileSystem(folders: ["/Volumes/data/box/claude"])
        fs.addFolder(openshell)
        fs.addSymlink(openshell + "/link", to: "/Volumes/data/box")
        fs.addSymlink(openshell + "/dangling", to: "/Volumes/none")
        #expect(Self.expand("~/agent-sessions/openshell/*/claude", fs).paths == [openshell + "/link/claude"])
    }

    @Test func missingParentGivesNoMatchAndNoError() {
        let fs = InMemoryDirectoryFileSystem(folders: [home])
        let expansion = Self.expand("~/agent-sessions/none/*/claude", fs)
        #expect(expansion.paths.isEmpty)
        #expect(expansion.matched == 0)
        #expect(expansion.listingErrors.isEmpty)
    }

    @Test func unreadableParentIsAListingError() {
        let fs = InMemoryDirectoryFileSystem(folders: [openshell + "/alpha/claude", home + "/other/beta/claude"])
        fs.makeUnreadable(openshell)
        let expansion = Self.expand("~/agent-sessions/openshell/*/claude", fs)
        #expect(expansion.paths.isEmpty)
        #expect(expansion.listingErrors == [WildcardListingError(path: openshell, reason: "not readable")])
        // A deeper level that cannot be listed is named too.
        fs.makeUnreadable(home + "/other/beta")
        let deeper = Self.expand("~/other/*/*", fs)
        #expect(deeper.listingErrors.map(\.path) == [home + "/other/beta"])
    }

    /// A match that is the home folder or `/` is dropped and not counted
    /// (spec 035 FR-006); the contract's `/Users/*` row.
    @Test func homeAndRootMatchesAreDropped() {
        let fs = InMemoryDirectoryFileSystem(folders: [home, "/Users/guest", "/Users/shared"])
        let expansion = Self.expand("/Users/*", fs)
        #expect(expansion.paths == ["/Users/guest", "/Users/shared"])
        #expect(expansion.matched == 2)
        // A symlinked base that resolves to the home folder.
        fs.addSymlink("/links/me", to: home)
        #expect(Self.expand("/links/m*", fs).paths.isEmpty)
        #expect(Self.expand("/links/m*", fs).matched == 0)
    }

    /// Path order by `String <`, then the cap of 100 (spec 035 FR-005).
    @Test func capKeepsTheFirstHundredInPathOrder() {
        let fs = InMemoryDirectoryFileSystem()
        for index in 0...100 { fs.addFolder(openshell + "/box-\(String(format: "%03d", index))/claude") }
        fs.addFolder(openshell + "/Box/claude")
        let expansion = Self.expand("~/agent-sessions/openshell/*/claude", fs)
        #expect(expansion.matched == 102)
        #expect(expansion.paths.count == 100)
        #expect(expansion.isCapped)
        // Upper case sorts before lower case in byte order.
        #expect(expansion.paths.first == openshell + "/Box/claude")
        #expect(expansion.paths.last == openshell + "/box-098/claude")
        #expect(WildcardExpander.cap == 100)
    }

    /// Two `*` levels give every combination, in path order, folders only.
    @Test func twoStarComponentsExpandEveryLevel() {
        let box = home + "/box"
        let fs = InMemoryDirectoryFileSystem(folders: [box + "/a/x", box + "/a/y", box + "/b/x"])
        fs.addFile(box + "/b/z")
        let expansion = Self.expand("~/box/*/*", fs)
        #expect(expansion.paths == [box + "/a/x", box + "/a/y", box + "/b/x"])
        #expect(expansion.canonicalPaths == expansion.paths)
    }

    /// Exactly 100 matches are all read and not capped (FR-005 boundary).
    @Test func exactlyHundredIsNotCapped() {
        let fs = InMemoryDirectoryFileSystem()
        for index in 0..<100 { fs.addFolder(openshell + "/box-\(String(format: "%03d", index))/claude") }
        let expansion = Self.expand("~/agent-sessions/openshell/*/claude", fs)
        #expect(expansion.matched == 100)
        #expect(expansion.paths.count == 100)
        #expect(!expansion.isCapped)
    }

    /// A match that resolves to `/` through a symlink is dropped too.
    @Test func rootThroughASymlinkIsDropped() {
        let fs = InMemoryDirectoryFileSystem(folders: ["/links/real"])
        fs.addSymlink("/links/root", to: "/")
        let expansion = Self.expand("/links/r*", fs)
        #expect(expansion.paths == ["/links/real"])
        #expect(expansion.matched == 1)
    }

    /// A bare `*` never lists the home folder or `/` under another
    /// spelling (spec 035 FR-006): the folder is named as not listed.
    @Test func bareStarUnderAnotherSpellingOfHomeIsNotListed() {
        let fs = InMemoryDirectoryFileSystem(folders: [home + "/Work", home + "/Documents"])
        fs.addSymlink("/links/me", to: home)
        fs.addSymlink("/links/top", to: "/")
        let viaLink = Self.expand("/links/me/*", fs)
        #expect(viaLink.paths.isEmpty)
        #expect(viaLink.listingErrors == [WildcardListingError(path: "/links/me", reason: WildcardListingError.bareStarReason)])
        #expect(Self.expand("/links/top/*", fs).paths.isEmpty)
        // A partial name under the home folder stays allowed.
        #expect(Self.expand("/links/me/W*", fs).paths == ["/links/me/Work"])
    }

    /// A level with more than `levelBudget` candidates keeps the first
    /// ones in path order and marks the expansion truncated.
    @Test func levelBudgetBoundsTheWork() {
        let fs = InMemoryDirectoryFileSystem()
        for index in 0...WildcardExpander.levelBudget { fs.addFolder(home + "/many/d-\(String(format: "%05d", index))/claude") }
        let expansion = Self.expand("~/many/*/*", fs)
        #expect(expansion.isTruncated)
        #expect(expansion.matched == WildcardExpander.levelBudget)
        #expect(expansion.paths.count == WildcardExpander.cap)
        #expect(!Self.expand("~/many/d-0000*/*", fs).isTruncated)
        #expect(WildcardExpander.levelBudget == 1000)
    }

    /// A trailing slash and `..` are standardized before matching.
    @Test func entryIsStandardized() {
        let fs = InMemoryDirectoryFileSystem(folders: [openshell + "/alpha/claude"])
        #expect(Self.expand("~/agent-sessions/x/../openshell/*/claude/", fs).paths == [openshell + "/alpha/claude"])
    }

    /// One run on disk with `LocalDirectoryFileSystem`, including a symlink
    /// and a file that must not match.
    @Test func localFileSystemRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wildcard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let base = root.appendingPathComponent("agent-sessions/openshell")
        try fm.createDirectory(at: base.appendingPathComponent("alpha/claude"), withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent(".cache/claude"), withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("gamma"), withIntermediateDirectories: true)
        try Data().write(to: base.appendingPathComponent("gamma/claude"))
        try fm.createDirectory(at: root.appendingPathComponent("elsewhere/box/claude"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: base.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("elsewhere/box"))
        let paths = Paths(home: root)
        let expansion = WildcardExpander(paths: paths, fileSystem: LocalDirectoryFileSystem()).expand("~/agent-sessions/openshell/*/claude")
        let expected = [paths.expand("~/agent-sessions/openshell/alpha/claude"), paths.expand("~/agent-sessions/openshell/link/claude")]
        #expect(expansion.paths == expected)
        #expect(expansion.listingErrors.isEmpty)
        #expect(LocalDirectoryFileSystem().contents(ofDirectory: root.appendingPathComponent("none").path) == .missing)
        // A link that points at itself is no folder and no error.
        try fm.createSymbolicLink(atPath: base.appendingPathComponent("loop").path, withDestinationPath: "loop")
        let again = WildcardExpander(paths: paths, fileSystem: LocalDirectoryFileSystem()).expand("~/agent-sessions/openshell/*/claude")
        #expect(again.paths == expected)
        #expect(again.listingErrors.isEmpty)
        #expect(LocalDirectoryFileSystem().canonicalPath(expected[1]) == Attributor.canonical(root.appendingPathComponent("elsewhere/box/claude").path))
    }
}
