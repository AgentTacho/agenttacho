# Project Breakdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the top 5 projects (git repositories) of each Details section in the dropdown, switchable with the existing per-model view.

**Architecture:** The session-log parser extracts each record's `cwd`; a cached `ProjectResolver` maps it to a git repository root (worktrees merged into their main repository); `LogIndex` stores the project on every `UsageRecord`; the pure `Aggregator` builds a ranked `perProject` list per breakdown; `UsageBreakdown.topProjects` cuts it to 5 rows plus "Other" with shares that add up to 100; `BreakdownView` gets a shared `Models | Projects` switch.

**Tech Stack:** Swift 5 language mode, SwiftPM, Swift Testing (`@Test`, `#expect`), SwiftUI (macOS 14+), Foundation only.

**Spec:** `docs/superpowers/specs/2026-10-14-project-breakdown-design.md`

## Global Constraints

- Build and test only through the Makefile: `make test` (adds the Swift Testing plugin path) and `make build` / `make run` (builds against the macOS 26 SDK; plain `swift build` fails on the macOS 27 SDK with "plugin for module 'SwiftUIMacros' not found").
- `Aggregator` stays free of filesystem access; only `ProjectResolver` touches the filesystem.
- The resolver never throws; failures fall back to the `cwd` folder.
- The switch is one shared choice stored under the UserDefaults key `detailsMode`, default Models.
- Top 5 rows plus "Other (n)"; no Total row in the Projects view; the day row stays unchanged in both views.
- Commit messages follow the repo style (`feat(scope): ...`) and end with the trailer `Assisted-By: 🤖 Claude Code`.
- Match the surrounding code: doc comments on public types and non-obvious functions, no comments that restate code.

## Review Focus

- Many working directories that no longer exist (deleted scratch and temp folders are common in `~/.claude/projects`): the diagnostic log gets one summary line per refresh, not one line per directory. Pinned in Task 3.
- A worktree whose `gitdir:` is a relative path (git 2.48 `worktree.useRelativePaths`) resolves to the main repository like an absolute one. Pinned in Task 2.
- A `cwd` with a trailing slash, `/./` or `..` components maps to the same project as its clean form. Pinned in Task 2.
- Shares of a section without an Other row (3 equal projects) still add up to exactly 100, not 99 or 101. Pinned in Task 5.
- A directory named `worktrees` somewhere in the path of an ordinary submodule must not be mistaken for a git worktree. Pinned in Task 2.

---

### Task 1: Parser extracts the working directory

**Files:**
- Modify: `Sources/UsageCore/Logs/UsageRecord.swift` (`RawUsageRecord`)
- Modify: `Sources/UsageCore/Logs/SessionRecordParser.swift` (`parse(data:)`, `Envelope`)
- Modify: `Tests/UsageCoreTests/FixtureSupport.swift` (`makeRaw`)
- Test: `Tests/UsageCoreTests/SessionRecordParserTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `RawUsageRecord.cwd: String?` (nil when absent or empty); `RawUsageRecord.init(..., cacheReadTokens: Int, cwd: String? = nil)`; test helper `makeRaw(..., cwd: String? = nil)`.

- [ ] **Step 1: Write the failing test**

Add to `SessionRecordParserTests`:

```swift
    @Test func extractsWorkingDirectory() {
        let line = #"{"type":"assistant","cwd":"/Users/me/work/repo","timestamp":"2026-10-12T10:00:00Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-4-6","usage":{"input_tokens":1,"output_tokens":1}}}"#
        #expect(parser.parse(line: line)?.cwd == "/Users/me/work/repo")

        let missing = line.replacingOccurrences(of: #""cwd":"/Users/me/work/repo","#, with: "")
        #expect(parser.parse(line: missing)?.cwd == nil)

        let empty = line.replacingOccurrences(of: "/Users/me/work/repo", with: "")
        #expect(parser.parse(line: empty)?.cwd == nil)
    }

    @Test func dedupeKeepsTheLastWorkingDirectory() {
        let records = [makeRaw(id: "m1", output: 1, cwd: "/a"), makeRaw(id: "m1", output: 2, cwd: "/b")]
        #expect(SessionRecordParser.dedupe(records).map(\.cwd) == ["/b"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test 2>&1 | grep -E "error:|✘" | head`
Expected: compile error "value of type 'RawUsageRecord' has no member 'cwd'" (and "extra argument 'cwd'").

- [ ] **Step 3: Implement**

In `RawUsageRecord` add the field after `cacheReadTokens`, extend the initializer with a defaulted parameter and assign it:

```swift
    public var cacheReadTokens: Int
    /// The session's working directory; nil when the line has none.
    public var cwd: String?

    public init(messageId: String, timestamp: Date, model: String, requestId: String, inputTokens: Int, outputTokens: Int, cacheWrite5mTokens: Int, cacheWrite1hTokens: Int, cacheReadTokens: Int, cwd: String? = nil) {
        // ... existing assignments unchanged ...
        self.cwd = cwd
    }
```

In `SessionRecordParser.Envelope` add `let cwd: String?`, and pass it when building the record in `parse(data:)`:

```swift
                                    cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                                    cwd: envelope.cwd.flatMap { $0.isEmpty ? nil : $0 })
```

In `FixtureSupport.swift` extend `makeRaw`:

```swift
func makeRaw(id: String = "msg_1", requestId: String = "req_vrtx_1", model: String = "claude-opus-5-5",
             timestamp: Date = isoDate("2026-10-12T10:00:00Z"),
             input: Int = 0, output: Int = 0, cw5m: Int = 0, cw1h: Int = 0, cr: Int = 0, cwd: String? = nil) -> RawUsageRecord {
    RawUsageRecord(messageId: id, timestamp: timestamp, model: model, requestId: requestId,
                   inputTokens: input, outputTokens: output, cacheWrite5mTokens: cw5m, cacheWrite1hTokens: cw1h, cacheReadTokens: cr,
                   cwd: cwd)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test 2>&1 | grep -E "error:|✘|Test run" | tail -3`
Expected: `✔ Test run with N tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Logs/UsageRecord.swift Sources/UsageCore/Logs/SessionRecordParser.swift Tests/UsageCoreTests/FixtureSupport.swift Tests/UsageCoreTests/SessionRecordParserTests.swift
git commit -m "feat(logs): extract the working directory of session log records" -m "Assisted-By: 🤖 Claude Code"
```

---

### Task 2: ProjectResolver

**Files:**
- Create: `Sources/UsageCore/Logs/ProjectResolver.swift`
- Test: `Tests/UsageCoreTests/ProjectResolverTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct Project: Equatable, Hashable, Sendable { rootPath: String; name: String; init(rootPath: String) }`; `name` is the last path component (`"/"` for the root).
  - `public final class ProjectResolver { init(fileManager: FileManager = .default); func project(forCwd: String?) -> Project?; func drainNotes() -> [String]; private(set) var lookups: Int }`.
  - Note text format: `"project fallback for <path>: <reason>"`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/UsageCoreTests/ProjectResolverTests.swift`:

```swift
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

    /// `main` plus a worktree `wt` whose `.git` file points at
    /// `main/.git/worktrees/wt` (absolute or relative gitdir).
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
        #expect(notes[0].hasPrefix("project fallback for \((gone as NSString).standardizingPath): directory not found"))
        #expect(notes[1].hasPrefix("project fallback for \(clean(broken)): unreadable .git file"))
        #expect(resolver.drainNotes().isEmpty)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test 2>&1 | grep -E "error:" | head -3`
Expected: "cannot find 'ProjectResolver' in scope" / "cannot find 'Project' in scope".

- [ ] **Step 3: Implement**

Create `Sources/UsageCore/Logs/ProjectResolver.swift`:

```swift
import Foundation

/// The project a usage record belongs to: the git repository root of the
/// session's working directory, or that directory itself outside a
/// repository (spec 2026-10-14 project breakdown).
public struct Project: Equatable, Hashable, Sendable {
    /// Standardized absolute path; the project's identity.
    public var rootPath: String
    /// Last path component of `rootPath` ("/" for the file system root).
    public var name: String

    public init(rootPath: String) {
        self.rootPath = rootPath
        self.name = (rootPath as NSString).lastPathComponent
    }
}

/// Maps a session's working directory to its `Project`. Results are cached
/// per `cwd` string, so each directory touches the file system once per
/// resolver lifetime. Not thread-safe; `LogIndex` owns one and calls it from
/// its sequential merge phase.
public final class ProjectResolver {
    private let fileManager: FileManager
    private var cache: [String: Project] = [:]
    private var notes: [String] = []
    /// File system walks performed so far (cache misses).
    public private(set) var lookups = 0

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// nil for a missing or empty `cwd` (shown as "Unknown").
    public func project(forCwd cwd: String?) -> Project? {
        guard let cwd, !cwd.isEmpty else { return nil }
        if let cached = cache[cwd] { return cached }
        lookups += 1
        let project = resolve((cwd as NSString).standardizingPath)
        cache[cwd] = project
        return project
    }

    /// Returns and clears the fallback notes collected since the last call.
    public func drainNotes() -> [String] {
        defer { notes = [] }
        return notes
    }

    private func resolve(_ cwd: String) -> Project {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            notes.append("project fallback for \(cwd): directory not found")
            return Project(rootPath: cwd)
        }
        var dir = cwd
        while true {
            let git = (dir as NSString).appendingPathComponent(".git")
            var gitIsDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: git, isDirectory: &gitIsDirectory) {
                return gitIsDirectory.boolValue ? Project(rootPath: dir) : project(forGitFile: git, in: dir, cwd: cwd)
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return Project(rootPath: cwd) }
            dir = parent
        }
    }

    /// A `.git` file points at the real git directory. A worktree's points at
    /// `<common>/worktrees/<name>`, whose `commondir` leads back to the main
    /// repository; anything else (a submodule) is its own project.
    private func project(forGitFile git: String, in dir: String, cwd: String) -> Project {
        guard let text = try? String(contentsOfFile: git, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else {
            notes.append("project fallback for \(cwd): unreadable .git file at \(git)")
            return Project(rootPath: cwd)
        }
        var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !gitdir.isEmpty else {
            notes.append("project fallback for \(cwd): empty gitdir in \(git)")
            return Project(rootPath: cwd)
        }
        if !gitdir.hasPrefix("/") { gitdir = (dir as NSString).appendingPathComponent(gitdir) }
        gitdir = (gitdir as NSString).standardizingPath

        let container = ((gitdir as NSString).deletingLastPathComponent as NSString).lastPathComponent
        guard container == "worktrees",
              let raw = try? String(contentsOfFile: (gitdir as NSString).appendingPathComponent("commondir"), encoding: .utf8) else {
            return Project(rootPath: dir)
        }
        var common = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !common.isEmpty else { return Project(rootPath: dir) }
        if !common.hasPrefix("/") { common = (gitdir as NSString).appendingPathComponent(common) }
        common = (common as NSString).standardizingPath
        return Project(rootPath: (common as NSString).deletingLastPathComponent)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test 2>&1 | grep -E "ProjectResolver|error:|Test run" | tail -12`
Expected: every `ProjectResolverTests` test passes; full run passes.

If `pathSpellingsMapToTheSameProject` or the fallback test fails only because of a `/private` prefix difference, the cause is `standardizingPath` dropping `/private` for existing paths: keep `clean(_:)` in the test as the single way expectations are built, do not change the resolver.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Logs/ProjectResolver.swift Tests/UsageCoreTests/ProjectResolverTests.swift
git commit -m "feat(logs): resolve working directories to git repository projects" -m "Assisted-By: 🤖 Claude Code"
```

---

### Task 3: Records carry their project; resolver notes reach the log

**Files:**
- Modify: `Sources/UsageCore/Logs/UsageRecord.swift` (`UsageRecord`)
- Modify: `Sources/UsageCore/Logs/LogIndex.swift` (init, `readAndMerge`, new `drainProjectNotes`)
- Modify: `Sources/UsageCore/Logs/SessionLogSource.swift` (`collect(context:)`)
- Modify: `Tests/UsageCoreTests/FixtureSupport.swift` (`makeRecord`)
- Test: `Tests/UsageCoreTests/LogIndexTests.swift`

**Interfaces:**
- Consumes: `RawUsageRecord.cwd` (Task 1); `ProjectResolver`, `Project` (Task 2).
- Produces:
  - `UsageRecord.project: Project?`; `UsageRecord.init(..., costUSD: Decimal?, project: Project? = nil)`; `UsageRecord.init(raw:canonicalModel:accountId:costUSD:project: Project? = nil)`.
  - `LogIndex.init(batchBytes: Int = 64 * 1024 * 1024, projectResolver: ProjectResolver = ProjectResolver())`; `LogIndex.drainProjectNotes() -> [String]`.
  - `SessionLogSource.summarizeProjectNotes(_ notes: [String]) -> String` (static, internal).
  - Test helper `makeRecord(..., cost: Decimal?, project: Project? = nil)`.

- [ ] **Step 1: Write the failing tests**

In `LogIndexTests`, give the `record` helper an optional `cwd` (existing callers are unchanged):

```swift
    private func record(id: String, at timestamp: String, output: Int = 10, cwd: String? = nil) -> String {
        let cwdField = cwd.map { #""cwd":"\#($0)","# } ?? ""
        return """
        {\(cwdField)"type":"assistant","timestamp":"\(timestamp)","requestId":"req_vrtx_\(id)","uuid":"\(id)","sessionId":"s","message":{"id":"msg_vrtx_\(id)","model":"claude-opus-4-6","role":"assistant","content":[],"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":\(output)}}}
        """
    }
```

Add the tests:

```swift
    @Test func recordsKeepTheirProjectAcrossIncrementalUpdates() throws {
        let root = try makeTempDirectory("index-project")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("projects/p/s.jsonl")
        try writeRecords([record(id: "a", at: "2026-10-12T10:00:00Z", cwd: repo.path)], to: file)

        let index = LogIndex()
        _ = index.update(files: LogDirectoryScanner().scan(directories: [root.path]).files, window: window,
                         parser: parser, attributor: attributor(), pricer: pricer)
        try FileHandle(forWritingTo: file).withAppend(Data((record(id: "b", at: "2026-10-12T11:00:00Z", cwd: repo.path + "/sub") + "\n").utf8))
        _ = index.update(files: LogDirectoryScanner().scan(directories: [root.path]).files, window: window,
                         parser: parser, attributor: attributor(), pricer: pricer)

        let expected = Project(rootPath: (repo.path as NSString).standardizingPath)
        #expect(index.records.count == 2)
        #expect(index.records.allSatisfy { $0.project == expected })
    }

    @Test func sourceLogsProjectFallbacksAsOneSummaryLine() async throws {
        let root = try makeTempDirectory("source-project-notes")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(".claude/projects/p/s.jsonl")
        let lines = (1...7).map { record(id: "n\($0)", at: "2026-10-12T10:0\($0):00Z", cwd: "/nonexistent/scratch-\($0)") }
        try writeRecords(lines, to: file)
        try FileManager.default.setAttributes([.modificationDate: isoDate("2026-10-12T12:00:00Z")], ofItemAtPath: file.path)
        let logURL = root.appendingPathComponent("usage.log")
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer)

        _ = try await source.collect(context: RefreshContext(configuration: Configuration(), window: window, now: isoDate("2026-10-12T12:00:00Z")))

        let logLines = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        let fallback = logLines.filter { $0.contains("project fallback") }
        #expect(fallback.count == 1)
        #expect(fallback.first?.contains("7 working directories") == true)
        #expect(fallback.first?.contains("/nonexistent/scratch-1: directory not found") == true)
        #expect(fallback.first?.contains("and 2 more") == true)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test 2>&1 | grep -E "error:" | head -3`
Expected: "value of type 'UsageRecord' has no member 'project'".

- [ ] **Step 3: Implement the record field**

In `UsageRecord` add after `costUSD`:

```swift
    /// nil when the log line has no working directory ("Unknown").
    public var project: Project?
```

Add `project: Project? = nil` as the last parameter of both initializers; the memberwise one assigns `self.project = project`, the `init(raw:...)` one forwards `project: project`.

In `FixtureSupport.swift` extend `makeRecord` with a trailing `project: Project? = nil` and pass `project: project` to `UsageRecord(...)`.

- [ ] **Step 4: Implement resolution in LogIndex**

Extend the existing initializer (keep its `batchBytes` parameter and body) and add the notes accessor:

```swift
    private let batchBytes: Int
    private let projects: ProjectResolver

    public init(batchBytes: Int = 64 * 1024 * 1024, projectResolver: ProjectResolver = ProjectResolver()) {
        self.batchBytes = max(1, batchBytes)
        self.projects = projectResolver
    }

    /// Fallback notes from project resolution since the last call.
    public func drainProjectNotes() -> [String] {
        projects.drainNotes()
    }
```

In `readAndMerge`, phase 3, build the record with its project:

```swift
                    merged[Self.key(raw)] = UsageRecord(raw: raw, canonicalModel: PriceTable.canonicalModel(raw.model),
                                                        accountId: accountId, costUSD: pricer.cost(of: raw),
                                                        project: projects.project(forCwd: raw.cwd))
```

The re-pricing loop in `update` copies records with `var r = record`, so the project is kept there without changes.

- [ ] **Step 5: Implement the summary line in SessionLogSource**

In `collect(context:)`, right after `log?.append(source: name, message: message)`:

```swift
        let notes = index.drainProjectNotes()
        if !notes.isEmpty {
            log?.append(source: name, message: Self.summarizeProjectNotes(notes))
        }
```

And add:

```swift
    /// One line for all project fallbacks of a refresh: deleted scratch
    /// directories are common and must not flood the log.
    static func summarizeProjectNotes(_ notes: [String]) -> String {
        let shown = 5
        let details = notes.prefix(shown).map { $0.replacingOccurrences(of: "project fallback for ", with: "") }
        var text = "project fallback for \(notes.count) working director\(notes.count == 1 ? "y" : "ies"): "
            + details.joined(separator: "; ")
        if notes.count > shown { text += "; and \(notes.count - shown) more" }
        return text
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `make test 2>&1 | grep -E "error:|✘|Test run" | tail -3`
Expected: full run passes.

- [ ] **Step 7: Commit**

```bash
git add Sources/UsageCore/Logs/UsageRecord.swift Sources/UsageCore/Logs/LogIndex.swift Sources/UsageCore/Logs/SessionLogSource.swift Tests/UsageCoreTests/FixtureSupport.swift Tests/UsageCoreTests/LogIndexTests.swift
git commit -m "feat(logs): attach the resolved project to every usage record" -m "Assisted-By: 🤖 Claude Code"
```

---

### Task 4: Per-project aggregation

**Files:**
- Modify: `Sources/UsageCore/Snapshot/UsageSnapshot.swift` (new `ProjectUsage`, `UsageBreakdown.perProject`)
- Modify: `Sources/UsageCore/Snapshot/Aggregator.swift` (`breakdown(of:...)`, new `perProject(of:priced:)`)
- Test: `Tests/UsageCoreTests/AggregatorTests.swift`

**Interfaces:**
- Consumes: `UsageRecord.project`, `Project` (Tasks 2, 3); `makeRecord(..., project:)`.
- Produces:
  - `public struct ProjectUsage: Equatable, Sendable, Identifiable { project: Project?; displayName: String; totalTokens: Int; costUSD: Decimal?; pricedCostUSD: Decimal; priced: Bool; id: String }` where `id` is `project?.rootPath ?? ""`.
  - `UsageBreakdown.perProject: [ProjectUsage]` (ranked), init parameter `perProject: [ProjectUsage] = []`.
  - `Aggregator.perProject(of: [UsageRecord], priced: Bool) -> [ProjectUsage]` (internal).

`pricedCostUSD` is an addition to the spec's field list: it holds the sum of the priced records so that ranking and shares can use it while `costUSD` is nil for an unpriced project.

- [ ] **Step 1: Write the failing tests**

Add to `AggregatorTests`:

```swift
    let agenttacho = Project(rootPath: "/Users/me/work/agenttacho")
    let cfp = Project(rootPath: "/Users/me/work/cfp")

    @Test func perProjectTotalsAndRankingByCost() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1000, cost: 2, project: agenttacho),
            makeRecord(id: "b", accountId: "acc-v1", input: 10, cost: 5, project: cfp),
            makeRecord(id: "c", accountId: "acc-v2", input: 20, cost: 1, project: agenttacho),
            makeRecord(id: "d", accountId: "acc-v2", input: 7, cost: 1, project: nil),
        ])
        let projects = snapshot.groups["grp"]!.breakdown.perProject
        #expect(projects.map(\.displayName) == ["cfp", "agenttacho", "Unknown"])
        #expect(projects.map(\.pricedCostUSD) == [5, 3, 1])
        #expect(projects[1].totalTokens == 1020)
        #expect(projects[1].costUSD == 3)
        #expect(projects.map(\.id) == ["/Users/me/work/cfp", "/Users/me/work/agenttacho", ""])
    }

    @Test func perProjectRanksByTokensWithoutCostAndBreaksTiesByName() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-max", input: 100, cost: nil, project: cfp),
            makeRecord(id: "b", accountId: "acc-max", input: 300, cost: nil, project: agenttacho),
            makeRecord(id: "c", accountId: "acc-max", input: 100, cost: nil, project: Project(rootPath: "/x/beta")),
        ], subscriptions: ["acc-max": SubscriptionEntry(status: nil, state: .ok)])
        let projects = snapshot.subscriptions["acc-max"]!.breakdown.perProject
        #expect(projects.map(\.displayName) == ["agenttacho", "beta", "cfp"])
        #expect(projects.allSatisfy { $0.costUSD == nil && $0.priced })
    }

    @Test func unpricedProjectKeepsItsPricedPartForRanking() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1, cost: 4, project: agenttacho),
            makeRecord(id: "b", accountId: "acc-v1", input: 1, cost: nil, project: agenttacho),
            makeRecord(id: "c", accountId: "acc-v1", input: 1, cost: 3, project: cfp),
        ])
        let projects = snapshot.groups["grp"]!.breakdown.perProject
        #expect(projects.map(\.displayName) == ["agenttacho", "cfp"])
        #expect(projects[0].priced == false)
        #expect(projects[0].costUSD == nil)
        #expect(projects[0].pricedCostUSD == 4)
    }

    @Test func sameFolderNameInDifferentRootsShowsTheParent() {
        let snapshot = aggregate([
            makeRecord(id: "a", accountId: "acc-v1", input: 1, cost: 2, project: Project(rootPath: "/Users/me/work/app")),
            makeRecord(id: "b", accountId: "acc-v1", input: 1, cost: 1, project: Project(rootPath: "/Users/me/private/app")),
            makeRecord(id: "c", accountId: "acc-v1", input: 1, cost: 0, project: cfp),
        ])
        let names = snapshot.groups["grp"]!.breakdown.perProject.map(\.displayName)
        #expect(names == ["app (work)", "app (private)", "cfp"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test 2>&1 | grep -E "error:" | head -3`
Expected: "value of type 'UsageBreakdown' has no member 'perProject'".

- [ ] **Step 3: Add the types**

In `UsageSnapshot.swift`, after `DayUsage`:

```swift
/// Usage of one project (git repository) within a breakdown.
public struct ProjectUsage: Equatable, Sendable, Identifiable {
    /// nil = Unknown (log lines without a working directory).
    public var project: Project?
    /// The project name, `name (parent)` when another root in the same
    /// breakdown has the same name, or "Unknown".
    public var displayName: String
    public var totalTokens: Int
    /// nil when any record is unpriced, or cost is not applicable (token-only breakdowns).
    public var costUSD: Decimal?
    /// Sum of the priced records only; ranks and shares priced breakdowns.
    public var pricedCostUSD: Decimal
    public var priced: Bool

    public var id: String { project?.rootPath ?? "" }

    public init(project: Project?, displayName: String, totalTokens: Int = 0, costUSD: Decimal? = nil,
                pricedCostUSD: Decimal = 0, priced: Bool = true) {
        self.project = project
        self.displayName = displayName
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.pricedCostUSD = pricedCostUSD
        self.priced = priced
    }
}
```

In `UsageBreakdown` add `public var perProject: [ProjectUsage]` with the doc comment `/// All projects, ranked (cost in priced breakdowns, tokens otherwise).`, and the init parameter `perProject: [ProjectUsage] = []` after `perDay`, assigned in the body.

- [ ] **Step 4: Implement the aggregation**

In `Aggregator.breakdown(of:priced:window:calendar:)` pass `perProject: perProject(of: records, priced: priced)` to the `UsageBreakdown` initializer. Add:

```swift
    /// Per-project totals, ranked: priced breakdowns by priced cost, then
    /// tokens; token-only breakdowns by tokens; then name and path.
    func perProject(of records: [UsageRecord], priced: Bool) -> [ProjectUsage] {
        var byId: [String: ProjectUsage] = [:]
        for r in records {
            let id = r.project?.rootPath ?? ""
            var p = byId[id] ?? ProjectUsage(project: r.project, displayName: r.project?.name ?? "Unknown",
                                             costUSD: priced ? 0 : nil)
            p.totalTokens += r.totalTokens
            if priced {
                if let cost = r.costUSD {
                    p.pricedCostUSD += cost
                    if p.priced { p.costUSD = (p.costUSD ?? 0) + cost }
                } else {
                    p.priced = false
                    p.costUSD = nil
                }
            }
            byId[id] = p
        }

        var nameCounts: [String: Int] = [:]
        for p in byId.values {
            if let name = p.project?.name { nameCounts[name, default: 0] += 1 }
        }
        for (id, p) in byId {
            guard let project = p.project, (nameCounts[project.name] ?? 0) > 1 else { continue }
            let parent = ((project.rootPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
            byId[id]?.displayName = "\(project.name) (\(parent))"
        }

        return byId.values.sorted { a, b in
            if priced, a.pricedCostUSD != b.pricedCostUSD { return a.pricedCostUSD > b.pricedCostUSD }
            if a.totalTokens != b.totalTokens { return a.totalTokens > b.totalTokens }
            if a.displayName != b.displayName { return a.displayName < b.displayName }
            return a.id < b.id
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test 2>&1 | grep -E "error:|✘|Test run" | tail -3`
Expected: full run passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageCore/Snapshot/UsageSnapshot.swift Sources/UsageCore/Snapshot/Aggregator.swift Tests/UsageCoreTests/AggregatorTests.swift
git commit -m "feat(aggregator): rank usage per project in every breakdown" -m "Assisted-By: 🤖 Claude Code"
```

---

### Task 5: Top 5 projects with Other row and shares

**Files:**
- Modify: `Sources/UsageCore/Snapshot/UsageSnapshot.swift` (new `ProjectRanking`, `ProjectRanked`, `OtherProjects`, `UsageBreakdown.topProjects`, `UsageBreakdown.shares`)
- Test: `Tests/UsageCoreTests/AggregatorTests.swift`

**Interfaces:**
- Consumes: `ProjectUsage`, `UsageBreakdown.perProject` (Task 4).
- Produces:
  - `public struct ProjectRanking: Equatable, Sendable { top: [ProjectRanked]; other: OtherProjects? }`
  - `public struct ProjectRanked: Equatable, Sendable, Identifiable { usage: ProjectUsage; sharePercent: Int?; id: String }`
  - `public struct OtherProjects: Equatable, Sendable { count: Int; totalTokens: Int; costUSD: Decimal?; sharePercent: Int? }`
  - `UsageBreakdown.topProjects(limit: Int = 5, byCost: Bool) -> ProjectRanking`
  - `static func UsageBreakdown.shares(_ values: [Decimal]) -> [Int]?` (internal)

The spec writes `topProjects(limit: Int = 5)`; a breakdown does not know whether it is priced, so the caller passes `byCost` (the view's `showsCost`). Shares use largest-remainder rounding over the top rows plus Other, which keeps the column at exactly 100 also when there is no Other row (spec: "the column always adds up to 100").

- [ ] **Step 1: Write the failing tests**

Add to `AggregatorTests`:

```swift
    private func projects(_ tokens: [Int]) -> UsageBreakdown {
        let records = tokens.enumerated().map { i, t in
            makeRecord(id: "r\(i)", accountId: "acc-max", input: t, cost: nil, project: Project(rootPath: "/p/project\(i)"))
        }
        return aggregate(records, subscriptions: ["acc-max": SubscriptionEntry(status: nil, state: .ok)])
            .subscriptions["acc-max"]!.breakdown
    }

    @Test func topProjectsWithoutUsage() {
        let ranking = UsageBreakdown.empty.topProjects(byCost: false)
        #expect(ranking.top.isEmpty)
        #expect(ranking.other == nil)
    }

    @Test func topProjectsBelowAndAtTheLimitHaveNoOtherRow() {
        let three = projects([500, 300, 200]).topProjects(byCost: false)
        #expect(three.top.map(\.sharePercent) == [50, 30, 20])
        #expect(three.other == nil)
        let five = projects([5, 4, 3, 2, 1]).topProjects(byCost: false)
        #expect(five.top.count == 5)
        #expect(five.other == nil)
    }

    @Test func topProjectsAboveTheLimitAddAnOtherRow() {
        let ranking = projects([400, 200, 100, 100, 50, 50, 50, 50]).topProjects(byCost: false)
        #expect(ranking.top.map(\.usage.displayName) == ["project0", "project1", "project2", "project3", "project4"])
        #expect(ranking.other?.count == 3)
        #expect(ranking.other?.totalTokens == 150)
        #expect(ranking.other?.costUSD == nil)
        let shares = ranking.top.compactMap(\.sharePercent) + [ranking.other?.sharePercent ?? 0]
        #expect(shares == [40, 20, 10, 10, 5, 15])
    }

    @Test func sharesAlwaysAddUpTo100() {
        let ranking = projects([1, 1, 1]).topProjects(byCost: false)
        #expect(ranking.top.compactMap(\.sharePercent).reduce(0, +) == 100)
        #expect(ranking.top.map(\.sharePercent) == [34, 33, 33])
    }

    @Test func zeroTotalHidesShares() {
        let breakdown = UsageBreakdown(perProject: [ProjectUsage(project: agenttacho, displayName: "agenttacho")])
        #expect(breakdown.topProjects(byCost: true).top.map(\.sharePercent) == [nil])
    }

    @Test func pricedSharesUseCostAndOtherCostIsNilWhenUnpriced() {
        let snapshot = aggregate((0..<7).map { i in
            makeRecord(id: "r\(i)", accountId: "acc-v1", input: 1, cost: i == 6 ? nil : Decimal(10 - i),
                       project: Project(rootPath: "/p/project\(i)"))
        })
        let ranking = snapshot.groups["grp"]!.breakdown.topProjects(byCost: true)
        // Priced costs 10, 9, 8, 7, 6 | 5, 0 (unpriced): total 45.
        #expect(ranking.top.map(\.sharePercent) == [22, 20, 18, 16, 13])
        #expect(ranking.other?.count == 2)
        #expect(ranking.other?.costUSD == nil)
        #expect(ranking.other?.sharePercent == 11)
    }
```

Check of the last expectation: exact shares are 22.2, 20.0, 17.8, 15.6, 13.3, 11.1; floors 22, 20, 17, 15, 13, 11 = 98; the two largest remainders (17.8, 15.6) get +1, giving 22, 20, 18, 16, 13, 11.

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test 2>&1 | grep -E "error:" | head -3`
Expected: "value of type 'UsageBreakdown' has no member 'topProjects'".

- [ ] **Step 3: Implement**

In `UsageSnapshot.swift`, after `ProjectUsage`:

```swift
/// The Projects view of a breakdown: the top rows and the rest combined.
public struct ProjectRanking: Equatable, Sendable {
    public var top: [ProjectRanked]
    /// nil when no project is beyond the top rows.
    public var other: OtherProjects?
}

public struct ProjectRanked: Equatable, Sendable, Identifiable {
    public var usage: ProjectUsage
    /// Whole percent of the breakdown total; nil when the total is 0.
    public var sharePercent: Int?
    public var id: String { usage.id }
}

public struct OtherProjects: Equatable, Sendable {
    public var count: Int
    public var totalTokens: Int
    /// nil when any of the projects is unpriced, or cost is not applicable.
    public var costUSD: Decimal?
    public var sharePercent: Int?
}
```

In `UsageBreakdown`:

```swift
    /// The first `limit` projects plus the rest as one Other entry. Shares
    /// use cost when `byCost` (priced breakdowns), tokens otherwise.
    public func topProjects(limit: Int = 5, byCost: Bool) -> ProjectRanking {
        let top = Array(perProject.prefix(limit))
        let rest = Array(perProject.dropFirst(limit))
        let value: (ProjectUsage) -> Decimal = { byCost ? $0.pricedCostUSD : Decimal($0.totalTokens) }
        var values = top.map(value)
        if !rest.isEmpty { values.append(rest.map(value).reduce(0, +)) }
        let shares = Self.shares(values)

        let ranked = top.enumerated().map { i, usage in ProjectRanked(usage: usage, sharePercent: shares?[i]) }
        guard !rest.isEmpty else { return ProjectRanking(top: ranked, other: nil) }
        let restCost: Decimal? = byCost && rest.allSatisfy(\.priced) ? rest.reduce(0) { $0 + $1.pricedCostUSD } : nil
        let other = OtherProjects(count: rest.count, totalTokens: rest.reduce(0) { $0 + $1.totalTokens },
                                  costUSD: restCost, sharePercent: shares?.last)
        return ProjectRanking(top: ranked, other: other)
    }

    /// Whole percents that add up to exactly 100 (largest remainder); nil
    /// when the total is 0.
    static func shares(_ values: [Decimal]) -> [Int]? {
        let total = values.reduce(0, +)
        guard total > 0 else { return nil }
        let exact = values.map { NSDecimalNumber(decimal: $0 * 100 / total).doubleValue }
        var result = exact.map { Int($0.rounded(.down)) }
        let order = exact.indices.sorted { a, b in
            let ra = exact[a] - Double(result[a]), rb = exact[b] - Double(result[b])
            return ra != rb ? ra > rb : a < b
        }
        for i in order.prefix(max(0, 100 - result.reduce(0, +))) { result[i] += 1 }
        return result
    }
```

`UsageSnapshot.swift` already imports Foundation, which provides `NSDecimalNumber`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test 2>&1 | grep -E "error:|✘|Test run" | tail -3`
Expected: full run passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Snapshot/UsageSnapshot.swift Tests/UsageCoreTests/AggregatorTests.swift
git commit -m "feat(snapshot): top projects with an Other row and shares adding up to 100" -m "Assisted-By: 🤖 Claude Code"
```

---

### Task 6: Models | Projects switch in the Details view

**Files:**
- Modify: `Sources/AgentTacho/BreakdownView.swift`

**Interfaces:**
- Consumes: `UsageBreakdown.topProjects(limit:byCost:)`, `ProjectRanking`, `ProjectRanked`, `OtherProjects`, `ProjectUsage.project?.rootPath` (Tasks 4, 5); existing `UsageFormat.tokens`, `UsageFormat.usd`.
- Produces: `enum DetailsMode: String, CaseIterable, Identifiable` (`models`, `projects`) stored under the UserDefaults key `detailsMode`.

The app target has no unit tests; this task is verified by building and looking at the running app.

- [ ] **Step 1: Add the mode and the switch**

Above `struct BreakdownView`:

```swift
/// Which table the expanded Details section shows; one choice for all
/// sections, remembered across launches.
enum DetailsMode: String, CaseIterable, Identifiable {
    case models, projects

    var id: Self { self }
    var title: String { self == .models ? "Models" : "Projects" }
}
```

In `BreakdownView` add `@AppStorage("detailsMode") private var mode: DetailsMode = .models` below `expanded`, and replace the `VStack` content of the `DisclosureGroup`:

```swift
            VStack(alignment: .leading, spacing: 6) {
                Picker("View", selection: $mode) {
                    ForEach(DetailsMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                switch mode {
                case .models: modelTable
                case .projects: projectTable
                }
                if !breakdown.perDay.isEmpty {
                    dayTrend
                }
            }
            .padding(.top, 4)
```

- [ ] **Step 2: Generalize `costText`**

Change `costText(_ model: ModelUsage)` to take the cost and update its call in `modelTable` to `costText(model.costUSD)`:

```swift
    private func costText(_ cost: Decimal?) -> Text {
        if let cost {
            return Text(UsageFormat.usd(cost))
        }
        return Text("unpriced").foregroundStyle(Color.orange)
    }
```

- [ ] **Step 3: Add the project table**

```swift
    /// Top 5 projects plus Other; no Total row, the section header has it.
    @ViewBuilder
    private var projectTable: some View {
        let ranking = breakdown.topProjects(byCost: showsCost)
        let showsShare = ranking.top.first?.sharePercent != nil
        if ranking.top.isEmpty {
            Text("No usage in this window").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("Project").gridColumnAlignment(.leading)
                    Text("Tokens")
                    if showsCost { Text("Cost") }
                    if showsShare { Text("Share") }
                }
                .foregroundStyle(.secondary)
                ForEach(ranking.top) { row in
                    GridRow {
                        Text(row.usage.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 160, alignment: .leading)
                            .help(row.usage.project?.rootPath ?? "")
                            .gridColumnAlignment(.leading)
                        Text(UsageFormat.tokens(row.usage.totalTokens))
                        if showsCost { costText(row.usage.costUSD) }
                        if showsShare { Text(shareText(row.sharePercent)) }
                    }
                    .monospacedDigit()
                }
                if let other = ranking.other {
                    GridRow {
                        Text("Other (\(other.count))").gridColumnAlignment(.leading)
                        Text(UsageFormat.tokens(other.totalTokens))
                        if showsCost { costText(other.costUSD) }
                        if showsShare { Text(shareText(other.sharePercent)) }
                    }
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shareText(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? ""
    }
```

- [ ] **Step 4: Mode-specific legend**

Replace the start of `explanation` (the `var lines = [...]` array, the Cost line and the Total line) so the first lines depend on the mode; keep the existing day-row, K/M/B and "Tokens come from the session logs" lines after them unchanged:

```swift
    private var explanation: String {
        var lines = mode == .models ? modelLegend : projectLegend
        // ... existing `let columns = ...` and the lines after it stay as they are ...
    }

    private var modelLegend: [String] {
        var lines = [
            "Model: the model id as recorded in the Claude Code session logs.",
            "In: input tokens sent to the model that did not come from the prompt cache.",
            "Out: output tokens the model generated.",
            "Cache w: input tokens written to the prompt cache (5-minute and 1-hour entries), billed above the normal input price.",
            "Cache r: input tokens served from the prompt cache, billed at a small fraction of the input price.",
        ]
        if showsCost {
            lines.append("Cost: US$ from the built-in price table or your overrides on the Prices tab. \"unpriced\" means the model has no price, so the total is incomplete.")
        }
        lines.append("Total: the sum over all models, shown when there is more than one.")
        return lines
    }

    private var projectLegend: [String] {
        var lines = [
            "Project: the git repository the Claude Code session ran in. Subdirectories and git worktrees count toward their repository; folders outside a repository count on their own. Point at a name for the full path.",
            "Unknown: log lines that do not record a working directory.",
            "Tokens: input, output and both cache kinds together.",
        ]
        if showsCost {
            lines.append("Cost: US$ from the price table. \"unpriced\" means a model used in the project has no price.")
            lines.append("Share: part of this section's priced cost.")
        } else {
            lines.append("Share: part of this section's tokens.")
        }
        lines.append("Other: the projects beyond the top 5, added up.")
        return lines
    }
```

- [ ] **Step 5: Build, test and look at it**

Run: `make test 2>&1 | grep -E "error:|✘|Test run" | tail -3` and `make run`
Expected: tests pass; the app launches. In the dropdown, expand a Details section:
- the `Models | Projects` control appears; Models shows the unchanged table;
- Projects shows up to 5 rows with Tokens (and Cost for budget groups) and Share, plus `Other (n)` when there are more projects;
- hovering a project name shows its full path; switching the mode in one section switches all sections; after quitting and relaunching, the last mode is still selected;
- the panel grows and shrinks with the content without clipping.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentTacho/BreakdownView.swift
git commit -m "feat(app): switch the details view between models and top projects" -m "Assisted-By: 🤖 Claude Code"
```
