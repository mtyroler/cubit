import XCTest
@testable import Cubit

@MainActor
final class MeasurementSessionTests: XCTestCase {
    private func makeSession() -> MeasurementSession {
        MeasurementSession(screenReference: CanonicalRect(x: 0, y: 0, width: 1000, height: 1000), scale: 2)
    }

    private func commitRect(_ session: MeasurementSession, from anchor: CanonicalPoint, to current: CanonicalPoint) {
        session.tool = .rectangle
        session.beginDraft(at: anchor, constrain: false, fromCenter: false)
        session.updateDraft(to: current, constrain: false, fromCenter: false)
        session.commitDraft()
    }

    func testCommitDraftAssignsSequentialColorIndices() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        commitRect(session, from: CanonicalPoint(x: 100, y: 100), to: CanonicalPoint(x: 150, y: 150))

        XCTAssertEqual(session.measurements.map(\.colorIndex), [0, 1])
    }

    func testColorIndexReusesFreedIndexAfterDelete() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        commitRect(session, from: CanonicalPoint(x: 100, y: 100), to: CanonicalPoint(x: 150, y: 150))

        session.select(session.measurements[0].id)
        session.deleteSelected()

        commitRect(session, from: CanonicalPoint(x: 200, y: 200), to: CanonicalPoint(x: 250, y: 250))
        XCTAssertEqual(session.measurements.map(\.colorIndex), [1, 0])
    }

    func testNewMeasurementIsSelectedAfterCommit() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        XCTAssertEqual(session.selectedID, session.measurements.first?.id)
    }

    func testUndoRestoresMeasurementsAfterCommit() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        XCTAssertEqual(session.measurements.count, 1)

        session.undo()
        XCTAssertTrue(session.measurements.isEmpty)
    }

    func testUndoRestoresMeasurementAfterDelete() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        let id = session.measurements[0].id

        session.select(id)
        session.deleteSelected()
        XCTAssertTrue(session.measurements.isEmpty)

        session.undo()
        XCTAssertEqual(session.measurements.map(\.id), [id])
    }

    func testDeleteSelectedClearsSelection() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        session.deleteSelected()
        XCTAssertNil(session.selectedID)
    }

    func testNudgeSelectedMovesRectAndUndoRestoresPosition() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        let original = session.measurements[0].rect

        session.nudgeSelected(dx: 5, dy: -5)
        XCTAssertEqual(session.measurements[0].rect, CanonicalRect(x: 5, y: -5, width: 50, height: 50))

        session.undo()
        XCTAssertEqual(session.measurements[0].rect, original)
    }

    func testSetLabelUpdatesMeasurementAndSupportsUndo() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        let id = session.measurements[0].id

        session.setLabel("cart", for: id)
        XCTAssertEqual(session.measurements[0].label, "cart")

        session.undo()
        XCTAssertEqual(session.measurements[0].label, "")
    }

    func testCommitDraftReclassifiesThinTallRectangleAsVerticalLine() {
        // A fast/imprecise rectangle-tool drag that's thin and long is unambiguously
        // a line gesture; committing it as a 0%-area rectangle is a footgun.
        let session = MeasurementSession(screenReference: CanonicalRect(x: 0, y: 0, width: 1440, height: 870), scale: 2)
        session.tool = .rectangle
        session.beginDraft(at: CanonicalPoint(x: 100, y: 50), constrain: false, fromCenter: false)
        session.updateDraft(to: CanonicalPoint(x: 102, y: 670), constrain: false, fromCenter: false)
        let committed = session.commitDraft()

        XCTAssertEqual(committed?.kind, .vertical)
        XCTAssertEqual(committed?.rect, CanonicalRect(x: 100, y: 50, width: 0, height: 620))

        let text = MeasurementLabel.text(for: committed!, reference: session.reference, scale: session.referenceScale)
        XCTAssertEqual(text, "71.3%")
    }

    func testCommitDraftReclassifiesThinWideRectangleAsHorizontalLine() {
        let session = MeasurementSession(screenReference: CanonicalRect(x: 0, y: 0, width: 1440, height: 870), scale: 2)
        session.tool = .rectangle
        session.beginDraft(at: CanonicalPoint(x: 50, y: 100), constrain: false, fromCenter: false)
        session.updateDraft(to: CanonicalPoint(x: 950, y: 102), constrain: false, fromCenter: false)
        let committed = session.commitDraft()

        XCTAssertEqual(committed?.kind, .horizontal)
        XCTAssertEqual(committed?.rect, CanonicalRect(x: 50, y: 100, width: 900, height: 0))
    }

    func testCommitDraftKeepsOrdinaryRectangleAsRectangle() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 100, y: 80))
        XCTAssertEqual(session.measurements[0].kind, .rectangle)
    }
}
