import XCTest
@testable import Cubit

@MainActor
final class ExportRendererTests: XCTestCase {
    // Regression: line measurements have degenerate rects, so areaPercent is always 0.
    // Callout/legend strings must use primaryPercent (width% / height%), never area%.
    func testHorizontalLineCalloutPercentIsNonZero() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let line = Measurement(kind: .horizontal, rect: CanonicalRect(x: 100, y: 250, width: 400, height: 0))
        let metrics = MeasurementEngine.metrics(for: line, reference: reference, scale: 2)

        XCTAssertEqual(metrics.areaPercent, 0, "degenerate rect area is zero")
        XCTAssertEqual(ExportRenderer.primaryText(metrics), "40.0%")
        XCTAssertNotEqual(ExportRenderer.primaryText(metrics), "0.0%")
        XCTAssertEqual(ExportRenderer.detailText(kind: .horizontal, metrics: metrics), "800 px")
    }

    func testVerticalLineCalloutPercentIsNonZero() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let line = Measurement(kind: .vertical, rect: CanonicalRect(x: 100, y: 100, width: 0, height: 250))
        let metrics = MeasurementEngine.metrics(for: line, reference: reference, scale: 1)

        XCTAssertEqual(ExportRenderer.primaryText(metrics), "50.0%")
        XCTAssertNotEqual(ExportRenderer.primaryText(metrics), "0.0%")
        XCTAssertEqual(ExportRenderer.detailText(kind: .vertical, metrics: metrics), "250 px")
    }

    func testRectangleDetailReportsWidthByHeightPixels() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 100, height: 50))
        let metrics = MeasurementEngine.metrics(for: rect, reference: reference, scale: 2)

        XCTAssertEqual(ExportRenderer.primaryText(metrics), "1.0%")
        XCTAssertEqual(ExportRenderer.detailText(kind: .rectangle, metrics: metrics), "200×100 px")
    }

    func testCropExpandsWindowReferenceByPaddingClampedToDisplay() {
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let reference = ResolvedReference(
            rect: CanonicalRect(x: 400, y: 300, width: 200, height: 150),
            mode: .windowUnderCursor,
            descriptor: "Window"
        )
        let crop = ExportRenderer.cropRect(reference: reference, displayFrame: display)
        XCTAssertEqual(crop, CanonicalRect(x: 352, y: 252, width: 296, height: 246))
    }

    func testCropClampsToDisplayEdges() {
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let reference = ResolvedReference(
            rect: CanonicalRect(x: 10, y: 10, width: 100, height: 100),
            mode: .custom,
            descriptor: "Custom"
        )
        let crop = ExportRenderer.cropRect(reference: reference, displayFrame: display)
        // Left/top expansion clamps to the display origin.
        XCTAssertEqual(crop.minX, 0)
        XCTAssertEqual(crop.minY, 0)
        XCTAssertEqual(crop.maxX, 158) // 10 + 100 + 48
        XCTAssertEqual(crop.maxY, 158)
    }

    func testScreenModeCropIsFullDisplay() {
        let display = CanonicalRect(x: 0, y: 0, width: 1440, height: 900)
        let reference = ResolvedReference(rect: CanonicalRect(x: 100, y: 100, width: 50, height: 50), mode: .screen, descriptor: "Screen")
        XCTAssertEqual(ExportRenderer.cropRect(reference: reference, displayFrame: display), display)
    }
}
