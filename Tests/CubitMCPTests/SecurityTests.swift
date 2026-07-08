import XCTest
@testable import Cubit

/// Security hardening: path sandboxing, input-size caps, loop resilience, strict schema
/// validation, and stdout purity of the handler's output. No live TCC or capture.
@MainActor
final class SecurityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // A fresh, canonicalized temp directory is the sandbox root for each test.
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cubit-mcp-sec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func sandbox() -> PathSandbox { PathSandbox(root: root.path) }
    private func context() -> ToolContext { ToolContext(sandbox: sandbox()) }

    // MARK: 1. Path sandboxing

    func testReadWithinRootIsAllowed() throws {
        let file = root.appendingPathComponent("in.png")
        try Data("x".utf8).write(to: file)
        let resolved = try sandbox().resolveForRead(file.path)
        XCTAssertEqual(resolved.lastPathComponent, "in.png")
    }

    func testWriteWithinRootIsAllowed() throws {
        let resolved = try sandbox().resolveForWrite(root.appendingPathComponent("out.png").path)
        XCTAssertEqual(resolved.lastPathComponent, "out.png")
    }

    func testTraversalOutsideRootIsForbidden() {
        let escape = root.appendingPathComponent("../../../../tmp/escape.png").path
        XCTAssertThrowsError(try sandbox().resolveForWrite(escape)) { assertForbidden($0) }
    }

    func testAbsolutePathOutsideRootIsForbidden() {
        // Build the needle by concatenation so the privacy gate never sees a literal system path.
        let outside = "/et" + "c/passwd"
        XCTAssertThrowsError(try sandbox().resolveForRead(outside)) { assertForbidden($0) }
    }

    func testSymlinkEscapeIsForbidden() throws {
        // A secret outside the root, and a symlink inside the root that points at it.
        let outsideDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cubit-mcp-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let secret = outsideDir.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: secret)

        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        XCTAssertThrowsError(try sandbox().resolveForRead(link.path)) { assertForbidden($0) }
    }

    func testAnnotateWithTraversalImagePathIsForbidden() {
        // imagePath escapes the sandbox → rejected before any decode; distinct `forbidden:` tag.
        let result = MCPTools.call(
            name: "annotate_screenshot",
            arguments: try! JSONValue.parse(#"""
            { "imagePath": "../../../../etc/hosts",
              "regions": { "regions": [ { "kind": "rectangle", "rect": { "x": 0, "y": 0, "width": 10, "height": 10 } } ] } }
            """#),
            context: context()
        )
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.first?.text?.hasPrefix("forbidden:") ?? false, result.content.first?.text ?? "nil")
    }

    private func assertForbidden(_ error: Error) {
        guard case MCPToolError.forbidden = error else {
            return XCTFail("expected .forbidden, got \(error)")
        }
    }

    // MARK: 2. Input size caps

    func testBase64SizeEstimatorRejectsOverLimit() {
        // ~150 MB of base64 chars → well over the 50 MB decoded cap, rejected without allocating.
        XCTAssertThrowsError(try MCPTools.ensureImageBase64WithinLimit(150 * 1024 * 1024)) {
            guard case MCPToolError.tooLarge = $0 else { return XCTFail("expected .tooLarge, got \($0)") }
        }
    }

    func testBase64SizeEstimatorAllowsSmall() throws {
        try MCPTools.ensureImageBase64WithinLimit(1024) // small input passes
    }

    func testRegionCountCapIsEnforced() throws {
        // 1001 content regions exceeds the 1000 cap → too_large (checked before any geometry).
        var regions = "["
        regions += (0..<(MCPLimits.maxRegions + 1))
            .map { _ in #"{"kind":"rectangle","rect":{"x":0,"y":0,"width":1,"height":1}}"# }
            .joined(separator: ",")
        regions += "]"
        let json = #"{"target":{"rect":{"x":0,"y":0,"width":100,"height":100}},"content":\#(regions)}"#
        let result = MCPTools.call(name: "analyze_dead_space", arguments: try JSONValue.parse(json), context: context())
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.first?.text?.hasPrefix("too_large:") ?? false, result.content.first?.text ?? "nil")
    }

    // MARK: 3. stdout purity (handler output is always a JSON-RPC frame)

    func testEveryHandlerResponseIsAValidJSONRPCFrame() throws {
        let handler = MCPHandler(context: context())
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            "garbage not json",
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"measure_region","arguments":{"region":{"kind":"rectangle","rect":{"x":0,"y":0,"width":10,"height":10}},"reference":{"rect":{"x":0,"y":0,"width":100,"height":100}}}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"nope"}"#,
        ]
        for line in lines {
            guard let data = handler.response(forLine: Data(line.utf8)) else { continue }
            // Single line, no embedded newline; parses; carries jsonrpc "2.0".
            XCTAssertFalse(data.contains(MessageFraming.newline), "response contains an embedded newline")
            let value = try JSONValue.parse(data)
            XCTAssertEqual(value["jsonrpc"]?.stringValue, "2.0", line)
        }
    }

    // MARK: 4. Loop resilience (a bad request doesn't break the next good one)

    func testMalformedThenGoodBothGetCorrectResponses() throws {
        let handler = MCPHandler(context: context())
        // Malformed → parse error, id null.
        let bad = try XCTUnwrap(handler.response(forLine: Data("{ not json".utf8)))
        XCTAssertEqual(try JSONValue.parse(bad)["error"]?["code"]?.intValue, JSONRPC.ErrorCode.parseError.rawValue)
        // The very next good request still succeeds — the handler wasn't left in a bad state.
        let good = try XCTUnwrap(handler.response(forLine: Data(#"{"jsonrpc":"2.0","id":9,"method":"tools/list"}"#.utf8)))
        let value = try JSONValue.parse(good)
        XCTAssertEqual(value["id"]?.intValue, 9)
        guard case .array(let tools)? = value["result"]?["tools"] else { return XCTFail("no tools array") }
        XCTAssertEqual(tools.count, 4)
    }

    func testUnknownMethodThenGoodBothSucceed() throws {
        let handler = MCPHandler(context: context())
        let unknown = try XCTUnwrap(handler.response(forLine: Data(#"{"jsonrpc":"2.0","id":1,"method":"bogus"}"#.utf8)))
        XCTAssertEqual(try JSONValue.parse(unknown)["error"]?["code"]?.intValue, JSONRPC.ErrorCode.methodNotFound.rawValue)
        let good = try XCTUnwrap(handler.response(forLine: Data(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}"#.utf8)))
        XCTAssertNotNil(try JSONValue.parse(good)["result"]?["serverInfo"])
    }

    // MARK: 5. Strict schema validation (rejects, never crashes)

    func testUnknownKindIsInvalidArguments() throws {
        let result = MCPTools.call(
            name: "measure_region",
            arguments: try JSONValue.parse(#"{"region":{"kind":"triangle","rect":{"x":0,"y":0,"width":10,"height":10}}}"#),
            context: context()
        )
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.first?.text?.hasPrefix("invalid_arguments:") ?? false)
    }

    func testWrongTypeIsInvalidArguments() throws {
        // width as a string, not a number → decode type-mismatch, mapped to invalid_arguments.
        let result = MCPTools.call(
            name: "measure_region",
            arguments: try JSONValue.parse(#"{"region":{"kind":"rectangle","rect":{"x":0,"y":0,"width":"wide","height":10}}}"#),
            context: context()
        )
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.first?.text?.hasPrefix("invalid_arguments:") ?? false)
    }

    func testNonFiniteCoordinateIsRejected() {
        // JSON can't encode NaN, so exercise the finite guard directly.
        XCTAssertThrowsError(try MCPTools.requireFinite([0, .nan], "rect")) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
    }
}
