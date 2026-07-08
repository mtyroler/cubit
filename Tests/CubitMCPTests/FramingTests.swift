import XCTest
@testable import Cubit

/// JSON-RPC value model, newline framing, and request classification — the transport layer,
/// tested without any live pipe.
final class FramingTests: XCTestCase {
    func testJSONValueRoundTripsNestedObject() throws {
        let json = #"{"a":1,"b":2.5,"c":"x","d":[true,null],"e":{"f":-3}}"#
        let value = try JSONValue.parse(json)
        // Re-encode and re-parse; the structure must survive.
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONValue.parse(data), value)
        XCTAssertEqual(value["a"]?.intValue, 1)
        XCTAssertEqual(value["b"]?.doubleValue, 2.5)
        XCTAssertEqual(value["c"]?.stringValue, "x")
        XCTAssertEqual(value["e"]?["f"]?.intValue, -3)
    }

    func testMessageFramingEndsWithSingleNewlineAndNoEmbeddedNewline() throws {
        let data = try MessageFraming.encode(RPCFailure(id: .int(1), error: .init(code: -32601, message: "x")))
        XCTAssertEqual(data.last, MessageFraming.newline)
        // Exactly one newline, at the very end (compact JSON has none internally).
        XCTAssertEqual(data.filter { $0 == MessageFraming.newline }.count, 1)
    }

    func testLineBufferSplitsAcrossChunksAndDropsBlankLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("{\"a\":1}".utf8)), []) // no newline yet → nothing
        let lines = buffer.append(Data("\n\n{\"b\":2}\n".utf8))
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertNil(buffer.flush())
    }

    func testLineBufferFlushReturnsTrailingPartial() {
        var buffer = LineBuffer()
        _ = buffer.append(Data("{\"a\":1}\n{\"b\"".utf8))
        XCTAssertEqual(buffer.flush().map { String(decoding: $0, as: UTF8.self) }, "{\"b\"")
    }

    func testRequestClassification() throws {
        let request = RPCRequest.from(try JSONValue.parse(#"{"jsonrpc":"2.0","id":7,"method":"initialize"}"#))
        XCTAssertEqual(request?.method, "initialize")
        XCTAssertFalse(request?.isNotification ?? true)
        XCTAssertEqual(request?.id, .int(7))

        let notification = RPCRequest.from(try JSONValue.parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertTrue(notification?.isNotification ?? false)

        // id: null present → a real (non-notification) request with a null id.
        let nullID = RPCRequest.from(try JSONValue.parse(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))
        XCTAssertFalse(nullID?.isNotification ?? true)
        XCTAssertEqual(nullID?.id, JSONValue.null)

        // Not a request object.
        XCTAssertNil(RPCRequest.from(try JSONValue.parse("[1,2,3]")))
        XCTAssertNil(RPCRequest.from(try JSONValue.parse(#"{"jsonrpc":"2.0","id":1}"#))) // no method
    }
}
