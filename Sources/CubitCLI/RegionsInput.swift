import CoreGraphics
import Foundation

/// The `--regions` document for `cubit annotate`. All coordinates are in IMAGE PIXELS
/// (top-left origin, y-down) — the same space you'd read off the input PNG. The CLI divides by
/// `scale` to reach Cubit's canonical point space before rendering, so percentages are
/// scale-independent.
///
/// Shape:
/// ```json
/// {
///   "scale": 2,
///   "reference": { "rect": { "x": 0, "y": 0, "width": 2400, "height": 1600 } },
///   "regions": [
///     { "kind": "rectangle", "rect": { "x": 200, "y": 240, "width": 600, "height": 400 },
///       "label": "hero", "colorIndex": 0 },
///     { "kind": "horizontal", "endpoints": [ { "x": 200, "y": 800 }, { "x": 1400, "y": 800 } ] },
///     { "kind": "vertical", "endpoints": [ { "x": 200, "y": 200 }, { "x": 200, "y": 1000 } ] }
///   ]
/// }
/// ```
/// `scale` and `reference` are optional (a `--scale` flag overrides the former; an omitted
/// reference means the whole image). `label` and `colorIndex` are optional per region.
struct RegionsInput: Decodable {
    struct Point: Decodable, Equatable {
        let x: Double
        let y: Double
    }

    struct Rect: Decodable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Reference: Decodable, Equatable {
        let rect: Rect?
    }

    struct Region: Decodable, Equatable {
        let kind: String
        let rect: Rect?
        let endpoints: [Point]?
        let label: String?
        let colorIndex: Int?
    }

    let scale: Double?
    let reference: Reference?
    let regions: [Region]
}

/// The fully resolved, canonical-space annotation the renderer consumes.
struct ResolvedRegions: Equatable {
    var measurements: [Measurement]
    /// Reference rect in canonical points (the percentage denominator).
    var referenceRect: CanonicalRect
    /// True when the document supplied an explicit reference sub-rect (drives outline + mode).
    var referenceExplicit: Bool
}

enum RegionsResolver {
    /// Endpoints of an axis-aligned line must share the perpendicular coordinate within this
    /// many pixels — a small tolerance for hand-authored JSON.
    static let axisTolerance: Double = 0.5

    /// Converts pixel-space input into canonical-space measurements + reference. `scale`
    /// resolution order is caller-decided: pass the already-resolved effective scale here.
    static func resolve(_ input: RegionsInput, imagePixelWidth: Int, imagePixelHeight: Int, scale: CGFloat) throws -> ResolvedRegions {
        guard scale > 0 else {
            throw CLIError(.usage, "cubit: scale must be greater than zero")
        }
        guard !input.regions.isEmpty else {
            throw CLIError(.usage, "cubit: regions document has no regions")
        }

        let s = CGFloat(scale)

        // Reference: explicit sub-rect, or the whole image.
        let referenceExplicit: Bool
        let referenceRect: CanonicalRect
        if let refRect = input.reference?.rect {
            guard refRect.width > 0, refRect.height > 0 else {
                throw CLIError(.usage, "cubit: reference rect must have positive width and height")
            }
            referenceRect = canonicalRect(refRect, scale: s)
            referenceExplicit = true
        } else {
            referenceRect = CanonicalRect(
                x: 0,
                y: 0,
                width: CGFloat(imagePixelWidth) / s,
                height: CGFloat(imagePixelHeight) / s
            )
            referenceExplicit = false
        }

        var measurements: [Measurement] = []
        for (index, region) in input.regions.enumerated() {
            measurements.append(try measurement(from: region, index: index, scale: s))
        }

        return ResolvedRegions(
            measurements: measurements,
            referenceRect: referenceRect,
            referenceExplicit: referenceExplicit
        )
    }

    static func measurement(from region: RegionsInput.Region, index: Int, scale s: CGFloat) throws -> Measurement {
        guard let kind = MeasurementKind(rawValue: region.kind) else {
            throw CLIError(.usage, "cubit: region \(index): unknown kind '\(region.kind)' (use rectangle, horizontal, or vertical)")
        }
        // Default color cycles through the palette by position so unspecified regions still
        // render as distinct colors; an explicit colorIndex wins.
        let colorIndex = region.colorIndex ?? index
        let label = region.label ?? ""

        let rect: CanonicalRect
        switch kind {
        case .rectangle:
            guard let r = region.rect else {
                throw CLIError(.usage, "cubit: region \(index): a rectangle needs a 'rect'")
            }
            guard r.width > 0, r.height > 0 else {
                throw CLIError(.usage, "cubit: region \(index): rectangle needs positive width and height")
            }
            rect = canonicalRect(r, scale: s)
        case .horizontal:
            let (a, b) = try endpoints(region, index: index)
            guard abs(a.y - b.y) <= axisTolerance else {
                throw CLIError(.usage, "cubit: region \(index): a horizontal line's endpoints must share the same y")
            }
            let minX = min(a.x, b.x), maxX = max(a.x, b.x)
            guard maxX - minX > 0 else {
                throw CLIError(.usage, "cubit: region \(index): horizontal line has zero length")
            }
            rect = CanonicalRect(x: CGFloat(minX) / s, y: CGFloat(a.y) / s, width: CGFloat(maxX - minX) / s, height: 0)
        case .vertical:
            let (a, b) = try endpoints(region, index: index)
            guard abs(a.x - b.x) <= axisTolerance else {
                throw CLIError(.usage, "cubit: region \(index): a vertical line's endpoints must share the same x")
            }
            let minY = min(a.y, b.y), maxY = max(a.y, b.y)
            guard maxY - minY > 0 else {
                throw CLIError(.usage, "cubit: region \(index): vertical line has zero length")
            }
            rect = CanonicalRect(x: CGFloat(a.x) / s, y: CGFloat(minY) / s, width: 0, height: CGFloat(maxY - minY) / s)
        }

        return Measurement(kind: kind, rect: rect, label: label, colorIndex: colorIndex)
    }

    private static func endpoints(_ region: RegionsInput.Region, index: Int) throws -> (RegionsInput.Point, RegionsInput.Point) {
        guard let points = region.endpoints, points.count == 2 else {
            throw CLIError(.usage, "cubit: region \(index): a \(region.kind) line needs exactly two 'endpoints'")
        }
        return (points[0], points[1])
    }

    private static func canonicalRect(_ rect: RegionsInput.Rect, scale s: CGFloat) -> CanonicalRect {
        CanonicalRect(
            x: CGFloat(rect.x) / s,
            y: CGFloat(rect.y) / s,
            width: CGFloat(rect.width) / s,
            height: CGFloat(rect.height) / s
        )
    }
}
