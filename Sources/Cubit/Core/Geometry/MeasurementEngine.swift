import CoreGraphics

struct Metrics: Equatable, Sendable {
    var kind: MeasurementKind
    var widthPx: CGFloat
    var heightPx: CGFloat
    var areaPx: CGFloat
    var widthPercent: Double
    var heightPercent: Double
    var areaPercent: Double

    var lengthPx: CGFloat {
        switch kind {
        case .horizontal: return widthPx
        case .vertical: return heightPx
        case .rectangle: return 0
        }
    }

    var primaryPercent: Double {
        switch kind {
        case .horizontal: return widthPercent
        case .vertical: return heightPercent
        case .rectangle: return areaPercent
        }
    }
}

enum RectEdge: Equatable, Sendable {
    case minX
    case maxX
    case minY
    case maxY
}

enum MeasurementEngine {
    static func metrics(kind: MeasurementKind, rect: CanonicalRect, reference: CanonicalRect, scale: CGFloat) -> Metrics {
        let widthPx = rect.width * scale
        let heightPx = rect.height * scale
        return Metrics(
            kind: kind,
            widthPx: widthPx,
            heightPx: heightPx,
            areaPx: widthPx * heightPx,
            widthPercent: percent(rect.width, of: reference.width),
            heightPercent: percent(rect.height, of: reference.height),
            areaPercent: percent(rect.area, of: reference.area)
        )
    }

    static func metrics(for measurement: Measurement, reference: CanonicalRect, scale: CGFloat) -> Metrics {
        metrics(kind: measurement.kind, rect: measurement.rect, reference: reference, scale: scale)
    }

    static func draftRect(
        anchor: CanonicalPoint,
        current: CanonicalPoint,
        kind: MeasurementKind,
        constrain: Bool,
        fromCenter: Bool
    ) -> CanonicalRect {
        var dx = current.x - anchor.x
        var dy = current.y - anchor.y

        switch kind {
        case .horizontal:
            dy = 0
        case .vertical:
            dx = 0
        case .rectangle:
            if constrain {
                let side = max(abs(dx), abs(dy))
                dx = dx < 0 ? -side : side
                dy = dy < 0 ? -side : side
            }
        }

        if fromCenter {
            let halfWidth = abs(dx)
            let halfHeight = abs(dy)
            return CanonicalRect(
                x: anchor.x - halfWidth,
                y: anchor.y - halfHeight,
                width: 2 * halfWidth,
                height: 2 * halfHeight
            )
        }

        return CanonicalRect(
            x: min(anchor.x, anchor.x + dx),
            y: min(anchor.y, anchor.y + dy),
            width: abs(dx),
            height: abs(dy)
        )
    }

    static func moved(_ rect: CanonicalRect, dx: CGFloat, dy: CGFloat) -> CanonicalRect {
        CanonicalRect(x: rect.origin.x + dx, y: rect.origin.y + dy, width: rect.width, height: rect.height)
    }

    static func resized(_ rect: CanonicalRect, edge: RectEdge, by delta: CGFloat) -> CanonicalRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch edge {
        case .minX: minX += delta
        case .maxX: maxX += delta
        case .minY: minY += delta
        case .maxY: maxY += delta
        }

        return CanonicalRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private static func percent(_ value: CGFloat, of total: CGFloat) -> Double {
        guard total > 0 else { return 0 }
        return Double(value / total) * 100
    }

    /// Rectangle drags with one near-zero dimension are unambiguously line gestures
    /// (e.g. a fast/imprecise drag with the rectangle tool) — committing them as a
    /// 0%-area rectangle is a footgun, so they're reclassified as the corresponding
    /// line kind with the thin axis zeroed. Non-rectangle kinds and rectangles that
    /// aren't both thin and long enough pass through unchanged.
    static let thinDimensionThreshold: CGFloat = 4
    static let minLineLength: CGFloat = 20

    static func classifyForCommit(kind: MeasurementKind, rect: CanonicalRect) -> (kind: MeasurementKind, rect: CanonicalRect) {
        guard kind == .rectangle else { return (kind, rect) }
        let minDim = min(rect.width, rect.height)
        let maxDim = max(rect.width, rect.height)
        guard minDim < thinDimensionThreshold, maxDim >= minLineLength else { return (kind, rect) }

        if rect.height > rect.width {
            return (.vertical, CanonicalRect(x: rect.origin.x, y: rect.origin.y, width: 0, height: rect.height))
        }
        return (.horizontal, CanonicalRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: 0))
    }
}
