import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let overlayController: OverlayController
    /// Registering the Carbon hotkey doesn't depend on app-launch completion, so this is
    /// built eagerly alongside `overlayController` rather than deferred to
    /// `applicationDidFinishLaunching`. Non-optional means the Settings scene (which reads
    /// this to build its Shortcuts tab) can never observe a not-yet-initialized state.
    let hotkeyManager: HotkeyManager

    override init() {
        let overlayController = OverlayController(settings: settings)
        self.overlayController = overlayController
        self.hotkeyManager = HotkeyManager(controller: overlayController)
        super.init()
    }
}
