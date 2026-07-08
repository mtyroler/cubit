import XCTest
@testable import Cubit

/// The JSON-RPC method layer: handshake shape, tools/list, dispatch, and every error path a
/// malformed or unexpected message can take. Byte-in, byte-out.
@MainActor
final class HandlerTests: XCTestCase {
    private let handler = MCPHandler()

    private func respond(_ line: String) throws -> JSONValue {
        let data = try XCTUnwrap(handler.response(forLine: Data(line.utf8)))
        return try JSONValue.parse(data)
    }

    func testInitializeHandshakeShape() throws {
        let response = try respond(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}"#)
        XCTAssertEqual(response["jsonrpc"]?.stringValue, "2.0")
        XCTAssertEqual(response["id"]?.intValue, 1)
        let result = try XCTUnwrap(response["result"])
        XCTAssertEqual(result["protocolVersion"]?.stringValue, MCPHandler.protocolVersion)
        XCTAssertEqual(result["serverInfo"]?["name"]?.stringValue, "cubit")
        XCTAssertEqual(result["serverInfo"]?["version"]?.stringValue, CubitCLIVersion.current)
        // capabilities.tools must be present (an object) to advertise tool support.
        XCTAssertNotNil(result["capabilities"]?["tools"])
    }

    func testToolsListReturnsAllToolsWithObjectSchemas() throws {
        let response = try respond(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try XCTUnwrap(response["result"]?["tools"])
        guard case .array(let items) = tools else { return XCTFail("tools is not an array") }
        XCTAssertEqual(items.count, 5)
        let names = Set(items.compactMap { $0["name"]?.stringValue })
        XCTAssertEqual(names, ["list_windows", "measure_region", "annotate_screenshot", "show_overlay", "analyze_dead_space"])
        for item in items {
            XCTAssertFalse(item["description"]?.stringValue?.isEmpty ?? true)
            XCTAssertEqual(item["inputSchema"]?["type"]?.stringValue, "object", "\(item["name"]?.stringValue ?? "?") schema must be an object")
            XCTAssertNotNil(item["inputSchema"]?["properties"])
        }
    }

    func testToolsCallDispatchesAndWrapsToolResult() throws {
        let response = try respond(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"measure_region","arguments":{"region":{"kind":"rectangle","rect":{"x":0,"y":0,"width":100,"height":100}},"reference":{"rect":{"x":0,"y":0,"width":200,"height":200}},"scale":2}}}"#)
        let result = try XCTUnwrap(response["result"])
        // A successful tool call is a JSON-RPC success whose result carries content + isError.
        XCTAssertEqual(result["isError"]?.boolValueForTest, false)
        XCTAssertNotNil(result["content"])
    }

    func testUnknownMethodIsMethodNotFound() throws {
        let response = try respond(#"{"jsonrpc":"2.0","id":4,"method":"does/not/exist"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, JSONRPC.ErrorCode.methodNotFound.rawValue)
        XCTAssertEqual(response["id"]?.intValue, 4)
    }

    func testMalformedJSONIsParseErrorWithNullID() throws {
        let response = try respond("{ this is not json ")
        XCTAssertEqual(response["error"]?["code"]?.intValue, JSONRPC.ErrorCode.parseError.rawValue)
        XCTAssertTrue(response["id"]?.isNull ?? false)
    }

    func testRequestWithoutMethodIsInvalidRequest() throws {
        let response = try respond(#"{"jsonrpc":"2.0","id":5}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, JSONRPC.ErrorCode.invalidRequest.rawValue)
    }

    func testToolsCallWithoutNameIsInvalidParams() throws {
        let response = try respond(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"arguments":{}}}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, JSONRPC.ErrorCode.invalidParams.rawValue)
    }

    func testNotificationProducesNoResponse() {
        XCTAssertNil(handler.response(forLine: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)))
    }

    func testStringIDIsEchoed() throws {
        let response = try respond(#"{"jsonrpc":"2.0","id":"abc","method":"tools/list"}"#)
        XCTAssertEqual(response["id"]?.stringValue, "abc")
    }
}

/// Small helper so tests can read a JSON boolean without pattern-matching every time.
extension JSONValue {
    var boolValueForTest: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}
