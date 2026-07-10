import XCTest
@testable import Cubit

final class PaletteTests: XCTestCase {
    func testFirstEightColorsAreUnique() {
        let colors = (0..<8).map(Palette.color(forIndex:))
        let unique = Set(colors.map { "\($0.red),\($0.green),\($0.blue)" })
        XCTAssertEqual(unique.count, 8)
    }

    func testCyclesPastEight() {
        for index in 0..<8 {
            XCTAssertEqual(Palette.color(forIndex: index), Palette.color(forIndex: index + 8))
            XCTAssertEqual(Palette.color(forIndex: index), Palette.color(forIndex: index + 16))
        }
    }

    func testMappingIsStableForSameIndex() {
        XCTAssertEqual(Palette.color(forIndex: 3), Palette.color(forIndex: 3))
    }

    func testAllComponentsAreValidUnitRange() {
        for index in 0..<8 {
            let color = Palette.color(forIndex: index)
            XCTAssertGreaterThanOrEqual(color.red, 0)
            XCTAssertLessThanOrEqual(color.red, 1)
            XCTAssertGreaterThanOrEqual(color.green, 0)
            XCTAssertLessThanOrEqual(color.green, 1)
            XCTAssertGreaterThanOrEqual(color.blue, 0)
            XCTAssertLessThanOrEqual(color.blue, 1)
        }
    }

    // MARK: names

    func testColorNamesParallelColorsAndCycle() {
        XCTAssertEqual(Palette.colorNames.count, Palette.colors.count)
        XCTAssertEqual(Palette.name(forIndex: 0), "orange")
        XCTAssertEqual(Palette.name(forIndex: 1), "sky blue")
        XCTAssertEqual(Palette.name(forIndex: 7), "gray")
        // Wraps like the color lookup, including negatives.
        XCTAssertEqual(Palette.name(forIndex: 8), "orange")
        XCTAssertEqual(Palette.name(forIndex: -1), "gray")
    }

    // MARK: ink

    /// The guarantee the overlay and the exporter both rely on: whatever swatch a measurement
    /// lands on, its label is readable. White-on-yellow — the old unconditional choice — was
    /// 1.3:1, well under the 3:1 floor for even large text.
    func testEveryPaletteColorClearsAAContrastWithItsInk() {
        for index in 0..<8 {
            let color = Palette.color(forIndex: index)
            XCTAssertGreaterThanOrEqual(
                color.inkContrastRatio, 4.5,
                "\(Palette.name(forIndex: index)) label fails WCAG AA for normal text"
            )
        }
    }

    func testInkPicksWhicheverToneContrastsMore() {
        // Light swatches take the dark ink...
        for name in ["orange", "sky blue", "yellow", "gray"] {
            let index = Palette.colorNames.firstIndex(of: name)!
            XCTAssertEqual(Palette.color(forIndex: index).ink, .darkInk, "\(name) should take dark ink")
        }
        // ...and the one genuinely dark swatch keeps white.
        let blue = Palette.colorNames.firstIndex(of: "blue")!
        XCTAssertEqual(Palette.color(forIndex: blue).ink, .lightInk, "blue should keep white ink")
    }

    func testRelativeLuminanceMatchesWCAGReferenceValues() {
        // Black, white, and mid gray against the published sRGB curve.
        XCTAssertEqual(PaletteColor(white: 0).relativeLuminance, 0, accuracy: 0.0001)
        XCTAssertEqual(PaletteColor(white: 1).relativeLuminance, 1, accuracy: 0.0001)
        XCTAssertEqual(PaletteColor(white: 0.5).relativeLuminance, 0.2140, accuracy: 0.0005)
    }

    func testContrastRatioIsSymmetricAndBounded() {
        let black = PaletteColor(white: 0)
        let white = PaletteColor(white: 1)
        XCTAssertEqual(black.contrastRatio(against: white), 21, accuracy: 0.0001)
        XCTAssertEqual(white.contrastRatio(against: black), 21, accuracy: 0.0001)
        XCTAssertEqual(white.contrastRatio(against: white), 1, accuracy: 0.0001)
    }

    // MARK: cycledIndex

    func testCycledIndexForwardWrapsAtEight() {
        XCTAssertEqual(Palette.cycledIndex(0, forward: true), 1)
        XCTAssertEqual(Palette.cycledIndex(6, forward: true), 7)
        XCTAssertEqual(Palette.cycledIndex(7, forward: true), 0)
    }

    func testCycledIndexBackwardWrapsAtZero() {
        XCTAssertEqual(Palette.cycledIndex(7, forward: false), 6)
        XCTAssertEqual(Palette.cycledIndex(1, forward: false), 0)
        XCTAssertEqual(Palette.cycledIndex(0, forward: false), 7)
    }

    func testCycledIndexForwardThenBackwardReturnsToStart() {
        for start in 0..<8 {
            XCTAssertEqual(Palette.cycledIndex(Palette.cycledIndex(start, forward: true), forward: false), start)
        }
    }
}
