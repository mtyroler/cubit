import Foundation

/// The `cubit-mcp` server: a JSON-RPC 2.0 loop over stdio. stdin is read on a dedicated thread
/// and split into newline-delimited messages; each is dispatched on the main actor (SwiftUI's
/// ImageRenderer, used by annotate, needs the main run loop) and the response is written back to
/// stdout. Protocol traffic is stdout-only; diagnostics go to stderr.
public final class MCPServer {
    /// The filesystem root every agent-supplied path is confined to (see `PathSandbox`).
    private let root: String
    /// The channel protocol frames are written to. Defaults to real stdout;
    /// `redirectStdoutToProtocolChannel()` swaps in the saved original fd after fd 1 is pointed
    /// at stderr.
    private var protocolOut = FileHandle.standardOutput

    public init(root: String = FileManager.default.currentDirectoryPath) {
        self.root = root
    }

    /// Guarantees stdout purity: duplicates the real stdout, then points fd 1 at stderr so ANY
    /// stray write from AppKit / ScreenCaptureKit / a system framework goes to stderr and can't
    /// corrupt the JSON-RPC stream. Protocol frames are written to the saved real stdout. Call
    /// ONCE, before initializing NSApplication. Executable-entry-point only — not for tests.
    public func redirectStdoutToProtocolChannel() {
        let realStdout = dup(STDOUT_FILENO)
        guard realStdout >= 0 else { return }
        dup2(STDERR_FILENO, STDOUT_FILENO)
        protocolOut = FileHandle(fileDescriptor: realStdout, closeOnDealloc: false)
    }

    /// Runs until stdin reaches EOF, then returns. Call from a main-actor task under a live
    /// `NSApplication` run loop (see the `cubit-mcp` executable's entry point).
    @MainActor
    public func run() async {
        let handler = MCPHandler(context: ToolContext(sandbox: PathSandbox(root: root)))
        for await line in Self.stdinLines() {
            if let response = handler.response(forLine: line) {
                write(response)
            }
        }
    }

    /// A single response line: the JSON bytes plus the framing newline, written to the protocol
    /// channel (never the redirected fd 1). Serialized on the main actor.
    @MainActor
    private func write(_ data: Data) {
        var line = data
        line.append(MessageFraming.newline)
        protocolOut.write(line)
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
