import XCTest
@testable import Cubit

/// Cubit renders exports from one implementation across three surfaces, and they do not want the
/// same language. The app follows the user's locale; `cubit annotate` and `annotate_screenshot`
/// are pinned to English so their output stays reproducible and parseable. These tests hold that
/// line — it is exactly the kind of boundary that erodes silently.
@MainActor
final class LocalizationBoundaryTests: XCTestCase {
    private let german = Locale(identifier: "de_DE")
    private let french = Locale(identifier: "fr_FR")
    private let english = Locale(identifier: "en_US")

    // MARK: numbers follow the locale

    func testPercentUsesTheLocaleDecimalSeparator() {
        XCTAssertEqual(LocalizedNumber.percent(10.0, locale: english), "10.0%")

        // German writes a comma, and a non-breaking space before the sign.
        let germanPercent = LocalizedNumber.percent(10.0, locale: german)
        XCTAssertTrue(germanPercent.hasPrefix("10,0"), germanPercent)
        XCTAssertFalse(germanPercent.contains("10.0"), germanPercent)
    }

    func testPercentDoesNotMultiplyAValueAlreadyOnAHundredScale() {
        // Cubit's metrics are 0...100 already; the formatter's default ×100 would render 1000%.
        XCTAssertEqual(LocalizedNumber.percent(10.0, locale: english), "10.0%")
        XCTAssertEqual(LocalizedNumber.percent(100.0, locale: english), "100.0%")
    }

    /// `1512×886` is a dimension, not a quantity. Grouping separators would read as two numbers.
    func testDimensionsNeverGroupDigits() {
        XCTAssertEqual(LocalizedNumber.dimension(1512, locale: english), "1512")
        XCTAssertEqual(LocalizedNumber.dimension(1512, locale: german), "1512")
        XCTAssertEqual(LocalizedNumber.dimension(1512, locale: french), "1512")
    }

    func testCountsDoGroupDigits() {
        XCTAssertEqual(LocalizedNumber.count(1512, locale: english), "1,512")
    }

    func testDimensionRoundsRatherThanTruncates() {
        XCTAssertEqual(LocalizedNumber.dimension(199.6, locale: english), "200")
    }

    // MARK: the agent contract is frozen English

    func testEnglishFixedVocabularyIsExactlyWhatAgentsParse() {
        let strings = ExportStrings.englishFixed
        XCTAssertEqual(strings.percent(10.0), "10.0%")
        XCTAssertEqual(strings.dimension(1512), "1512")
        XCTAssertEqual(strings.pixelDimension(1512), "1512 px")
        XCTAssertEqual(strings.untitledMeasurement(number: 3), "Measurement 3")
        XCTAssertEqual(strings.totalArea, "Total area")
        XCTAssertEqual(strings.totalWidth, "Total width")
        XCTAssertEqual(strings.totalHeight, "Total height")
        XCTAssertEqual(strings.machineCaption, "Machine")
        XCTAssertEqual(strings.windowCaption, "Window")
        XCTAssertEqual(strings.appCaption, "App")
    }

    /// `en_US_POSIX` rather than `en_US`: the agent contract must not move when Apple revises
    /// the region's formatting, and must not follow the host's regional overrides.
    func testEnglishFixedIsPinnedToPOSIXNotTheHostLocale() {
        XCTAssertEqual(ExportStrings.englishFixed.locale.identifier, "en_US_POSIX")
    }

    /// The renderer's text helpers default to the frozen vocabulary, so a surface that forgets
    /// to pass one gets the agent contract rather than the host's language.
    func testRendererTextHelpersDefaultToEnglish() {
        let metrics = MeasurementEngine.metrics(
            kind: .rectangle,
            rect: CanonicalRect(x: 0, y: 0, width: 500, height: 200),
            reference: CanonicalRect(x: 0, y: 0, width: 1000, height: 1000),
            scale: 2
        )
        XCTAssertEqual(ExportRenderer.primaryText(metrics), "10.0%")
        XCTAssertEqual(ExportRenderer.detailText(kind: .rectangle, metrics: metrics), "1000×400 px")
    }

    func testTotalsLinesUseTheInjectedVocabulary() {
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 1000)
        let measurements = [
            Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 500, height: 200), colorIndex: 0),
            Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 500, height: 200), colorIndex: 1)
        ]

        let englishTotals = ExportRenderer.measurementTotals(measurements, reference: reference, scale: 2)
        XCTAssertEqual(englishTotals, ["Total area  ·  20.0%"])

        var germanish = ExportStrings.englishFixed
        germanish.locale = german
        germanish.totalArea = "Gesamtfläche"
        let germanTotals = ExportRenderer.measurementTotals(measurements, reference: reference, scale: 2, strings: germanish)
        XCTAssertEqual(germanTotals.count, 1)
        XCTAssertTrue(germanTotals[0].hasPrefix("Gesamtfläche"), germanTotals[0])
        XCTAssertTrue(germanTotals[0].contains("20,0"), germanTotals[0])
    }

    // MARK: the app follows the user

    func testMeasurementLabelFollowsTheLocale() {
        let measurement = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 500, height: 200), colorIndex: 0)
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 1000)

        XCTAssertEqual(MeasurementLabel.text(for: measurement, reference: reference, scale: 2, locale: english), "10.0%")
        XCTAssertTrue(MeasurementLabel.text(for: measurement, reference: reference, scale: 2, locale: german).hasPrefix("10,0"))
    }

    func testMeasurementLabelKeepsTheUserLabelUntranslated() {
        let measurement = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 500, height: 200), label: "hero", colorIndex: 0)
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertEqual(MeasurementLabel.text(for: measurement, reference: reference, scale: 2, locale: english), "10.0% · hero")
    }

    func testSpokenValueFollowsTheLocaleDecimalSeparator() {
        let measurement = Cubit.Measurement(kind: .rectangle, rect: CanonicalRect(x: 0, y: 0, width: 500, height: 200), colorIndex: 0)
        let reference = CanonicalRect(x: 0, y: 0, width: 1000, height: 1000)
        let spoken = MeasurementAccessibilityDescription.value(
            for: measurement, reference: reference, referenceMode: .screen, scale: 2, locale: german
        )
        XCTAssertTrue(spoken.contains("10,0"), spoken)
    }

    // MARK: palette — stable slugs vs display names

    /// These eight strings are written into every JSON sidecar and read by `cubit` and
    /// `cubit-mcp`. Translating or re-wording them breaks every consumer, silently.
    func testColorSlugsAreFrozen() {
        XCTAssertEqual(
            Palette.colorNames,
            ["orange", "sky blue", "bluish green", "yellow", "blue", "vermillion", "reddish purple", "gray"]
        )
        XCTAssertEqual(Palette.name(forIndex: 1), "sky blue")
    }

    func testDisplayNamesAreSeparateFromSlugsAndTitleCased() {
        XCTAssertEqual(Palette.displayName(forIndex: 1), "Sky Blue")
        XCTAssertNotEqual(Palette.displayName(forIndex: 1), Palette.name(forIndex: 1))
    }

    func testDisplayNamesWrapAndHandleNegativeIndicesLikeSlugs() {
        XCTAssertEqual(Palette.displayName(forIndex: 8), Palette.displayName(forIndex: 0))
        XCTAssertEqual(Palette.displayName(forIndex: -1), Palette.displayName(forIndex: 7))
    }

    /// A bundle with no strings table — which is exactly what the `cubit` and `cubit-mcp`
    /// executables carry — must yield the English wording rather than the raw key.
    func testMissingStringsTableFallsBackToEnglishNotTheKey() {
        let empty = Bundle(for: LocalizationBoundaryTests.self)
        let name = Palette.displayName(forIndex: 3, bundle: empty)
        XCTAssertEqual(name, "Yellow")
        XCTAssertFalse(name.hasPrefix("palette.color."), "a missing key must never leak into the UI")
    }

    func testLocalizedVocabularyFallsBackToEnglishWordingWithoutATable() {
        let strings = ExportStrings.localized(locale: english, bundle: Bundle(for: LocalizationBoundaryTests.self))
        XCTAssertEqual(strings.totalArea, "Total area")
        XCTAssertEqual(strings.untitledMeasurementFormat, "Measurement %@")
    }
}
