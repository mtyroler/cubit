import Foundation

/// Parses the `cubit://` handoff URL. This is the app's external transport: macOS launches or
/// foregrounds Cubit and delivers the URL, which is handled read-only — it only ever draws
/// EDITABLE shapes the user can dismiss. This parser is pure (Foundation only) and unit-tested;
/// the AppKit layer hands it a string and receives a `Payload`.
///
/// Two forms of `cubit://show`:
/// - `cubit://show?path=<url-encoded-abs-path>` — the primary form; the file at that path holds a
///   handoff JSON document (dodges URL-length limits). The AppKit layer reads the file.
/// - `cubit://show?regions=<base64url-json>` — a convenience for small inline payloads; the
///   base64url decodes to the same handoff JSON bytes.
///
/// When both parameters are present, `regions` (self-contained inline) wins.
enum HandoffURL {
    enum Payload: Equatable {
        /// A filesystem path to read + parse as a handoff document (read-only).
        case path(String)
        /// Already-decoded JSON bytes from an inline `regions=` base64url payload.
        case inline(Data)
    }

    enum ParseError: Error, Equatable {
        case notAURL
        case wrongScheme(String?)
        case wrongHost(String?)
        case missingParameter
        case invalidBase64
    }

    static let scheme = "cubit"
    static let host = "show"

    static func parse(_ urlString: String) throws -> Payload {
        guard let components = URLComponents(string: urlString) else {
            throw ParseError.notAURL
        }
        guard components.scheme?.lowercased() == scheme else {
            throw ParseError.wrongScheme(components.scheme)
        }
        // A custom-scheme URL puts the "show" token in the host slot (cubit://show?...).
        guard components.host?.lowercased() == host else {
            throw ParseError.wrongHost(components.host)
        }

        let items = components.queryItems ?? []
        // Inline (self-contained) wins over a path when both are supplied.
        if let regions = firstNonEmptyValue(items, name: "regions") {
            guard let data = decodeBase64URL(regions) else {
                throw ParseError.invalidBase64
            }
            return .inline(data)
        }
        if let path = firstNonEmptyValue(items, name: "path") {
            return .path(path)
        }
        throw ParseError.missingParameter
    }

    private static func firstNonEmptyValue(_ items: [URLQueryItem], name: String) -> String? {
        for item in items where item.name == name {
            if let value = item.value, !value.isEmpty { return value }
        }
        return nil
    }

    /// Decodes a base64url string (RFC 4648 §5: `-`→`+`, `_`→`/`, padding optional). Tolerates
    /// embedded whitespace/newlines. Returns nil when the payload isn't valid base64url.
    static func decodeBase64URL(_ string: String) -> Data? {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters])
    }

    /// Builds a `cubit://show?path=…` URL for the given absolute path, percent-encoding the path.
    /// Used by the `cubit` CLI and `cubit-mcp` server to trigger the app.
    static func showURL(forPath path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
}
