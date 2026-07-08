import XCTest
@testable import Cubit

final class CoordinateConverterTests: XCTestCase {
    private let builtin = DisplayDescriptor(
        id: 1,
        cocoaFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        scale: 2
    )

    private func singleDisplayConverter() -> CoordinateConverter {
        CoordinateConverter(primaryScreenHeight: 1117, displays: [builtin])
    }

    // MARK: (a) single 1728x1117 @2x display

    func testSingleDisplayPointConversion() {
        let converter = singleDisplayConverter()

        // Cocoa bottom-left corner maps to canonical bottom-left (y == height).
        XCTAssertEqual(converter.canonical(fromCocoa: CGPoint(x: 0, y: 0)), CanonicalPoint(x: 0, y: 1117))
        // Cocoa top-left corner maps to canonical origin.
        XCTAssertEqual(converter.canonical(fromCocoa: CGPoint(x: 0, y: 1117)), CanonicalPoint(x: 0, y: 0))
        XCTAssertEqual(converter.canonical(fromCocoa: CGPoint(x: 400, y: 900)), CanonicalPoint(x: 400, y: 217))
    }

    func testSingleDisplayRectConversion() {
        let converter = singleDisplayConverter()
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 400)

        let canonical = converter.canonical(fromCocoa: cocoa)
        XCTAssertEqual(canonical, CanonicalRect(x: 100, y: 517, width: 300, height: 400))
    }

    func testSingleDisplayPixelRect() {
        let converter = singleDisplayConverter()
        let canonical = CanonicalRect(x: 100, y: 517, width: 300, height: 400)

        let pixels = converter.displayPixelRect(fromCanonical: canonical, on: builtin)
        XCTAssertEqual(pixels, CGRect(x: 200, y: 1034, width: 600, height: 800))
    }

    func testPointsToPixelsScales() {
        let converter = singleDisplayConverter()
        XCTAssertEqual(converter.pixels(points: 300, on: builtin), 600)
    }

    // MARK: (b) secondary display LEFT of primary (negative X), different scale

    func testSecondaryLeftNegativeX() {
        let secondary = DisplayDescriptor(
            id: 2,
            cocoaFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            scale: 1
        )
        let converter = CoordinateConverter(primaryScreenHeight: 1117, displays: [builtin, secondary])

        // Top-left of the secondary in cocoa maps to the secondary's canonical top-left.
        XCTAssertEqual(
            converter.canonical(fromCocoa: CGPoint(x: -1920, y: 1080)),
            CanonicalPoint(x: -1920, y: 37)
        )
        XCTAssertEqual(
            converter.canonicalFrame(of: secondary),
            CanonicalRect(x: -1920, y: 37, width: 1920, height: 1080)
        )
        // Display-local mapping cancels the negative origin.
        XCTAssertEqual(
            converter.displayLocal(CanonicalPoint(x: -1920, y: 37), on: secondary),
            CanonicalPoint(x: 0, y: 0)
        )
        // Scale 1x: canonical points equal pixels within the display.
        XCTAssertEqual(
            converter.displayPixelRect(
                fromCanonical: CanonicalRect(x: -1920, y: 37, width: 1920, height: 1080),
                on: secondary
            ),
            CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
    }

    // MARK: (c) secondary display ABOVE primary (negative canonical Y)

    func testSecondaryAboveNegativeY() {
        let secondary = DisplayDescriptor(
            id: 3,
            cocoaFrame: CGRect(x: 0, y: 1117, width: 1728, height: 900),
            scale: 2
        )
        let converter = CoordinateConverter(primaryScreenHeight: 1117, displays: [builtin, secondary])

        XCTAssertEqual(
            converter.canonicalFrame(of: secondary),
            CanonicalRect(x: 0, y: -900, width: 1728, height: 900)
        )
        // Top-left of the display above sits above the primary origin (negative Y).
        XCTAssertEqual(
            converter.canonical(fromCocoa: CGPoint(x: 0, y: 2017)),
            CanonicalPoint(x: 0, y: -900)
        )
    }

    // MARK: (d) round-trips

    func testPointRoundTrip() {
        let converter = singleDisplayConverter()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 864, y: 1117), CGPoint(x: 1728, y: 558.5)]
        for point in points {
            let back = converter.cocoa(fromCanonical: converter.canonical(fromCocoa: point))
            XCTAssertEqual(back, point)
        }
    }

    func testRectRoundTrip() {
        let secondary = DisplayDescriptor(
            id: 2,
            cocoaFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            scale: 1
        )
        let converter = CoordinateConverter(primaryScreenHeight: 1117, displays: [builtin, secondary])
        let rects = [
            CGRect(x: 100, y: 200, width: 300, height: 400),
            CGRect(x: -1500, y: 50, width: 200, height: 900)
        ]
        for rect in rects {
            let back = converter.cocoa(fromCanonical: converter.canonical(fromCocoa: rect))
            XCTAssertEqual(back, rect)
        }
    }

    // MARK: (e) rect conversion preserves size

    func testRectConversionPreservesSize() {
        let converter = singleDisplayConverter()
        let cocoa = CGRect(x: 42, y: 84, width: 321, height: 654)
        let canonical = converter.canonical(fromCocoa: cocoa)
        XCTAssertEqual(canonical.width, cocoa.width)
        XCTAssertEqual(canonical.height, cocoa.height)

        let roundTrip = converter.cocoa(fromCanonical: canonical)
        XCTAssertEqual(roundTrip.width, cocoa.width)
        XCTAssertEqual(roundTrip.height, cocoa.height)
    }

    // MARK: (f) display-local mapping at display corners

    func testDisplayLocalAtCorners() {
        let secondary = DisplayDescriptor(
            id: 2,
            cocoaFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            scale: 1
        )
        let converter = CoordinateConverter(primaryScreenHeight: 1117, displays: [builtin, secondary])

        for display in [builtin, secondary] {
            let frame = converter.canonicalFrame(of: display)
            let topLeft = frame.origin
            let topRight = CanonicalPoint(x: frame.maxX, y: frame.minY)
            let bottomLeft = CanonicalPoint(x: frame.minX, y: frame.maxY)
            let bottomRight = CanonicalPoint(x: frame.maxX, y: frame.maxY)

            XCTAssertEqual(converter.displayLocal(topLeft, on: display), CanonicalPoint(x: 0, y: 0))
            XCTAssertEqual(converter.displayLocal(topRight, on: display), CanonicalPoint(x: frame.width, y: 0))
            XCTAssertEqual(converter.displayLocal(bottomLeft, on: display), CanonicalPoint(x: 0, y: frame.height))
            XCTAssertEqual(converter.displayLocal(bottomRight, on: display), CanonicalPoint(x: frame.width, y: frame.height))
        }
    }
}
