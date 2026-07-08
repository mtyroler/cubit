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

    // MARK: Color cycling — X / Shift+X / 1–8

    func testCycleColorOnSelectedWrapsAtEight() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))

        for expected in 1...7 {
            session.cycleColor(forward: true)
            XCTAssertEqual(session.measurements[0].colorIndex, expected)
        }
        session.cycleColor(forward: true)
        XCTAssertEqual(session.measurements[0].colorIndex, 0, "cycling forward past the last color wraps to the first")
    }

    func testShiftCyclesColorBackward() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))

        session.cycleColor(forward: false)
        XCTAssertEqual(session.measurements[0].colorIndex, 7, "cycling backward from the first color wraps to the last")
        session.cycleColor(forward: false)
        XCTAssertEqual(session.measurements[0].colorIndex, 6)
    }

    func testDigitsMapOneToIndexZeroThroughEightToIndexSevenOnSelected() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))

        for digit in 1...8 {
            session.setColor(index: digit - 1)
            XCTAssertEqual(session.measurements[0].colorIndex, digit - 1)
        }
    }

    func testDigitsMapOnDraftToo() {
        let session = makeSession()
        session.tool = .rectangle
        session.beginDraft(at: CanonicalPoint(x: 0, y: 0), constrain: false, fromCenter: false)

        for digit in 1...8 {
            session.setColor(index: digit - 1)
            XCTAssertEqual(session.draft?.colorIndex, digit - 1)
        }
    }

    func testSetColorIgnoresOutOfRangeIndex() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        session.setColor(index: 99)
        XCTAssertEqual(session.measurements[0].colorIndex, 0)
        session.setColor(index: -1)
        XCTAssertEqual(session.measurements[0].colorIndex, 0)
    }

    func testDraftAdoptsNextFreeColorAtBeginAndPreservesCyclingThroughCommit() {
        let session = makeSession()
        session.tool = .rectangle
        session.beginDraft(at: CanonicalPoint(x: 0, y: 0), constrain: false, fromCenter: false)
        XCTAssertEqual(session.draft?.colorIndex, 0, "draft previews the next-free color as soon as it begins")

        session.cycleColor(forward: true)
        session.cycleColor(forward: true)
        XCTAssertEqual(session.draft?.colorIndex, 2)

        session.updateDraft(to: CanonicalPoint(x: 50, y: 50), constrain: false, fromCenter: false)
        let committed = session.commitDraft()

        XCTAssertEqual(committed?.colorIndex, 2, "commit keeps whatever color the user cycled to")
        XCTAssertEqual(session.measurements[0].colorIndex, 2)
    }

    func testCycleColorTargetsActiveDraftOverAnExistingSelection() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        XCTAssertEqual(session.selectedID, session.measurements[0].id, "commit selects the new measurement")

        session.tool = .rectangle
        session.beginDraft(at: CanonicalPoint(x: 100, y: 100), constrain: false, fromCenter: false)
        session.cycleColor(forward: true)

        // The draft is the active target while drafting, even though a prior measurement
        // remains selected underneath — the draft's color changes, not the selection's.
        XCTAssertEqual(session.draft?.colorIndex, 2)
        XCTAssertEqual(session.measurements[0].colorIndex, 0, "the still-selected measurement is untouched")
    }

    func testCurrentColorIndexPrefersDraftOverSelectionOverNil() {
        let session = makeSession()
        XCTAssertNil(session.currentColorIndex, "nothing to color when there's no draft or selection")

        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        XCTAssertEqual(session.currentColorIndex, 0)

        session.tool = .rectangle
        session.beginDraft(at: CanonicalPoint(x: 100, y: 100), constrain: false, fromCenter: false)
        XCTAssertEqual(session.currentColorIndex, session.draft?.colorIndex)
    }

    func testCycleColorIsNoOpWithNoDraftOrSelection() {
        let session = makeSession()
        session.cycleColor(forward: true)
        session.setColor(index: 3)
        XCTAssertNil(session.currentColorIndex)
    }

    func testUndoRestoresColorAfterCycle() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))

        session.cycleColor(forward: true)
        XCTAssertEqual(session.measurements[0].colorIndex, 1)

        session.undo()
        XCTAssertEqual(session.measurements[0].colorIndex, 0)
    }

    func testRapidColorCyclingOnSameMeasurementCoalescesIntoOneUndoStep() {
        // Cycling several times in immediate succession (holding X, or the pill swatch
        // double-clicked) collapses into the single undo step that preceded the streak,
        // rather than one step per keystroke.
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))

        session.cycleColor(forward: true)
        session.cycleColor(forward: true)
        session.cycleColor(forward: true)
        XCTAssertEqual(session.measurements[0].colorIndex, 3)

        session.undo()
        XCTAssertEqual(session.measurements[0].colorIndex, 0, "one undo unwinds the whole rapid streak")
    }

    func testColorEditsOnDifferentMeasurementsDoNotCoalesce() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        commitRect(session, from: CanonicalPoint(x: 100, y: 100), to: CanonicalPoint(x: 150, y: 150))
        let firstID = session.measurements[0].id
        let secondID = session.measurements[1].id

        session.select(firstID)
        session.cycleColor(forward: true)
        session.select(secondID)
        session.cycleColor(forward: true)

        session.undo()
        XCTAssertEqual(session.measurements.first(where: { $0.id == secondID })?.colorIndex, 1, "second edit reverted")
        XCTAssertEqual(session.measurements.first(where: { $0.id == firstID })?.colorIndex, 1, "first edit untouched by that undo")

        session.undo()
        XCTAssertEqual(session.measurements.first(where: { $0.id == firstID })?.colorIndex, 0, "first edit now reverted too")
    }

    func testNextFreeColorSkipsUserOverriddenColorOnceVacated() {
        let session = makeSession()
        commitRect(session, from: CanonicalPoint(x: 0, y: 0), to: CanonicalPoint(x: 50, y: 50))
        XCTAssertEqual(session.measurements[0].colorIndex, 0)

        session.setColor(index: 5)
        XCTAssertEqual(session.measurements[0].colorIndex, 5, "user override moves it off the auto-assigned color")

        // Index 0 is free again (nothing currently uses it), so the next commit gets it —
        // auto-assignment always reflects the *current* set of used colors, not history.
        commitRect(session, from: CanonicalPoint(x: 100, y: 100), to: CanonicalPoint(x: 150, y: 150))
        XCTAssertEqual(session.measurements[1].colorIndex, 0)

        // And a third one skips both 0 and 5, which are now both in use.
        commitRect(session, from: CanonicalPoint(x: 200, y: 200), to: CanonicalPoint(x: 250, y: 250))
        XCTAssertEqual(session.measurements[2].colorIndex, 1)
    }
}
