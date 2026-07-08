import CoreGraphics
import Foundation

/// Semantic weight for exported text, mapped to a concrete font at the AppKit/SwiftUI edge.
enum ExportFontWeight: Sendable {
    case regular
    case medium
    case semibold
    case bold
}

/// Every distinct piece of text an export can draw. The layout engine measures strings by
/// role (via `TextMeasuring`) without knowing the concrete font; the renderer maps each role
/// to an `NSFont`/`Font` so measurement and drawing agree.
enum ExportFontRole: Sendable, CaseIterable {
    case calloutLabel
    case calloutPrimary
    case calloutDetail
    case legendHeader
    case legendLabel
    case legendValue
    case wordmark

    var pointSize: CGFloat {
        switch self {
        case .calloutLabel: return 10
        case .calloutPrimary: return 13
        case .calloutDetail: return 10
        case .legendHeader: return 11
        case .legendLabel: return 11
        case .legendValue: return 11
        case .wordmark: return 11
        }
    }

    var weight: ExportFontWeight {
        switch self {
        case .calloutLabel: return .semibold
        case .calloutPrimary: return .bold
        case .calloutDetail: return .regular
        case .legendHeader: return .medium
        case .legendLabel: return .semibold
        case .legendValue: return .regular
        case .wordmark: return .bold
        }
    }

    var monospacedDigit: Bool {
        switch self {
        case .calloutPrimary, .calloutDetail, .legendValue: return true
        case .calloutLabel, .legendHeader, .legendLabel, .wordmark: return false
        }
    }
}

/// The one point where the pure layout engine reaches for text metrics. The real
/// implementation lives at the AppKit edge (`NSAttributedString`); tests inject a
/// deterministic estimator so legend/pill sizing is exact.
protocol TextMeasuring: Sendable {
    func size(of string: String, role: ExportFontRole) -> CGSize
}

// MARK: - Engine input (all rects canonical; strings pre-composed by the renderer)

/// A single measurement to annotate. `rect` is canonical; strings are opaque to the engine —
/// it measures and relays them but never formats them, keeping display formatting out of Core.
struct CalloutInput: Sendable {
    var id: UUID
    var kind: MeasurementKind
    var rect: CanonicalRect
    var colorIndex: Int
    var labelText: String?
    var primaryText: String
    var detailText: String
}

struct LegendRowInput: Sendable {
    var colorIndex: Int
    var labelText: String
    var valueText: String
}

struct LegendInput: Sendable {
    var headerText: String
    var rows: [LegendRowInput]
    var wordmark: String
    /// Reserved vertical space in the footer for M6b metadata imprints. Zero for now.
    var metadataHeight: CGFloat
}

struct LayoutRequest: Sendable {
    /// Canonical crop rect of the export image. Its origin maps to export-point (0, 0).
    var cropRect: CanonicalRect
    /// Export image size in points (crop pixels ÷ scale). Drives bounds/legend placement.
    var imageSize: CGSize
    var referenceRect: CanonicalRect
    var referenceMode: ReferenceMode
    var callouts: [CalloutInput]
    var legend: LegendInput
}

// MARK: - Engine output (all geometry in export-image point coordinates, y-down, origin top-left)

struct ShapeGeometry: Sendable, Identifiable {
    var id: UUID
    var kind: MeasurementKind
    var rect: CGRect
    var colorIndex: Int
}

struct Leader: Sendable, Equatable {
    /// On the pill's edge, nearest the shape.
    var start: CGPoint
    /// On the shape, nearest the pill.
    var end: CGPoint
}

struct PlacedCallout: Sendable, Identifiable {
    var id: UUID
    var frame: CGRect
    var colorIndex: Int
    var labelText: String?
    var primaryText: String
    var detailText: String
    /// Present only when the pill is displaced away from its shape (crowded fallback).
    var leader: Leader?
}

struct LegendGeometry: Sendable {
    var frame: CGRect
    var headerText: String
    var rows: [LegendRowInput]
    var wordmark: String
    var metadataHeight: CGFloat
}

struct ExportLayout: Sendable {
    var imageSize: CGSize
    var shapes: [ShapeGeometry]
    var callouts: [PlacedCallout]
    var legend: LegendGeometry
    /// Outline the reference frame only when it isn't the whole screen.
    var referenceOutline: CGRect?
}
