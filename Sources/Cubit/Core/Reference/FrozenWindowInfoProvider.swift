import Foundation

/// The window list as it stood when the overlay froze the screen.
///
/// The overlay draws a FROZEN snapshot, so the reference frame must be resolved against the window
/// stack that produced those pixels — not against the live one. Querying live (`CGWindowInfoProvider`)
/// means a `⌘Tab`, a notification, or any app raising itself mid-session silently re-points "the
/// window under the cursor" at a window that is nowhere in the image the user is measuring. The
/// overlay keeps showing the old scene while the numbers, and any export taken from them, quietly
/// describe a different window.
///
/// Freezing the list alongside the pixels keeps what the user sees and what the export reports the
/// same thing. Windows that move or close during the session are irrelevant by construction: the
/// user is measuring a photograph, not the live desktop.
struct FrozenWindowInfoProvider: WindowInfoProviding {
    private let snapshot: [WindowInfo]

    /// - Parameter snapshot: on-screen windows ordered front-to-back, captured at freeze time.
    init(snapshot: [WindowInfo]) {
        self.snapshot = snapshot
    }

    func windows() -> [WindowInfo] { snapshot }
}
