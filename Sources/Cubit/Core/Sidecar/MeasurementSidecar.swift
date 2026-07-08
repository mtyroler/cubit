import CoreGraphics
import Foundation

/// A machine-readable description of an exported measurement session, written alongside the
/// PNG so an agent can parse the results without OCR. Pure data (no AppKit, no I/O): the
/// exporter builds it from the same crop/scale/reference the renderer uses, and serializes
/// it with `jsonData()`.
///
/// Coordinate contract: canonical space is CG-global (top-left origin, y-down, points).
/// The exported image's top-left corner sits at `image.cropOrigin` in canonical space, so
/// for any canonical point P: `imagePixel = (P - cropOrigin) * image.scale`. Every pixel
/// value in this document is that transform applied — values may be negative or exceed the
/// image bounds (e.g. a reference frame larger than the crop), which is intentional and
/// keeps the mapping explicit.
///
/// Privacy: this document carries no absolute paths, usernames, hostnames, or timestamps.
/// App/window names being measured are user content and may appear in `reference.name`.
struct MeasurementSidecar: Codable, Sendable, Equatable {
    /// Bumped on any breaking schema change. Readers should reject unknown major versions.
    let schemaVersion: Int
    let image: Image
    let reference: Reference
    let measurements: [Measurement]
    /// Summed totals exactly as the export's legend renders them (one line per kind, only
    /// when the export was configured to show totals). Empty otherwise.
    let totals: [String]

    struct Point: Codable, Sendable, Equatable {
        let x: Double
        let y: Double
    }

    struct Rect: Codable, Sendable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Size: Codable, Sendable, Equatable {
        let width: Double
        let height: Double
    }

    struct Image: Codable, Sendable, Equatable {
        /// Exported image dimensions in pixels.
        let pixelWidth: Int
        let pixelHeight: Int
        /// Point→pixel scale factor (a Retina display is typically 2).
        let scale: Double
        /// Canonical point of the exported image's top-left corner.
        let cropOrigin: Point
        /// Exported image dimensions in points (`pixel / scale`).
        let pointWidth: Double
        let pointHeight: Double
    }

    struct Reference: Codable, Sendable, Equatable {
        /// One of `window`, `screen`, `custom`.
        let kind: String
        /// The reference's rendered descriptor (e.g. "Safari — 1440×870"), or nil for none.
        let name: String?
        let rectPoints: Rect
        let rectPixels: Rect
    }

    struct Percentages: Codable, Sendable, Equatable {
        let width: Double
        let height: Double
        let area: Double
        /// The value the app surfaces for this kind (width% for a horizontal line, height%
        /// for a vertical line, area% for a rectangle).
        let primary: Double
    }

    struct Measurement: Codable, Sendable, Equatable {
        /// One of `rectangle`, `horizontal`, `vertical`.
        let kind: String
        let colorIndex: Int
        let colorName: String
        /// The user's label, or nil when unlabeled.
        let label: String?
        /// Primary percentage as rendered on the callout, e.g. "40.0%".
        let valueText: String
        /// Secondary detail as rendered, e.g. "200×100 px" or "800 px".
        let detailText: String
        let sizePoints: Size
        let sizePixels: Size
        let percentages: Percentages
        /// Present for rectangles; the full bounding rect.
        let rectPoints: Rect?
        let rectPixels: Rect?
        /// Present for lines; the two endpoints (start, end).
        let endpointsPoints: [Point]?
        let endpointsPixels: [Point]?
    }

    /// Deterministic, diffable serialization: keys sorted, pretty-printed.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}

extension MeasurementSidecar {
    /// Builds the sidecar from the exact crop/scale/reference the renderer used. `cropRect`
    /// is the canonical rect of the exported image (its origin is `image.cropOrigin`);
    /// `pixelWidth`/`pixelHeight` are the final integral image dimensions.
    static func make(
        measurements: [Cubit.Measurement],
        referenceRect: CanonicalRect,
        referenceMode: ReferenceMode,
        referenceName: String?,
        scale: CGFloat,
        cropRect: CanonicalRect,
        pixelWidth: Int,
        pixelHeight: Int,
        totals: [String],
        valueText: (Metrics) -> String,
        detailText: (MeasurementKind, Metrics) -> String
    ) -> MeasurementSidecar {
        let origin = cropRect.origin
        let s = Double(scale)

        func point(_ x: CGFloat, _ y: CGFloat) -> Point {
            Point(x: Double(x - origin.x) * s, y: Double(y - origin.y) * s)
        }
        func rectPx(_ r: CanonicalRect) -> Rect {
            Rect(
                x: Double(r.minX - origin.x) * s,
                y: Double(r.minY - origin.y) * s,
                width: Double(r.width) * s,
                height: Double(r.height) * s
            )
        }
        func rectPt(_ r: CanonicalRect) -> Rect {
            Rect(x: Double(r.minX), y: Double(r.minY), width: Double(r.width), height: Double(r.height))
        }

        let image = Image(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scale: s,
            cropOrigin: Point(x: Double(origin.x), y: Double(origin.y)),
            pointWidth: Double(cropRect.width),
            pointHeight: Double(cropRect.height)
        )

        let reference = Reference(
            kind: kindName(for: referenceMode),
            name: referenceName,
            rectPoints: rectPt(referenceRect),
            rectPixels: rectPx(referenceRect)
        )

        let items = measurements.map { m -> Measurement in
            let metrics = MeasurementEngine.metrics(for: m, reference: referenceRect, scale: scale)
            let r = m.rect
            let isRect = m.kind == .rectangle

            let endpointsPt: [Point]?
            let endpointsPx: [Point]?
            if isRect {
                endpointsPt = nil
                endpointsPx = nil
            } else {
                // A horizontal/vertical line's rect has one zero dimension; its endpoints are
                // the two non-degenerate corners.
                let start = (r.minX, r.minY)
                let end = m.kind == .horizontal ? (r.maxX, r.minY) : (r.minX, r.maxY)
                endpointsPt = [Point(x: Double(start.0), y: Double(start.1)), Point(x: Double(end.0), y: Double(end.1))]
                endpointsPx = [point(start.0, start.1), point(end.0, end.1)]
            }

            return Measurement(
                kind: m.kind.rawValue,
                colorIndex: m.colorIndex,
                colorName: Palette.name(forIndex: m.colorIndex),
                label: m.label.isEmpty ? nil : m.label,
                valueText: valueText(metrics),
                detailText: detailText(m.kind, metrics),
                sizePoints: Size(width: Double(r.width), height: Double(r.height)),
                sizePixels: Size(width: Double(metrics.widthPx), height: Double(metrics.heightPx)),
                percentages: Percentages(
                    width: metrics.widthPercent,
                    height: metrics.heightPercent,
                    area: metrics.areaPercent,
                    primary: metrics.primaryPercent
                ),
                rectPoints: isRect ? rectPt(r) : nil,
                rectPixels: isRect ? rectPx(r) : nil,
                endpointsPoints: endpointsPt,
                endpointsPixels: endpointsPx
            )
        }

        return MeasurementSidecar(
            schemaVersion: 1,
            image: image,
            reference: reference,
            measurements: items,
            totals: totals
        )
    }

    private static func kindName(for mode: ReferenceMode) -> String {
        switch mode {
        case .windowUnderCursor: return "window"
        case .screen: return "screen"
        case .custom: return "custom"
        }
    }
}
