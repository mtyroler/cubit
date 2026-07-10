import Foundation

/// Locale-correct number formatting. Every percentage and dimension in Cubit used to go through
/// `String(format: "%.1f%%")`, which hardcodes the period as the decimal separator and the
/// percent sign as a trailing suffix. In German that should read `10,0 %` — comma, and a
/// non-breaking space before the sign. For a measurement app, formatting numbers wrong is not a
/// cosmetic problem.
enum LocalizedNumber {
    /// A percentage that is ALREADY on a 0...100 scale (Cubit's metrics are), so the formatter's
    /// multiplier is pinned to 1 rather than the default 100.
    static func percent(_ value: Double, fractionDigits: Int = 1, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.multiplier = 1
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f%%", value)
    }

    /// A whole-number dimension in points or pixels. Grouping separators are suppressed on
    /// purpose: `1512×886` is a dimension, not a quantity, and `1,512×886` reads as two numbers.
    /// The formatter still applies the locale's digits, which is the part that matters for
    /// locales that don't use Western Arabic numerals.
    static func dimension(_ value: CGFloat, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: Int(value.rounded()))) ?? "\(Int(value.rounded()))"
    }

    /// A counted quantity ("3 measurements"), where grouping IS wanted.
    static func count(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
