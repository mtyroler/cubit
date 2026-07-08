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

    // MARK: - Clean-window substitution (occlusion fix)

    /// A solid CGImage of a given pixel size, used to stand in for a capture.
    private static func solidImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // With a clean window capture supplied, an exact-window export must render from that image
    // (its native pixel size) rather than cropping the display snapshot — this is what keeps an
    // occluding window from bleeding into the crop.
    func testExactWindowExportRendersFromCleanWindowImage() throws {
        let scale: CGFloat = 2
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let displayImage = Self.solidImage(width: Int(1000 * scale), height: Int(800 * scale))
        let captured = CapturedDisplay(displayID: 1, cgImage: displayImage, canonicalFrame: display, scale: scale)

        let windowRect = CanonicalRect(x: 100, y: 100, width: 400, height: 300)
        let reference = ResolvedReference(rect: windowRect, mode: .windowUnderCursor, descriptor: "Window")
        let windowImage = Self.solidImage(width: Int(400 * scale), height: Int(300 * scale))

        let out = try XCTUnwrap(ExportRenderer.renderCGImage(
            measurements: [],
            reference: reference,
            captured: captured,
            includeContext: false,
            windowShadow: false, // plain path: no shadow margins, so size == window image
            windowImage: windowImage
        ))
        XCTAssertEqual(out.width, windowImage.width, "output must match the clean window image width")
        XCTAssertEqual(out.height, windowImage.height, "output must match the clean window image height")
    }

    // Context exports still crop the display snapshot even when a window image is offered — the
    // surrounding desktop is the whole point of that mode.
    func testContextExportIgnoresCleanWindowImage() throws {
        let scale: CGFloat = 2
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let displayImage = Self.solidImage(width: Int(1000 * scale), height: Int(800 * scale))
        let captured = CapturedDisplay(displayID: 1, cgImage: displayImage, canonicalFrame: display, scale: scale)

        let windowRect = CanonicalRect(x: 100, y: 100, width: 400, height: 300)
        let reference = ResolvedReference(rect: windowRect, mode: .windowUnderCursor, descriptor: "Window")
        let windowImage = Self.solidImage(width: Int(400 * scale), height: Int(300 * scale))

        let out = try XCTUnwrap(ExportRenderer.renderCGImage(
            measurements: [],
            reference: reference,
            captured: captured,
            includeContext: true,
            windowShadow: false,
            windowImage: windowImage
        ))
        // Context crop = window padded by 48pt each side → 496×396 pt at scale 2.
        XCTAssertEqual(out.width, Int(496 * scale), "context export must use the padded display crop")
        XCTAssertNotEqual(out.width, windowImage.width, "context export must not use the bare window image")
    }

    // MARK: - Save-panel default directory fallback (pure, no real filesystem touched)

    func testResolvedSaveDirectoryNilPathFallsBackToSystemDefault() {
        XCTAssertNil(Exporter.resolvedSaveDirectory(forPath: nil, isDirectory: { _ in true }))
    }

    func testResolvedSaveDirectoryMissingFolderFallsBackToSystemDefault() {
        let result = Exporter.resolvedSaveDirectory(forPath: "/does/not/exist", isDirectory: { _ in false })
        XCTAssertNil(result, "a folder that no longer exists must fall back, never crash")
    }

    func testResolvedSaveDirectoryExistingFolderResolvesToURL() {
        let path = "/var/example/Desktop"
        let result = Exporter.resolvedSaveDirectory(forPath: path, isDirectory: { _ in true })
        XCTAssertEqual(result, URL(fileURLWithPath: path, isDirectory: true))
    }

    func testResolvedSaveDirectoryDefaultClosureUsesRealFilesystem() {
        let tempDir = FileManager.default.temporaryDirectory
        let resolved = Exporter.resolvedSaveDirectory(forPath: tempDir.path)
        XCTAssertEqual(resolved?.standardizedFileURL, tempDir.standardizedFileURL)

        let missing = tempDir.appendingPathComponent("cubit-export-tests-\(UUID().uuidString)").path
        XCTAssertNil(Exporter.resolvedSaveDirectory(forPath: missing))
    }
}
