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
}
