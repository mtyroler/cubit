import XCTest
@testable import Cubit

/// Core handoff logic (v0.3 M4): cubit:// URL parsing, handoff-document decode + validation,
/// canonical→Measurement mapping, and clamping. Pure — no live overlay or TCC.
final class HandoffTests: XCTestCase {

    // MARK: - URL parsing

    func testParsePathForm() throws {
        let payload = try HandoffURL.parse("cubit://show?path=/tmp/handoff.json")
        XCTAssertEqual(payload, .path("/tmp/handoff.json"))
    }

    func testParsePathIsPercentDecoded() throws {
        let payload = try HandoffURL.parse("cubit://show?path=/tmp/my%20folder/handoff.json")
        XCTAssertEqual(payload, .path("/tmp/my folder/handoff.json"))
    }

    func testParseInlineRegionsBase64URL() throws {
        let json = #"{"schemaVersion":1,"measurements":[{"kind":"rectangle","rect":{"x":1,"y":2,"width":3,"height":4}}]}"#
        let encoded = Self.base64URL(Data(json.utf8))
        let payload = try HandoffURL.parse("cubit://show?regions=\(encoded)")
        guard case .inline(let data) = payload else { return XCTFail("expected .inline") }
        XCTAssertEqual(String(decoding: data, as: UTF8.self), json)
    }

    func testInlineWinsWhenBothPresent() throws {
        let encoded = Self.base64URL(Data(#"{"measurements":[]}"#.utf8))
        let payload = try HandoffURL.parse("cubit://show?path=/tmp/x.json&regions=\(encoded)")
        guard case .inline = payload else { return XCTFail("regions (inline) should win over path") }
    }

    func testWrongSchemeRejected() {
        XCTAssertThrowsError(try HandoffURL.parse("https://show?path=/tmp/x.json")) { error in
            XCTAssertEqual(error as? HandoffURL.ParseError, .wrongScheme("https"))
        }
    }

    func testWrongHostRejected() {
        XCTAssertThrowsError(try HandoffURL.parse("cubit://export?path=/tmp/x.json")) { error in
            XCTAssertEqual(error as? HandoffURL.ParseError, .wrongHost("export"))
        }
    }

    func testMissingParameterRejected() {
        XCTAssertThrowsError(try HandoffURL.parse("cubit://show")) { error in
            XCTAssertEqual(error as? HandoffURL.ParseError, .missingParameter)
        }
    }

    func testEmptyParameterValueRejected() {
        XCTAssertThrowsError(try HandoffURL.parse("cubit://show?path=")) { error in
            XCTAssertEqual(error as? HandoffURL.ParseError, .missingParameter)
        }
    }

    func testInvalidBase64Rejected() {
        // "!!!" is not decodable even after base64url normalization + ignoring unknown chars: it
        // has no valid base64 quantum.
        XCTAssertThrowsError(try HandoffURL.parse("cubit://show?regions=%21%21%21")) { error in
            XCTAssertEqual(error as? HandoffURL.ParseError, .invalidBase64)
        }
    }

    func testSchemeIsCaseInsensitive() throws {
        let payload = try HandoffURL.parse("CUBIT://show?path=/tmp/x.json")
        XCTAssertEqual(payload, .path("/tmp/x.json"))
    }

    func testShowURLRoundTripsPath() throws {
        let path = "/tmp/my folder/handoff.json"
        let url = try XCTUnwrap(HandoffURL.showURL(forPath: path))
        XCTAssertEqual(url.scheme, "cubit")
        let payload = try HandoffURL.parse(url.absoluteString)
        XCTAssertEqual(payload, .path(path))
    }

    // MARK: - base64url decoding edge cases

    func testBase64URLDecodesUnpadded() {
        // "Cubit" → base64 "Q3ViaXQ=" → base64url unpadded "Q3ViaXQ".
        let decoded = HandoffURL.decodeBase64URL("Q3ViaXQ")
        XCTAssertEqual(decoded.map { String(decoding: $0, as: UTF8.self) }, "Cubit")
    }

    func testBase64URLDecodesDashUnderscoreAlphabet() {
        // Bytes 0xFB 0xEF 0xFF → standard base64 "++//", base64url "--__".
        let decoded = HandoffURL.decodeBase64URL("--__")
        XCTAssertEqual(decoded.map(Array.init), [0xFB, 0xEF, 0xFF])
    }

    // MARK: - Document decode

    func testSchemaVersionDefaultsToCurrentWhenOmitted() throws {
        let doc = try Self.decode(#"{"measurements":[{"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1}}]}"#)
        XCTAssertEqual(doc.schemaVersion, HandoffDocument.currentSchemaVersion)
    }

    func testNoteDecodes() throws {
        let doc = try Self.decode(#"{"note":"hi","measurements":[{"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1}}]}"#)
        XCTAssertEqual(doc.note, "hi")
    }

    // MARK: - Mapping (exact values, canonical points used as-is)

    func testRectangleMapsCanonicalPointsUnchanged() throws {
        let doc = try Self.decode(#"{"measurements":[{"kind":"rectangle","rect":{"x":320,"y":140,"width":480,"height":300}}]}"#)
        let m = try HandoffMapper.measurements(from: doc)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].kind, .rectangle)
        XCTAssertEqual(m[0].rect, CanonicalRect(x: 320, y: 140, width: 480, height: 300))
    }

    func testHorizontalLineFromEndpoints() throws {
        let doc = try Self.decode(#"{"measurements":[{"kind":"horizontal","endpoints":[{"x":800,"y":480},{"x":320,"y":480}]}]}"#)
        let m = try HandoffMapper.measurements(from: doc)
        // Normalized to min-x origin, zero height.
        XCTAssertEqual(m[0].kind, .horizontal)
        XCTAssertEqual(m[0].rect, CanonicalRect(x: 320, y: 480, width: 480, height: 0))
    }

    func testVerticalLineFromEndpoints() throws {
        let doc = try Self.decode(#"{"measurements":[{"kind":"vertical","endpoints":[{"x":320,"y":440},{"x":320,"y":140}]}]}"#)
        let m = try HandoffMapper.measurements(from: doc)
        XCTAssertEqual(m[0].kind, .vertical)
        XCTAssertEqual(m[0].rect, CanonicalRect(x: 320, y: 140, width: 0, height: 300))
    }

    func testColorIndexDefaultsToPositionAndExplicitWins() throws {
        let doc = try Self.decode("""
        {"measurements":[
          {"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1}},
          {"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1},"colorIndex":5}
        ]}
        """)
        let m = try HandoffMapper.measurements(from: doc)
        XCTAssertEqual(m[0].colorIndex, 0) // position
        XCTAssertEqual(m[1].colorIndex, 5) // explicit
    }

    func testColorIndexNormalizedIntoPalette() throws {
        let doc = try Self.decode(#"{"measurements":[{"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1},"colorIndex":-3}]}"#)
        let m = try HandoffMapper.measurements(from: doc)
        XCTAssertEqual(m[0].colorIndex, Palette.colors.count - 3) // -3 wraps to 5 for an 8-color palette
    }

    func testLabelPassThroughAndTruncation() throws {
        let long = String(repeating: "a", count: HandoffMapper.maxLabelLength + 50)
        let doc = HandoffDocument(measurements: [
            .init(kind: "rectangle", rect: .init(x: 0, y: 0, width: 1, height: 1), endpoints: nil, label: long, colorIndex: nil)
        ])
        let m = try HandoffMapper.measurements(from: doc)
        XCTAssertEqual(m[0].label.count, HandoffMapper.maxLabelLength)
    }

    // MARK: - Validation errors

    func testUnknownKindRejected() {
        let doc = HandoffDocument(measurements: [.init(kind: "triangle", rect: .init(x: 0, y: 0, width: 1, height: 1), endpoints: nil, label: nil, colorIndex: nil)])
        XCTAssertThrowsError(try HandoffMapper.measurements(from: doc)) {
            XCTAssertEqual($0 as? HandoffMapper.HandoffError, .invalidMeasurement(index: 0, reason: "unknown kind 'triangle' (use rectangle, horizontal, or vertical)"))
        }
    }

    func testEmptyDocumentRejected() {
        XCTAssertThrowsError(try HandoffMapper.measurements(from: HandoffDocument(measurements: []))) {
            XCTAssertEqual($0 as? HandoffMapper.HandoffError, .emptyDocument)
        }
    }

    func testOverCapRejected() {
        let items = (0..<(HandoffMapper.maxMeasurements + 1)).map { _ in
            HandoffDocument.ProposedMeasurement(kind: "rectangle", rect: .init(x: 0, y: 0, width: 1, height: 1), endpoints: nil, label: nil, colorIndex: nil)
        }
        XCTAssertThrowsError(try HandoffMapper.measurements(from: HandoffDocument(measurements: items))) {
            XCTAssertEqual($0 as? HandoffMapper.HandoffError, .tooManyMeasurements(count: HandoffMapper.maxMeasurements + 1, limit: HandoffMapper.maxMeasurements))
        }
    }

    func testAtCapAccepted() throws {
        let items = (0..<HandoffMapper.maxMeasurements).map { _ in
            HandoffDocument.ProposedMeasurement(kind: "rectangle", rect: .init(x: 0, y: 0, width: 1, height: 1), endpoints: nil, label: nil, colorIndex: nil)
        }
        XCTAssertEqual(try HandoffMapper.measurements(from: HandoffDocument(measurements: items)).count, HandoffMapper.maxMeasurements)
    }

    func testUnsupportedSchemaVersionRejected() {
        let doc = HandoffDocument(schemaVersion: 99, measurements: [.init(kind: "rectangle", rect: .init(x: 0, y: 0, width: 1, height: 1), endpoints: nil, label: nil, colorIndex: nil)])
        XCTAssertThrowsError(try HandoffMapper.measurements(from: doc)) {
            XCTAssertEqual($0 as? HandoffMapper.HandoffError, .unsupportedSchemaVersion(99))
        }
    }

    func testZeroSizeRectangleRejected() {
        let doc = HandoffDocument(measurements: [.init(kind: "rectangle", rect: .init(x: 0, y: 0, width: 0, height: 10), endpoints: nil, label: nil, colorIndex: nil)])
        XCTAssertThrowsError(try HandoffMapper.measurements(from: doc))
    }

    func testNonFiniteCoordinateRejected() {
        let doc = HandoffDocument(measurements: [.init(kind: "rectangle", rect: .init(x: .infinity, y: 0, width: 10, height: 10), endpoints: nil, label: nil, colorIndex: nil)])
        XCTAssertThrowsError(try HandoffMapper.measurements(from: doc)) {
            XCTAssertEqual($0 as? HandoffMapper.HandoffError, .invalidMeasurement(index: 0, reason: "coordinate is not finite"))
        }
    }

    func testHorizontalLineNotSharingYRejected() {
        let doc = HandoffDocument(measurements: [.init(kind: "horizontal", rect: nil, endpoints: [.init(x: 0, y: 0), .init(x: 10, y: 5)], label: nil, colorIndex: nil)])
        XCTAssertThrowsError(try HandoffMapper.measurements(from: doc))
    }

    func testZeroLengthLineRejected() {
        let doc = HandoffDocument(measurements: [.init(kind: "horizontal", rect: nil, endpoints: [.init(x: 5, y: 5), .init(x: 5, y: 5)], label: nil, colorIndex: nil)])
        XCTAssertThrowsError(try HandoffMapper.measurements(from: doc))
    }

    func testRectangleMissingRectRejected() {
        let doc = HandoffDocument(measurements: [.init(kind: "rectangle", rect: nil, endpoints: nil, label: nil, colorIndex: nil)])
        XCTAssertThrowsError(try HandoffMapper.measurements(from: doc))
    }

    // MARK: - Clamping

    func testInBoundsMeasurementUnchanged() {
        let bounds = [CanonicalRect(x: 0, y: 0, width: 1000, height: 800)]
        let m = Measurement(kind: .rectangle, rect: CanonicalRect(x: 100, y: 100, width: 200, height: 200))
        XCTAssertEqual(HandoffMapper.clamped([m], to: bounds)[0].rect, m.rect)
    }

    func testOffScreenMeasurementPulledIn() {
        let bounds = [CanonicalRect(x: 0, y: 0, width: 1000, height: 800)]
        let m = Measurement(kind: .rectangle, rect: CanonicalRect(x: 5000, y: 5000, width: 200, height: 200))
        let clamped = HandoffMapper.clamped([m], to: bounds)[0].rect
        // Pinned to the bottom-right corner, size preserved.
        XCTAssertEqual(clamped, CanonicalRect(x: 800, y: 600, width: 200, height: 200))
    }

    func testOversizedMeasurementCappedToBounds() {
        let bounds = [CanonicalRect(x: 0, y: 0, width: 1000, height: 800)]
        let m = Measurement(kind: .rectangle, rect: CanonicalRect(x: -100, y: -100, width: 5000, height: 5000))
        let clamped = HandoffMapper.clamped([m], to: bounds)[0].rect
        XCTAssertEqual(clamped, CanonicalRect(x: 0, y: 0, width: 1000, height: 800))
    }

    func testClampUsesUnionOfMultipleScreens() {
        // Two side-by-side 1000-wide displays → union bounding box is 2000 wide.
        let bounds = [
            CanonicalRect(x: 0, y: 0, width: 1000, height: 800),
            CanonicalRect(x: 1000, y: 0, width: 1000, height: 800)
        ]
        let m = Measurement(kind: .rectangle, rect: CanonicalRect(x: 1500, y: 100, width: 200, height: 200))
        // Already within the union — unchanged.
        XCTAssertEqual(HandoffMapper.clamped([m], to: bounds)[0].rect, m.rect)
    }

    func testClampWithNoBoundsReturnsUnchanged() {
        let m = Measurement(kind: .rectangle, rect: CanonicalRect(x: 5000, y: 5000, width: 10, height: 10))
        XCTAssertEqual(HandoffMapper.clamped([m], to: [])[0].rect, m.rect)
    }

    // MARK: - Helpers

    private static func decode(_ json: String) throws -> HandoffDocument {
        try JSONDecoder().decode(HandoffDocument.self, from: Data(json.utf8))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
