import Foundation

/// Pure composition of the text shown on a committed measurement's persistent
/// label pill: the live primary percent (area% for rects, length% for lines)
/// against the current reference, plus an optional user label.
enum MeasurementLabel {
    static func text(for measurement: Measurement, reference: CanonicalRect, scale: CGFloat) -> String {
        let metrics = MeasurementEngine.metrics(for: measurement, reference: reference, scale: scale)
        let percent = String(format: "%.1f%%", metrics.primaryPercent)
        return measurement.label.isEmpty ? percent : "\(percent) · \(measurement.label)"
    }
}
