import Foundation

/// JSON-RPC 2.0 over MCP's stdio transport. The transport framing is newline-delimited: each
/// message is one UTF-8 JSON object on its own line with no embedded newlines (compact
/// encoding guarantees that). This matches the MCP stdio convention — messages delimited by
/// `\n`, never length-prefixed — so a `stdio` MCP client reads us directly.
enum JSONRPC {
    static let version = "2.0"

    /// Standard JSON-RPC error codes plus MCP's use of them.
    enum ErrorCode: Int {
        case parseError = -32700
        case invalidRequest = -32600
        case methodNotFound = -32601
        case invalidParams = -32602
        case internalError = -32603
    }
}

/// A decoded inbound message. `id` is nil for notifications (which get no response). `params`
/// is kept as a raw `JSONValue` and decoded per-method.
struct RPCRequest: Equatable {
    let id: JSONValue?
    let method: String
    let params: JSONValue?

    var isNotification: Bool { id == nil }

    /// Extracts a well-formed request from a parsed JSON value, or nil if it isn't a JSON-RPC
    /// request object (missing or non-string `method`). A present-but-null `id` is treated as a
    /// real id (JSON-RPC allows null ids); an absent `id` marks a notification.
    static func from(_ value: JSONValue) -> RPCRequest? {
        guard case .object(let dict) = value else { return nil }
        guard let method = dict["method"]?.stringValue else { return nil }
        // Distinguish "id absent" (notification) from "id: null" (a request with null id).
        let id: JSONValue? = dict.keys.contains("id") ? (dict["id"] ?? .null) : nil
        return RPCRequest(id: id, method: method, params: dict["params"])
    }
}

/// Framing: encode a value to a single newline-terminated line; split an incoming byte stream on
/// newlines. Kept free of I/O so it's exercised directly in tests.
enum MessageFraming {
    static let newline: UInt8 = 0x0A

    /// Compact JSON (no pretty-printing → no embedded newlines) plus a trailing `\n`.
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(newline)
        return data
    }
}

/// Accumulates bytes and yields complete newline-delimited lines, retaining any partial trailing
/// line for the next chunk. Pure and synchronous so framing is unit-testable without a live pipe.
struct LineBuffer {
    private var buffer = Data()

    /// Appends `chunk` and returns every complete line it now contains (newline stripped).
    /// Blank lines are dropped (a client may pad with them). Bytes after the last newline stay
    /// buffered.
    mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: MessageFraming.newline) {
            let line = buffer.subdata(in: buffer.startIndex..<index)
            buffer.removeSubrange(buffer.startIndex...index)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    /// Any bytes buffered after the final newline (a last line with no trailing newline at EOF).
    mutating func flush() -> Data? {
        guard !buffer.isEmpty else { return nil }
        let remaining = buffer
        buffer.removeAll()
        return remaining.isEmpty ? nil : remaining
    }
}
