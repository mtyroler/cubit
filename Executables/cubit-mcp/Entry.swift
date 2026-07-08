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
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let server = MCPServer()
        Task { @MainActor in
            await server.run()
            exit(0)
        }
        app.run()
    }
}
