import XCTest
@testable import Cubit

/// The `cubit show` / `show_overlay` shared validation path. Covers document validation and its
/// mapping to `CLIError`s (an agent branches on the exit code / tagged message). Does NOT exercise
/// the actual URL open — that needs the installed app and is the orchestrator's live pass.
@MainActor
final class HandoffLauncherTests: XCTestCase {
    private func validate(_ json: String) throws -> Int {
        try HandoffLauncher.validate(Data(json.utf8))
    }

    func testValidDocumentReturnsCount() throws {
        let count = try validate("""
        {"measurements":[
          {"kind":"rectangle","rect":{"x":0,"y":0,"width":10,"height":10}},
          {"kind":"horizontal","endpoints":[{"x":0,"y":5},{"x":20,"y":5}]}
        ]}
        """)
        XCTAssertEqual(count, 2)
    }

    func testUnknownKindIsUsageError() {
        XCTAssertThrowsError(try validate(#"{"measurements":[{"kind":"triangle","rect":{"x":0,"y":0,"width":1,"height":1}}]}"#)) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
    }

    func testMissingMeasurementsKeyIsUsageError() {
        XCTAssertThrowsError(try validate(#"{"note":"hi"}"#)) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
    }

    func testOverCapIsUsageError() {
        let items = Array(repeating: #"{"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1}}"#, count: HandoffMapper.maxMeasurements + 1)
        XCTAssertThrowsError(try validate("{\"measurements\":[\(items.joined(separator: ","))]}")) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
    }
}
