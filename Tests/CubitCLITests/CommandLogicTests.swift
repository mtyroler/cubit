import XCTest
@testable import Cubit

final class WindowMatchTests: XCTestCase {
    private func window(_ id: UInt32, _ owner: String, _ title: String?) -> WindowInfo {
        WindowInfo(
            canonicalBounds: CanonicalRect(x: 0, y: 0, width: 100, height: 100),
            ownerName: owner,
            windowLayer: 0,
            ownerPID: 1,
            windowID: id,
            title: title
        )
    }

    func testNumericMatchesWindowID() throws {
        let windows = [window(64, "Ghostty", "shell"), window(157, "Safari", "GitHub")]
        XCTAssertEqual(try WindowMatch.find("157", in: windows).windowID, 157)
    }

    func testNumericMissThrowsNotFound() {
        XCTAssertThrowsError(try WindowMatch.find("999", in: [window(1, "A", nil)])) {
            XCTAssertEqual(($0 as? CLIError)?.code, .notFound)
        }
    }

    func testCaseInsensitiveSubstringSingleMatch() throws {
        let windows = [window(64, "Ghostty", nil), window(157, "Safari", "GitHub")]
        XCTAssertEqual(try WindowMatch.find("safari", in: windows).windowID, 157)
    }

    func testMatchesAgainstTitleToo() throws {
        let windows = [window(64, "Ghostty", "release notes"), window(157, "Safari", "GitHub")]
        XCTAssertEqual(try WindowMatch.find("release", in: windows).windowID, 64)
    }

    func testAmbiguousThrowsNotFound() {
        let windows = [window(154, "Safari", ""), window(157, "Safari", "GitHub")]
        XCTAssertThrowsError(try WindowMatch.find("safari", in: windows)) {
            XCTAssertEqual(($0 as? CLIError)?.code, .notFound)
        }
    }

    func testNoMatchThrowsNotFound() {
        XCTAssertThrowsError(try WindowMatch.find("nope", in: [window(1, "A", nil)])) {
            XCTAssertEqual(($0 as? CLIError)?.code, .notFound)
        }
    }
}

final class WindowsDocumentTests: XCTestCase {
    func testBuildDocumentAssignsFrontToBackOrderAndPassesFields() {
        let windows = [
            WindowInfo(canonicalBounds: CanonicalRect(x: 10, y: 20, width: 300, height: 200),
                       ownerName: "Safari", windowLayer: 0, ownerPID: 1, windowID: 157, title: "GitHub"),
            WindowInfo(canonicalBounds: CanonicalRect(x: 0, y: 0, width: 100, height: 100),
                       ownerName: "Finder", windowLayer: 0, ownerPID: 2, windowID: 40, title: nil),
        ]
        let doc = WindowsCommand.buildDocument(windows: windows, screenRecordingGranted: false)

        XCTAssertFalse(doc.permission.screenRecording)
        XCTAssertEqual(doc.windows.map(\.order), [0, 1])
        XCTAssertEqual(doc.windows[0].number, 157)
        XCTAssertEqual(doc.windows[0].app, "Safari")
        XCTAssertEqual(doc.windows[0].title, "GitHub")
        XCTAssertEqual(doc.windows[0].frame.x, 10)
        XCTAssertEqual(doc.windows[0].frame.width, 300)
        XCTAssertNil(doc.windows[1].title) // nil title survives as JSON null, not ""
    }

    func testDocumentEncodesSortedKeysAndPermissionBlock() throws {
        let doc = WindowsCommand.buildDocument(windows: [], screenRecordingGranted: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let json = String(decoding: try encoder.encode(doc), as: UTF8.self)
        XCTAssertTrue(json.contains("\"screenRecording\" : true"))
        XCTAssertTrue(json.contains("\"windows\" : ["))
    }
}

final class ScaleAndIndexTests: XCTestCase {
    func testScaleFlagWins() throws {
        XCTAssertEqual(try AnnotateCommand.resolveScale(flag: "3", document: 2), 3)
    }

    func testDocumentScaleUsedWhenNoFlag() throws {
        XCTAssertEqual(try AnnotateCommand.resolveScale(flag: nil, document: 1.5), 1.5)
    }

    func testDefaultScaleIsTwo() throws {
        XCTAssertEqual(try AnnotateCommand.resolveScale(flag: nil, document: nil), 2)
    }

    func testNonNumericScaleFlagIsUsageError() {
        XCTAssertThrowsError(try AnnotateCommand.resolveScale(flag: "big", document: nil)) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
    }

    func testNonPositiveScaleFlagIsUsageError() {
        XCTAssertThrowsError(try AnnotateCommand.resolveScale(flag: "0", document: nil)) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
    }

    func testScreenIndexDefaultsToZero() throws {
        XCTAssertEqual(try CaptureCommand.screenIndex([], count: 2), 0)
    }

    func testScreenIndexParsesPositional() throws {
        XCTAssertEqual(try CaptureCommand.screenIndex(["1"], count: 2), 1)
    }

    func testScreenIndexNonNumericIsUsageError() {
        XCTAssertThrowsError(try CaptureCommand.screenIndex(["main"], count: 2)) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
    }

    func testScreenIndexOutOfRangeIsNotFound() {
        XCTAssertThrowsError(try CaptureCommand.screenIndex(["5"], count: 2)) {
            XCTAssertEqual(($0 as? CLIError)?.code, .notFound)
        }
    }
}

final class ReferenceDescriptorTests: XCTestCase {
    func testExplicitReferenceIsCustomWithDescriptor() {
        let resolved = ResolvedRegions(
            measurements: [],
            referenceRect: CanonicalRect(x: 50, y: 50, width: 1000, height: 700),
            referenceExplicit: true
        )
        let reference = AnnotateCommand.makeReference(resolved, scale: 2)
        XCTAssertEqual(reference.mode, .custom)
        XCTAssertEqual(reference.descriptor, "Reference — 1000×700")
    }

    func testFullImageReferenceIsScreenWithDescriptor() {
        let resolved = ResolvedRegions(
            measurements: [],
            referenceRect: CanonicalRect(x: 0, y: 0, width: 1200, height: 800),
            referenceExplicit: false
        )
        let reference = AnnotateCommand.makeReference(resolved, scale: 2)
        XCTAssertEqual(reference.mode, .screen)
        XCTAssertEqual(reference.descriptor, "Image — 1200×800")
    }

    func testSidecarURLSwapsExtension() {
        XCTAssertEqual(AnnotateCommand.sidecarURL(forOutput: "/tmp/out.png").lastPathComponent, "out.json")
    }
}
