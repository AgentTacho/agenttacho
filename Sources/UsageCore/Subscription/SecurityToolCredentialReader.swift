import Foundation

/// Reads Claude Code's credential through Apple's `/usr/bin/security` tool
/// instead of the keychain API.
///
/// Claude Code writes its keychain items with that tool, so every item lists
/// `/usr/bin/security` as a trusted application and reading through it never
/// shows a keychain dialog. Reading with the keychain API from this app did:
/// each rebuild gets a new ad-hoc signature that the item does not trust.
///
/// Read-only: only `find-generic-password` is ever run. The secret travels
/// through a pipe in memory and is never logged or written anywhere (FR-011a).
public struct SecurityToolCredentialReader: CredentialReader {
    /// Result of one tool run.
    public struct Output: Sendable {
        public var status: Int32
        public var stdout: Data
        public var stderr: Data

        public init(status: Int32, stdout: Data, stderr: Data) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public struct ToolError: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    /// Runs the tool with the given arguments. Injectable for tests.
    public typealias Runner = @Sendable (_ arguments: [String]) throws -> Output

    /// `security` exits with 44 when no matching item exists.
    static let itemNotFoundStatus: Int32 = 44

    let paths: Paths
    let run: Runner

    public init(paths: Paths = Paths(), run: @escaping Runner = SecurityToolCredentialReader.runSecurityTool) {
        self.paths = paths
        self.run = run
    }

    public func read(configDirectory: String) throws -> OAuthCredential? {
        let service = KeychainServiceName.for(configDirectory: configDirectory, paths: paths)
        let output = try run(["find-generic-password", "-s", service, "-w"])
        switch output.status {
        case 0:
            // `-w` prints the secret followed by a newline.
            var data = output.stdout
            while let last = data.last, last == 0x0A || last == 0x0D { data.removeLast() }
            return try OAuthCredential.decode(keychainJSON: data)
        case Self.itemNotFoundStatus:
            return nil
        default:
            // stderr carries the tool's message, never the secret.
            let message = String(decoding: output.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolError(description: "security exited with \(output.status)\(message.isEmpty ? "" : ": \(message)")")
        }
    }

    /// True when the default directory has a stored credential. Used for the
    /// first-launch default configuration (FR-034).
    public func hasDefaultCredential() -> Bool {
        (try? read(configDirectory: Paths.defaultClaudeDirectory)) != nil
    }

    /// Runs `/usr/bin/security` and waits at most 15 seconds, so a dialog
    /// that should never appear cannot hold up a refresh forever.
    public static let runSecurityTool: Runner = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        // The credential is a few kilobytes, far below the pipe buffer, so
        // reading after exit cannot block the tool.
        if finished.wait(timeout: .now() + 15) == .timedOut {
            process.terminate()
            throw ToolError(description: "security did not finish within 15 seconds")
        }
        return Output(status: process.terminationStatus,
                      stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
                      stderr: stderr.fileHandleForReading.readDataToEndOfFile())
    }
}
