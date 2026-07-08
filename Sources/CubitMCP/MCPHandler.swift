import Foundation

/// Turns one inbound JSON-RPC line into an outbound response (or nothing, for notifications).
/// Pure of I/O — the server owns stdin/stdout — so the whole request→response mapping is
/// unit-testable by feeding bytes and inspecting bytes.
@MainActor
final class MCPHandler {
    static let serverName = "cubit"
    /// The MCP protocol revision this server implements.
    static let protocolVersion = "2025-06-18"

    /// Parses and dispatches one line. Returns the response bytes (no trailing newline), or nil
    /// when no response is due (a notification). Never throws — every failure becomes a
    /// JSON-RPC error response so the read loop can't be killed by a bad message.
    func response(forLine line: Data) -> Data? {
        let value: JSONValue
        do {
            value = try JSONValue.parse(line)
        } catch {
            return failure(id: .null, code: .parseError, message: "Parse error: invalid JSON")
        }
        guard let request = RPCRequest.from(value) else {
            return failure(id: .null, code: .invalidRequest, message: "Invalid Request: not a JSON-RPC 2.0 request object")
        }
        return response(for: request)
    }

    func response(for request: RPCRequest) -> Data? {
        if request.isNotification {
            handleNotification(request)
            return nil
        }
        let id = request.id ?? .null
        switch request.method {
        case "initialize":
            return success(id: id, result: initializeResult())
        case "tools/list":
            return success(id: id, result: ToolsListResult(tools: MCPTools.descriptors))
        case "tools/call":
            return toolsCall(id: id, params: request.params)
        default:
            return failure(id: id, code: .methodNotFound, message: "Method not found: \(request.method)")
        }
    }

    // MARK: - Method handlers

    private func initializeResult() -> InitializeResult {
        InitializeResult(
            protocolVersion: Self.protocolVersion,
            capabilities: .init(tools: .object([:])),
            serverInfo: .init(name: Self.serverName, version: CubitCLIVersion.current)
        )
    }

    private func toolsCall(id: JSONValue, params: JSONValue?) -> Data? {
        guard let name = params?["name"]?.stringValue else {
            return failure(id: id, code: .invalidParams, message: "Invalid params: 'name' is required for tools/call")
        }
        let result = MCPTools.call(name: name, arguments: params?["arguments"])
        return success(id: id, result: result)
    }

    private func handleNotification(_ request: RPCRequest) {
        // `notifications/initialized` completes the handshake; nothing to do. Other client
        // notifications (e.g. cancellations) are accepted and ignored in this milestone.
    }

    // MARK: - Encoding

    private func success(id: JSONValue, result: some Encodable) -> Data {
        encode(RPCSuccess(id: id, result: result))
    }

    private func failure(id: JSONValue, code: JSONRPC.ErrorCode, message: String) -> Data {
        encode(RPCFailure(id: id, error: .init(code: code.rawValue, message: message)))
    }

    private func encode(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(value) { return data }
        return Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error: response encoding failed"}}"#.utf8)
    }
}
