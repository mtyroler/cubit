import Foundation

/// Pure composition of the text shown on a committed measurement's persistent
/// label pill: the live primary percent (area% for rects, length% for lines)
/// against the current reference, plus an optional user label.
enum MeasurementLabel {
    /// This pill is drawn on the user's own screen, so it follows the user's locale — unlike the
    /// exported image's text, whose vocabulary is injected (see `ExportStrings`).
    static func text(
        for measurement: Measurement,
        reference: CanonicalRect,
        scale: CGFloat,
        locale: Locale = .current
    ) -> String {
        let metrics = MeasurementEngine.metrics(for: measurement, reference: reference, scale: scale)
        let percent = LocalizedNumber.percent(metrics.primaryPercent, locale: locale)
        return measurement.label.isEmpty ? percent : "\(percent) · \(measurement.label)"
    }
}
