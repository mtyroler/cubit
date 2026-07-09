import XCTest
@testable import Cubit

/// Core handoff coverage under the app toolchain (xcodebuild). The comprehensive suite lives in
/// CubitMCPTests (swift test); this is a focused subset of exact-value assertions so the app
/// target also verifies the URL parse → decode → map → clamp path the overlay depends on.
final class HandoffTests: XCTestCase {

    func testURLPathAndInlineForms() throws {
        XCTAssertEqual(try HandoffURL.parse("cubit://show?path=/tmp/h.json"), .path("/tmp/h.json"))

        let json = #"{"measurements":[{"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1}}]}"#
        let b64url = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard case .inline(let data) = try HandoffURL.parse("cubit://show?regions=\(b64url)") else {
            return XCTFail("expected inline payload")
        }
        XCTAssertEqual(String(decoding: data, as: UTF8.self), json)
    }

    @MainActor
    func testMapsCanonicalPointsUnchangedAndSelectsFirst() throws {
        let doc = try JSONDecoder().decode(HandoffDocument.self, from: Data(#"""
        {"measurements":[
          {"kind":"rectangle","rect":{"x":320,"y":140,"width":480,"height":300},"label":"hero"},
          {"kind":"vertical","endpoints":[{"x":320,"y":440},{"x":320,"y":140}]}
        ]}
        """#.utf8))
        let measurements = try HandoffMapper.measurements(from: doc)
        XCTAssertEqual(measurements[0].rect, CanonicalRect(x: 320, y: 140, width: 480, height: 300))
        XCTAssertEqual(measurements[0].label, "hero")
        XCTAssertEqual(measurements[1].kind, .vertical)
        XCTAssertEqual(measurements[1].rect, CanonicalRect(x: 320, y: 140, width: 0, height: 300))

        // The session injects them as one undo step and selects the first — the affordance that
        // makes the existing handles live immediately.
        let session = MeasurementSession(screenReference: CanonicalRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        XCTAssertTrue(session.injectProposed(measurements))
        XCTAssertEqual(session.measurements.count, 2)
        XCTAssertEqual(session.selectedID, measurements.first?.id)
        session.undo()
        XCTAssertTrue(session.measurements.isEmpty)
    }

    func testClampPullsOffScreenIntoBounds() {
        let bounds = [CanonicalRect(x: 0, y: 0, width: 1000, height: 800)]
        let m = Measurement(kind: .rectangle, rect: CanonicalRect(x: 5000, y: 5000, width: 200, height: 200))
        XCTAssertEqual(HandoffMapper.clamped([m], to: bounds)[0].rect, CanonicalRect(x: 800, y: 600, width: 200, height: 200))
    }

    func testOverCapRejected() {
        let items = (0...HandoffMapper.maxMeasurements).map { _ in
            HandoffDocument.ProposedMeasurement(kind: "rectangle", rect: .init(x: 0, y: 0, width: 1, height: 1), endpoints: nil, label: nil, colorIndex: nil)
        }
        XCTAssertThrowsError(try HandoffMapper.measurements(from: HandoffDocument(measurements: items)))
    }
}
