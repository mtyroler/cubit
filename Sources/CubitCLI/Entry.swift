import AppKit
import Foundation

/// Process entry point. SwiftUI's `ImageRenderer` (annotate) and ScreenCaptureKit (capture)
/// both need an initialized AppKit app and a live main run loop. We start `NSApplication` as an
/// `.accessory` (no Dock icon, no menu bar, never steals focus), drive the async command on the
/// main actor, and `exit()` from inside the task once it resolves.
///
/// `@main` lives in this non-`main.swift` file so the `cubit` module stays importable by the
/// test target (a top-level `main.swift` would emit a conflicting `main` symbol).
@main
enum CubitCLIMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let code = await CubitCLI.run(arguments)
            exit(code.rawValue)
        }
        app.run()
    }
}
