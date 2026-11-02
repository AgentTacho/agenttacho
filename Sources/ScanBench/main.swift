import Foundation
import UsageCore

// Maintainer bench over a session directory (spec 039 FR-001 to FR-005,
// contracts/bench-cli.md). Parses arguments and prints; the logic lives in
// UsageCore's ScanBench (constitution II). Exit codes: 0 success or
// identical digests, 1 different digests, 2 bad arguments or files.

let usage = """
usage: scan-bench run --reader claude|codex [--dir <path>] [--config <file>] [--since <ISO date>] [--until <ISO date>] [--digest <file>] [--workers <n>]
       scan-bench compare <digest-a> <digest-b>
       scan-bench digest --reader claude|codex --dir <path> --config <file> --since <ISO date> --out <file>
"""

/// One line on stderr, then exit.
func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("scan-bench: \(message)\n".utf8))
    exit(code)
}

func failWithUsage() -> Never {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

/// An ISO 8601 date with or without fractional seconds.
func date(_ text: String, option: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: text) { return date }
    fail("\(option) needs an ISO 8601 date such as 2026-10-01T00:00:00Z, got \"\(text)\"")
}

/// A file argument with a leading `~` expanded.
func fileURL(_ text: String) -> URL {
    URL(fileURLWithPath: Paths().expand(text))
}

/// `--name value` pairs; an unknown option or a missing value fails.
func options(_ arguments: ArraySlice<String>, allowed: Set<String>) -> [String: String] {
    var result: [String: String] = [:]
    var rest = arguments
    while let name = rest.popFirst() {
        guard allowed.contains(name) else { fail("unknown option \(name)") }
        guard let value = rest.popFirst(), !value.isEmpty else { fail("\(name) needs a value") }
        result[name] = value
    }
    return result
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { failWithUsage() }

switch command {
case "run", "digest":
    let isRun = command == "run"
    let given = options(arguments.dropFirst(),
                        allowed: isRun ? ["--reader", "--dir", "--config", "--since", "--until", "--digest", "--workers"]
                                       : ["--reader", "--dir", "--config", "--since", "--out"])
    guard let readerName = given["--reader"] else { fail("--reader is required (claude or codex)") }
    guard let reader = ScanBenchReader(rawValue: readerName) else { fail("--reader must be claude or codex, got \"\(readerName)\"") }
    if !isRun {
        for name in ["--dir", "--config", "--since", "--out"] where given[name] == nil {
            fail("digest needs \(name)")
        }
    }
    // A count above the cores is clamped to them by ScanWorkers.
    let workers = given["--workers"].map { text -> Int in
        guard let count = Int(text), count >= 1 else { fail("--workers needs a whole number of at least 1, got \"\(text)\"") }
        return count
    }
    let benchOptions = ScanBenchOptions(reader: reader,
                                        directory: given["--dir"],
                                        configurationFile: given["--config"].map(fileURL),
                                        windowStart: given["--since"].map { date($0, option: "--since") },
                                        until: given["--until"].map { date($0, option: "--until") },
                                        digestPath: (isRun ? given["--digest"] : given["--out"]).map(fileURL),
                                        useImportedPrices: isRun,
                                        commit: ProcessInfo.processInfo.environment["SCAN_BENCH_COMMIT"] ?? "unknown",
                                        workers: workers)
    do {
        let report = try await ScanBench.run(benchOptions)
        print(report.text, terminator: "")
    } catch let error as ScanBenchError {
        fail(error.description)
    } catch {
        fail("\(error)")
    }

case "compare":
    let paths = Array(arguments.dropFirst())
    guard paths.count == 2 else { fail("compare needs two digest files") }
    for (label, path) in zip(["A", "B"], paths) where path.isEmpty {
        fail("compare needs a digest file for \(label)")
    }
    do {
        let comparison = try ScanBench.compare(fileURL(paths[0]), fileURL(paths[1]))
        print(comparison.text, terminator: "")
        exit(comparison.identical ? 0 : 1)
    } catch let error as ScanBenchError {
        fail(error.description)
    } catch {
        fail("\(error)")
    }

case "help", "-h", "--help":
    print(usage)

default:
    failWithUsage()
}
