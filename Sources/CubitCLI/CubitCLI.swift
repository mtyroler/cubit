import Foundation

/// Top-level command dispatch. Renders a thrown `CLIError` to stderr and maps it to an exit
/// code; unexpected errors become a generic failure.
@MainActor
public enum CubitCLI {
    public static func run(_ arguments: [String]) async -> ExitCode {
        do {
            return try await dispatch(arguments)
        } catch let error as CLIError {
            Output.stderrLine(error.message)
            return error.code
        } catch {
            Output.stderrLine("cubit: \(error.localizedDescription)")
            return .generic
        }
    }

    private static func dispatch(_ arguments: [String]) async throws -> ExitCode {
        guard let command = arguments.first else {
            // No subcommand: help to stderr, usage exit code (a bare invocation is a misuse).
            Output.stderrLine(Help.top)
            return .usage
        }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "--help", "-h", "help":
            Output.stdout(Help.top + "\n")
            return .ok
        case "--version", "-V", "version":
            Output.stdoutLine(CubitCLIVersion.current)
            return .ok
        case "windows":
            return try WindowsCommand.run(rest)
        case "capture":
            return try await CaptureCommand.run(rest)
        case "annotate":
            return try AnnotateCommand.run(rest)
        default:
            throw CLIError(.usage, "cubit: unknown command '\(command)'\nRun 'cubit --help' for usage.")
        }
    }
}
