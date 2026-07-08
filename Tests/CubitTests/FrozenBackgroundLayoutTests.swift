import XCTest
import CoreGraphics
@testable import Cubit

final class FrozenBackgroundLayoutTests: XCTestCase {
    func testFullDisplayNoInsetMapsWholeImageOneToOne() {
        let layout = FrozenBackgroundLayout.layout(
            imagePixelWidth: 3024, imagePixelHeight: 1964, scale: 2,
            canvasSize: CGSize(width: 1512, height: 982), topInsetPoints: 0
        )
        XCTAssertEqual(layout.destPointRect, CGRect(x: 0, y: 0, width: 1512, height: 982))
        XCTAssertEqual(layout.sourcePixelRect, CGRect(x: 0, y: 0, width: 3024, height: 1964))
        XCTAssertFalse(layout.isEmpty)
    }

    func testMenuBarStripExcludedFromTop() {
        let layout = FrozenBackgroundLayout.layout(
            imagePixelWidth: 3024, imagePixelHeight: 1964, scale: 2,
            canvasSize: CGSize(width: 1512, height: 982), topInsetPoints: 33
        )
        // Dest starts below the 33pt menu bar; source starts 66px (33 * scale) down the image.
        XCTAssertEqual(layout.destPointRect, CGRect(x: 0, y: 33, width: 1512, height: 949))
        XCTAssertEqual(layout.sourcePixelRect, CGRect(x: 0, y: 66, width: 3024, height: 1898))
    }

    func testShorterCanvasCropsInsteadOfSquashing() {
        // A canvas shorter than the display must show the top 800pt at 1:1, not a rescaled
        // full image (source height 1600px == 800 * scale, not the full 1964px).
        let layout = FrozenBackgroundLayout.layout(
            imagePixelWidth: 3024, imagePixelHeight: 1964, scale: 2,
            canvasSize: CGSize(width: 1512, height: 800), topInsetPoints: 0
        )
        XCTAssertEqual(layout.destPointRect, CGRect(x: 0, y: 0, width: 1512, height: 800))
        XCTAssertEqual(layout.sourcePixelRect, CGRect(x: 0, y: 0, width: 3024, height: 1600))
        // 1:1 invariant: source pixels == dest points * scale.
        XCTAssertEqual(layout.sourcePixelRect.height, layout.destPointRect.height * 2)
    }

    func testNonRetinaScale() {
        let layout = FrozenBackgroundLayout.layout(
            imagePixelWidth: 1920, imagePixelHeight: 1080, scale: 1,
            canvasSize: CGSize(width: 1920, height: 1080), topInsetPoints: 24
        )
        XCTAssertEqual(layout.destPointRect, CGRect(x: 0, y: 24, width: 1920, height: 1056))
        XCTAssertEqual(layout.sourcePixelRect, CGRect(x: 0, y: 24, width: 1920, height: 1056))
    }

    func testInsetTallerThanCanvasYieldsEmptyLayout() {
        let layout = FrozenBackgroundLayout.layout(
            imagePixelWidth: 3024, imagePixelHeight: 1964, scale: 2,
            canvasSize: CGSize(width: 1512, height: 30), topInsetPoints: 33
        )
        XCTAssertTrue(layout.isEmpty)
        XCTAssertEqual(layout.destPointRect.height, 0)
    }
}
