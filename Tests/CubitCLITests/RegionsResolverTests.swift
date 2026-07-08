import XCTest
@testable import Cubit

final class RegionsResolverTests: XCTestCase {
    private func decode(_ json: String) throws -> RegionsInput {
        try JSONDecoder().decode(RegionsInput.self, from: Data(json.utf8))
    }

    // MARK: Geometry (exact values)

    func testRectangleConvertsPixelsToCanonicalPoints() throws {
        let input = try decode("""
        { "regions": [ { "kind": "rectangle", "rect": { "x": 200, "y": 240, "width": 600, "height": 400 } } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 2400, imagePixelHeight: 1600, scale: 2)
        XCTAssertEqual(resolved.measurements.count, 1)
        let m = resolved.measurements[0]
        XCTAssertEqual(m.kind, .rectangle)
        // Pixels ÷ scale = canonical points.
        XCTAssertEqual(m.rect, CanonicalRect(x: 100, y: 120, width: 300, height: 200))
        // Default reference is the whole image in points.
        XCTAssertEqual(resolved.referenceRect, CanonicalRect(x: 0, y: 0, width: 1200, height: 800))
        XCTAssertFalse(resolved.referenceExplicit)
    }

    func testHorizontalLineFromEndpoints() throws {
        let input = try decode("""
        { "regions": [ { "kind": "horizontal", "endpoints": [ { "x": 1400, "y": 900 }, { "x": 200, "y": 900 } ] } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 2400, imagePixelHeight: 1600, scale: 2)
        // Endpoints out of order still normalize to min→max x; height is zero.
        XCTAssertEqual(resolved.measurements[0].rect, CanonicalRect(x: 100, y: 450, width: 600, height: 0))
    }

    func testVerticalLineFromEndpoints() throws {
        let input = try decode("""
        { "regions": [ { "kind": "vertical", "endpoints": [ { "x": 300, "y": 1100 }, { "x": 300, "y": 300 } ] } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 2400, imagePixelHeight: 1600, scale: 2)
        XCTAssertEqual(resolved.measurements[0].rect, CanonicalRect(x: 150, y: 150, width: 0, height: 400))
    }

    func testExplicitReferenceRect() throws {
        let input = try decode("""
        { "reference": { "rect": { "x": 100, "y": 100, "width": 2000, "height": 1400 } },
          "regions": [ { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 200, "height": 200 } } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 2400, imagePixelHeight: 1600, scale: 2)
        XCTAssertTrue(resolved.referenceExplicit)
        XCTAssertEqual(resolved.referenceRect, CanonicalRect(x: 50, y: 50, width: 1000, height: 700))
    }

    func testDefaultColorIndexCyclesByPosition() throws {
        let input = try decode("""
        { "regions": [
          { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 10, "height": 10 } },
          { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 10, "height": 10 }, "colorIndex": 5 },
          { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 10, "height": 10 } }
        ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 1)
        XCTAssertEqual(resolved.measurements.map(\.colorIndex), [0, 5, 2])
    }

    func testScaleOneIsIdentity() throws {
        let input = try decode("""
        { "regions": [ { "kind": "rectangle", "rect": { "x": 10, "y": 20, "width": 30, "height": 40 } } ] }
        """)
        let resolved = try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 1)
        XCTAssertEqual(resolved.measurements[0].rect, CanonicalRect(x: 10, y: 20, width: 30, height: 40))
    }

    // MARK: Validation errors (all usage → exit 2)

    func testEmptyRegionsIsUsageError() throws {
        let input = try decode(#"{ "regions": [] }"#)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testUnknownKindIsUsageError() throws {
        let input = try decode(#"{ "regions": [ { "kind": "circle" } ] }"#)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testRectangleWithoutRectIsUsageError() throws {
        let input = try decode(#"{ "regions": [ { "kind": "rectangle" } ] }"#)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testZeroSizeRectangleIsUsageError() throws {
        let input = try decode("""
        { "regions": [ { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 0, "height": 100 } } ] }
        """)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testHorizontalWithMismatchedYIsUsageError() throws {
        let input = try decode("""
        { "regions": [ { "kind": "horizontal", "endpoints": [ { "x": 0, "y": 0 }, { "x": 100, "y": 50 } ] } ] }
        """)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testVerticalWithMismatchedXIsUsageError() throws {
        let input = try decode("""
        { "regions": [ { "kind": "vertical", "endpoints": [ { "x": 0, "y": 0 }, { "x": 50, "y": 100 } ] } ] }
        """)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testLineWithWrongEndpointCountIsUsageError() throws {
        let input = try decode("""
        { "regions": [ { "kind": "horizontal", "endpoints": [ { "x": 0, "y": 0 } ] } ] }
        """)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testZeroLengthLineIsUsageError() throws {
        let input = try decode("""
        { "regions": [ { "kind": "horizontal", "endpoints": [ { "x": 50, "y": 10 }, { "x": 50, "y": 10 } ] } ] }
        """)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 2) }
    }

    func testNonPositiveScaleIsUsageError() throws {
        let input = try decode("""
        { "regions": [ { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 10, "height": 10 } } ] }
        """)
        assertUsage { try RegionsResolver.resolve(input, imagePixelWidth: 100, imagePixelHeight: 100, scale: 0) }
    }

    private func assertUsage(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage, file: file, line: line)
        }
    }
}
