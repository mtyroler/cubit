import XCTest
@testable import Cubit

final class OptionsTests: XCTestCase {
    func testValueFlagSpaceSeparated() throws {
        let options = try ParsedOptions.parse(["--out", "a.png"], valueFlags: ["--out"], boolFlags: [])
        XCTAssertEqual(options.value("--out"), "a.png")
        XCTAssertTrue(options.positionals.isEmpty)
    }

    func testValueFlagInline() throws {
        let options = try ParsedOptions.parse(["--out=a.png"], valueFlags: ["--out"], boolFlags: [])
        XCTAssertEqual(options.value("--out"), "a.png")
    }

    func testInlineValueKeepsLaterEquals() throws {
        let options = try ParsedOptions.parse(["--key=a=b"], valueFlags: ["--key"], boolFlags: [])
        XCTAssertEqual(options.value("--key"), "a=b")
    }

    func testBoolFlagAndPositionals() throws {
        let options = try ParsedOptions.parse(["--screen", "1"], valueFlags: [], boolFlags: ["--screen"])
        XCTAssertTrue(options.flag("--screen"))
        XCTAssertEqual(options.positionals, ["1"])
    }

    func testAliases() throws {
        let options = try ParsedOptions.parse(["-o", "a.png"], valueFlags: ["--out", "-o"], boolFlags: [])
        XCTAssertEqual(options.value("--out", "-o"), "a.png")
    }

    func testUnknownOptionThrowsUsage() {
        XCTAssertThrowsError(try ParsedOptions.parse(["--nope"], valueFlags: [], boolFlags: [])) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage)
        }
    }

    func testMissingValueThrowsUsage() {
        XCTAssertThrowsError(try ParsedOptions.parse(["--out"], valueFlags: ["--out"], boolFlags: [])) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage)
        }
    }

    func testBoolFlagWithValueThrowsUsage() {
        XCTAssertThrowsError(try ParsedOptions.parse(["--screen=1"], valueFlags: [], boolFlags: ["--screen"])) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage)
        }
    }

    func testBareDashIsPositional() throws {
        let options = try ParsedOptions.parse(["-"], valueFlags: [], boolFlags: [])
        XCTAssertEqual(options.positionals, ["-"])
    }
}
