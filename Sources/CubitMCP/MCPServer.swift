import Foundation

/// The `cubit-mcp` server: a JSON-RPC 2.0 loop over stdio. stdin is read on a dedicated thread
/// and split into newline-delimited messages; each is dispatched on the main actor (SwiftUI's
/// ImageRenderer, used by annotate, needs the main run loop) and the response is written back to
/// stdout. Protocol traffic is stdout-only; diagnostics go to stderr.
public final class MCPServer {
    public init() {}

    /// Runs until stdin reaches EOF, then returns. Call from a main-actor task under a live
    /// `NSApplication` run loop (see the `cubit-mcp` executable's entry point).
    @MainActor
    public func run() async {
        let handler = MCPHandler()
        for await line in Self.stdinLines() {
            if let response = handler.response(forLine: line) {
                Self.write(response)
            }
        }
    }

    /// A single response line: the JSON bytes plus the framing newline. stdout writes are
    /// serialized on the main actor.
    @MainActor
    private static func write(_ data: Data) {
        var line = data
        line.append(MessageFraming.newline)
        FileHandle.standardOutput.write(line)
    }

    /// Reads stdin on a background thread and yields complete newline-delimited messages. Blocking
    /// reads live off the main actor so the run loop stays free for rendering. Finishes on EOF.
    private static func stdinLines() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let thread = Thread {
                var buffer = LineBuffer()
                let handle = FileHandle.standardInput
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        if let last = buffer.flush() { continuation.yield(last) }
                        break
                    }
                    for line in buffer.append(chunk) { continuation.yield(line) }
                }
                continuation.finish()
            }
            thread.name = "cubit-mcp-stdin"
            thread.start()
        }
    }
}

/// Writes a diagnostic line to stderr. stdout is reserved exclusively for JSON-RPC.
func mcpLog(_ message: String) {
    FileHandle.standardError.write(Data(("cubit-mcp: " + message + "\n").utf8))
}
