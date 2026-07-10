import XCTest
import AppKit
@testable import Cubit

/// The contextual menu is the overlay's discovery surface: delete, duplicate, label, color and
/// undo are all reachable by key, and right-click is where a Mac user looks for them. These
/// tests drive the real `menu(for:)` with a real right-click event.
@MainActor
final class OverlayContextMenuTests: XCTestCase {
    private var window: NSWindow!
    private var canvas: OverlayCanvasView!
    private var session: MeasurementSession!

    private let canvasSize = CGSize(width: 900, height: 600)

    override func setUp() async throws {
        try await super.setUp()

        let descriptor = DisplayDescriptor(id: 1, cocoaFrame: CGRect(origin: .zero, size: canvasSize), scale: 2)
        let converter = CoordinateConverter(primaryScreenHeight: canvasSize.height, displays: [descriptor])
        session = MeasurementSession(screenReference: converter.canonicalFrame(of: descriptor), scale: 2, mode: .screen)

        canvas = OverlayCanvasView(frame: CGRect(origin: .zero, size: canvasSize))
        canvas.converter = converter
        canvas.display = descriptor
        canvas.session = session

        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: canvasSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
    }

    override func tearDown() async throws {
        window.contentView = nil
        window = nil
        canvas = nil
        session = nil
        try await super.tearDown()
    }

    /// A right-click at the centre of the canvas, in window (Cocoa, y-up) coordinates.
    private func rightClickAtCentre() throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    /// A measurement covering the whole canvas, so a centre click always lands on its body.
    private func addFullCanvasMeasurement(colorIndex: Int = 3) {
        session.measurements.append(
            Measurement(
                kind: .rectangle,
                rect: CanonicalRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height),
                colorIndex: colorIndex
            )
        )
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map(\.title)
    }

    // MARK: empty canvas

    func testRightClickOnEmptyCanvasOffersHistoryToolsAndDone() throws {
        let menu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))
        let titles = titles(menu)

        XCTAssertTrue(titles.contains("Undo"))
        XCTAssertTrue(titles.contains("Redo"))
        XCTAssertTrue(titles.contains("Rectangle Tool"))
        XCTAssertTrue(titles.contains("Horizontal Tool"))
        XCTAssertTrue(titles.contains("Vertical Tool"))
        XCTAssertTrue(titles.contains("Custom Reference Frame"))
        XCTAssertTrue(titles.contains("Clear All Measurements"))
        XCTAssertTrue(titles.contains("Done"))
    }

    func testUndoAndClearAreDisabledWithNothingToActOn() throws {
        let menu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))

        XCTAssertFalse(menu.items.first { $0.title == "Undo" }?.isEnabled ?? true)
        XCTAssertFalse(menu.items.first { $0.title == "Redo" }?.isEnabled ?? true)
        XCTAssertFalse(menu.items.first { $0.title == "Clear All Measurements" }?.isEnabled ?? true)
    }

    func testActiveToolIsCheckedInTheCanvasMenu() throws {
        session.tool = .vertical
        let menu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))

        XCTAssertEqual(menu.items.first { $0.title == "Vertical Tool" }?.state, .on)
        XCTAssertEqual(menu.items.first { $0.title == "Rectangle Tool" }?.state, .off)
    }

    // MARK: over a measurement

    func testRightClickOnAMeasurementSelectsItAndOffersItsActions() throws {
        addFullCanvasMeasurement()
        XCTAssertNil(session.selectedID)

        let menu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))

        XCTAssertEqual(session.selectedID, session.measurements[0].id, "right-click selects what it targets")
        let titles = titles(menu)
        XCTAssertTrue(titles.contains("Edit Label…"))
        XCTAssertTrue(titles.contains("Duplicate"))
        XCTAssertTrue(titles.contains("Delete"))
        XCTAssertTrue(titles.contains("Color"))
    }

    func testColorSubmenuListsEveryPaletteColorAndChecksTheCurrentOne() throws {
        addFullCanvasMeasurement(colorIndex: 3)
        let menu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))
        let submenu = try XCTUnwrap(menu.items.first { $0.title == "Color" }?.submenu)

        XCTAssertEqual(submenu.items.count, Palette.colors.count)
        XCTAssertEqual(submenu.items.map(\.title), Palette.colorNames.map { $0.capitalized })
        XCTAssertEqual(submenu.items[3].state, .on, "the measurement's own color is checked")
        XCTAssertEqual(submenu.items[0].state, .off)

        // Every entry carries an SF Symbol swatch — custom artwork is reserved for the app icon.
        for item in submenu.items {
            XCTAssertNotNil(item.image, "\(item.title) is missing its swatch")
        }
    }

    func testUndoItemIsTitledWithTheActionItWillUnwind() throws {
        addFullCanvasMeasurement()
        session.select(session.measurements[0].id)
        session.nudgeSelected(dx: 5, dy: 0)

        let menu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))
        let undo = try XCTUnwrap(menu.items.first { $0.title.hasPrefix("Undo") })
        XCTAssertEqual(undo.title, "Undo Move Measurement")
        XCTAssertTrue(undo.isEnabled)
    }

    /// Menus that set `isEnabled` by hand must opt out of AppKit's automatic validation,
    /// otherwise the flags are recomputed and thrown away.
    func testMenusDisableAutomaticItemEnabling() throws {
        addFullCanvasMeasurement()
        let measurementMenu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))
        XCTAssertFalse(measurementMenu.autoenablesItems)
        XCTAssertFalse(try XCTUnwrap(measurementMenu.items.first { $0.title == "Color" }?.submenu).autoenablesItems)

        session.measurements.removeAll()
        let canvasMenu = try XCTUnwrap(canvas.menu(for: rightClickAtCentre()))
        XCTAssertFalse(canvasMenu.autoenablesItems)
    }
}
