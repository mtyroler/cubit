import Foundation

/// `cubit show --regions <file>` — the live-overlay handoff trigger (v0.3 M4). Validates a
/// handoff document (canonical-point proposed measurements) and opens the Cubit app's overlay
/// with those measurements injected as EDITABLE shapes, ready for the human to adjust and export.
@MainActor
enum ShowCommand {
    static func run(_ tokens: [String]) throws -> ExitCode {
        if tokens.contains("--help") || tokens.contains("-h") {
            Output.stdout(Help.show)
            return .ok
        }
        let options = try ParsedOptions.parse(
            tokens,
            valueFlags: ["--regions", "-r"],
            boolFlags: []
        )
        guard let path = options.value("--regions", "-r") else {
            throw CLIError(.usage, "cubit show: --regions <file> is required")
        }
        let result = try HandoffLauncher.open(documentAtPath: path)
        try Output.json(ShowResult(
            opened: result.path,
            measurementCount: result.count,
            status: HandoffStatus.delivered.rawValue,
            note: HandoffStatus.deliveredNote
        ))
        return .ok
    }

    struct ShowResult: Encodable {
        let opened: String
        let measurementCount: Int
        /// Always `delivered`: see `HandoffStatus`.
        let status: String
        let note: String
    }
}
