import XCTest
@testable import Cubit

/// Tool behavior with exact-value assertions on the geometry, plus the argument-validation and
/// error-mapping paths an agent depends on. Nothing here needs live TCC or capture.
@MainActor
final class ToolsTests: XCTestCase {
    /// Calls a tool and returns (result, decoded first text-content JSON).
    private func call(_ name: String, _ json: String) throws -> (ToolResult, JSONValue) {
        let result = MCPTools.call(name: name, arguments: try JSONValue.parse(json))
        let text = try XCTUnwrap(result.content.first { $0.type == "text" }?.text)
        return (result, try JSONValue.parse(Data(text.utf8)))
    }

    /// Unwraps a JSON number for an exact/approximate numeric assertion.
    private func number(_ value: JSONValue?) throws -> Double {
        try XCTUnwrap(value?.doubleValue)
    }

    // MARK: measure_region

    func testMeasureRectangleExactPercentagesAndPixels() throws {
        // 300×200 pt rectangle against a 1000×700 pt reference, scale 2.
        let (result, doc) = try call("measure_region", #"""
        { "region": { "kind": "rectangle", "rect": { "x": 100, "y": 120, "width": 300, "height": 200 } },
          "reference": { "rect": { "x": 0, "y": 0, "width": 1000, "height": 700 } },
          "scale": 2 }
        """#)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(doc["kind"]?.stringValue, "rectangle")
        XCTAssertEqual(try number(doc["percentages"]?["width"]), 30, accuracy: 1e-9)      // 300/1000
        XCTAssertEqual(try number(doc["percentages"]?["height"]), 200.0 / 700 * 100, accuracy: 1e-9)
        XCTAssertEqual(try number(doc["percentages"]?["area"]), 300.0 * 200 / (1000 * 700) * 100, accuracy: 1e-9)
        XCTAssertEqual(try number(doc["percentages"]?["primary"]), try number(doc["percentages"]?["area"]), accuracy: 1e-12)
        XCTAssertEqual(try number(doc["sizePixels"]?["width"]), 600)   // 300 * scale 2
        XCTAssertEqual(try number(doc["sizePixels"]?["height"]), 400)
        XCTAssertEqual(doc["valueText"]?.stringValue, "8.6%")           // %.1f of 8.571…
        XCTAssertEqual(doc["detailText"]?.stringValue, "600×400 px")
        XCTAssertEqual(doc["reference"]?["kind"]?.stringValue, "custom")
        XCTAssertEqual(try number(doc["reference"]?["areaPoints"]), 700000)
    }

    func testMeasureHorizontalLineWidthPercent() throws {
        let (result, doc) = try call("measure_region", #"""
        { "region": { "kind": "horizontal", "endpoints": [ { "x": 200, "y": 900 }, { "x": 1400, "y": 900 } ] },
          "reference": { "rect": { "x": 0, "y": 0, "width": 2400, "height": 1600 } }, "scale": 2 }
        """#)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(try number(doc["percentages"]?["primary"]), 1200.0 / 2400 * 100, accuracy: 1e-9) // 50%
        XCTAssertEqual(doc["detailText"]?.stringValue, "2400 px")   // 1200 pt * scale 2
    }

    func testMeasureRegionMissingRegionIsInvalidArguments() throws {
        let result = MCPTools.call(name: "measure_region", arguments: .object([:]))
        XCTAssertTrue(result.isError)
        let message = try XCTUnwrap(result.content.first?.text)
        XCTAssertTrue(message.hasPrefix("invalid_arguments:"), message)
        XCTAssertTrue(message.contains("region"), message)
    }

    func testMeasureHorizontalWithMismatchedYIsInvalidArguments() {
        let result = MCPTools.call(name: "measure_region", arguments: try! JSONValue.parse(#"""
        { "region": { "kind": "horizontal", "endpoints": [ { "x": 200, "y": 900 }, { "x": 1400, "y": 905 } ] },
          "reference": { "rect": { "x": 0, "y": 0, "width": 2400, "height": 1600 } } }
        """#))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.first?.text?.hasPrefix("invalid_arguments:") ?? false)
    }

    // MARK: analyze_dead_space

    func testDeadSpaceArithmeticExact() throws {
        // 1000×800 reference (area 800000 pt²). Two content rects: 200×100 and 400×200.
        let (result, doc) = try call("analyze_dead_space", #"""
        { "target": { "rect": { "x": 0, "y": 0, "width": 1000, "height": 800 } },
          "scale": 2,
          "content": [
            { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 200, "height": 100 }, "label": "nav" },
            { "kind": "rectangle", "rect": { "x": 300, "y": 300, "width": 400, "height": 200 } }
          ] }
        """#)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(try number(doc["reference"]?["areaPoints"]), 800000)
        XCTAssertEqual(try number(doc["reference"]?["areaPixels"]), 800000 * 4)  // scale² = 4
        XCTAssertEqual(try number(doc["usedAreaPoints"]), 100000)                // 20000 + 80000
        XCTAssertEqual(try number(doc["usedPercent"]), 12.5, accuracy: 1e-9)     // 100000/800000
        XCTAssertEqual(try number(doc["deadSpacePercent"]), 87.5, accuracy: 1e-9)
        XCTAssertEqual(doc["regionCount"]?.intValue, 2)
        guard case .array(let regions) = try XCTUnwrap(doc["regions"]) else { return XCTFail("regions not array") }
        XCTAssertEqual(regions[0]["label"]?.stringValue, "nav")
        XCTAssertEqual(try number(regions[0]["areaPercent"]), 2.5, accuracy: 1e-9)    // 20000/800000
        XCTAssertEqual(try number(regions[1]["areaPercent"]), 10, accuracy: 1e-9)     // 80000/800000
        XCTAssertFalse(doc["note"]?.stringValue?.isEmpty ?? true)
    }

    func testDeadSpaceZeroContentIsAllDeadSpace() throws {
        let (result, doc) = try call("analyze_dead_space", #"""
        { "target": { "rect": { "x": 0, "y": 0, "width": 500, "height": 500 } }, "content": [] }
        """#)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(try number(doc["usedPercent"]), 0)
        XCTAssertEqual(try number(doc["deadSpacePercent"]), 100)
    }

    // MARK: errors & dispatch

    func testUnknownToolIsError() {
        let result = MCPTools.call(name: "nope", arguments: .object([:]))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.first?.text?.hasPrefix("unknown_tool:") ?? false)
    }

    func testPermissionDeniedMappingIsTagged() {
        let result = MCPTools.mapError(CLIError(.permissionDenied, "Screen Recording permission is required."))
        XCTAssertTrue(result.isError)
        let message = try? XCTUnwrap(result.content.first?.text)
        XCTAssertTrue(message?.hasPrefix("permission_denied:") ?? false, message ?? "nil")
    }

    func testNotFoundMappingIsTagged() {
        let result = MCPTools.mapError(CLIError(.notFound, "no on-screen window has number 999"))
        XCTAssertTrue(result.content.first?.text?.hasPrefix("not_found:") ?? false)
    }

    // MARK: schemas

    func testEveryToolSchemaIsAValidObjectSchema() {
        for descriptor in MCPTools.descriptors {
            XCTAssertEqual(descriptor.inputSchema["type"]?.stringValue, "object", descriptor.name)
            XCTAssertNotNil(descriptor.inputSchema["properties"], descriptor.name)
        }
    }
}
