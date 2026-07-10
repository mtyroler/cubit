import XCTest
@testable import Cubit

final class MeasurementAccessibilityDescriptionTests: XCTestCase {
    private let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 1000)

    private func rectangle(width: CGFloat, height: CGFloat, label: String = "", colorIndex: Int = 0) -> Cubit.Measurement {
        Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: width, height: height), label: label, colorIndex: colorIndex)
    }

    // MARK: label — identity, stable while dragging

    func testLabelNamesKindAndColor() {
        XCTAssertEqual(MeasurementAccessibilityDescription.label(for: rectangle(width: 10, height: 10, colorIndex: 0)), "Rectangle, orange")
    }

    func testLabelIncludesUserLabelWhenPresent() {
        let measurement = rectangle(width: 10, height: 10, label: "hero", colorIndex: 1)
        XCTAssertEqual(MeasurementAccessibilityDescription.label(for: measurement), "Rectangle, sky blue, hero")
    }

    func testLabelNamesLineKinds() {
        let horizontal = Cubit.Measurement(kind: .horizontal, rect: CanonicalRect(x: 0, y: 0, width: 100, height: 0), colorIndex: 4)
        let vertical = Cubit.Measurement(kind: .vertical, rect: CanonicalRect(x: 0, y: 0, width: 0, height: 100), colorIndex: 4)
        XCTAssertEqual(MeasurementAccessibilityDescription.label(for: horizontal), "Horizontal line, blue")
        XCTAssertEqual(MeasurementAccessibilityDescription.label(for: vertical), "Vertical line, blue")
    }

    /// The label must not carry the measurement's size — VoiceOver re-reads the value on change
    /// and the label on focus, so size in the label means the name changes while you drag.
    func testLabelIsIndependentOfSize() {
        let small = rectangle(width: 10, height: 10, label: "hero")
        let large = rectangle(width: 900, height: 900, label: "hero")
        XCTAssertEqual(
            MeasurementAccessibilityDescription.label(for: small),
            MeasurementAccessibilityDescription.label(for: large)
        )
    }

    // MARK: value — what it currently measures

    func testRectangleValueReportsAreaPercentAndSize() {
        let value = MeasurementAccessibilityDescription.value(
            for: rectangle(width: 500, height: 200),
            reference: reference,
            referenceMode: .windowUnderCursor,
            scale: 2
        )
        XCTAssertEqual(value, "10.0 percent of window area, 500 points by 200 points")
    }

    func testHorizontalValueReportsWidthPercent() {
        let line = Cubit.Measurement(kind: .horizontal, rect: CanonicalRect(x: 0, y: 0, width: 250, height: 0), colorIndex: 0)
        let value = MeasurementAccessibilityDescription.value(for: line, reference: reference, referenceMode: .screen, scale: 2)
        XCTAssertEqual(value, "25.0 percent of screen width, 250 points")
    }

    func testVerticalValueReportsHeightPercent() {
        let line = Cubit.Measurement(kind: .vertical, rect: CanonicalRect(x: 0, y: 0, width: 0, height: 100), colorIndex: 0)
        let value = MeasurementAccessibilityDescription.value(for: line, reference: reference, referenceMode: .custom, scale: 2)
        XCTAssertEqual(value, "10.0 percent of custom frame height, 100 points")
    }

    /// "1 points" is the kind of thing that makes an app sound like a robot.
    func testSingularPointIsNotPluralized() {
        let line = Cubit.Measurement(kind: .horizontal, rect: CanonicalRect(x: 0, y: 0, width: 1, height: 0), colorIndex: 0)
        let value = MeasurementAccessibilityDescription.value(for: line, reference: reference, referenceMode: .screen, scale: 2)
        XCTAssertTrue(value.hasSuffix("1 point"), value)
        XCTAssertFalse(value.hasSuffix("1 points"), value)
    }

    /// "%" is spoken as "percent sign" by some voices; the value spells the word.
    func testValueSpellsPercentRatherThanUsingTheSymbol() {
        let value = MeasurementAccessibilityDescription.value(for: rectangle(width: 100, height: 100), reference: reference, referenceMode: .screen, scale: 2)
        XCTAssertFalse(value.contains("%"))
        XCTAssertTrue(value.contains("percent"))
    }

    // MARK: announcement

    func testAddedAnnouncementCombinesLabelAndValue() {
        let measurement = rectangle(width: 500, height: 200, label: "hero", colorIndex: 0)
        let announcement = MeasurementAccessibilityDescription.addedAnnouncement(
            for: measurement,
            reference: reference,
            referenceMode: .windowUnderCursor,
            scale: 2
        )
        XCTAssertEqual(announcement, "Added Rectangle, orange, hero. 10.0 percent of window area, 500 points by 200 points")
    }

    func testReferenceNounMatchesEachMode() {
        XCTAssertEqual(MeasurementAccessibilityDescription.referenceNoun(.windowUnderCursor), "window")
        XCTAssertEqual(MeasurementAccessibilityDescription.referenceNoun(.screen), "screen")
        XCTAssertEqual(MeasurementAccessibilityDescription.referenceNoun(.custom), "custom frame")
    }
}
