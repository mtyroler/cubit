import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let overlayController: OverlayController
    private(set) var hotkeyManager: HotkeyManager?

    override init() {
        overlayController = OverlayController(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeyManager = HotkeyManager(controller: overlayController)
    }
}
