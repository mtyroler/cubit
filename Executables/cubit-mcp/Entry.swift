import AppKit
import Cubit
import Foundation

/// Process entry point for `cubit-mcp`. SwiftUI's `ImageRenderer` (used by the annotate tool) and
/// ScreenCaptureKit need an initialized AppKit app with a live main run loop, so we boot
/// `NSApplication` as an `.accessory` (no Dock icon, no menu bar, never steals focus), run the
/// stdio JSON-RPC server on the main actor, and `exit()` once stdin closes.
///
/// `@main` lives in this non-`main.swift` file so it stays out of the shared `Cubit` library
/// (a top-level `main.swift` would emit a conflicting `main` symbol).
@main
enum CubitMCPMain {
    static func main() {
        let root = rootArgument() ?? FileManager.default.currentDirectoryPath
        let server = MCPServer(root: root)
        // Reserve stdout for JSON-RPC BEFORE NSApplication (or any framework) can write to it.
        server.redirectStdoutToProtocolChannel()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await server.run()
            exit(0)
        }
        app.run()
    }

    /// `--root <dir>` / `--root=<dir>` — the directory agent-supplied file paths are confined to.
    /// Defaults to the current working directory.
    private static func rootArgument() -> String? {
        let arguments = CommandLine.arguments
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--root", index + 1 < arguments.count {
                return arguments[index + 1]
            }
            if argument.hasPrefix("--root=") {
                return String(argument.dropFirst("--root=".count))
            }
            index += 1
        }
        return nil
    }
}
