import Foundation

/// A minimal, dependency-free option parser (the project forbids third-party packages, so no
/// swift-argument-parser). Each subcommand declares which flags take a value and which are
/// boolean; anything else is a positional. Supports `--key value`, `--key=value`, and short
/// aliases registered as their own flag strings (e.g. both `-o` and `--out`).
struct ParsedOptions {
    private var values: [String: String] = [:]
    private var presentFlags: Set<String> = []
    private(set) var positionals: [String] = []

    /// First matching value among `names` (aliases), or nil.
    func value(_ names: String...) -> String? {
        for name in names where values[name] != nil { return values[name] }
        return nil
    }

    /// Whether any of the alias `names` was present as a boolean flag.
    func flag(_ names: String...) -> Bool {
        for name in names where presentFlags.contains(name) { return true }
        return false
    }

    static func parse(
        _ tokens: [String],
        valueFlags: Set<String>,
        boolFlags: Set<String>
    ) throws -> ParsedOptions {
        var result = ParsedOptions()
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token.hasPrefix("-"), token != "-" else {
                result.positionals.append(token)
                index += 1
                continue
            }

            let (key, inlineValue) = splitInlineValue(token)
            if valueFlags.contains(key) {
                if let inlineValue {
                    result.values[key] = inlineValue
                } else {
                    index += 1
                    guard index < tokens.count else {
                        throw CLIError(.usage, "cubit: option '\(key)' requires a value")
                    }
                    result.values[key] = tokens[index]
                }
            } else if boolFlags.contains(key) {
                guard inlineValue == nil else {
                    throw CLIError(.usage, "cubit: option '\(key)' takes no value")
                }
                result.presentFlags.insert(key)
            } else {
                throw CLIError(.usage, "cubit: unknown option '\(key)'\nRun with --help for usage.")
            }
            index += 1
        }
        return result
    }

    /// Splits `--key=value` into (`--key`, `value`); a bare flag yields (flag, nil). Only splits
    /// on the first `=` so values may themselves contain `=`.
    static func splitInlineValue(_ token: String) -> (String, String?) {
        guard token.hasPrefix("--"), let eq = token.firstIndex(of: "=") else { return (token, nil) }
        return (String(token[..<eq]), String(token[token.index(after: eq)...]))
    }
}
