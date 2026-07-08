import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlayController = OverlayController()
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeyManager = HotkeyManager(controller: overlayController)
    }
}
