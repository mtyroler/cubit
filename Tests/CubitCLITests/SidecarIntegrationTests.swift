import XCTest
@testable import Cubit

/// Verifies the annotate path feeds the M1 `MeasurementSidecar` schema correctly: pixel values
/// round-trip exactly, formatting matches the app export's, and the reference block is right.
/// Built without the SwiftUI renderer (which needs a live app/run loop) so it stays a
/// deterministic unit test; the real-binary run exercises the full render pipeline.
final class SidecarIntegrationTests: XCTestCase {
    /// Mirrors `ExportRenderer.sidecar(geometry:…)` for a full-image annotate crop.
    private func makeSidecar(
        _ resolved: ResolvedRegions,
        scale: CGFloat,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> MeasurementSidecar {
        let reference = AnnotateCommand.makeReference(resolved, scale: scale)
        let cropRect = CanonicalRect(x: 0, y: 0, width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        return MeasurementSidecar.make(
            measurements: resolved.measurements,
            referenceRect: reference.rect,
            referenceMode: reference.mode,
            referenceName: reference.descriptor,
            scale: scale,
            cropRect: cropRect,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            totals: [],
            valueText: { ExportRenderer.primaryText($0) },
            detailText: { ExportRenderer.detailText(kind: $0, metrics: $1) }
        )
    }

    private func decode(_ json: String) throws -> RegionsInput {
        try JSONDecoder().decode(RegionsInput.self, from: Data(json.utf8))
    }

    func testRectangleSidecarRoundTripsPixelsExactly() throws {
        let input = try decode("""
        { "reference": { "rect": { "x": 0, "y": 0, "width": 2000, "height": 1400 } },
          "regions": [ { "kind": "rectangle", "rect": { "x": 200, "y": 240, "width": 600, "height": 400 },
                         "label": "hero", "colorIndex": 0 } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 2400, imagePixelHeight: 1600, scale: 2)
        let sidecar = makeSidecar(resolved, scale: 2, pixelWidth: 2400, pixelHeight: 1600)

        XCTAssertEqual(sidecar.schemaVersion, 1)
        XCTAssertEqual(sidecar.image.pixelWidth, 2400)
        XCTAssertEqual(sidecar.image.pixelHeight, 1600)
        XCTAssertEqual(sidecar.image.scale, 2)

        let m = sidecar.measurements[0]
        XCTAssertEqual(m.kind, "rectangle")
        XCTAssertEqual(m.label, "hero")
        XCTAssertEqual(m.colorName, "orange")
        XCTAssertEqual(m.valueText, "8.6%")             // primary = area% (600·400 / 2000·1400)
        XCTAssertEqual(m.detailText, "600×400 px")
        // Input pixels come back byte-for-byte through the point↔pixel transform.
        XCTAssertEqual(m.rectPixels, MeasurementSidecar.Rect(x: 200, y: 240, width: 600, height: 400))
        XCTAssertEqual(m.rectPoints, MeasurementSidecar.Rect(x: 100, y: 120, width: 300, height: 200))
        XCTAssertEqual(m.percentages.width, 30, accuracy: 1e-9)
        XCTAssertEqual(m.percentages.area, 600.0 * 400.0 / (2000.0 * 1400.0) * 100, accuracy: 1e-9)
        XCTAssertEqual(m.percentages.primary, m.percentages.area, accuracy: 1e-9)
    }

    func testLineEndpointsAndReferenceBlock() throws {
        let input = try decode("""
        { "regions": [ { "kind": "horizontal", "endpoints": [ { "x": 200, "y": 900 }, { "x": 1400, "y": 900 } ] } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 2400, imagePixelHeight: 1600, scale: 2)
        let sidecar = makeSidecar(resolved, scale: 2, pixelWidth: 2400, pixelHeight: 1600)

        let m = sidecar.measurements[0]
        XCTAssertEqual(m.kind, "horizontal")
        XCTAssertNil(m.rectPixels)
        XCTAssertEqual(m.endpointsPixels, [
            MeasurementSidecar.Point(x: 200, y: 900),
            MeasurementSidecar.Point(x: 1400, y: 900),
        ])
        XCTAssertEqual(m.detailText, "1200 px")
        XCTAssertEqual(m.percentages.primary, 50, accuracy: 1e-9) // 1200px / 2400px full-image width

        // Full-image reference reports as "screen" with the whole-image rect.
        XCTAssertEqual(sidecar.reference.kind, "screen")
        XCTAssertEqual(sidecar.reference.name, "Image — 1200×800")
        XCTAssertEqual(sidecar.reference.rectPixels, MeasurementSidecar.Rect(x: 0, y: 0, width: 2400, height: 1600))
    }

    func testExplicitReferenceReportsCustom() throws {
        let input = try decode("""
        { "reference": { "rect": { "x": 100, "y": 100, "width": 2000, "height": 1400 } },
          "regions": [ { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 200, "height": 200 } } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 2400, imagePixelHeight: 1600, scale: 2)
        let sidecar = makeSidecar(resolved, scale: 2, pixelWidth: 2400, pixelHeight: 1600)
        XCTAssertEqual(sidecar.reference.kind, "custom")
        XCTAssertEqual(sidecar.reference.rectPixels, MeasurementSidecar.Rect(x: 100, y: 100, width: 2000, height: 1400))
    }

    func testSidecarSerializesWithSortedPrettyKeys() throws {
        let input = try decode("""
        { "regions": [ { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 100, "height": 100 } } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 200, imagePixelHeight: 200, scale: 2)
        let sidecar = makeSidecar(resolved, scale: 2, pixelWidth: 200, pixelHeight: 200)
        let json = String(decoding: try sidecar.jsonData(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
        // sortedKeys → "image" precedes "measurements" precedes "reference".
        let iImage = try XCTUnwrap(json.range(of: "\"image\""))
        let iMeasurements = try XCTUnwrap(json.range(of: "\"measurements\""))
        XCTAssertLessThan(iImage.lowerBound, iMeasurements.lowerBound)
    }
}
