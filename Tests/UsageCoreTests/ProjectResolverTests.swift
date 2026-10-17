import Foundation
import Testing
@testable import UsageCore

@Suite struct ProjectResolverTests {
    private func clean(_ url: URL) -> String { (url.path as NSString).standardizingPath }

    private func makeRepo(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent(".git"), withIntermediateDirectories: true)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// `main` plus a worktree whose `.git` file points at
    /// `main/.git/worktrees/<name>` (absolute or relative gitdir).
    private func makeWorktree(main: URL, worktree: URL, relative: Bool) throws {
        let name = worktree.lastPathComponent
        let gitdir = main.appendingPathComponent(".git/worktrees/\(name)")
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        let pointer = relative ? "../\(main.lastPathComponent)/.git/worktrees/\(name)" : gitdir.path
        try write("gitdir: \(pointer)\n", to: worktree.appendingPathComponent(".git"))
    }

    @Test func repositoryRootAndSubdirectory() throws {
        let root = try makeTempDirectory("resolver-repo")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("agenttacho")
        try makeRepo(repo)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("Sources/UsageCore"), withIntermediateDirectories: true)

        let resolver = ProjectResolver()
        let expected = Project(rootPath: clean(repo))
        #expect(expected.name == "agenttacho")
        #expect(resolver.project(forCwd: repo.path) == expected)
        #expect(resolver.project(forCwd: repo.appendingPathComponent("Sources/UsageCore").path) == expected)
    }

    @Test func pathSpellingsMapToTheSameProject() throws {
        let root = try makeTempDirectory("resolver-spelling")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try makeRepo(repo)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)

        let resolver = ProjectResolver()
        let expected = Project(rootPath: clean(repo))
        #expect(resolver.project(forCwd: repo.path + "/") == expected)
        #expect(resolver.project(forCwd: repo.path + "/./sub/..") == expected)
    }

    @Test func worktreesResolveToTheMainRepository() throws {
        let root = try makeTempDirectory("resolver-worktree")
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main")
        try makeRepo(main)
        let absolute = root.appendingPathComponent("main-feature")
        let relative = root.appendingPathComponent("main-relative")
        try makeWorktree(main: main, worktree: absolute, relative: false)
        try makeWorktree(main: main, worktree: relative, relative: true)

        let resolver = ProjectResolver()
        let expected = Project(rootPath: clean(main))
        #expect(resolver.project(forCwd: absolute.path) == expected)
        #expect(resolver.project(forCwd: relative.path) == expected)
        #expect(resolver.drainNotes().isEmpty)
    }

    @Test func worktreeWithoutCommondirIsItsOwnProject() throws {
        let root = try makeTempDirectory("resolver-no-commondir")
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main")
        try makeRepo(main)
        let wt = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: main.appendingPathComponent(".git/worktrees/wt"), withIntermediateDirectories: true)
        try write("gitdir: \(main.path)/.git/worktrees/wt\n", to: wt.appendingPathComponent(".git"))

        #expect(ProjectResolver().project(forCwd: wt.path) == Project(rootPath: clean(wt)))
    }

    @Test func submoduleIsItsOwnProjectEvenUnderAWorktreesFolder() throws {
        let root = try makeTempDirectory("resolver-submodule")
        defer { try? FileManager.default.removeItem(at: root) }
        // The parent repository lives in a folder named "worktrees".
        let parent = root.appendingPathComponent("worktrees/app")
        try makeRepo(parent)
        let sub = parent.appendingPathComponent("vendor/lib")
        try FileManager.default.createDirectory(at: parent.appendingPathComponent(".git/modules/lib"), withIntermediateDirectories: true)
        try write("gitdir: ../../.git/modules/lib\n", to: sub.appendingPathComponent(".git"))

        #expect(ProjectResolver().project(forCwd: sub.path) == Project(rootPath: clean(sub)))
    }

    @Test func foldersOutsideARepositoryAreTheirOwnProject() throws {
        let root = try makeTempDirectory("resolver-plain")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let resolver = ProjectResolver()
        #expect(resolver.project(forCwd: folder.path) == Project(rootPath: clean(folder)))
        #expect(resolver.project(forCwd: "/")?.name == "/")
        #expect(resolver.drainNotes().isEmpty)
    }

    @Test func missingDirectoryAndUnreadableGitFileFallBackWithANote() throws {
        let root = try makeTempDirectory("resolver-fallback")
        defer { try? FileManager.default.removeItem(at: root) }
        let gone = root.appendingPathComponent("deleted/project").path
        let broken = root.appendingPathComponent("broken")
        try write("not a pointer\n", to: broken.appendingPathComponent(".git"))

        let resolver = ProjectResolver()
        #expect(resolver.project(forCwd: gone) == Project(rootPath: (gone as NSString).standardizingPath))
        #expect(resolver.project(forCwd: broken.path) == Project(rootPath: clean(broken)))
        let notes = resolver.drainNotes()
        #expect(notes.count == 2)
        #expect(notes.first?.hasPrefix("project fallback for \((gone as NSString).standardizingPath): directory not found") == true)
        #expect(notes.last?.hasPrefix("project fallback for \(clean(broken)): unreadable .git file") == true)
        #expect(resolver.drainNotes().isEmpty)
    }

    @Test func deletedDirectoryInsideARepositoryCountsTowardIt() throws {
        let root = try makeTempDirectory("resolver-deleted-worktree")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("agenttacho")
        try makeRepo(repo)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".claude/worktrees"), withIntermediateDirectories: true)
        // A removed Claude Code worktree and a subdirectory of it.
        let worktree = repo.appendingPathComponent(".claude/worktrees/003-monthly-budget-period")
        let nested = worktree.appendingPathComponent("Sources")

        let resolver = ProjectResolver()
        let expected = Project(rootPath: clean(repo))
        #expect(resolver.project(forCwd: worktree.path) == expected)
        #expect(resolver.project(forCwd: nested.path) == expected)
        #expect(resolver.drainNotes().isEmpty)
    }

    @Test func worktreeOfABareRepositoryResolvesToTheBareRepository() throws {
        let root = try makeTempDirectory("resolver-bare")
        defer { try? FileManager.default.removeItem(at: root) }
        let bare = root.appendingPathComponent("src/project.git")
        let gitdir = bare.appendingPathComponent("worktrees/feature")
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        let wt = root.appendingPathComponent("src/feature")
        try write("gitdir: \(gitdir.path)\n", to: wt.appendingPathComponent(".git"))

        #expect(ProjectResolver().project(forCwd: wt.path) == Project(rootPath: clean(bare)))
    }

    @Test func nilOrEmptyCwdHasNoProject() {
        let resolver = ProjectResolver()
        #expect(resolver.project(forCwd: nil) == nil)
        #expect(resolver.project(forCwd: "") == nil)
        #expect(resolver.lookups == 0)
    }

    @Test func resultsAreCachedPerCwd() throws {
        let root = try makeTempDirectory("resolver-cache")
        let repo = root.appendingPathComponent("repo")
        try makeRepo(repo)

        let resolver = ProjectResolver()
        let first = resolver.project(forCwd: repo.path)
        try FileManager.default.removeItem(at: root)
        // The directory is gone; a second walk would fall back and add a note.
        #expect(resolver.project(forCwd: repo.path) == first)
        #expect(resolver.lookups == 1)
        #expect(resolver.drainNotes().isEmpty)
    }
}
