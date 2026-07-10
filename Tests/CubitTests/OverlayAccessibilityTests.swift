import XCTest
import AppKit
@testable import Cubit

/// The overlay draws its shapes instead of building subviews, so its accessibility tree is
/// hand-published and nothing else would catch it regressing to a single opaque rectangle.
@MainActor
final class OverlayAccessibilityTests: XCTestCase {
    private var canvas: OverlayCanvasView!
    private var session: MeasurementSession!
    private var converter: CoordinateConverter!

    private let canvasSize = CGSize(width: 900, height: 600)

    override func setUp() async throws {
        try await super.setUp()
        let descriptor = DisplayDescriptor(id: 1, cocoaFrame: CGRect(origin: .zero, size: canvasSize), scale: 2)
        converter = CoordinateConverter(primaryScreenHeight: canvasSize.height, displays: [descriptor])
        session = MeasurementSession(screenReference: converter.canonicalFrame(of: descriptor), scale: 2, mode: .screen)

        canvas = OverlayCanvasView(frame: CGRect(origin: .zero, size: canvasSize))
        canvas.converter = converter
        canvas.display = descriptor
        canvas.session = session
    }

    override func tearDown() async throws {
        canvas = nil
        session = nil
        converter = nil
        try await super.tearDown()
    }

    @discardableResult
    private func addMeasurement(label: String = "", colorIndex: Int = 0) -> Cubit.Measurement {
        let measurement = Cubit.Measurement(
            kind: .rectangle,
            rect: CanonicalRect(x: 100, y: 80, width: 200, height: 150),
            label: label,
            colorIndex: colorIndex
        )
        session.measurements.append(measurement)
        canvas.refreshFromAccessibility()
        return measurement
    }

    private func elements() -> [MeasurementAccessibilityElement] {
        (canvas.accessibilityChildren() ?? []).compactMap { $0 as? MeasurementAccessibilityElement }
    }

    // MARK: the canvas

    func testCanvasIsALayoutAreaNotAnOpaqueRectangle() {
        XCTAssertEqual(canvas.accessibilityRole(), .layoutArea)
        XCTAssertTrue(canvas.isAccessibilityElement())
        XCTAssertEqual(canvas.accessibilityLabel(), "Measurement canvas")
    }

    func testCanvasExposesOneElementPerMeasurement() {
        XCTAssertEqual(elements().count, 0)
        addMeasurement()
        addMeasurement()
        XCTAssertEqual(elements().count, 2)
    }

    func testElementsAreReusedAcrossRedrawsSoFocusSurvives() {
        addMeasurement()
        let first = try! XCTUnwrap(elements().first)
        canvas.refreshFromAccessibility()
        canvas.refreshFromAccessibility()
        XCTAssertTrue(elements().first === first, "a redraw must not rebuild the focused element")
    }

    func testRemovingAMeasurementRemovesItsElement() {
        let measurement = addMeasurement()
        session.select(measurement.id)
        session.deleteSelected()
        canvas.refreshFromAccessibility()
        XCTAssertTrue(elements().isEmpty)
    }

    /// A draft in flight is the canvas's value, so drawing isn't silent.
    func testCanvasValueReportsTheDraftInProgress() {
        XCTAssertNil(canvas.accessibilityValue())

        session.tool = .rectangle
        session.beginDraft(at: CanonicalPoint(x: 0, y: 0), constrain: false, fromCenter: false)
        session.updateDraft(to: CanonicalPoint(x: 450, y: 300), constrain: false, fromCenter: false)

        let value = canvas.accessibilityValue() as? String
        XCTAssertNotNil(value)
        XCTAssertTrue(value!.contains("percent of screen area"), value ?? "nil")
    }

    // MARK: elements

    func testElementIsALayoutItemWithLabelAndValue() {
        addMeasurement(label: "hero", colorIndex: 3)
        let element = elements()[0]

        XCTAssertEqual(element.accessibilityRole(), .layoutItem)
        XCTAssertTrue(element.isAccessibilityElement())
        XCTAssertEqual(element.accessibilityLabel(), "Rectangle, Yellow, hero")
        // 200×150 of the 900×600 screen reference.
        XCTAssertEqual(element.accessibilityValue() as? String, "5.6 percent of screen area, 200 points by 150 points")
    }

    func testElementFrameIsInGlobalCocoaScreenCoordinates() {
        let measurement = addMeasurement()
        let element = elements()[0]
        XCTAssertEqual(element.accessibilityFrame(), converter.cocoa(fromCanonical: measurement.rect))
    }

    // MARK: selection

    func testPressingAnElementSelectsItsMeasurement() {
        let measurement = addMeasurement()
        let element = elements()[0]

        XCTAssertFalse(element.isAccessibilitySelected())
        XCTAssertTrue(element.accessibilityPerformPress())
        XCTAssertEqual(session.selectedID, measurement.id)
        XCTAssertTrue(element.isAccessibilitySelected())
    }

    func testCanvasReportsTheSelectedElementAsItsSelectedChild() {
        addMeasurement()
        addMeasurement()
        let second = elements()[1]
        second.setAccessibilitySelected(true)

        let selected = (canvas.accessibilitySelectedChildren() ?? []).compactMap { $0 as? MeasurementAccessibilityElement }
        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(selected[0] === second)
    }

    func testDeselectingAnElementClearsTheSessionSelection() {
        addMeasurement()
        let element = elements()[0]
        element.setAccessibilitySelected(true)
        element.setAccessibilitySelected(false)
        XCTAssertNil(session.selectedID)
    }

    // MARK: actions

    func testDeleteActionRemovesTheMeasurementAndIsUndoable() {
        addMeasurement()
        let element = elements()[0]

        XCTAssertTrue(element.accessibilityPerformDelete())
        XCTAssertTrue(session.measurements.isEmpty)

        session.undo()
        XCTAssertEqual(session.measurements.count, 1, "a VoiceOver delete is a first-class undoable edit")
    }

    /// VoiceOver repositions a layout item by writing its frame. That has to land as the same
    /// undoable move the mouse and arrow keys perform, and must preserve the shape's size.
    func testSettingAnElementFrameMovesTheMeasurementUndoably() {
        let original = addMeasurement()
        let element = elements()[0]

        let target = CanonicalRect(x: 300, y: 200, width: original.rect.width, height: original.rect.height)
        element.setAccessibilityFrame(converter.cocoa(fromCanonical: target))

        let moved = session.measurements[0]
        XCTAssertEqual(moved.rect.origin.x, 300, accuracy: 0.5)
        XCTAssertEqual(moved.rect.origin.y, 200, accuracy: 0.5)
        XCTAssertEqual(moved.rect.width, original.rect.width, accuracy: 0.001, "a move must not resize")
        XCTAssertEqual(moved.rect.height, original.rect.height, accuracy: 0.001)

        session.undo()
        XCTAssertEqual(session.measurements[0].rect.origin.x, original.rect.origin.x, accuracy: 0.001)
    }

    func testSettingAnElementFrameToItsCurrentPositionRegistersNoUndoStep() {
        let original = addMeasurement()
        let element = elements()[0]
        element.setAccessibilityFrame(converter.cocoa(fromCanonical: original.rect))
        XCTAssertFalse(session.canUndo, "a no-op reposition must not pollute the undo stack")
    }
}
