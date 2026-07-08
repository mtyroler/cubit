import Foundation

/// A successful JSON-RPC response wrapping any `Encodable` result.
struct RPCSuccess<Result: Encodable>: Encodable {
    let jsonrpc = JSONRPC.version
    let id: JSONValue
    let result: Result
}

/// A JSON-RPC error response. `id` is `.null` when the offending request had no usable id
/// (e.g. a parse error).
struct RPCFailure: Encodable {
    struct ErrorBody: Encodable {
        let code: Int
        let message: String
    }
    let jsonrpc = JSONRPC.version
    let id: JSONValue
    let error: ErrorBody
}

// MARK: - initialize

struct InitializeResult: Encodable {
    struct Capabilities: Encodable {
        /// Presence of the (possibly empty) `tools` object advertises tool support.
        let tools: JSONValue
    }
    struct ServerInfo: Encodable {
        let name: String
        let version: String
    }
    let protocolVersion: String
    let capabilities: Capabilities
    let serverInfo: ServerInfo
}

// MARK: - tools/list

struct ToolDescriptor: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONValue
}

struct ToolsListResult: Encodable {
    let tools: [ToolDescriptor]
}

// MARK: - tools/call

/// One content block of a tool result. `text` blocks carry JSON or prose; `image` blocks carry
/// base64 PNG bytes. Optional fields are omitted when nil (synthesized `encodeIfPresent`).
struct ToolContent: Encodable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?

    static func text(_ value: String) -> ToolContent {
        ToolContent(type: "text", text: value, data: nil, mimeType: nil)
    }

    static func image(base64 data: String, mimeType: String) -> ToolContent {
        ToolContent(type: "image", text: nil, data: data, mimeType: mimeType)
    }
}

/// The `tools/call` result. `isError: true` signals a TOOL failure (e.g. bad arguments, window
/// not found, permission denied) — distinct from a JSON-RPC protocol error — so the agent sees
/// the message and can react without the whole request failing.
struct ToolResult: Encodable {
    let content: [ToolContent]
    let isError: Bool

    static func ok(_ content: [ToolContent]) -> ToolResult {
        ToolResult(content: content, isError: false)
    }

    static func failure(_ message: String) -> ToolResult {
        ToolResult(content: [.text(message)], isError: true)
    }
}
