import Foundation

/// Process exit codes, documented in `--help`. Agents key off these to react without parsing
/// stderr: 3 means "grant Screen Recording", 4 means "your window/name didn't resolve".
public enum ExitCode: Int32, Sendable {
    case ok = 0
    case generic = 1
    case usage = 2
    case permissionDenied = 3
    case notFound = 4
}

/// A recoverable CLI failure carrying the human-readable message (written to stderr) and the
/// exit code to return. Throw it from anywhere in a command; the dispatcher renders it.
struct CLIError: Error {
    let code: ExitCode
    let message: String

    init(_ code: ExitCode, _ message: String) {
        self.code = code
        self.message = message
    }
}
