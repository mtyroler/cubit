import CoreGraphics
import Foundation

/// `cubit windows [--json]` — lists on-screen windows front-to-back with owner app, title
/// (nil without Screen Recording), canonical frame, and the scale factor of the display the
/// window sits on. The top-level `permission.screenRecording` flag tells an agent why titles
/// may be missing.
enum WindowsCommand {
    struct WindowsDocument: Encodable {
        struct Permission: Encodable {
            let screenRecording: Bool
        }
        struct Frame: Encodable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }
        struct Window: Encodable {
            let order: Int
            let number: UInt32
            let app: String
            let title: String?
            let layer: Int
            let frame: Frame
            let scale: Double
        }
        let permission: Permission
        let windows: [Window]
    }

    static func run(_ tokens: [String]) throws -> ExitCode {
        if tokens.contains("--help") || tokens.contains("-h") {
            Output.stdout(Help.windows)
            return .ok
        }
        let options = try ParsedOptions.parse(tokens, valueFlags: [], boolFlags: ["--json"])
        guard options.positionals.isEmpty else {
            throw CLIError(.usage, "cubit windows: unexpected argument '\(options.positionals[0])'")
        }

        let document = buildDocument(
            windows: CGWindowInfoProvider().windows(),
            screenRecordingGranted: CGPreflightScreenCaptureAccess()
        )

        // --json is the default and only output form; it's accepted (and validated as a known
        // flag) so scripts can be explicit and forward-compatible if a human-readable form is
        // ever added.
        try Output.json(document)
        return .ok
    }

    /// Pure assembly of the output document from raw window info — unit-tested without touching
    /// the window server.
    static func buildDocument(windows: [WindowInfo], screenRecordingGranted: Bool) -> WindowsDocument {
        let displays = Displays.all()
        let items = windows.enumerated().map { index, window -> WindowsDocument.Window in
            let bounds = window.canonicalBounds
            let center = CanonicalPoint(x: bounds.minX + bounds.width / 2, y: bounds.minY + bounds.height / 2)
            let scale = scaleForCenter(center, displays: displays)
            return WindowsDocument.Window(
                order: index,
                number: window.windowID,
                app: window.ownerName,
                title: window.title,
                layer: window.windowLayer,
                frame: WindowsDocument.Frame(
                    x: Double(bounds.minX),
                    y: Double(bounds.minY),
                    width: Double(bounds.width),
                    height: Double(bounds.height)
                ),
                scale: Double(scale)
            )
        }
        return WindowsDocument(
            permission: WindowsDocument.Permission(screenRecording: screenRecordingGranted),
            windows: items
        )
    }

    /// Scale of the display containing `center`; falls back to the first display, then 2.0.
    private static func scaleForCenter(_ center: CanonicalPoint, displays: [Displays.Display]) -> CGFloat {
        for display in displays where contains(display.frame, center) { return display.scale }
        return displays.first?.scale ?? 2
    }

    private static func contains(_ rect: CanonicalRect, _ point: CanonicalPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
