import CoreGraphics
import Foundation
import ImageIO

/// Decodes an image file (PNG and anything else ImageIO reads) into a `CGImage` for the
/// annotate pipeline. Errors surface as CLI errors with sensible exit codes.
enum ImageLoader {
    static func load(path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError(.notFound, "cubit: input image not found: \(path)")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIError(.usage, "cubit: could not decode image: \(path)")
        }
        return image
    }
}
