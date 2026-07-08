import Foundation

/// Resolves a user-supplied `--window` argument to a single window. A purely numeric argument
/// matches a window number exactly; otherwise it's a case-insensitive substring against the
/// owner app name plus the window title. Zero matches → not-found; more than one → ambiguous
/// (both exit code 4), with the candidate list on stderr so the agent can retry by number.
enum WindowMatch {
    static func find(_ query: String, in windows: [WindowInfo]) throws -> WindowInfo {
        if let number = UInt32(query) {
            if let hit = windows.first(where: { $0.windowID == number }) { return hit }
            throw CLIError(.notFound, "cubit: no on-screen window has number \(number)")
        }

        let needle = query.lowercased()
        let matches = windows.filter { window in
            let haystack = (window.ownerName + " " + (window.title ?? "")).lowercased()
            return haystack.contains(needle)
        }

        if matches.isEmpty {
            throw CLIError(.notFound, "cubit: no on-screen window matches '\(query)'")
        }
        if matches.count > 1 {
            let list = matches.map { candidateLine($0) }.joined(separator: "\n")
            throw CLIError(.notFound, "cubit: '\(query)' matches \(matches.count) windows; disambiguate by number:\n\(list)")
        }
        return matches[0]
    }

    static func candidateLine(_ window: WindowInfo) -> String {
        let title = window.title.map { " — \($0)" } ?? ""
        return "  \(window.windowID)  \(window.ownerName)\(title)"
    }
}
