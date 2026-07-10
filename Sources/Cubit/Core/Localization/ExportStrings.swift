import Foundation

/// Every word and number format the shared render pipeline puts into an image.
///
/// Cubit renders exports from ONE implementation across three surfaces (the app, `cubit annotate`,
/// and `annotate_screenshot`), but those surfaces do not want the same language. The app must
/// follow the user's locale — a German user's exported screenshot reading "Total width" is
/// half-translated and looks broken. The agent surfaces must NOT: an MCP tool whose PNG text and
/// number formatting change with the host's region settings is not reproducible, and any agent
/// parsing the legend breaks the moment it runs somewhere else.
///
/// So the vocabulary is injected rather than looked up. `renderExport` takes whatever the app
/// hands it; `renderAnnotatedExport` pins `.englishFixed` internally and does not offer callers
/// the choice. Neither surface can get it wrong by forgetting.
struct ExportStrings: Sendable, Equatable {
    var locale: Locale

    var totalArea: String
    var totalWidth: String
    var totalHeight: String

    /// Unit abbreviation for pixel dimensions. In `ExportStrings` rather than hardcoded so a
    /// locale that abbreviates differently can, even though most do not.
    var pixels: String

    /// Positional so translators can reorder: "Measurement %@" / "Messung %@".
    var untitledMeasurementFormat: String

    var machineCaption: String
    var windowCaption: String
    var appCaption: String

    // MARK: Formatting

    func percent(_ value: Double) -> String {
        LocalizedNumber.percent(value, locale: locale)
    }

    func dimension(_ value: CGFloat) -> String {
        LocalizedNumber.dimension(value, locale: locale)
    }

    func pixelDimension(_ value: CGFloat) -> String {
        "\(dimension(value)) \(pixels)"
    }

    func untitledMeasurement(number: Int) -> String {
        untitledMeasurementFormat.replacingOccurrences(
            of: "%@",
            with: LocalizedNumber.count(number, locale: locale)
        )
    }

    // MARK: Vocabularies

    /// The agent contract. Frozen English, POSIX number formatting. Changing any of these strings
    /// changes `cubit annotate` and `annotate_screenshot` output for every caller, everywhere.
    static let englishFixed = ExportStrings(
        locale: Locale(identifier: "en_US_POSIX"),
        totalArea: "Total area",
        totalWidth: "Total width",
        totalHeight: "Total height",
        pixels: "px",
        untitledMeasurementFormat: "Measurement %@",
        machineCaption: "Machine",
        windowCaption: "Window",
        appCaption: "App"
    )

    /// The app's vocabulary, in the user's language. `bundle` is injectable so tests can point at
    /// a specific `.lproj` instead of whatever the host machine is set to.
    static func localized(locale: Locale = .current, bundle: Bundle = .main) -> ExportStrings {
        func string(_ key: String, _ english: String, _ comment: String) -> String {
            NSLocalizedString(key, tableName: nil, bundle: bundle, value: english, comment: comment)
        }

        return ExportStrings(
            locale: locale,
            totalArea: string("export.totals.area", "Total area", "Legend line summing the area of every rectangle"),
            totalWidth: string("export.totals.width", "Total width", "Legend line summing the length of every horizontal line"),
            totalHeight: string("export.totals.height", "Total height", "Legend line summing the length of every vertical line"),
            pixels: string("unit.pixels.abbreviation", "px", "Abbreviation for pixels, following a number"),
            untitledMeasurementFormat: string(
                "export.legend.untitledMeasurement",
                "Measurement %@",
                "Legend row for a measurement the user never named; %@ is its position, e.g. 3"
            ),
            machineCaption: string("export.footer.machine", "Machine", "Caption above the machine name imprint"),
            windowCaption: string("export.footer.window", "Window", "Caption above the window title imprint"),
            appCaption: string("export.footer.app", "App", "Caption above the app name imprint")
        )
    }
}
