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

    // Default (context off): window/custom exports crop to the reference rect EXACTLY —
    // window-only, no surrounding desktop.
    func testWindowModeExactCropByDefault() {
        let display = CanonicalRect(x: 0, y: 0, width: 1512, height: 982)
        let windowRect = CanonicalRect(x: 36, y: 56, width: 1440, height: 870)
        let reference = ResolvedReference(rect: windowRect, mode: .windowUnderCursor, descriptor: "Window")
        let crop = ExportRenderer.cropRect(reference: reference, displayFrame: display, includeContext: false)
        XCTAssertEqual(crop, windowRect, "window mode default must be the window rect exactly")
        XCTAssertNotEqual(crop, display, "must not degenerate to the whole display")
    }

    func testCustomModeExactCropByDefault() {
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let customRect = CanonicalRect(x: 120, y: 90, width: 300, height: 220)
        let reference = ResolvedReference(rect: customRect, mode: .custom, descriptor: "Custom")
        XCTAssertEqual(ExportRenderer.cropRect(reference: reference, displayFrame: display, includeContext: false), customRect)
    }

    func testExactCropClampsWindowToDisplay() {
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        // Window overhangs the left/top edges.
        let windowRect = CanonicalRect(x: -40, y: -30, width: 300, height: 200)
        let reference = ResolvedReference(rect: windowRect, mode: .windowUnderCursor, descriptor: "Window")
        let crop = ExportRenderer.cropRect(reference: reference, displayFrame: display, includeContext: false)
        XCTAssertEqual(crop, CanonicalRect(x: 0, y: 0, width: 260, height: 170))
    }

    func testCropExpandsWindowReferenceByPaddingWhenContextOn() {
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let reference = ResolvedReference(
            rect: CanonicalRect(x: 400, y: 300, width: 200, height: 150),
            mode: .windowUnderCursor,
            descriptor: "Window"
        )
        let crop = ExportRenderer.cropRect(reference: reference, displayFrame: display, includeContext: true)
        XCTAssertEqual(crop, CanonicalRect(x: 352, y: 252, width: 296, height: 246))
    }

    func testContextCropClampsToDisplayEdges() {
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let reference = ResolvedReference(
            rect: CanonicalRect(x: 10, y: 10, width: 100, height: 100),
            mode: .custom,
            descriptor: "Custom"
        )
        let crop = ExportRenderer.cropRect(reference: reference, displayFrame: display, includeContext: true)
        // Left/top expansion clamps to the display origin.
        XCTAssertEqual(crop.minX, 0)
        XCTAssertEqual(crop.minY, 0)
        XCTAssertEqual(crop.maxX, 158) // 10 + 100 + 48
        XCTAssertEqual(crop.maxY, 158)
    }

    func testScreenModeCropIsFullDisplayRegardlessOfContext() {
        let display = CanonicalRect(x: 0, y: 0, width: 1440, height: 900)
        let reference = ResolvedReference(rect: CanonicalRect(x: 100, y: 100, width: 50, height: 50), mode: .screen, descriptor: "Screen")
        XCTAssertEqual(ExportRenderer.cropRect(reference: reference, displayFrame: display, includeContext: false), display)
        XCTAssertEqual(ExportRenderer.cropRect(reference: reference, displayFrame: display, includeContext: true), display)
    }

    // Native-window styling only applies to an exact window crop with the shadow on.
    func testWindowStylingOnlyForExactWindowWithShadow() {
        XCTAssertTrue(ExportRenderer.windowStyled(mode: .windowUnderCursor, includeContext: false, windowShadow: true))
        XCTAssertFalse(ExportRenderer.windowStyled(mode: .windowUnderCursor, includeContext: false, windowShadow: false), "shadow toggle off")
        XCTAssertFalse(ExportRenderer.windowStyled(mode: .windowUnderCursor, includeContext: true, windowShadow: true), "context shot is not a clean window")
        XCTAssertFalse(ExportRenderer.windowStyled(mode: .screen, includeContext: false, windowShadow: true), "screen is full-bleed")
        XCTAssertFalse(ExportRenderer.windowStyled(mode: .custom, includeContext: false, windowShadow: true), "custom is an arbitrary region")
    }

    func testFramingPreferenceDefaultsShadowOnContextOff() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        let prefs = ExportLayoutPreferences(defaults: suite)
        XCTAssertTrue(prefs.windowShadow, "window shadow defaults on")
        XCTAssertFalse(prefs.includeContext, "context defaults off")
        XCTAssertEqual(prefs.framing, .default)
    }

    func testFramingPreferenceRoundTrips() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        let prefs = ExportLayoutPreferences(defaults: suite)
        prefs.save(ExportFraming(includeContext: true, windowShadow: false))
        XCTAssertTrue(prefs.includeContext)
        XCTAssertFalse(prefs.windowShadow)
        XCTAssertEqual(ExportLayoutPreferences(defaults: suite).framing, ExportFraming(includeContext: true, windowShadow: false))
    }
}
