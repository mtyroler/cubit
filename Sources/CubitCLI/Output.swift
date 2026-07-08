import Foundation

/// stdout carries machine-readable output only (JSON); stderr carries human/diagnostic text.
/// JSON is pretty-printed with sorted keys, matching the M1 sidecar's conventions so an agent
/// sees one stable serialization style across every Cubit surface.
enum Output {
    static func stdout(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    static func stdoutLine(_ string: String) {
        stdout(string + "\n")
    }

    static func stderrLine(_ string: String) {
        FileHandle.standardError.write(Data((string + "\n").utf8))
    }

    static func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
