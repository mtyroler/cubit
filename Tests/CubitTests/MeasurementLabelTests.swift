import XCTest
@testable import Cubit

@MainActor
final class MeasurementLabelTests: XCTestCase {
    // Exercises the *actual* draft → commit pipeline (not a hand-built Measurement)
    // to rule out draftRect/commitDraft silently zeroing the wrong dimension.
    func testVerticalDragThroughSessionProducesCorrectLiveLabel() {
        let session = MeasurementSession(
            screenReference: CanonicalRect(x: 0, y: 0, width: 1440, height: 870),
            scale: 2
        )
        session.tool = .vertical
        session.beginDraft(at: CanonicalPoint(x: 100, y: 50), constrain: false, fromCenter: false)
        session.updateDraft(to: CanonicalPoint(x: 100, y: 670), constrain: false, fromCenter: false)
        let committed = session.commitDraft()

        XCTAssertNotNil(committed)
        XCTAssertEqual(committed?.rect, CanonicalRect(x: 100, y: 50, width: 0, height: 620))

        let text = MeasurementLabel.text(for: committed!, reference: session.reference, scale: session.referenceScale)
        XCTAssertEqual(text, "71.3%")
        XCTAssertNotEqual(text, "0.0%")
    }

    func testVerticalLineLabelUsesHeightPercentNotArea() {
        // Reproduces the reported bug: a vertical line spanning ~620pt of an
        // 870pt-tall "Ghostty" window reference showed "0.0%" — a degenerate
        // rect (width 0) has areaPercent == 0, so the pill must read
        // primaryPercent (heightPercent for vertical), not areaPercent.
        let reference = CanonicalRect(x: 0, y: 0, width: 1440, height: 870)
        let line = CanonicalRect(x: 100, y: 50, width: 0, height: 620)
        let measurement = Measurement(kind: .vertical, rect: line)

        let text = MeasurementLabel.text(for: measurement, reference: reference, scale: 2)

        XCTAssertEqual(text, "71.3%")
        XCTAssertNotEqual(text, "0.0%")
    }

    func testHorizontalLineLabelUsesWidthPercentNotArea() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1440, height: 870)
        let line = CanonicalRect(x: 50, y: 100, width: 900, height: 0)
        let measurement = Measurement(kind: .horizontal, rect: line)

        let text = MeasurementLabel.text(for: measurement, reference: reference, scale: 2)

        XCTAssertEqual(text, "62.5%")
        XCTAssertNotEqual(text, "0.0%")
    }

    func testRectangleLabelUsesAreaPercent() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = CanonicalRect(x: 0, y: 0, width: 100, height: 50)
        let measurement = Measurement(kind: .rectangle, rect: rect)

        let text = MeasurementLabel.text(for: measurement, reference: reference, scale: 2)

        XCTAssertEqual(text, "1.0%")
    }

    func testAppendsUserLabelWhenPresent() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1440, height: 870)
        let line = CanonicalRect(x: 100, y: 50, width: 0, height: 620)
        let measurement = Measurement(kind: .vertical, rect: line, label: "sidebar")

        let text = MeasurementLabel.text(for: measurement, reference: reference, scale: 2)

        XCTAssertEqual(text, "71.3% · sidebar")
    }
}
