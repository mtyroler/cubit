import XCTest
@testable import Cubit

@MainActor
final class SidecarExportTests: XCTestCase {
    // MARK: - Preference (default off)

    func testSidecarPreferenceDefaultsOff() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        XCTAssertFalse(ExportLayoutPreferences(defaults: suite).writeJSONSidecar)
        XCTAssertFalse(SettingsStore(defaults: suite).writeJSONSidecar)
    }

    func testSidecarPreferenceRoundTripsThroughSettingsStore() {
        let suite = UserDefaults(suiteName: "cubit.test.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        store.writeJSONSidecar = true
        // Persisted under the shared contract key, readable by the layout prefs.
        XCTAssertTrue(ExportLayoutPreferences(defaults: suite).writeJSONSidecar)
        XCTAssertTrue(SettingsStore(defaults: suite).writeJSONSidecar)
    }

    // MARK: - Exporter sidecar location + write

    func testSidecarURLSwapsExtensionToJSON() {
        let png = URL(fileURLWithPath: "/var/example/Cubit measurement.png")
        XCTAssertEqual(Exporter.sidecarURL(for: png).lastPathComponent, "Cubit measurement.json")
    }

    func testWriteSidecarProducesDeterministicJSONFile() throws {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let sidecar = MeasurementSidecar.make(
            measurements: [Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 100, height: 50), label: "A", colorIndex: 0)],
            referenceRect: reference, referenceMode: .screen, referenceName: "Screen",
            scale: 2, cropRect: reference, pixelWidth: 2000, pixelHeight: 1000, totals: [],
            valueText: { ExportRenderer.primaryText($0) },
            detailText: { ExportRenderer.detailText(kind: $0, metrics: $1) }
        )

        let dir = FileManager.default.temporaryDirectory
        let imageURL = dir.appendingPathComponent("cubit-sidecar-\(UUID().uuidString).png")
        let written = try XCTUnwrap(Exporter.writeSidecar(sidecar, besideImageAt: imageURL))
        defer { try? FileManager.default.removeItem(at: written) }

        XCTAssertEqual(written.pathExtension, "json")
        let onDisk = try Data(contentsOf: written)
        XCTAssertEqual(onDisk, try sidecar.jsonData(), "file bytes must equal the deterministic encoding")
    }

    // MARK: - renderExport (PNG + matching sidecar in one pass)

    private static func solidImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // A screen export: the sidecar's image dims must equal the produced PNG's pixel dims, and
    // the reference (== full display) must map to the whole image.
    func testRenderExportSidecarMatchesRenderedImage() throws {
        let scale: CGFloat = 2
        let display = CanonicalRect(x: 0, y: 0, width: 1000, height: 800)
        let displayImage = Self.solidImage(width: 2000, height: 1600)
        let captured = CapturedDisplay(displayID: 1, cgImage: displayImage, canonicalFrame: display, scale: scale)
        let reference = ResolvedReference(rect: display, mode: .screen, descriptor: "Screen — 1000×800")

        let measurements = [
            Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 100, y: 100, width: 200, height: 100), label: "Box", colorIndex: 2)
        ]
        let export = try XCTUnwrap(ExportRenderer.renderExport(
            measurements: measurements, reference: reference, captured: captured
        ))

        // The PNG decodes to the same pixel size the sidecar reports (screen mode has no footer).
        let rep = try XCTUnwrap(NSBitmapImageRep(data: export.png))
        XCTAssertEqual(export.sidecar.image.pixelWidth, rep.pixelsWide)
        XCTAssertEqual(export.sidecar.image.pixelHeight, rep.pixelsHigh)
        XCTAssertEqual(export.sidecar.reference.rectPixels, .init(x: 0, y: 0, width: 2000, height: 1600))
        XCTAssertEqual(export.sidecar.measurements.first?.rectPixels, .init(x: 200, y: 200, width: 400, height: 200))
        XCTAssertEqual(export.sidecar.measurements.first?.colorName, "bluish green")
    }
}
