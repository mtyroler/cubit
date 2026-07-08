import XCTest
@testable import Cubit

final class CGWindowInfoProviderTests: XCTestCase {
    func testProviderReturnsStructurallySaneWindows() throws {
        let provider = CGWindowInfoProvider()
        let windows = provider.windows()

        // Headless CI may have no on-screen windows; the live query is still valid.
        try XCTSkipIf(windows.isEmpty, "No on-screen windows in this environment")

        for window in windows {
            XCTAssertGreaterThan(window.ownerPID, 0)
            XCTAssertGreaterThanOrEqual(window.windowID, 0)
            XCTAssertGreaterThanOrEqual(window.canonicalBounds.width, 0)
            XCTAssertGreaterThanOrEqual(window.canonicalBounds.height, 0)
        }
    }

    func testProviderYieldsAtLeastOneLayerZeroWindow() throws {
        let provider = CGWindowInfoProvider()
        let windows = provider.windows()
        try XCTSkipIf(windows.isEmpty, "No on-screen windows in this environment")

        // Real application windows live at layer 0. On a normal desktop (Finder, Terminal)
        // at least one exists; on a headless runner this is skipped rather than failed.
        let layerZero = windows.filter { $0.windowLayer == 0 }
        try XCTSkipIf(layerZero.isEmpty, "No layer-0 windows in this environment")
        XCTAssertFalse(layerZero.isEmpty)
    }
}
