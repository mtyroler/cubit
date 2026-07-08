import XCTest
@testable import Cubit

final class MeasurementSidecarTests: XCTestCase {
    // Rendered-text closures mirror the app's real callout formatters so the sidecar carries
    // the exact strings the export displays.
    private func valueText(_ metrics: Metrics) -> String { ExportRenderer.primaryText(metrics) }
    private func detailText(_ kind: MeasurementKind, _ metrics: Metrics) -> String {
        ExportRenderer.detailText(kind: kind, metrics: metrics)
    }

    private func make(
        measurements: [Cubit.Measurement],
        referenceRect: CanonicalRect,
        referenceMode: ReferenceMode = .screen,
        referenceName: String? = "Screen — 1000×500",
        scale: CGFloat,
        cropRect: CanonicalRect,
        pixelWidth: Int,
        pixelHeight: Int,
        totals: [String] = []
    ) -> MeasurementSidecar {
        MeasurementSidecar.make(
            measurements: measurements,
            referenceRect: referenceRect,
            referenceMode: referenceMode,
            referenceName: referenceName,
            scale: scale,
            cropRect: cropRect,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            totals: totals,
            valueText: valueText,
            detailText: detailText
        )
    }

    // MARK: - Image + reference geometry

    func testImageDescribesPixelSizeScaleAndCropOrigin() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let sidecar = make(
            measurements: [],
            referenceRect: reference,
            scale: 2,
            cropRect: reference,
            pixelWidth: 2000,
            pixelHeight: 1000
        )
        XCTAssertEqual(sidecar.schemaVersion, 1)
        XCTAssertEqual(sidecar.image.pixelWidth, 2000)
        XCTAssertEqual(sidecar.image.pixelHeight, 1000)
        XCTAssertEqual(sidecar.image.scale, 2)
        XCTAssertEqual(sidecar.image.cropOrigin, .init(x: 0, y: 0))
        XCTAssertEqual(sidecar.image.pointWidth, 1000)
        XCTAssertEqual(sidecar.image.pointHeight, 500)
    }

    // The crop can sit anywhere in canonical space; the reference maps into image pixels via
    // (P - cropOrigin) * scale — here a window crop offset from the display origin.
    func testReferenceRectMapsToImagePixelsThroughCropOrigin() {
        let window = CanonicalRect(x: 100, y: 50, width: 400, height: 300)
        let sidecar = make(
            measurements: [],
            referenceRect: window,
            referenceMode: .windowUnderCursor,
            referenceName: "Safari — 400×300",
            scale: 2,
            cropRect: window,
            pixelWidth: 800,
            pixelHeight: 600
        )
        XCTAssertEqual(sidecar.reference.kind, "window")
        XCTAssertEqual(sidecar.reference.name, "Safari — 400×300")
        XCTAssertEqual(sidecar.reference.rectPoints, .init(x: 100, y: 50, width: 400, height: 300))
        // Reference == crop, so it fills the image from the origin.
        XCTAssertEqual(sidecar.reference.rectPixels, .init(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(sidecar.image.cropOrigin, .init(x: 100, y: 50))
    }

    func testReferenceKindMapping() {
        func kind(_ mode: ReferenceMode) -> String {
            make(measurements: [], referenceRect: .init(x: 0, y: 0, width: 10, height: 10),
                 referenceMode: mode, scale: 1, cropRect: .init(x: 0, y: 0, width: 10, height: 10),
                 pixelWidth: 10, pixelHeight: 10).reference.kind
        }
        XCTAssertEqual(kind(.windowUnderCursor), "window")
        XCTAssertEqual(kind(.screen), "screen")
        XCTAssertEqual(kind(.custom), "custom")
    }

    // MARK: - Rectangle measurement

    func testRectangleCanonicalAndPixelGeometry() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500) // area 500,000
        let rect = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 200, y: 100, width: 100, height: 50), label: "Header", colorIndex: 1)
        let sidecar = make(
            measurements: [rect],
            referenceRect: reference,
            scale: 2,
            cropRect: reference,
            pixelWidth: 2000,
            pixelHeight: 1000
        )
        let m = sidecar.measurements[0]
        XCTAssertEqual(m.kind, "rectangle")
        XCTAssertEqual(m.label, "Header")
        XCTAssertEqual(m.colorIndex, 1)
        XCTAssertEqual(m.colorName, "sky blue")
        XCTAssertEqual(m.rectPoints, .init(x: 200, y: 100, width: 100, height: 50))
        XCTAssertEqual(m.rectPixels, .init(x: 400, y: 200, width: 200, height: 100))
        XCTAssertEqual(m.sizePoints, .init(width: 100, height: 50))
        XCTAssertEqual(m.sizePixels, .init(width: 200, height: 100))
        XCTAssertNil(m.endpointsPoints)
        XCTAssertNil(m.endpointsPixels)
        // area% = (100*50)/(1000*500) * 100 = 1.0
        XCTAssertEqual(m.percentages.area, 1.0, accuracy: 1e-9)
        XCTAssertEqual(m.percentages.primary, 1.0, accuracy: 1e-9)
        XCTAssertEqual(m.percentages.width, 10.0, accuracy: 1e-9)
        XCTAssertEqual(m.percentages.height, 10.0, accuracy: 1e-9)
        XCTAssertEqual(m.valueText, "1.0%")
        XCTAssertEqual(m.detailText, "200×100 px")
    }

    func testUnlabeledMeasurementHasNilLabel() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 10, height: 10))
        let sidecar = make(measurements: [rect], referenceRect: reference, scale: 1, cropRect: reference, pixelWidth: 1000, pixelHeight: 500)
        XCTAssertNil(sidecar.measurements[0].label)
    }

    // MARK: - Line measurements (endpoints, not rect)

    func testHorizontalLineEndpointsAndPercent() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let line = Cubit.Measurement(kind: .horizontal, rect: CanonicalRect(x: 100, y: 250, width: 400, height: 0), colorIndex: 0)
        let sidecar = make(measurements: [line], referenceRect: reference, scale: 2, cropRect: reference, pixelWidth: 2000, pixelHeight: 1000)
        let m = sidecar.measurements[0]
        XCTAssertEqual(m.kind, "horizontal")
        XCTAssertEqual(m.colorName, "orange")
        XCTAssertNil(m.rectPoints)
        XCTAssertNil(m.rectPixels)
        XCTAssertEqual(m.endpointsPoints, [.init(x: 100, y: 250), .init(x: 500, y: 250)])
        XCTAssertEqual(m.endpointsPixels, [.init(x: 200, y: 500), .init(x: 1000, y: 500)])
        XCTAssertEqual(m.sizePoints, .init(width: 400, height: 0))
        XCTAssertEqual(m.sizePixels, .init(width: 800, height: 0))
        // width% = 400/1000 = 40; area% degenerate = 0
        XCTAssertEqual(m.percentages.primary, 40.0, accuracy: 1e-9)
        XCTAssertEqual(m.percentages.width, 40.0, accuracy: 1e-9)
        XCTAssertEqual(m.percentages.area, 0.0, accuracy: 1e-9)
        XCTAssertEqual(m.valueText, "40.0%")
        XCTAssertEqual(m.detailText, "800 px")
    }

    func testVerticalLineEndpoints() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let line = Cubit.Measurement(kind: .vertical, rect: CanonicalRect(x: 100, y: 100, width: 0, height: 250))
        let sidecar = make(measurements: [line], referenceRect: reference, scale: 1, cropRect: reference, pixelWidth: 1000, pixelHeight: 500)
        let m = sidecar.measurements[0]
        XCTAssertEqual(m.kind, "vertical")
        XCTAssertEqual(m.endpointsPoints, [.init(x: 100, y: 100), .init(x: 100, y: 350)])
        XCTAssertEqual(m.endpointsPixels, [.init(x: 100, y: 100), .init(x: 100, y: 350)])
        XCTAssertEqual(m.percentages.primary, 50.0, accuracy: 1e-9)
        XCTAssertEqual(m.detailText, "250 px")
    }

    // MARK: - Totals passthrough

    func testTotalsAreCarriedVerbatim() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let sidecar = make(measurements: [], referenceRect: reference, scale: 1, cropRect: reference,
                           pixelWidth: 1000, pixelHeight: 500, totals: ["Total area  ·  3.0%"])
        XCTAssertEqual(sidecar.totals, ["Total area  ·  3.0%"])
    }

    // MARK: - Deterministic JSON

    func testJSONIsSortedAndPrettyPrinted() throws {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 100, height: 50), label: "A", colorIndex: 2)
        let sidecar = make(measurements: [rect], referenceRect: reference, referenceName: "Screen",
                           scale: 2, cropRect: reference, pixelWidth: 2000, pixelHeight: 1000)
        let json = String(data: try sidecar.jsonData(), encoding: .utf8)!

        // Pretty-printed (newlines + indentation).
        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("  \"schemaVersion\" : 1"))
        // sortedKeys: within `image`, cropOrigin precedes pixelHeight precedes scale.
        let cropIdx = json.range(of: "\"cropOrigin\"")!.lowerBound
        let pixelIdx = json.range(of: "\"pixelHeight\"")!.lowerBound
        let scaleIdx = json.range(of: "\"scale\"")!.lowerBound
        XCTAssertTrue(cropIdx < pixelIdx)
        XCTAssertTrue(pixelIdx < scaleIdx)
    }

    func testJSONRoundTripsThroughDecoder() throws {
        let reference = CanonicalRect(x: 10, y: 20, width: 800, height: 600)
        let measurements = [
            Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 50, y: 60, width: 200, height: 100), label: "Box", colorIndex: 3),
            Cubit.Measurement(kind: .horizontal, rect: CanonicalRect(x: 20, y: 400, width: 300, height: 0), colorIndex: 5)
        ]
        let sidecar = make(measurements: measurements, referenceRect: reference, referenceMode: .custom,
                           referenceName: "Custom", scale: 2, cropRect: reference, pixelWidth: 1600, pixelHeight: 1200,
                           totals: ["Total area  ·  4.2%"])
        let data = try sidecar.jsonData()
        let decoded = try JSONDecoder().decode(MeasurementSidecar.self, from: data)
        XCTAssertEqual(decoded, sidecar)
    }

    // MARK: - Privacy

    func testJSONContainsNoPathsUsernamesOrTimestampKeys() throws {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 100, height: 50), label: "A", colorIndex: 0)
        let sidecar = make(measurements: [rect], referenceRect: reference, referenceName: "Safari — 1000×500",
                           scale: 2, cropRect: reference, pixelWidth: 2000, pixelHeight: 1000)
        let json = try XCTUnwrap(String(data: try sidecar.jsonData(), encoding: .utf8))
        // Needle built by concatenation so the source itself carries no absolute-path literal.
        let homePrefix = "/" + "Users" + "/"
        XCTAssertFalse(json.contains(homePrefix))
        XCTAssertFalse(json.contains(NSHomeDirectory()))
        XCTAssertFalse(json.lowercased().contains("timestamp"))
        XCTAssertFalse(json.lowercased().contains("\"date\""))
        XCTAssertFalse(json.lowercased().contains("path"))
    }
}
