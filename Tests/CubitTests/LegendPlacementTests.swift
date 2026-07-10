import XCTest
@testable import Cubit

/// Deterministic text metrics, mirroring the engine tests' stub.
private struct FakeMeasurer: TextMeasuring {
    func size(of string: String, role: ExportFontRole, pointSize: CGFloat) -> CGSize {
        let scale = pointSize / role.pointSize
        return CGSize(width: CGFloat(string.count) * 7 * scale, height: 14 * scale)
    }
}

@MainActor
final class LegendPlacementTests: XCTestCase {
    private let measuring = FakeMeasurer()

    private func request(placement: LegendPlacement) -> LayoutRequest {
        let image = CGSize(width: 800, height: 600)
        return LayoutRequest(
            cropRect: CanonicalRect(x: 0, y: 0, width: image.width, height: image.height),
            imageSize: image,
            referenceRect: CanonicalRect(x: 0, y: 0, width: image.width, height: image.height),
            referenceMode: .windowUnderCursor,
            callouts: [CalloutInput(
                id: UUID(),
                kind: .rectangle,
                rect: CanonicalRect(x: 100, y: 100, width: 200, height: 150),
                colorIndex: 0,
                labelText: nil,
                primaryText: "50.0%",
                detailText: "400×300 px"
            )],
            legend: LegendInput(
                headerText: "Window",
                rows: [LegendRowInput(colorIndex: 0, labelText: "M", valueText: "50.0%")],
                wordmark: "Cubit",
                metadataHeight: 0
            ),
            legendPlacement: placement
        )
    }

    func testOverlayPlacementAnchorsBottomRightAsBefore() {
        let layout = AnnotationLayoutEngine.layout(request(placement: .overlay), measuring: measuring)
        XCTAssertEqual(layout.legend.placement, .overlay)
        XCTAssertEqual(layout.legend.frame.maxX, 800 - AnnotationLayoutEngine.legendMargin)
        XCTAssertEqual(layout.legend.frame.maxY, 600 - AnnotationLayoutEngine.legendMargin)
    }

    // A below-window legend keeps its measured size (the card renders from it) but claims
    // no position in the image: origin zero.
    func testBelowPlacementKeepsSizeButNoImagePosition() {
        let below = AnnotationLayoutEngine.layout(request(placement: .below), measuring: measuring)
        let overlay = AnnotationLayoutEngine.layout(request(placement: .overlay), measuring: measuring)
        XCTAssertEqual(below.legend.placement, .below)
        XCTAssertEqual(below.legend.frame.origin, .zero)
        XCTAssertEqual(below.legend.frame.size, overlay.legend.frame.size, "size must stay engine-measured")
    }

    // With the legend out of the image, its old corner stops being a pill obstacle: a shape
    // in the bottom-right corner keeps its pill beside the shape instead of being displaced.
    func testBelowPlacementFreesLegendCornerForPills() {
        var req = request(placement: .below)
        req.callouts = [CalloutInput(
            id: UUID(),
            kind: .rectangle,
            rect: CanonicalRect(x: 560, y: 400, width: 220, height: 180),
            colorIndex: 0,
            labelText: nil,
            primaryText: "8.3%",
            detailText: "440×360 px"
        )]
        let below = AnnotationLayoutEngine.layout(req, measuring: measuring)

        var overlayReq = req
        overlayReq.legendPlacement = .overlay
        let overlay = AnnotationLayoutEngine.layout(overlayReq, measuring: measuring)

        let belowPill = below.callouts[0].frame
        let legendFrame = overlay.legend.frame
        // The below-layout pill may overlap where the legend card would have been.
        // (The overlay layout must avoid it — sanity-check the premise.)
        XCTAssertFalse(overlay.callouts[0].frame.intersects(legendFrame))
        XCTAssertNil(below.callouts[0].leader, "pill should sit beside its shape, not be displaced")
        XCTAssertTrue(belowPill.maxX <= 800 && belowPill.maxY <= 600, "pill stays in bounds")
    }

    // MARK: - Renderer integration: legend moves below only over a real background

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

    func testStyledExportGrowsForBelowLegendOnlyWithBackground() throws {
        let scale: CGFloat = 2
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let captured = CapturedDisplay(
            displayID: 1,
            cgImage: Self.solidImage(width: Int(1000 * scale), height: Int(800 * scale)),
            canonicalFrame: display,
            scale: scale
        )
        let windowRect = CanonicalRect(x: 100, y: 100, width: 400, height: 300)
        let reference = ResolvedReference(rect: windowRect, mode: .windowUnderCursor, descriptor: "Window")
        let windowImage = Self.solidImage(width: Int(400 * scale), height: Int(300 * scale))
        let measurement = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 150, y: 150, width: 100, height: 80))

        func render(_ background: ExportBackgroundStyle) throws -> CGImage {
            try XCTUnwrap(ExportRenderer.renderCGImage(
                measurements: [measurement],
                reference: reference,
                captured: captured,
                includeContext: false,
                windowShadow: true,
                windowImage: windowImage,
                background: background
            ), "render failed for \(background.rawValue)")
        }

        let transparent = try render(.transparent)
        let studio = try render(.studio)
        XCTAssertEqual(transparent.width, studio.width, "margins are constant, width must match")
        XCTAssertGreaterThan(
            studio.height, transparent.height,
            "over a background the legend stacks below the window, growing the canvas"
        )

        // No measurements → no rows → the branding legend stays in-image; sizes match the
        // transparent layout exactly (no phantom below-card).
        let emptyTransparent = try XCTUnwrap(ExportRenderer.renderCGImage(
            measurements: [], reference: reference, captured: captured,
            includeContext: false, windowShadow: true, windowImage: windowImage, background: .transparent
        ))
        let emptyStudio = try XCTUnwrap(ExportRenderer.renderCGImage(
            measurements: [], reference: reference, captured: captured,
            includeContext: false, windowShadow: true, windowImage: windowImage, background: .studio
        ))
        XCTAssertEqual(emptyStudio.height, emptyTransparent.height)
    }

    // MARK: - Sidecar toggle rides the framing

    func testSidecarDefaultsOffAndRoundTripsThroughFraming() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        let prefs = ExportLayoutPreferences(defaults: suite)
        XCTAssertFalse(prefs.framing.writeJSONSidecar)
        XCTAssertFalse(ExportFraming.default.writeJSONSidecar)

        let saved = ExportFraming(includeContext: false, windowShadow: true, writeJSONSidecar: true)
        prefs.save(saved)
        XCTAssertTrue(prefs.writeJSONSidecar)
        XCTAssertEqual(ExportLayoutPreferences(defaults: suite).framing, saved)
        // Same key the Settings toggle uses — one source of truth.
        XCTAssertTrue(suite.bool(forKey: ExportLayoutPreferences.jsonSidecarKey))
    }
}
