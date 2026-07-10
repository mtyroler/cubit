import AppKit
import Foundation

/// The outcome an agent can actually be told about after triggering a handoff.
///
/// Opening a `cubit://` URL is FIRE-AND-FORGET: macOS hands the URL to the app and returns. The
/// app may then present the overlay — or show its Screen Recording permission gate first, or be
/// mid-launch, or have the user dismiss it. None of that comes back across the process boundary.
/// So the result says `delivered`, never `displayed`, and the note spells out the difference. An
/// agent that reports "I put measurements on your screen" is guessing; one that reports "I sent
/// them" is telling the truth.
enum HandoffStatus: String {
    case delivered

    static let deliveredNote = """
    The handoff was delivered to the Cubit app. This does not confirm the overlay is on screen: \
    if Cubit lacks Screen Recording permission it shows its permission gate first, and the \
    proposal is discarded if the user dismisses it or does not grant access within \
    2 minutes. Ask the user what they see.
    """
}

/// Triggers the live-overlay handoff (v0.3 M4): validates a handoff document and opens a
/// `cubit://show?path=…` URL so the Cubit app presents the overlay and injects the proposed
/// measurements as editable shapes. Shared by the `cubit show` command and the `cubit-mcp`
/// `show_overlay` tool. The launcher NEVER executes anything from the document — it only reads +
/// validates JSON and hands macOS a URL to open.
@MainActor
enum HandoffLauncher {
    /// Validates the handoff document at `path`, then opens `cubit://show?path=<abs>`. Returns the
    /// resolved absolute path and the measurement count. Throws a `CLIError` for a missing file, a
    /// malformed document, or a launch failure (Cubit not installed/registered).
    @discardableResult
    static func open(documentAtPath path: String) throws -> (path: String, count: Int) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError(.notFound, "cubit: handoff file not found: \(path)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CLIError(.generic, "cubit: could not read \(path): \(error.localizedDescription)")
        }
        let count = try validate(data)
        let absolutePath = url.standardizedFileURL.path
        try openShowURL(forPath: absolutePath)
        return (absolutePath, count)
    }

    /// Validates an already-decoded document, stages it to a temp file, and opens
    /// `cubit://show?path=<tmp>`. Used by the `cubit-mcp` `show_overlay` tool, which receives the
    /// proposal as tool arguments rather than a file. Returns the temp path and measurement count.
    @discardableResult
    static func open(document: HandoffDocument) throws -> (path: String, count: Int) {
        let count = try validate(document)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cubit-handoff-\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(document).write(to: tmpURL)
        } catch {
            throw CLIError(.generic, "cubit: could not stage handoff document: \(error.localizedDescription)")
        }
        try openShowURL(forPath: tmpURL.path)
        return (tmpURL.path, count)
    }

    /// Decodes + validates handoff JSON, returning the measurement count.
    @discardableResult
    static func validate(_ data: Data) throws -> Int {
        let document: HandoffDocument
        do {
            document = try JSONDecoder().decode(HandoffDocument.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw CLIError(.usage, "cubit: handoff JSON missing required key '\(key.stringValue)'")
        } catch {
            throw CLIError(.usage, "cubit: could not parse handoff JSON: \(error.localizedDescription)")
        }
        return try validate(document)
    }

    /// Applies the same strict checks the app applies (schema version, count cap, per-measurement
    /// shape) as `CLIError`s so an agent gets actionable feedback at trigger time.
    @discardableResult
    static func validate(_ document: HandoffDocument) throws -> Int {
        do {
            return try HandoffMapper.measurements(from: document).count
        } catch let error as HandoffMapper.HandoffError {
            throw CLIError(.usage, "cubit: invalid handoff document: \(describe(error))")
        }
    }

    /// Opens `cubit://show?path=<path>`. A false return from `NSWorkspace` means no app is
    /// registered for the scheme (Cubit isn't installed) — surfaced as a not-found error.
    static func openShowURL(forPath path: String) throws {
        guard let url = HandoffURL.showURL(forPath: path) else {
            throw CLIError(.generic, "cubit: could not build a cubit:// URL for \(path)")
        }
        guard NSWorkspace.shared.open(url) else {
            throw CLIError(.notFound, "cubit: could not open \(url.absoluteString) — is the Cubit app installed?")
        }
    }

    private static func describe(_ error: HandoffMapper.HandoffError) -> String {
        switch error {
        case .unsupportedSchemaVersion(let version):
            return "unsupported schemaVersion \(version) (this build expects \(HandoffDocument.currentSchemaVersion))"
        case .emptyDocument:
            return "no measurements"
        case .tooManyMeasurements(let count, let limit):
            return "\(count) measurements exceeds the limit of \(limit)"
        case .invalidMeasurement(let index, let reason):
            return "measurement \(index): \(reason)"
        }
    }
}
