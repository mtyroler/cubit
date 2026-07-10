import Foundation

/// What VoiceOver says about a measurement. Pure string composition, like `MeasurementLabel`,
/// so the phrasing is unit-tested rather than discovered by ear.
///
/// Split label/value the way AppKit expects: the LABEL is the identity of the thing and doesn't
/// change as you drag it ("Rectangle, orange, hero"); the VALUE is what it currently measures
/// ("8.6 percent of window area, 210 by 250 points"). VoiceOver re-reads only the value when it
/// changes, so a drag doesn't re-announce the shape's name on every frame.
///
/// Every phrase is localizable and every format string is positional, because the word order
/// here does not survive translation: German puts the unit and the noun elsewhere entirely.
/// `bundle` is injectable so tests can pin a language instead of inheriting the host's.
enum MeasurementAccessibilityDescription {
    static func label(for measurement: Measurement, bundle: Bundle = .main) -> String {
        var parts = [
            kindName(measurement.kind, bundle: bundle),
            Palette.displayName(forIndex: measurement.colorIndex, bundle: bundle)
        ]
        if !measurement.label.isEmpty { parts.append(measurement.label) }
        return parts.joined(separator: listSeparator(bundle: bundle))
    }

    static func value(
        for measurement: Measurement,
        reference: CanonicalRect,
        referenceMode: ReferenceMode,
        scale: CGFloat,
        locale: Locale = .current,
        bundle: Bundle = .main
    ) -> String {
        let metrics = MeasurementEngine.metrics(for: measurement, reference: reference, scale: scale)
        let noun = referenceNoun(referenceMode, bundle: bundle)

        switch measurement.kind {
        case .rectangle:
            return format(
                "a11y.value.rectangle", "%1$@ of %2$@ area, %3$@ by %4$@",
                "Spoken size of a rectangle: percent, reference noun, width, height",
                bundle,
                spokenPercent(metrics.areaPercent, locale: locale, bundle: bundle),
                noun,
                spokenPoints(measurement.rect.width, locale: locale, bundle: bundle),
                spokenPoints(measurement.rect.height, locale: locale, bundle: bundle)
            )
        case .horizontal:
            return format(
                "a11y.value.horizontal", "%1$@ of %2$@ width, %3$@",
                "Spoken size of a horizontal line: percent, reference noun, length",
                bundle,
                spokenPercent(metrics.widthPercent, locale: locale, bundle: bundle),
                noun,
                spokenPoints(measurement.rect.width, locale: locale, bundle: bundle)
            )
        case .vertical:
            return format(
                "a11y.value.vertical", "%1$@ of %2$@ height, %3$@",
                "Spoken size of a vertical line: percent, reference noun, length",
                bundle,
                spokenPercent(metrics.heightPercent, locale: locale, bundle: bundle),
                noun,
                spokenPoints(measurement.rect.height, locale: locale, bundle: bundle)
            )
        }
    }

    /// Spoken when a measurement is added, so a VoiceOver user knows the drag produced something.
    static func addedAnnouncement(
        for measurement: Measurement,
        reference: CanonicalRect,
        referenceMode: ReferenceMode,
        scale: CGFloat,
        locale: Locale = .current,
        bundle: Bundle = .main
    ) -> String {
        format(
            "a11y.announce.added", "Added %1$@. %2$@",
            "Spoken when a measurement is drawn: its name, then what it measures",
            bundle,
            label(for: measurement, bundle: bundle),
            value(for: measurement, reference: reference, referenceMode: referenceMode, scale: scale, locale: locale, bundle: bundle)
        )
    }

    static func kindName(_ kind: MeasurementKind, bundle: Bundle = .main) -> String {
        switch kind {
        case .rectangle:
            return string("measurement.kind.rectangle", "Rectangle", "A rectangular measurement", bundle)
        case .horizontal:
            return string("measurement.kind.horizontal", "Horizontal line", "A horizontal line measurement", bundle)
        case .vertical:
            return string("measurement.kind.vertical", "Vertical line", "A vertical line measurement", bundle)
        }
    }

    static func referenceNoun(_ mode: ReferenceMode, bundle: Bundle = .main) -> String {
        switch mode {
        case .windowUnderCursor:
            return string("reference.noun.window", "window", "The thing a measurement is a percentage OF; appears mid-sentence", bundle)
        case .screen:
            return string("reference.noun.screen", "screen", "The thing a measurement is a percentage OF; appears mid-sentence", bundle)
        case .custom:
            return string("reference.noun.custom", "custom frame", "The thing a measurement is a percentage OF; appears mid-sentence", bundle)
        }
    }

    // MARK: Speech

    /// "8.6 percent", not "8.6%". Some voices read the sign as "percent sign", and a few read it
    /// as nothing at all. This is speech, so the word is spelled — the decimal separator still
    /// comes from the locale.
    private static func spokenPercent(_ value: Double, locale: Locale, bundle: Bundle) -> String {
        format(
            "a11y.value.percent", "%@ percent", "A percentage, spoken. %@ is the number, e.g. 8.6",
            bundle,
            decimal(value, locale: locale)
        )
    }

    private static func decimal(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    /// "1 point", never "1 points". English needs only the two cases; a language with richer
    /// plural rules needs a `.stringsdict`, which is why the key names are plural-ready.
    private static func spokenPoints(_ value: CGFloat, locale: Locale, bundle: Bundle) -> String {
        let whole = Int(value.rounded())
        if whole == 1 {
            return string("a11y.value.points.one", "1 point", "Exactly one point, spoken", bundle)
        }
        return format(
            "a11y.value.points.other", "%@ points", "A number of points, spoken. %@ is the count",
            bundle,
            LocalizedNumber.dimension(value, locale: locale)
        )
    }

    /// Comma-space in English. Some locales enumerate differently.
    private static func listSeparator(bundle: Bundle) -> String {
        string("a11y.label.separator", ", ", "Separates the parts of a spoken measurement name", bundle)
    }

    // MARK: Lookup

    private static func string(_ key: String, _ english: String, _ comment: String, _ bundle: Bundle) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: english, comment: comment)
    }

    private static func format(_ key: String, _ english: String, _ comment: String, _ bundle: Bundle, _ arguments: CVarArg...) -> String {
        String(format: string(key, english, comment, bundle), arguments: arguments)
    }
}
