import Foundation

/// What VoiceOver says about a measurement. Pure string composition, like `MeasurementLabel`,
/// so the phrasing is unit-tested rather than discovered by ear.
///
/// Split label/value the way AppKit expects: the LABEL is the identity of the thing and doesn't
/// change as you drag it ("Rectangle, orange, hero"); the VALUE is what it currently measures
/// ("8.6 percent of window area, 210 by 250 points"). VoiceOver re-reads only the value when it
/// changes, so a drag doesn't re-announce the shape's name on every frame.
enum MeasurementAccessibilityDescription {
    static func label(for measurement: Measurement) -> String {
        var parts = [kindName(measurement.kind), Palette.name(forIndex: measurement.colorIndex)]
        if !measurement.label.isEmpty { parts.append(measurement.label) }
        return parts.joined(separator: ", ")
    }

    static func value(
        for measurement: Measurement,
        reference: CanonicalRect,
        referenceMode: ReferenceMode,
        scale: CGFloat
    ) -> String {
        let metrics = MeasurementEngine.metrics(for: measurement, reference: reference, scale: scale)
        let noun = referenceNoun(referenceMode)

        switch measurement.kind {
        case .rectangle:
            return "\(percent(metrics.areaPercent)) of \(noun) area, "
                + "\(points(measurement.rect.width)) by \(points(measurement.rect.height))"
        case .horizontal:
            return "\(percent(metrics.widthPercent)) of \(noun) width, \(points(measurement.rect.width))"
        case .vertical:
            return "\(percent(metrics.heightPercent)) of \(noun) height, \(points(measurement.rect.height))"
        }
    }

    /// Spoken when a measurement is added, so a VoiceOver user knows the drag produced something.
    static func addedAnnouncement(for measurement: Measurement, reference: CanonicalRect, referenceMode: ReferenceMode, scale: CGFloat) -> String {
        "Added \(label(for: measurement)). \(value(for: measurement, reference: reference, referenceMode: referenceMode, scale: scale))"
    }

    static func kindName(_ kind: MeasurementKind) -> String {
        switch kind {
        case .rectangle: return "Rectangle"
        case .horizontal: return "Horizontal line"
        case .vertical: return "Vertical line"
        }
    }

    static func referenceNoun(_ mode: ReferenceMode) -> String {
        switch mode {
        case .windowUnderCursor: return "window"
        case .screen: return "screen"
        case .custom: return "custom frame"
        }
    }

    /// Speech, not display: "8.6 percent" rather than "8.6%", which VoiceOver renders as
    /// "8.6 percent sign" in some voices. One decimal place matches the on-screen label.
    private static func percent(_ value: Double) -> String {
        "\(rounded(value, places: 1)) percent"
    }

    /// "1 point" / "210 points" — the unit is spoken, and singular is not "1 points".
    private static func points(_ value: CGFloat) -> String {
        let whole = Int(value.rounded())
        return whole == 1 ? "1 point" : "\(whole) points"
    }

    private static func rounded(_ value: Double, places: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(places)f", value)
    }
}
