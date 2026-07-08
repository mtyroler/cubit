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
}
