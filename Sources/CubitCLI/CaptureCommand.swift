import CoreGraphics
import Foundation

/// `cubit capture --window <name|number> [-o out.png]` and `cubit capture --screen [index]
/// [-o out.png]` — a frozen ScreenCaptureKit snapshot written as a metadata-free PNG (the same
/// byte-level stripping the app export uses). Window mode captures the window's own pixels, so
/// an occluding window never bleeds in.
@MainActor
enum CaptureCommand {
    struct CaptureResult: Encodable {
        let output: String
        let pixelWidth: Int
        let pixelHeight: Int
        let scale: Double
    }

    static func run(_ tokens: [String]) async throws -> ExitCode {
        if tokens.contains("--help") || tokens.contains("-h") {
            Output.stdout(Help.capture)
            return .ok
        }
        let options = try ParsedOptions.parse(
            tokens,
            valueFlags: ["--window", "-w", "--out", "-o"],
            boolFlags: ["--screen"]
        )

        let window = options.value("--window", "-w")
        let screen = options.flag("--screen")
        guard window == nil || !screen else {
            throw CLIError(.usage, "cubit capture: choose either --window or --screen, not both")
        }

        // Screen Recording is required for any capture; fail with a distinct, detectable code.
        guard CGPreflightScreenCaptureAccess() else {
            throw CLIError(
                .permissionDenied,
                "cubit: Screen Recording permission is required. Grant it in System Settings › Privacy & Security › Screen Recording, then re-run."
            )
        }

        if let window {
            return try await captureWindow(query: window, options: options)
        }
        if screen {
            return try await captureScreen(options: options)
        }
        throw CLIError(.usage, "cubit capture: specify --window <name|number> or --screen [index]")
    }

    private static func captureWindow(query: String, options: ParsedOptions) async throws -> ExitCode {
        let windows = CGWindowInfoProvider().windows()
        let target = try WindowMatch.find(query, in: windows)

        let service = ScreenCaptureService()
        guard let image = await service.captureWindow(windowID: target.windowID) else {
            throw CLIError(.generic, "cubit: failed to capture window \(target.windowID) (\(target.ownerName)); it may have closed")
        }

        let scale = Displays.scale(containing: CanonicalPoint(
            x: target.canonicalBounds.minX + target.canonicalBounds.width / 2,
            y: target.canonicalBounds.minY + target.canonicalBounds.height / 2
        ))
        let outPath = options.value("--out", "-o") ?? OutputPath.generated(prefix: "cubit-window")
        try writePNG(image, to: outPath)
        try Output.json(CaptureResult(
            output: outPath,
            pixelWidth: image.width,
            pixelHeight: image.height,
            scale: Double(scale)
        ))
        return .ok
    }

    private static func captureScreen(options: ParsedOptions) async throws -> ExitCode {
        let displays = Displays.all()
        guard !displays.isEmpty else {
            throw CLIError(.generic, "cubit: no active displays found")
        }
        let index = try screenIndex(options.positionals, count: displays.count)
        let display = displays[index]

        let request = CaptureRequest(
            displayID: display.id,
            canonicalFrame: display.frame,
            scale: display.scale
        )
        let service = ScreenCaptureService()
        switch await service.captureAll([request]) {
        case .permissionDenied:
            throw CLIError(.permissionDenied, "cubit: Screen Recording permission was declined.")
        case .failed(let error):
            throw CLIError(.generic, "cubit: screen capture failed: \(error.localizedDescription)")
        case .captured(let results):
            guard let captured = results.first else {
                throw CLIError(.generic, "cubit: screen capture produced no image")
            }
            let outPath = options.value("--out", "-o") ?? OutputPath.generated(prefix: "cubit-screen")
            try writePNG(captured.cgImage, to: outPath)
            try Output.json(CaptureResult(
                output: outPath,
                pixelWidth: captured.pixelWidth,
                pixelHeight: captured.pixelHeight,
                scale: Double(captured.scale)
            ))
            return .ok
        }
    }

    /// Resolves the optional `[index]` positional for `--screen`. Defaults to 0 (main display).
    nonisolated static func screenIndex(_ positionals: [String], count: Int) throws -> Int {
        guard let first = positionals.first else { return 0 }
        guard let index = Int(first) else {
            throw CLIError(.usage, "cubit capture: display index must be a number, got '\(first)'")
        }
        guard index >= 0, index < count else {
            throw CLIError(.notFound, "cubit capture: display index \(index) is out of range (0…\(count - 1))")
        }
        return index
    }

    private static func writePNG(_ image: CGImage, to path: String) throws {
        guard let data = ExportRenderer.pngData(from: image) else {
            throw CLIError(.generic, "cubit: failed to encode PNG")
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            throw CLIError(.generic, "cubit: could not write \(path): \(error.localizedDescription)")
        }
    }
}

/// Timestamped default output name in the current directory when `-o` is omitted.
enum OutputPath {
    static func generated(prefix: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(prefix)-\(formatter.string(from: date)).png"
    }
}
