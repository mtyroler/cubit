import XCTest
@testable import Cubit

final class CursorStyleCatalogTests: XCTestCase {
    func testToolMapsToMatchingCursorStyle() {
        XCTAssertEqual(CursorStyleCatalog.style(forTool: .rectangle), .rectangle)
        XCTAssertEqual(CursorStyleCatalog.style(forTool: .horizontal), .horizontal)
        XCTAssertEqual(CursorStyleCatalog.style(forTool: .vertical), .vertical)
    }

    func testBadgeSymbolNamesAreDistinctAndNonEmpty() {
        let names = CursorStyle.allCases.map(CursorStyleCatalog.badgeSymbolName(for:))
        XCTAssertEqual(Set(names).count, names.count, "each cursor style should get a distinct badge glyph")
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testFlashLabelsAreDistinctAndNonEmpty() {
        let labels = CursorStyle.allCases.map(CursorStyleCatalog.flashLabel(for:))
        XCTAssertEqual(Set(labels).count, labels.count, "each cursor style should get a distinct flash label")
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })
    }

    func testSpecificBadgeSymbolNames() {
        XCTAssertEqual(CursorStyleCatalog.badgeSymbolName(for: .rectangle), "rectangle")
        XCTAssertEqual(CursorStyleCatalog.badgeSymbolName(for: .horizontal), "arrow.left.and.right")
        XCTAssertEqual(CursorStyleCatalog.badgeSymbolName(for: .vertical), "arrow.up.and.down")
        XCTAssertEqual(CursorStyleCatalog.badgeSymbolName(for: .customFrame), "rectangle.dashed")
    }

    func testSpecificFlashLabels() {
        XCTAssertEqual(CursorStyleCatalog.flashLabel(for: .rectangle), "Rectangle")
        XCTAssertEqual(CursorStyleCatalog.flashLabel(for: .horizontal), "Horizontal line")
        XCTAssertEqual(CursorStyleCatalog.flashLabel(for: .vertical), "Vertical line")
        XCTAssertEqual(CursorStyleCatalog.flashLabel(for: .customFrame), "Custom frame")
    }
}
