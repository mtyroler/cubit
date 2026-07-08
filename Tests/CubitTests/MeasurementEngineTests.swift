import XCTest
@testable import Cubit

final class MeasurementEngineTests: XCTestCase {
    private let accuracy = 1e-9

    // MARK: metrics — lines

    func testHorizontalLineMetrics() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let line = CanonicalRect(x: 100, y: 200, width: 200, height: 0)
        let metrics = MeasurementEngine.metrics(kind: .horizontal, rect: line, reference: reference, scale: 2)

        XCTAssertEqual(metrics.lengthPx, 400)
        XCTAssertEqual(metrics.widthPx, 400)
        XCTAssertEqual(metrics.widthPercent, 20.0, accuracy: accuracy)
        XCTAssertEqual(metrics.primaryPercent, 20.0, accuracy: accuracy)
        XCTAssertEqual(metrics.areaPx, 0)
    }

    func testVerticalLineMetrics() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 600)
        let line = CanonicalRect(x: 100, y: 50, width: 0, height: 300)
        let metrics = MeasurementEngine.metrics(kind: .vertical, rect: line, reference: reference, scale: 2)

        XCTAssertEqual(metrics.lengthPx, 600)
        XCTAssertEqual(metrics.heightPx, 600)
        XCTAssertEqual(metrics.heightPercent, 50.0, accuracy: accuracy)
        XCTAssertEqual(metrics.primaryPercent, 50.0, accuracy: accuracy)
        XCTAssertEqual(metrics.areaPx, 0)
    }

    // MARK: metrics — rectangle

    func testRectanglePercentages() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = CanonicalRect(x: 10, y: 10, width: 100, height: 50)
        let metrics = MeasurementEngine.metrics(kind: .rectangle, rect: rect, reference: reference, scale: 1)

        XCTAssertEqual(metrics.areaPercent, 1.0, accuracy: accuracy)
        XCTAssertEqual(metrics.widthPercent, 10.0, accuracy: accuracy)
        XCTAssertEqual(metrics.heightPercent, 10.0, accuracy: accuracy)
        XCTAssertEqual(metrics.primaryPercent, 1.0, accuracy: accuracy)
        XCTAssertEqual(metrics.areaPx, 5000)
    }

    func testRectanglePixelsScaleWithBackingFactor() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = CanonicalRect(x: 0, y: 0, width: 100, height: 50)
        let metrics = MeasurementEngine.metrics(kind: .rectangle, rect: rect, reference: reference, scale: 2)

        XCTAssertEqual(metrics.widthPx, 200)
        XCTAssertEqual(metrics.heightPx, 100)
        XCTAssertEqual(metrics.areaPx, 20000)
    }

    func testMetricsForMeasurementMatchesKindRectOverload() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = CanonicalRect(x: 5, y: 5, width: 250, height: 125)
        let measurement = Measurement(kind: .rectangle, rect: rect)

        let a = MeasurementEngine.metrics(for: measurement, reference: reference, scale: 2)
        let b = MeasurementEngine.metrics(kind: .rectangle, rect: rect, reference: reference, scale: 2)
        XCTAssertEqual(a, b)
    }

    // MARK: metrics — guards

    func testZeroReferenceDimensionsProduceZeroPercent() {
        let reference = CanonicalRect(x: 0, y: 0, width: 0, height: 0)
        let rect = CanonicalRect(x: 0, y: 0, width: 100, height: 50)
        let metrics = MeasurementEngine.metrics(kind: .rectangle, rect: rect, reference: reference, scale: 1)

        XCTAssertEqual(metrics.widthPercent, 0)
        XCTAssertEqual(metrics.heightPercent, 0)
        XCTAssertEqual(metrics.areaPercent, 0)
        XCTAssertFalse(metrics.areaPercent.isNaN)
    }

    // MARK: draftRect — rectangle

    func testDraftRectangleForwardDrag() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 100, y: 100),
            current: CanonicalPoint(x: 300, y: 250),
            kind: .rectangle,
            constrain: false,
            fromCenter: false
        )
        XCTAssertEqual(rect, CanonicalRect(x: 100, y: 100, width: 200, height: 150))
    }

    func testDraftRectangleNegativeDragNormalizes() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 300, y: 250),
            current: CanonicalPoint(x: 100, y: 100),
            kind: .rectangle,
            constrain: false,
            fromCenter: false
        )
        XCTAssertEqual(rect, CanonicalRect(x: 100, y: 100, width: 200, height: 150))
    }

    func testDraftRectangleSquareConstrainLargerAxisWins() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 0, y: 0),
            current: CanonicalPoint(x: 100, y: 40),
            kind: .rectangle,
            constrain: true,
            fromCenter: false
        )
        XCTAssertEqual(rect, CanonicalRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testDraftRectangleSquareConstrainPreservesSigns() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 200, y: 200),
            current: CanonicalPoint(x: 100, y: 160),
            kind: .rectangle,
            constrain: true,
            fromCenter: false
        )
        // larger axis = |dx| = 100, both extents 100, dragging up-left → origin (100,100)
        XCTAssertEqual(rect, CanonicalRect(x: 100, y: 100, width: 100, height: 100))
    }

    func testDraftRectangleFromCenterDoubles() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 500, y: 500),
            current: CanonicalPoint(x: 600, y: 550),
            kind: .rectangle,
            constrain: false,
            fromCenter: true
        )
        XCTAssertEqual(rect, CanonicalRect(x: 400, y: 450, width: 200, height: 100))
    }

    func testDraftRectangleFromCenterConstrainDoublesSquare() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 500, y: 500),
            current: CanonicalPoint(x: 600, y: 540),
            kind: .rectangle,
            constrain: true,
            fromCenter: true
        )
        // side = max(100, 40) = 100 → half extents 100 → 200x200 centered on anchor
        XCTAssertEqual(rect, CanonicalRect(x: 400, y: 400, width: 200, height: 200))
    }

    // MARK: draftRect — lines

    func testDraftHorizontalIgnoresVerticalDrag() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 100, y: 200),
            current: CanonicalPoint(x: 400, y: 900),
            kind: .horizontal,
            constrain: false,
            fromCenter: false
        )
        XCTAssertEqual(rect, CanonicalRect(x: 100, y: 200, width: 300, height: 0))
    }

    func testDraftVerticalIgnoresHorizontalDrag() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 100, y: 200),
            current: CanonicalPoint(x: 900, y: 500),
            kind: .vertical,
            constrain: false,
            fromCenter: false
        )
        XCTAssertEqual(rect, CanonicalRect(x: 100, y: 200, width: 0, height: 300))
    }

    func testDraftHorizontalUnaffectedByConstrain() {
        let plain = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 100, y: 200),
            current: CanonicalPoint(x: 400, y: 900),
            kind: .horizontal,
            constrain: true,
            fromCenter: false
        )
        XCTAssertEqual(plain, CanonicalRect(x: 100, y: 200, width: 300, height: 0))
    }

    func testDraftHorizontalFromCenterDoublesLength() {
        let rect = MeasurementEngine.draftRect(
            anchor: CanonicalPoint(x: 500, y: 300),
            current: CanonicalPoint(x: 650, y: 999),
            kind: .horizontal,
            constrain: false,
            fromCenter: true
        )
        XCTAssertEqual(rect, CanonicalRect(x: 350, y: 300, width: 300, height: 0))
    }

    // MARK: moved / resized

    func testMovedShiftsOriginPreservesSize() {
        let rect = CanonicalRect(x: 100, y: 100, width: 200, height: 150)
        let moved = MeasurementEngine.moved(rect, dx: 10, dy: -5)
        XCTAssertEqual(moved, CanonicalRect(x: 110, y: 95, width: 200, height: 150))
    }

    func testResizedMaxXGrowsWidth() {
        let rect = CanonicalRect(x: 100, y: 100, width: 200, height: 150)
        let resized = MeasurementEngine.resized(rect, edge: .maxX, by: 50)
        XCTAssertEqual(resized, CanonicalRect(x: 100, y: 100, width: 250, height: 150))
    }

    func testResizedMinXMovesOriginAndShrinksWidth() {
        let rect = CanonicalRect(x: 100, y: 100, width: 200, height: 150)
        let resized = MeasurementEngine.resized(rect, edge: .minX, by: 30)
        XCTAssertEqual(resized, CanonicalRect(x: 130, y: 100, width: 170, height: 150))
    }

    func testResizedEdgeCrossingOppositeNormalizes() {
        let rect = CanonicalRect(x: 100, y: 100, width: 200, height: 150)
        let resized = MeasurementEngine.resized(rect, edge: .maxX, by: -260)
        // maxX 300 - 260 = 40, now left of minX 100 → normalized origin 40, width 60
        XCTAssertEqual(resized, CanonicalRect(x: 40, y: 100, width: 60, height: 150))
    }

    // MARK: classifyForCommit — thin-rectangle-to-line reclassification
    //
    // Three explicit, non-overlapping regimes around a thin rectangle drag:
    //   1. below minDrag (handled separately in MeasurementSession.commitDraft) — discarded entirely.
    //   2. thin (min dimension < 4pt) AND long (max dimension >= 20pt) — reclassified as a line.
    //   3. everything else — committed as-is (stays a rectangle).

    func testThinTallRectangleConvertsToVertical() {
        let rect = CanonicalRect(x: 10, y: 20, width: 2, height: 100)
        let result = MeasurementEngine.classifyForCommit(kind: .rectangle, rect: rect)
        XCTAssertEqual(result.kind, .vertical)
        XCTAssertEqual(result.rect, CanonicalRect(x: 10, y: 20, width: 0, height: 100))
    }

    func testThinWideRectangleConvertsToHorizontal() {
        let rect = CanonicalRect(x: 10, y: 20, width: 100, height: 2)
        let result = MeasurementEngine.classifyForCommit(kind: .rectangle, rect: rect)
        XCTAssertEqual(result.kind, .horizontal)
        XCTAssertEqual(result.rect, CanonicalRect(x: 10, y: 20, width: 100, height: 0))
    }

    func testWidthExactlyAtThinThresholdStaysRectangle() {
        // width == 4 is NOT "< 4" — regime 3, stays a rectangle.
        let rect = CanonicalRect(x: 0, y: 0, width: 4, height: 100)
        let result = MeasurementEngine.classifyForCommit(kind: .rectangle, rect: rect)
        XCTAssertEqual(result.kind, .rectangle)
        XCTAssertEqual(result.rect, rect)
    }

    func testWidthJustBelowThinThresholdConverts() {
        let rect = CanonicalRect(x: 0, y: 0, width: 3.9, height: 100)
        let result = MeasurementEngine.classifyForCommit(kind: .rectangle, rect: rect)
        XCTAssertEqual(result.kind, .vertical)
        XCTAssertEqual(result.rect, CanonicalRect(x: 0, y: 0, width: 0, height: 100))
    }

    func testMaxDimensionBelowMinLineLengthStaysRectangle() {
        // Thin (width 2) but too short overall (max dimension 19 < 20) — regime 3.
        let rect = CanonicalRect(x: 0, y: 0, width: 2, height: 19)
        let result = MeasurementEngine.classifyForCommit(kind: .rectangle, rect: rect)
        XCTAssertEqual(result.kind, .rectangle)
        XCTAssertEqual(result.rect, rect)
    }

    func testMaxDimensionExactlyAtMinLineLengthConverts() {
        let rect = CanonicalRect(x: 0, y: 0, width: 2, height: 20)
        let result = MeasurementEngine.classifyForCommit(kind: .rectangle, rect: rect)
        XCTAssertEqual(result.kind, .vertical)
        XCTAssertEqual(result.rect, CanonicalRect(x: 0, y: 0, width: 0, height: 20))
    }

    func testOrdinaryRectangleUnaffected() {
        let rect = CanonicalRect(x: 0, y: 0, width: 200, height: 150)
        let result = MeasurementEngine.classifyForCommit(kind: .rectangle, rect: rect)
        XCTAssertEqual(result.kind, .rectangle)
        XCTAssertEqual(result.rect, rect)
    }

    func testNonRectangleKindsPassThroughUnchanged() {
        let line = CanonicalRect(x: 0, y: 0, width: 0, height: 500)
        XCTAssertEqual(MeasurementEngine.classifyForCommit(kind: .vertical, rect: line).kind, .vertical)
        XCTAssertEqual(MeasurementEngine.classifyForCommit(kind: .vertical, rect: line).rect, line)

        let hLine = CanonicalRect(x: 0, y: 0, width: 500, height: 0)
        XCTAssertEqual(MeasurementEngine.classifyForCommit(kind: .horizontal, rect: hLine).kind, .horizontal)
        XCTAssertEqual(MeasurementEngine.classifyForCommit(kind: .horizontal, rect: hLine).rect, hLine)
    }
}
