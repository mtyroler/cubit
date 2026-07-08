import Foundation

/// Hard limits on agent-supplied input, enforced before any allocation or decode so a hostile
/// or buggy client can't OOM the server.
enum MCPLimits {
    /// Maximum decoded size of an inline base64 image (50 MB).
    static let maxDecodedImageBytes = 50 * 1024 * 1024
    /// Maximum on-disk size of an image read from a (sandboxed) path.
    static let maxImageFileBytes = 50 * 1024 * 1024
    /// Maximum number of regions in a single annotate / analyze request.
    static let maxRegions = 1000
}

/// A tool-level failure that isn't a CLI error: a sandbox rejection or an over-limit input.
/// Mapped to a tagged `isError` result (`forbidden:` / `too_large:`) so an agent can react.
enum MCPToolError: Error {
    case forbidden(String)
    case tooLarge(String)
}

/// Shared, per-connection tool state. Currently just the filesystem sandbox; a struct so more
/// context (limits, client info) can be threaded without touching every tool signature.
struct ToolContext {
    let sandbox: PathSandbox
}

/// Confines every agent-supplied path to an allowed root directory. Agent input is untrusted:
/// paths are canonicalized (lexical `..` removed AND symlinks resolved) BEFORE any read/write,
/// and anything that lands outside the root — via `..`, an absolute path, or a symlink that
/// points out — is refused with `MCPToolError.forbidden`. The root defaults to the server's
/// working directory and can be set with `--root`.
struct PathSandbox {
    let root: URL

    init(root: String) {
        // Canonicalize the root itself so containment checks compare like-for-like (e.g. macOS
        // maps /tmp and /var to /private/... via symlinks).
        let url = URL(fileURLWithPath: root, isDirectory: true)
        self.root = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    /// True iff `url` is the root or nested under it, compared by path components (so `/a/rootX`
    /// is not treated as inside `/a/root`).
    private func isWithin(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        let rootComponents = root.pathComponents
        let components = target.pathComponents
        guard components.count >= rootComponents.count else { return false }
        return Array(components.prefix(rootComponents.count)) == rootComponents
    }

    /// A RELATIVE agent path is resolved against the sandbox root (not the process working
    /// directory); an ABSOLUTE path is taken as-is. Either way it's standardized to an absolute
    /// URL before the containment check.
    private func absolute(_ path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: root).absoluteURL.standardizedFileURL
    }

    /// Resolves a path intended for READING. The file must resolve (following symlinks) to a
    /// location inside the root, else `forbidden`.
    func resolveForRead(_ path: String) throws -> URL {
        let canonical = absolute(path).resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(canonical) else {
            throw MCPToolError.forbidden("path is outside the allowed root: \(path)")
        }
        return canonical
    }

    /// Resolves a path intended for WRITING. The leaf may not exist yet, so the PARENT directory
    /// is canonicalized (catching a symlinked parent) and both parent and target must stay inside
    /// the root. If the leaf already exists as a symlink pointing out, that's refused too.
    func resolveForWrite(_ path: String) throws -> URL {
        let requested = absolute(path)
        let parent = requested.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let target = parent.appendingPathComponent(requested.lastPathComponent)
        guard isWithin(parent), isWithin(target) else {
            throw MCPToolError.forbidden("path is outside the allowed root: \(path)")
        }
        // An existing leaf that symlinks elsewhere must not escape.
        let leafResolved = target.resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(leafResolved) else {
            throw MCPToolError.forbidden("path resolves via symlink outside the allowed root: \(path)")
        }
        return target
    }
}
