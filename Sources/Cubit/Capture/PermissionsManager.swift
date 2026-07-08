import AppKit
import CoreGraphics

/// Abstracts the CoreGraphics screen-capture TCC calls so the gate logic is testable
/// with a fake provider.
protocol ScreenCapturePermissionProviding: Sendable {
    func preflight() -> Bool
    func request() -> Bool
}

struct SystemScreenCapturePermissionProvider: ScreenCapturePermissionProviding {
    func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    func request() -> Bool { CGRequestScreenCaptureAccess() }
}

/// What the overlay entry flow should do given the current permission state.
enum OverlayEntryDecision: Equatable {
    case presentOverlay
    case showOnboarding
}

@MainActor
final class PermissionsManager {
    private let provider: ScreenCapturePermissionProviding

    init(provider: ScreenCapturePermissionProviding = SystemScreenCapturePermissionProvider()) {
        self.provider = provider
    }

    var isGranted: Bool { provider.preflight() }

    /// Triggers the system prompt on first call per TCC lifetime; returns whether access
    /// is granted.
    @discardableResult
    func requestAccess() -> Bool { provider.request() }

    /// Decides whether the hotkey should open the overlay or the onboarding window.
    /// Granted access always presents; a session-scoped "continue without" lets the user
    /// proceed live even while denied.
    func entryDecision(hasContinuedWithout: Bool) -> OverlayEntryDecision {
        if isGranted { return .presentOverlay }
        if hasContinuedWithout { return .presentOverlay }
        return .showOnboarding
    }

    func openSystemSettings() {
        // macOS 26's System Settings uses the PrivacySecurity *extension* pane id; the legacy
        // `com.apple.preference.security` id is no longer recognized and silently falls back to
        // General. The `Privacy_ScreenCapture` anchor still selects the Screen Recording list.
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Relaunches the app. macOS commonly requires a relaunch for a freshly granted
    /// Screen Recording permission to take effect.
    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
