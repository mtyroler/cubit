import XCTest
@testable import Cubit

final class ExportMetadataTests: XCTestCase {
    // MARK: MacModelNames

    func testKnownIdentifierMapsToFriendlyName() {
        XCTAssertEqual(MacModelNames.friendlyName(forIdentifier: "Mac15,3"), "MacBook Pro 14-inch, M3")
    }

    func testUnknownIdentifierPassesThroughUnchanged() {
        XCTAssertEqual(MacModelNames.friendlyName(forIdentifier: "Mac99,99"), "Mac99,99")
    }

    // MARK: MachineInfo formatting

    func testMachineInfoLinesFormatModelOSAndDisplay() {
        let machine = MachineInfo(
            modelName: "MacBook Pro 14-inch, M3",
            displayPixelsWidth: 3024,
            displayPixelsHeight: 1964,
            displayPointsWidth: 1512,
            displayPointsHeight: 982,
            scale: 2,
            osVersion: "26.1"
        )
        XCTAssertEqual(machine.lines, [
            "MacBook Pro 14-inch, M3 · macOS 26.1",
            "3024×1964 px @2x"
        ])
    }

    func testMachineInfoNonIntegerScaleFormatsWithDecimal() {
        let machine = MachineInfo(
            modelName: "External Display",
            displayPixelsWidth: 2560,
            displayPixelsHeight: 1440,
            displayPointsWidth: 2048,
            displayPointsHeight: 1152,
            scale: 1.25,
            osVersion: "26.1"
        )
        XCTAssertEqual(machine.lines[1], "2560×1440 px @1.2x")
    }

    // MARK: WindowInfoMeta

    func testWindowInfoOmitsNilTitleLine() {
        let window = WindowInfoMeta(
            title: nil,
            ownerName: "Safari",
            sizePointsWidth: 800,
            sizePointsHeight: 600,
            sizePixelsWidth: 1600,
            sizePixelsHeight: 1200
        )
        XCTAssertEqual(window.lines, ["Safari", "800×600 pt (1600×1200 px)"])
    }

    func testWindowInfoOmitsBlankTitleLine() {
        let window = WindowInfoMeta(
            title: "   ",
            ownerName: "Safari",
            sizePointsWidth: 800,
            sizePointsHeight: 600,
            sizePixelsWidth: 1600,
            sizePixelsHeight: 1200
        )
        XCTAssertEqual(window.lines, ["Safari", "800×600 pt (1600×1200 px)"])
    }

    func testWindowInfoIncludesTitleWhenPresent() {
        let window = WindowInfoMeta(
            title: "Inbox — 42 unread",
            ownerName: "Mail",
            sizePointsWidth: 900,
            sizePointsHeight: 700,
            sizePixelsWidth: 1800,
            sizePixelsHeight: 1400
        )
        XCTAssertEqual(window.lines, ["Inbox — 42 unread", "Mail", "900×700 pt (1800×1400 px)"])
    }

    // MARK: AppInfoMeta

    func testAppInfoIncludesVersionWhenPresent() {
        let app = AppInfoMeta(name: "Safari", version: "18.1")
        XCTAssertEqual(app.lines, ["Safari 18.1"])
    }

    func testAppInfoOmitsVersionWhenNil() {
        let app = AppInfoMeta(name: "SomeDaemon", version: nil)
        XCTAssertEqual(app.lines, ["SomeDaemon"])
    }

    func testAppInfoOmitsEmptyVersion() {
        let app = AppInfoMeta(name: "SomeDaemon", version: "")
        XCTAssertEqual(app.lines, ["SomeDaemon"])
    }

    // MARK: ExportMetadata.isEmpty

    func testExportMetadataIsEmptyWhenAllNil() {
        XCTAssertTrue(ExportMetadata().isEmpty)
    }

    func testExportMetadataIsNotEmptyWithAnyCategory() {
        let machine = MachineInfo(
            modelName: "Mac", displayPixelsWidth: 1, displayPixelsHeight: 1,
            displayPointsWidth: 1, displayPointsHeight: 1, scale: 1, osVersion: "26.0"
        )
        XCTAssertFalse(ExportMetadata(machine: machine).isEmpty)
    }
}
