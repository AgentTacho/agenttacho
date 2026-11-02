import Foundation
import Testing
@testable import UsageCore

/// The scan fixture trees of spec 039 (T003, T004) and the counts the
/// bench must report for them, computed from the files themselves.
enum ScanFixtures {
    static let since = isoDate("2026-10-01T00:00:00Z")

    static func treeURL(_ reader: String) throws -> URL {
        try #require(Bundle.module.url(forResource: reader, withExtension: nil, subdirectory: "Fixtures/scan"),
                     "missing scan fixture tree \(reader)")
    }

    static func configURL(_ reader: String) throws -> URL {
        try Fixtures.url("digests/\(reader)-config.json")
    }

    /// Copies a fixture tree byte for byte into `root`. The copies are
    /// written, not cloned, so their modification dates are fresh and every
    /// file is inside the window. Returns the copied files' contents.
    @discardableResult
    static func copyTree(_ reader: String, to root: URL) throws -> [String: Data] {
        let source = try treeURL(reader).resolvingSymlinksInPath()
        let fm = FileManager.default
        var copied: [String: Data] = [:]
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let resolved = url.resolvingSymlinksInPath().path
            let relative = String(resolved.dropFirst(source.path.count + 1))
            let target = root.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Data(contentsOf: url)
            try data.write(to: target)
            copied[relative] = data
        }
        return copied
    }

    /// Non-empty complete lines, a trailing CR trimmed, as the Claude Code
    /// reader visits them (spec 001 FR-018: an incomplete last line waits).
    static func completeLines(_ data: Data) -> Int {
        guard let last = data.lastIndex(of: 0x0A) else { return 0 }
        return data[data.startIndex...last].split(separator: 0x0A, omittingEmptySubsequences: false)
            .filter { line in
                var bytes = line
                if bytes.last == 0x0D { bytes = bytes.dropLast() }
                return !bytes.isEmpty
            }.count
    }

    /// Non-empty lines including an incomplete last one, as the Codex
    /// parser walks a whole file.
    static func allLines(_ data: Data) -> Int {
        data.split(separator: 0x0A, omittingEmptySubsequences: true).count
    }
}

/// The bench command's validation, report and digest (spec 039 FR-001 to
/// FR-005, FR-008, research R8, contracts/bench-cli.md).
@Suite(.serialized) struct ScanBenchTests {
    /// A temporary home, so `~` and the agents' directories of the checks
    /// are the test's own.
    static func makeHome(_ name: String) throws -> URL {
        try makeTempDirectory("scan-bench-\(name)")
    }

    static func options(_ reader: ScanBenchReader, directory: URL?, config: URL, digest: URL? = nil) -> ScanBenchOptions {
        ScanBenchOptions(reader: reader, directory: directory?.path, configurationFile: config, windowStart: ScanFixtures.since,
                         digestPath: digest, useImportedPrices: false, commit: "test")
    }

    /// Runs the bench and expects `ScanBenchError.invalid` whose text names
    /// `expectedPath` with `~`.
    static func expectInvalid(_ options: ScanBenchOptions, paths: Paths, naming expectedPath: String,
                              sourceLocation: SourceLocation = #_sourceLocation) async {
        do {
            let report = try await ScanBench.run(options, paths: paths)
            Issue.record("expected ScanBenchError.invalid, got a report of \(report.records) records", sourceLocation: sourceLocation)
        } catch let ScanBenchError.invalid(message) {
            #expect(message.contains(expectedPath), "\(message)", sourceLocation: sourceLocation)
            #expect(!message.contains(paths.home.path), "\(message)", sourceLocation: sourceLocation)
            #expect(!message.contains("\n"), sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: Validation (spec edge cases, contracts/bench-cli.md exit code 2)

    @Test func missingDirectoryIsInvalid() async throws {
        let home = try Self.makeHome("missing-dir")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        await Self.expectInvalid(Self.options(.claudeCode, directory: home.appendingPathComponent("nowhere"), config: try ScanFixtures.configURL("claude")),
                                 paths: paths, naming: "~/nowhere")
    }

    @Test func directoryWithoutTheReadersFolderIsInvalid() async throws {
        let home = try Self.makeHome("no-projects")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let empty = home.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await Self.expectInvalid(Self.options(.claudeCode, directory: empty, config: try ScanFixtures.configURL("claude")),
                                 paths: paths, naming: "~/empty")
        // A Claude Code tree has no `sessions` folder for the Codex reader.
        let claude = home.appendingPathComponent("claude-tree")
        try ScanFixtures.copyTree("claude", to: claude)
        await Self.expectInvalid(Self.options(.codex, directory: claude, config: try ScanFixtures.configURL("codex")),
                                 paths: paths, naming: "~/claude-tree")
    }

    @Test func unreadableDirectoryIsInvalid() async throws {
        let home = try Self.makeHome("locked-dir")
        let locked = home.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: home)
        }
        try ScanFixtures.copyTree("claude", to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        await Self.expectInvalid(Self.options(.claudeCode, directory: locked, config: try ScanFixtures.configURL("claude")),
                                 paths: Paths(home: home), naming: "~/locked")
    }

    /// A readable directory whose `projects` or `sessions` folder is not
    /// readable is refused too, not reported as an empty scan.
    @Test(arguments: [ScanBenchReader.claudeCode, .codex])
    func unreadableReadersFolderIsInvalid(_ reader: ScanBenchReader) async throws {
        let name = reader == .claudeCode ? "claude" : "codex"
        let home = try Self.makeHome("locked-folder-\(name)")
        let tree = home.appendingPathComponent("tree")
        let folder = tree.appendingPathComponent(reader == .claudeCode ? "projects" : "sessions")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: home)
        }
        try ScanFixtures.copyTree(name, to: tree)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        await Self.expectInvalid(Self.options(reader, directory: tree, config: try ScanFixtures.configURL(name)),
                                 paths: Paths(home: home), naming: "~/tree")
    }

    /// The bench never falls back to a default configuration, and never
    /// creates one: `ConfigStore.load()` would write a default file where
    /// none exists (spec 001 FR-034).
    @Test func missingConfigurationIsInvalidAndNotCreated() async throws {
        let home = try Self.makeHome("missing-config")
        defer { try? FileManager.default.removeItem(at: home) }
        let tree = home.appendingPathComponent("tree")
        try ScanFixtures.copyTree("claude", to: tree)
        let config = home.appendingPathComponent(".config/agenttacho/config.json")
        await Self.expectInvalid(Self.options(.claudeCode, directory: tree, config: config),
                                 paths: Paths(home: home), naming: "~/.config/agenttacho/config.json")
        #expect(!FileManager.default.fileExists(atPath: config.path))
        #expect(!FileManager.default.fileExists(atPath: config.deletingLastPathComponent().path))
    }

    @Test func invalidOrUnreadableConfigurationIsInvalid() async throws {
        let home = try Self.makeHome("bad-config")
        let unreadable = home.appendingPathComponent("unreadable.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
            try? FileManager.default.removeItem(at: home)
        }
        let tree = home.appendingPathComponent("tree")
        try ScanFixtures.copyTree("claude", to: tree)
        let broken = home.appendingPathComponent("broken.json")
        try Data("{ not json".utf8).write(to: broken)
        await Self.expectInvalid(Self.options(.claudeCode, directory: tree, config: broken), paths: Paths(home: home), naming: "~/broken.json")
        #expect(try Data(contentsOf: broken) == Data("{ not json".utf8))
        try Data(contentsOf: try ScanFixtures.configURL("claude")).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        await Self.expectInvalid(Self.options(.claudeCode, directory: tree, config: unreadable), paths: Paths(home: home),
                                 naming: "~/unreadable.json")
    }

    /// FR-004: never a digest under the agents' directories or the scanned
    /// one.
    @Test func digestUnderAnAgentDirectoryIsRefused() async throws {
        let home = try Self.makeHome("digest-refused")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let tree = home.appendingPathComponent("tree")
        try ScanFixtures.copyTree("claude", to: tree)
        let config = try ScanFixtures.configURL("claude")
        for (relative, shown) in [(".claude/x.digest", "~/.claude/x.digest"), (".codex/sub/x.digest", "~/.codex/sub/x.digest"),
                                  ("tree/x.digest", "~/tree/x.digest"), ("tree/projects/x.digest", "~/tree/projects/x.digest")] {
            let digest = home.appendingPathComponent(relative)
            await Self.expectInvalid(Self.options(.claudeCode, directory: tree, config: config, digest: digest), paths: paths, naming: shown)
            #expect(!FileManager.default.fileExists(atPath: digest.path))
        }
    }

    /// A `projects` or `sessions` folder that links out of the scanned
    /// directory: the tree it leads to is refused as well (FR-004).
    @Test(arguments: [ScanBenchReader.claudeCode, .codex])
    func digestUnderALinkedSessionTreeIsRefused(_ reader: ScanBenchReader) async throws {
        let name = reader == .claudeCode ? "claude" : "codex"
        let folder = reader == .claudeCode ? "projects" : "sessions"
        let home = try Self.makeHome("digest-linked-\(name)")
        defer { try? FileManager.default.removeItem(at: home) }
        let shared = home.appendingPathComponent("shared")
        try ScanFixtures.copyTree(name, to: shared)
        let linked = home.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent(folder),
                                                   withDestinationURL: shared.appendingPathComponent(folder))
        let digest = shared.appendingPathComponent("\(folder)/x.digest")
        await Self.expectInvalid(Self.options(reader, directory: linked, config: try ScanFixtures.configURL(name), digest: digest),
                                 paths: Paths(home: home), naming: "~/shared/\(folder)/x.digest")
        #expect(!FileManager.default.fileExists(atPath: digest.path))
    }

    /// A `..` after a link climbs from where the link leads, not from the
    /// link's own folder: the digest path is checked as the write reaches
    /// it (FR-004).
    @Test func digestThroughALinkAndDotDotIsRefused() async throws {
        let home = try Self.makeHome("digest-dotdot")
        defer { try? FileManager.default.removeItem(at: home) }
        let tree = home.appendingPathComponent("tree")
        try ScanFixtures.copyTree("claude", to: tree)
        let work = home.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: work.appendingPathComponent("lnk"),
                                                   withDestinationURL: tree.appendingPathComponent("projects/fixture-project"))
        let digest = URL(fileURLWithPath: work.path + "/lnk/../evil.digest")
        await Self.expectInvalid(Self.options(.claudeCode, directory: tree, config: try ScanFixtures.configURL("claude"), digest: digest),
                                 paths: Paths(home: home), naming: "evil.digest")
        #expect(!FileManager.default.fileExists(atPath: tree.appendingPathComponent("projects/evil.digest").path))
        #expect(!FileManager.default.fileExists(atPath: work.appendingPathComponent("evil.digest").path))
    }

    /// A digest that cannot be written is an error naming its path with
    /// `~`, not a report.
    @Test func digestThatCannotBeWrittenIsInvalid() async throws {
        let home = try Self.makeHome("digest-unwritable")
        defer { try? FileManager.default.removeItem(at: home) }
        let tree = home.appendingPathComponent("tree")
        try ScanFixtures.copyTree("claude", to: tree)
        let digest = home.appendingPathComponent("nowhere/x.digest")
        await Self.expectInvalid(Self.options(.claudeCode, directory: tree, config: try ScanFixtures.configURL("claude"), digest: digest),
                                 paths: Paths(home: home), naming: "~/nowhere/x.digest")
    }

    /// The configured session directories of both agents are refused,
    /// whichever reader runs (FR-004, checkpoint 1 review).
    @Test func digestUnderTheOtherAgentsConfiguredDirectoryIsRefused() async throws {
        let home = try Self.makeHome("digest-other-agent")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let config = home.appendingPathComponent("config.json")
        try Data("""
        {"version": 1, "accounts": [
          {"id": "acc-max", "type": "subscription", "displayName": "Max", "harness": "claudeCode", "credentialDirectory": "~/claude-work"},
          {"id": "acc-plus", "type": "codexSubscription", "displayName": "Plus", "harness": "codex", "codexHome": "~/codex-work"}
        ]}
        """.utf8).write(to: config)
        let claudeTree = home.appendingPathComponent("claude-tree")
        try ScanFixtures.copyTree("claude", to: claudeTree)
        let codexTree = home.appendingPathComponent("codex-tree")
        try ScanFixtures.copyTree("codex", to: codexTree)
        await Self.expectInvalid(Self.options(.claudeCode, directory: claudeTree, config: config,
                                              digest: home.appendingPathComponent("codex-work/x.digest")),
                                 paths: paths, naming: "~/codex-work/x.digest")
        await Self.expectInvalid(Self.options(.codex, directory: codexTree, config: config,
                                              digest: home.appendingPathComponent("claude-work/x.digest")),
                                 paths: paths, naming: "~/claude-work/x.digest")
    }

    @Test func compareWithAMissingOrUnreadableDigestIsInvalid() throws {
        let home = try Self.makeHome("compare-missing")
        let locked = home.appendingPathComponent("locked.digest")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: home)
        }
        let paths = Paths(home: home)
        let present = home.appendingPathComponent("a.digest")
        try Data(RecordsDigest(records: [], header: RecordsDigestTests.header).text.utf8).write(to: present)
        try Data(RecordsDigest(records: [], header: RecordsDigestTests.header).text.utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        for (a, b, shown) in [(present, home.appendingPathComponent("missing.digest"), "~/missing.digest"),
                              (home.appendingPathComponent("gone.digest"), present, "~/gone.digest"),
                              (present, locked, "~/locked.digest")] {
            #expect(throws: ScanBenchError.self) { try ScanBench.compare(a, b, paths: paths) }
            do {
                _ = try ScanBench.compare(a, b, paths: paths)
            } catch let ScanBenchError.invalid(message) {
                #expect(message.contains(shown), "\(message)")
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        #expect(try ScanBench.compare(present, present, paths: paths).identical)
    }

    // MARK: Fixture digests (spec 039 FR-008)

    /// The records of each fixture tree equal its committed digest, record
    /// for record and field for field. The digest run uses the committed
    /// fixture configuration, the fixed window start and no imported
    /// prices, as `make bench-digests` does. Only `make bench-digests`
    /// regenerates the committed files, never an edit to make this pass.
    @Test(arguments: [ScanBenchReader.claudeCode, .codex])
    func fixtureRecordsEqualTheCommittedDigest(_ reader: ScanBenchReader) async throws {
        let name = reader == .claudeCode ? "claude" : "codex"
        let home = try Self.makeHome("fixture-digest-\(name)")
        defer { try? FileManager.default.removeItem(at: home) }
        let tree = home.appendingPathComponent("tree")
        try ScanFixtures.copyTree(name, to: tree)
        let out = home.appendingPathComponent("\(name).digest")
        _ = try await ScanBench.run(Self.options(reader, directory: tree, config: try ScanFixtures.configURL(name), digest: out),
                                    paths: Paths(home: home))
        let committed = try RecordsDigest.parse(String(contentsOf: try Fixtures.url("digests/\(name).digest"), encoding: .utf8))
        let actual = try RecordsDigest.parse(String(contentsOf: out, encoding: .utf8))
        let comparison = RecordsDigest.compare(committed, actual)
        #expect(comparison.identical, """
            \(name) records differ from the committed digest
            only in the committed digest (\(comparison.onlyInACount)):
            \(comparison.onlyInA.joined(separator: "\n"))
            only in this run (\(comparison.onlyInBCount)):
            \(comparison.onlyInB.joined(separator: "\n"))
            """)
        #expect(committed.headerLines.contains("window-start 2026-10-01T00:00:00Z"))
        #expect(!committed.lines.isEmpty)
    }

    // MARK: Report (spec 039 FR-002, FR-003)

    @Test func claudeRunReportsTheTreesFiguresAndASecondRefresh() async throws {
        let home = try Self.makeHome("report-claude")
        defer { try? FileManager.default.removeItem(at: home) }
        let tree = home.appendingPathComponent("tree")
        let files = try ScanFixtures.copyTree("claude", to: tree)
        // A unique content string, so the test can tell the report and the
        // digest never hold a session line's content (FR-003).
        let secret = "fixture-content-5f1c9e"
        let extra = #"{"type":"assistant","timestamp":"2026-10-14T08:00:00.000Z","requestId":"req_vrtx_S1","uuid":"s1","sessionId":"s-secret","cwd":"/fixture/proj-gamma","message":{"id":"msg_vrtx_S1","model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"\#(secret)"}],"usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":3}}}"#
            + "\n"
        let extraURL = tree.appendingPathComponent("projects/fixture-project/secret.jsonl")
        try Data(extra.utf8).write(to: extraURL)
        let jsonl = files.filter { $0.key.hasSuffix(".jsonl") }
        let expectedLines = jsonl.values.reduce(0) { $0 + ScanFixtures.completeLines($1) } + 1
        let digest = home.appendingPathComponent("out/claude.digest")
        try FileManager.default.createDirectory(at: digest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let report = try await ScanBench.run(Self.options(.claudeCode, directory: tree, config: try ScanFixtures.configURL("claude"), digest: digest),
                                             paths: Paths(home: home))
        #expect(report.filesSeen == jsonl.count + 1)
        #expect(report.filesRead == jsonl.count + 1)
        #expect(report.linesVisited == expectedLines)
        #expect(report.records > 0)
        #expect(report.bytesRead == jsonl.values.reduce(0) { $0 + $1.count } + extra.utf8.count)
        #expect(report.corpusBytes == report.bytesRead)
        #expect(report.secondRefresh.filesRead == 0)
        #expect(report.directory == "~/tree")
        #expect(report.commit == "test")
        let text = report.text
        #expect(text.hasPrefix("scan-bench 1  commit test  reader claude\n"))
        #expect(text.contains("corpus bytes \(report.corpusBytes)"))
        for label in ["\nconfig         ", "\nwall           ", "\ncpu            user ", "\npeak memory    footprint ",
                      "\ndisk read      ", "\nworkers        "] {
            #expect(text.contains(label), "\(label)")
        }
        #expect(text.contains("second refresh"))
        #expect(text.contains("files seen     \(jsonl.count + 1)"))
        #expect(text.contains("lines \(expectedLines)"))
        #expect(text.contains("records \(report.records)"))
        #expect(text.contains("window start   2026-10-01T00:00:00Z"))
        #expect(text.contains("directory      ~/tree"))
        #expect(!text.contains(home.path))
        #expect(!text.contains(secret))
        let digestText = try String(contentsOf: digest, encoding: .utf8)
        #expect(!digestText.contains(secret))
        #expect(digestText.contains("/fixture/proj-gamma"))
        let parsed = try RecordsDigest.parse(digestText)
        #expect(parsed.lines.count == report.records)
    }

    /// User Story 3 scenario 6: the same figures for the Codex reader.
    @Test func codexRunReportsTheTreesFigures() async throws {
        let home = try Self.makeHome("report-codex")
        defer { try? FileManager.default.removeItem(at: home) }
        let tree = home.appendingPathComponent("tree")
        let files = try ScanFixtures.copyTree("codex", to: tree).filter { $0.key.hasSuffix(".jsonl") }
        let report = try await ScanBench.run(Self.options(.codex, directory: tree, config: try ScanFixtures.configURL("codex")),
                                             paths: Paths(home: home))
        #expect(report.filesSeen == files.count)
        #expect(report.filesRead == files.count)
        #expect(report.linesVisited == files.values.reduce(0) { $0 + ScanFixtures.allLines($1) })
        #expect(report.bytesRead == files.values.reduce(0) { $0 + $1.count })
        #expect(report.corpusBytes == report.bytesRead)
        #expect(report.records > 0)
        #expect(report.secondRefresh.filesRead == 0)
        #expect(report.text.contains("reader codex"))
        #expect(report.text.contains("second refresh"))
    }

    /// `--workers` measures a worker count; the report states the count in
    /// effect, clamped to the cores (spec 039 research R7, T039).
    @Test func workersOptionSetsTheCountInEffect() async throws {
        let home = try Self.makeHome("workers")
        defer { try? FileManager.default.removeItem(at: home) }
        let tree = home.appendingPathComponent("tree")
        try ScanFixtures.copyTree("claude", to: tree)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        var options = Self.options(.claudeCode, directory: tree, config: try ScanFixtures.configURL("claude"))
        let unset = try await ScanBench.run(options, paths: Paths(home: home))
        #expect(unset.workers == ScanWorkers.defaultCount)
        options.workers = 2
        let two = try await ScanBench.run(options, paths: Paths(home: home))
        #expect(two.workers == min(2, cores))
        #expect(two.text.contains("workers        \(min(2, cores)) (utility)"))
        #expect(two.records == unset.records)
        options.workers = cores + 4
        #expect(try await ScanBench.run(options, paths: Paths(home: home)).workers == cores)
    }

    /// Without a directory, a configuration file or a window start, the
    /// bench reads the app's configuration file, scans its directories and
    /// derives the window from it as the app does (FR-001).
    @Test func defaultsComeFromTheAppsConfiguration() async throws {
        let home = try Self.makeHome("defaults")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        try ScanFixtures.copyTree("claude", to: home.appendingPathComponent(".claude"))
        try FileManager.default.createDirectory(at: paths.configFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = Data("""
        {"version": 1, "accounts": [
          {"id": "acc-max", "type": "subscription", "displayName": "Max", "harness": "claudeCode", "credentialDirectory": "~/.claude"}
        ]}
        """.utf8)
        try config.write(to: paths.configFileURL)
        let report = try await ScanBench.run(ScanBenchOptions(reader: .claudeCode, useImportedPrices: false, commit: "test"), paths: paths)
        #expect(report.configurationFile == "~/.config/agenttacho/config.json")
        #expect(report.directory.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.allSatisfy { $0 == "~/.claude" },
                "\(report.directory)")
        #expect(report.filesSeen > 0)
        let configuration = ConfigStore(fileURL: paths.configFileURL).load().0
        let now = Date()
        let resolver = WindowResolver()
        let (weekly, _) = resolver.resolve(now: now, alignmentReset: nil, fallback: configuration.weekFallback, calendar: .current)
        let window = resolver.collectionWindow(weekly: weekly, now: now, configuration: configuration, calendar: .current)
        #expect(report.windowStart == ScanBench.isoText(window.start))
        #expect(try Data(contentsOf: paths.configFileURL) == config)
    }

    /// Edge cases the committed digests cannot see: the fixture files keep
    /// their CRLF ends, the byte that is not UTF-8 and their incomplete last
    /// lines, whatever an editor or git does to them.
    @Test func fixtureFilesKeepTheirRawBytes() throws {
        let tree = try ScanFixtures.treeURL("claude").appendingPathComponent("projects/fixture-project")
        func bytes(_ name: String) throws -> Data { try Data(contentsOf: tree.appendingPathComponent(name)) }
        #expect(try bytes("crlf.jsonl").range(of: Data([0x0D, 0x0A])) != nil)
        #expect(try bytes("non-utf8.jsonl").contains(0xFF))
        #expect(try bytes("incomplete-tail.jsonl").last != 0x0A)
        #expect(try bytes("truncated.jsonl").last != 0x0A)
    }
}
