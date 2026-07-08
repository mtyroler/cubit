import CoreGraphics
import Foundation

/// `cubit annotate --in shot.png --regions regions.json -o out.png [--scale N] [--sidecar]
/// [--totals]` — renders Cubit-style measurement annotations onto an existing image using the
/// exact same layout engine and SwiftUI drawing pipeline as an app export, so the output is
/// visually identical. `--sidecar` writes the M1 `MeasurementSidecar` JSON next to the output.
@MainActor
enum AnnotateCommand {
    nonisolated static let defaultScale: CGFloat = 2

    static func run(_ tokens: [String]) throws -> ExitCode {
        if tokens.contains("--help") || tokens.contains("-h") {
            Output.stdout(Help.annotate)
            return .ok
        }
        let options = try ParsedOptions.parse(
            tokens,
            valueFlags: ["--in", "-i", "--regions", "-r", "--out", "-o", "--scale"],
            boolFlags: ["--sidecar", "--totals"]
        )

        guard let inPath = options.value("--in", "-i") else {
            throw CLIError(.usage, "cubit annotate: --in <image> is required")
        }
        guard let regionsPath = options.value("--regions", "-r") else {
            throw CLIError(.usage, "cubit annotate: --regions <json> is required")
        }
        guard let outPath = options.value("--out", "-o") else {
            throw CLIError(.usage, "cubit annotate: -o <out.png> is required")
        }

        let image = try ImageLoader.load(path: inPath)
        let input = try loadRegions(path: regionsPath)
        let scale = try resolveScale(flag: options.value("--scale"), document: input.scale)

        let resolved = try RegionsResolver.resolve(
            input,
            imagePixelWidth: image.width,
            imagePixelHeight: image.height,
            scale: scale
        )

        let reference = makeReference(resolved, scale: scale)
        let cropRect = CanonicalRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )

        guard let rendered = ExportRenderer.renderAnnotatedExport(
            image: image,
            cropRect: cropRect,
            scale: scale,
            measurements: resolved.measurements,
            reference: reference,
            showTotals: options.flag("--totals")
        ) else {
            throw CLIError(.generic, "cubit: failed to render annotated image")
        }

        do {
            try rendered.png.write(to: URL(fileURLWithPath: outPath))
        } catch {
            throw CLIError(.generic, "cubit: could not write \(outPath): \(error.localizedDescription)")
        }

        var sidecarPath: String?
        if options.flag("--sidecar") {
            let url = sidecarURL(forOutput: outPath)
            do {
                try rendered.sidecar.jsonData().write(to: url)
                sidecarPath = url.path
            } catch {
                throw CLIError(.generic, "cubit: could not write sidecar: \(error.localizedDescription)")
            }
        }

        try Output.json(AnnotateResult(
            output: outPath,
            sidecar: sidecarPath,
            scale: Double(scale),
            measurementCount: resolved.measurements.count
        ))
        return .ok
    }

    struct AnnotateResult: Encodable {
        let output: String
        let sidecar: String?
        let scale: Double
        let measurementCount: Int
    }

    /// Scale precedence: `--scale` flag > `scale` in the regions document > default (2).
    nonisolated static func resolveScale(flag: String?, document: Double?) throws -> CGFloat {
        if let flag {
            guard let value = Double(flag), value > 0 else {
                throw CLIError(.usage, "cubit annotate: --scale must be a positive number, got '\(flag)'")
            }
            return CGFloat(value)
        }
        if let document {
            guard document > 0 else {
                throw CLIError(.usage, "cubit annotate: regions 'scale' must be positive")
            }
            return CGFloat(document)
        }
        return defaultScale
    }

    /// A `.custom` reference (draws the dashed outline) when the document supplied a sub-rect,
    /// else `.screen` (whole image, no outline). Descriptor becomes the legend header and the
    /// sidecar's `reference.name`.
    nonisolated static func makeReference(_ resolved: ResolvedRegions, scale: CGFloat) -> ResolvedReference {
        let rect = resolved.referenceRect
        let width = Int(rect.width.rounded())
        let height = Int(rect.height.rounded())
        if resolved.referenceExplicit {
            return ResolvedReference(rect: rect, mode: .custom, descriptor: "Reference — \(width)×\(height)")
        }
        return ResolvedReference(rect: rect, mode: .screen, descriptor: "Image — \(width)×\(height)")
    }

    nonisolated static func sidecarURL(forOutput outPath: String) -> URL {
        URL(fileURLWithPath: outPath).deletingPathExtension().appendingPathExtension("json")
    }

    private static func loadRegions(path: String) throws -> RegionsInput {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError(.notFound, "cubit: regions file not found: \(path)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CLIError(.generic, "cubit: could not read \(path): \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(RegionsInput.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw CLIError(.usage, "cubit: regions JSON missing required key '\(key.stringValue)'")
        } catch let DecodingError.typeMismatch(_, context) {
            throw CLIError(.usage, "cubit: regions JSON type mismatch at \(pathDescription(context.codingPath))")
        } catch {
            throw CLIError(.usage, "cubit: could not parse regions JSON: \(error.localizedDescription)")
        }
    }

    private static func pathDescription(_ codingPath: [CodingKey]) -> String {
        codingPath.isEmpty ? "<root>" : codingPath.map(\.stringValue).joined(separator: ".")
    }
}
