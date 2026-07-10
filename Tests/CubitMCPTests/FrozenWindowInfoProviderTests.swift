import XCTest
@testable import Cubit

/// The overlay measures a FROZEN snapshot, so the reference frame must resolve against the window
/// stack that produced those pixels. Resolving live let a ⌘Tab mid-session silently re-point "the
/// window under the cursor" at a window absent from the image: the overlay kept showing the old
/// scene at one percentage while the export reported another, against a different window.
final class FrozenWindowInfoProviderTests: XCTestCase {

    private func window(_ name: String, _ rect: CanonicalRect, id: UInt32) -> WindowInfo {
        WindowInfo(
            canonicalBounds: rect,
            ownerName: name,
            windowLayer: 0,
            ownerPID: pid_t(id),
            windowID: id,
            title: name
        )
    }

    /// Both windows contain the cursor; `front` is first (front-to-back order).
    private var front: WindowInfo { window("Frozen", CanonicalRect(x: 0, y: 0, width: 1512, height: 886), id: 1) }
    private var behind: WindowInfo { window("Raised", CanonicalRect(x: 0, y: 0, width: 1440, height: 870), id: 2) }
    private let cursor = CanonicalPoint(x: 700, y: 400)
    private var screen: CanonicalRect { CanonicalRect(x: 0, y: 0, width: 1512, height: 982) }

    func testReturnsTheSnapshotVerbatim() {
        let provider = FrozenWindowInfoProvider(snapshot: [front, behind])
        XCTAssertEqual(provider.windows(), [front, behind])
    }

    func testSnapshotIsStableAcrossCalls() {
        let provider = FrozenWindowInfoProvider(snapshot: [front, behind])
        XCTAssertEqual(provider.windows(), provider.windows())
    }

    func testEmptySnapshot() {
        XCTAssertTrue(FrozenWindowInfoProvider(snapshot: []).windows().isEmpty)
    }

    /// Resolving against the frozen stack picks the window that was frontmost when the shutter
    /// fired — 1512×886, matching the frozen pixels.
    func testResolvesAgainstFrozenStack() {
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: cursor,
            screens: [screen],
            customRect: nil,
            provider: FrozenWindowInfoProvider(snapshot: [front, behind]),
            excludedPID: 0
        )
        XCTAssertEqual(resolved.rect.width, 1512)
        XCTAssertEqual(resolved.rect.height, 886)
        XCTAssertEqual(resolved.window?.ownerName, "Frozen")
    }

    /// The bug: a live provider whose order changed mid-session (another app raised) yields a
    /// DIFFERENT reference — 1440×870 — for the very same cursor. This is what the export used to
    /// report while the overlay still showed the frozen scene. Frozen order must win.
    func testReorderedLiveStackWouldChangeTheReference() {
        let stale = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: cursor,
            screens: [screen],
            customRect: nil,
            provider: FrozenWindowInfoProvider(snapshot: [behind, front]), // as if "Raised" came forward
            excludedPID: 0
        )
        XCTAssertEqual(stale.rect.width, 1440)
        XCTAssertEqual(stale.window?.ownerName, "Raised")

        // Same cursor, frozen order → the original window. The provider is the only difference.
        let frozen = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: cursor,
            screens: [screen],
            customRect: nil,
            provider: FrozenWindowInfoProvider(snapshot: [front, behind]),
            excludedPID: 0
        )
        XCTAssertEqual(frozen.rect.width, 1512)
        XCTAssertNotEqual(frozen.rect, stale.rect)
    }
}
