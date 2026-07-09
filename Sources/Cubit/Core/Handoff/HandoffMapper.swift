import CoreGraphics
import Foundation

/// Validates a `HandoffDocument` and maps its canonical-point proposals to editable
/// `Measurement`s. Pure and unit-tested. The URL scheme is an external attack surface (any app or
/// webpage can open `cubit://`), so this is strict: it caps the count, rejects unknown schema
/// versions and malformed measurements, and rejects non-finite coordinates. `clamped(_:to:)`
/// then pins measurements inside the live screen bounds. Nothing here reads files, captures,
/// exports, or executes anything — it only produces shapes to draw.
enum HandoffMapper {
    /// Hard cap on proposed measurements. A document over this is rejected wholesale.
    static let maxMeasurements = 200
    /// Longest accepted label; a longer one is truncated (not rejected).
    static let maxLabelLength = 200

    enum HandoffError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
        case emptyDocument
        case tooManyMeasurements(count: Int, limit: Int)
        case invalidMeasurement(index: Int, reason: String)
    }

    /// Validates the document and returns the mapped measurements in raw canonical space
    /// (unclamped). Throws `HandoffError` on any problem so the caller can log + no-op.
    static func measurements(from document: HandoffDocument) throws -> [Measurement] {
        guard document.schemaVersion == HandoffDocument.currentSchemaVersion else {
            throw HandoffError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard !document.measurements.isEmpty else {
            throw HandoffError.emptyDocument
        }
        guard document.measurements.count <= maxMeasurements else {
            throw HandoffError.tooManyMeasurements(count: document.measurements.count, limit: maxMeasurements)
        }
        return try document.measurements.enumerated().map { index, proposed in
            try measurement(from: proposed, index: index)
        }
    }

    /// Maps one proposal. `index` seeds a default color (cycling the palette by position) and a
    /// stable error position. Coordinates are canonical points — used as-is, no scale division.
    static func measurement(from proposed: HandoffDocument.ProposedMeasurement, index: Int) throws -> Measurement {
        guard let kind = MeasurementKind(rawValue: proposed.kind) else {
            throw HandoffError.invalidMeasurement(index: index, reason: "unknown kind '\(proposed.kind)' (use rectangle, horizontal, or vertical)")
        }
        let colorIndex = normalizedColorIndex(proposed.colorIndex ?? index)
        let label = normalizedLabel(proposed.label)

        let rect: CanonicalRect
        switch kind {
        case .rectangle:
            guard let r = proposed.rect else {
                throw HandoffError.invalidMeasurement(index: index, reason: "a rectangle needs a 'rect'")
            }
            try requireFinite([r.x, r.y, r.width, r.height], index: index)
            guard r.width > 0, r.height > 0 else {
                throw HandoffError.invalidMeasurement(index: index, reason: "rectangle needs positive width and height")
            }
            rect = CanonicalRect(x: CGFloat(r.x), y: CGFloat(r.y), width: CGFloat(r.width), height: CGFloat(r.height))
        case .horizontal:
            let (a, b) = try endpoints(proposed, index: index)
            try requireFinite([a.x, a.y, b.x, b.y], index: index)
            guard abs(a.y - b.y) <= axisTolerance else {
                throw HandoffError.invalidMeasurement(index: index, reason: "a horizontal line's endpoints must share the same y")
            }
            let minX = min(a.x, b.x), maxX = max(a.x, b.x)
            guard maxX - minX > 0 else {
                throw HandoffError.invalidMeasurement(index: index, reason: "horizontal line has zero length")
            }
            rect = CanonicalRect(x: CGFloat(minX), y: CGFloat(a.y), width: CGFloat(maxX - minX), height: 0)
        case .vertical:
            let (a, b) = try endpoints(proposed, index: index)
            try requireFinite([a.x, a.y, b.x, b.y], index: index)
            guard abs(a.x - b.x) <= axisTolerance else {
                throw HandoffError.invalidMeasurement(index: index, reason: "a vertical line's endpoints must share the same x")
            }
            let minY = min(a.y, b.y), maxY = max(a.y, b.y)
            guard maxY - minY > 0 else {
                throw HandoffError.invalidMeasurement(index: index, reason: "vertical line has zero length")
            }
            rect = CanonicalRect(x: CGFloat(a.x), y: CGFloat(minY), width: 0, height: CGFloat(maxY - minY))
        }

        return Measurement(kind: kind, rect: rect, label: label, colorIndex: colorIndex)
    }

    /// Pins every measurement inside the union bounding box of the live screens, so a proposal
    /// with off-screen or oversized coordinates still lands somewhere reachable. Never throws:
    /// clamping is a safety net, not validation. A measurement whose center already sits on a
    /// screen is left untouched (agent coordinates from `list_windows` are already global-correct).
    static func clamped(_ measurements: [Measurement], to screenBounds: [CanonicalRect]) -> [Measurement] {
        guard let bounds = boundingBox(of: screenBounds) else { return measurements }
        return measurements.map { clamp($0, to: bounds) }
    }

    // MARK: - Helpers

    /// Endpoints of an axis-aligned line must share the perpendicular coordinate within this many
    /// points — a small tolerance for hand-authored JSON. Matches the CLI regions resolver.
    static let axisTolerance: Double = 0.5

    private static func endpoints(_ proposed: HandoffDocument.ProposedMeasurement, index: Int) throws -> (HandoffDocument.Point, HandoffDocument.Point) {
        guard let points = proposed.endpoints, points.count == 2 else {
            throw HandoffError.invalidMeasurement(index: index, reason: "a \(proposed.kind) line needs exactly two 'endpoints'")
        }
        return (points[0], points[1])
    }

    private static func requireFinite(_ values: [Double], index: Int) throws {
        for value in values where !value.isFinite {
            throw HandoffError.invalidMeasurement(index: index, reason: "coordinate is not finite")
        }
    }

    /// Wraps an arbitrary integer into the palette's index range (the palette itself wraps, but
    /// normalizing keeps the stored index tidy and non-negative).
    private static func normalizedColorIndex(_ index: Int) -> Int {
        let count = Palette.colors.count
        return ((index % count) + count) % count
    }

    private static func normalizedLabel(_ label: String?) -> String {
        guard let label else { return "" }
        return label.count > maxLabelLength ? String(label.prefix(maxLabelLength)) : label
    }

    private static func boundingBox(of rects: [CanonicalRect]) -> CanonicalRect? {
        guard let first = rects.first else { return nil }
        var minX = first.minX, minY = first.minY, maxX = first.maxX, maxY = first.maxY
        for rect in rects.dropFirst() {
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        return CanonicalRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func clamp(_ measurement: Measurement, to bounds: CanonicalRect) -> Measurement {
        var m = measurement
        let width = min(measurement.rect.width, bounds.width)
        let height = min(measurement.rect.height, bounds.height)
        let x = min(max(measurement.rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(measurement.rect.minY, bounds.minY), bounds.maxY - height)
        m.rect = CanonicalRect(x: x, y: y, width: width, height: height)
        return m
    }
}
