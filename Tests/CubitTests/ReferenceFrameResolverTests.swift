import XCTest
@testable import Cubit

final class ReferenceFrameResolverTests: XCTestCase {
    private struct MockProvider: WindowInfoProviding {
        var list: [WindowInfo]
        func windows() -> [WindowInfo] { list }
    }

    // Single 1728x1117 screen anchored at canonical origin.
    private let screen = CanonicalRect(x: 0, y: 0, width: 1728, height: 1117)
    private let ownPID: pid_t = 999

    private func window(
        _ ownerName: String,
        _ rect: CanonicalRect,
        layer: Int = 0,
        pid: pid_t = 1,
        id: UInt32 = 1,
        title: String? = nil
    ) -> WindowInfo {
        WindowInfo(canonicalBounds: rect, ownerName: ownerName, windowLayer: layer, ownerPID: pid, windowID: id, title: title)
    }

    // MARK: window mode

    func testTopmostOfOverlappingWindowsWins() {
        let front = window("Safari", CanonicalRect(x: 100, y: 100, width: 800, height: 600), pid: 1, id: 1)
        let back = window("Notes", CanonicalRect(x: 50, y: 50, width: 900, height: 700), pid: 2, id: 2)
        let provider = MockProvider(list: [front, back]) // front-to-back
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 400, y: 300),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.mode, .windowUnderCursor)
        XCTAssertEqual(resolved.rect, front.canonicalBounds)
        XCTAssertEqual(resolved.descriptor, "Safari — 800×600")
    }

    func testCursorOutsideAllWindowsFallsBackToScreen() {
        let win = window("Safari", CanonicalRect(x: 100, y: 100, width: 200, height: 200))
        let provider = MockProvider(list: [win])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 1500, y: 1000),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.mode, .screen)
        XCTAssertEqual(resolved.rect, screen)
        XCTAssertEqual(resolved.descriptor, "Screen — 1728×1117")
    }

    func testNonZeroLayerWindowExcluded() {
        let menuBar = window("Window Server", CanonicalRect(x: 0, y: 0, width: 1728, height: 24), layer: 25)
        let real = window("Safari", CanonicalRect(x: 0, y: 0, width: 800, height: 600), layer: 0, pid: 2, id: 2)
        // menu bar is topmost (front) but layer != 0 → skipped; real window (layer 0) chosen.
        let provider = MockProvider(list: [menuBar, real])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 10, y: 10),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.rect, real.canonicalBounds)
        XCTAssertEqual(resolved.descriptor, "Safari — 800×600")
    }

    func testOwnPIDWindowExcluded() {
        let overlay = window("Cubit", CanonicalRect(x: 0, y: 0, width: 1728, height: 1117), pid: ownPID, id: 1)
        let real = window("Xcode", CanonicalRect(x: 100, y: 100, width: 900, height: 700), pid: 2, id: 2)
        let provider = MockProvider(list: [overlay, real])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 400, y: 400),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.rect, real.canonicalBounds)
        XCTAssertEqual(resolved.descriptor, "Xcode — 900×700")
    }

    func testTinyWindowExcluded() {
        let tiny = window("Tooltip", CanonicalRect(x: 100, y: 100, width: 40, height: 40))
        let big = window("Safari", CanonicalRect(x: 0, y: 0, width: 800, height: 600), pid: 2, id: 2)
        let provider = MockProvider(list: [tiny, big])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 110, y: 110),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.rect, big.canonicalBounds)
    }

    func testExactlyMinSizeWindowIncluded() {
        let atMin = window("Panel", CanonicalRect(x: 100, y: 100, width: 50, height: 50))
        let provider = MockProvider(list: [atMin])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 120, y: 120),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.mode, .windowUnderCursor)
        XCTAssertEqual(resolved.rect, atMin.canonicalBounds)
    }

    func testDescriptorUsesOwnerNameNotWindowTitle() {
        // Titles leak document names and depend on TCC; descriptor stays on the app name.
        let win = window("Safari", CanonicalRect(x: 0, y: 0, width: 1440, height: 812), title: "Apple — Start Page")
        let provider = MockProvider(list: [win])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 100, y: 100),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.descriptor, "Safari — 1440×812")
    }

    func testEmptyOwnerNameFallsBackToGenericLabel() {
        let win = window("   ", CanonicalRect(x: 0, y: 0, width: 1440, height: 812))
        let provider = MockProvider(list: [win])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 100, y: 100),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.descriptor, "Window — 1440×812")
    }

    // MARK: screen mode

    func testScreenModeSelectsScreenContainingCursor() {
        let left = CanonicalRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CanonicalRect(x: 1440, y: 0, width: 1920, height: 1080)
        let resolved = ReferenceFrameResolver.resolve(
            mode: .screen,
            cursor: CanonicalPoint(x: 2000, y: 500),
            screens: [left, right],
            customRect: nil,
            provider: MockProvider(list: []),
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.rect, right)
        XCTAssertEqual(resolved.descriptor, "Screen — 1920×1080")
    }

    func testScreenModeCursorOffAllScreensUsesFirst() {
        let left = CanonicalRect(x: 0, y: 0, width: 1440, height: 900)
        let resolved = ReferenceFrameResolver.resolve(
            mode: .screen,
            cursor: CanonicalPoint(x: 9000, y: 9000),
            screens: [left],
            customRect: nil,
            provider: MockProvider(list: []),
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.rect, left)
    }

    func testWindowModeMultiScreenFallbackUsesCursorScreen() {
        let left = CanonicalRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CanonicalRect(x: 1440, y: 0, width: 1920, height: 1080)
        // No window under the cursor → fall back to the screen the cursor is on.
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 1500, y: 200),
            screens: [left, right],
            customRect: nil,
            provider: MockProvider(list: []),
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.mode, .screen)
        XCTAssertEqual(resolved.rect, right)
    }

    // MARK: custom mode

    func testCustomModeUsesStoredRect() {
        let custom = CanonicalRect(x: 200, y: 200, width: 800, height: 600)
        let resolved = ReferenceFrameResolver.resolve(
            mode: .custom,
            cursor: CanonicalPoint(x: 0, y: 0),
            screens: [screen],
            customRect: custom,
            provider: MockProvider(list: []),
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.mode, .custom)
        XCTAssertEqual(resolved.rect, custom)
        XCTAssertEqual(resolved.descriptor, "Custom — 800×600")
    }

    func testCustomModeFallsBackToScreenWhenNoRectDrawn() {
        let resolved = ReferenceFrameResolver.resolve(
            mode: .custom,
            cursor: CanonicalPoint(x: 100, y: 100),
            screens: [screen],
            customRect: nil,
            provider: MockProvider(list: []),
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.mode, .screen)
        XCTAssertEqual(resolved.rect, screen)
    }

    // MARK: descriptor rounding

    func testDescriptorRoundsFractionalPointsToIntegers() {
        let win = window("App", CanonicalRect(x: 0, y: 0, width: 811.6, height: 456.4))
        let provider = MockProvider(list: [win])
        let resolved = ReferenceFrameResolver.resolve(
            mode: .windowUnderCursor,
            cursor: CanonicalPoint(x: 10, y: 10),
            screens: [screen],
            customRect: nil,
            provider: provider,
            excludedPID: ownPID
        )
        XCTAssertEqual(resolved.descriptor, "App — 812×456")
    }

    func testTopmostWindowHelperReturnsNilWhenNothingQualifies() {
        let provider = MockProvider(list: [window("Menu", CanonicalRect(x: 0, y: 0, width: 100, height: 100), layer: 25)])
        XCTAssertNil(ReferenceFrameResolver.topmostWindow(
            at: CanonicalPoint(x: 10, y: 10),
            provider: provider,
            excludedPID: ownPID
        ))
    }
}
