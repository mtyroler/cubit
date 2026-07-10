import XCTest
@testable import Cubit

/// Guards the catalogs themselves. Translations rot silently: a key gets added in English, the
/// other four files never hear about it, and the app quietly shows English to a French user — or
/// worse, shows the raw key. Nothing else in the build notices.
@MainActor
final class LocalizationCatalogTests: XCTestCase {
    /// Every language Cubit ships. `en` is deliberately absent from `Localizable.strings`: dotted
    /// keys carry an English `value:` in code, and SwiftUI's keys ARE the English strings.
    private let translatedLanguages = ["de", "fr", "es", "ja"]

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "\(language).lproj is missing from the app bundle"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    private func strings(for language: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            bundle(for: language).path(forResource: "Localizable", ofType: "strings"),
            "\(language) has no Localizable.strings"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testAppBundleAdvertisesEveryShippedLanguage() {
        let advertised = Set(Bundle.main.localizations)
        for language in translatedLanguages + ["en"] {
            XCTAssertTrue(advertised.contains(language), "\(language) is not among \(advertised.sorted())")
        }
    }

    /// The one that actually catches drift: all four catalogs must define exactly the same keys.
    /// A key added to German and forgotten in Japanese fails here, not in front of a user.
    func testEveryCatalogDefinesTheSameKeys() throws {
        let reference = Set(try strings(for: "de").keys)
        XCTAssertGreaterThan(reference.count, 100, "the German catalog looks suspiciously empty")

        for language in translatedLanguages.dropFirst() {
            let keys = Set(try strings(for: language).keys)
            XCTAssertEqual(
                keys.symmetricDifference(reference), [],
                "\(language) is out of sync with de — missing or extra keys"
            )
        }
    }

    func testNoTranslationIsEmptyOrLeftAsItsKey() throws {
        for language in translatedLanguages {
            for (key, value) in try strings(for: language) {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): \(key) is empty")
                // A dotted key echoed back as its own value means someone pasted the key in.
                XCTAssertFalse(value.hasPrefix("a11y."), "\(language): \(key) still holds a key, not a translation")
                XCTAssertFalse(value.hasPrefix("menu."), "\(language): \(key) still holds a key, not a translation")
            }
        }
    }

    /// Positional specifiers must survive translation: if English says `%1$@ … %2$@`, so must
    /// every translation, or `String(format:)` reads the wrong argument — or crashes.
    func testFormatSpecifiersSurviveTranslation() throws {
        let positional = ["a11y.value.rectangle": 4, "a11y.value.horizontal": 3, "a11y.value.vertical": 3,
                          "a11y.announce.added": 2, "toast.handoff.withNote": 2, "menu.undoWithAction": 2]

        for language in translatedLanguages {
            let table = try strings(for: language)
            for (key, count) in positional {
                let value = try XCTUnwrap(table[key], "\(language) is missing \(key)")
                for index in 1...count {
                    XCTAssertTrue(
                        value.contains("%\(index)$@"),
                        "\(language): \(key) drops %\(index)$@ — String(format:) would read the wrong argument"
                    )
                }
            }
        }
    }

    func testSingleArgumentFormatsKeepTheirPlaceholder() throws {
        let single = ["a11y.value.percent", "a11y.announce.undid", "a11y.announce.deleted",
                      "toast.saved", "export.legend.untitledMeasurement"]
        for language in translatedLanguages {
            let table = try strings(for: language)
            for key in single {
                let value = try XCTUnwrap(table[key], "\(language) is missing \(key)")
                XCTAssertTrue(value.contains("%@"), "\(language): \(key) lost its %@ placeholder")
            }
        }
    }

    // MARK: plural rules

    /// `.stringsdict` is the only thing that can express plural categories. A ternary in Swift
    /// gets Russian and Arabic wrong; these three strings go through the real machinery.
    func testCountBasedStringsUsePluralRulesNotATernary() throws {
        let cases: [(String, String)] = [
            ("a11y.announce.cleared", "Cleared %d measurements"),
            ("toast.restored", "Restored %d measurements — ⌘Z to clear"),
            ("toast.handoff", "Agent proposed %d measurements — adjust or ⌘E to export")
        ]

        for (key, english) in cases {
            let format = NSLocalizedString(key, tableName: nil, bundle: .main, value: english, comment: "")
            let one = String(format: format, locale: Locale(identifier: "en"), 1)
            let many = String(format: format, locale: Locale(identifier: "en"), 5)

            XCTAssertFalse(one.contains("1 measurements"), "singular is wrong: \(one)")
            XCTAssertTrue(one.contains("1 measurement"), one)
            XCTAssertTrue(many.contains("5 measurements"), many)
        }
    }

    func testGermanPluralsAreDistinctForOneAndMany() throws {
        let path = try XCTUnwrap(bundle(for: "de").path(forResource: "Localizable", ofType: "stringsdict"))
        XCTAssertNotNil(NSDictionary(contentsOfFile: path), "German stringsdict is unreadable")

        let format = try bundle(for: "de").localizedString(forKey: "a11y.announce.cleared", value: "", table: nil)
        let one = String(format: format, locale: Locale(identifier: "de"), 1)
        let many = String(format: format, locale: Locale(identifier: "de"), 5)
        XCTAssertEqual(one, "1 Messung gelöscht")
        XCTAssertEqual(many, "5 Messungen gelöscht")
    }

    // MARK: the export vocabulary, in a real language

    func testLocalizedExportVocabularyPicksUpTheGermanCatalog() throws {
        let strings = ExportStrings.localized(locale: Locale(identifier: "de_DE"), bundle: try bundle(for: "de"))
        XCTAssertEqual(strings.totalArea, "Gesamtfläche")
        XCTAssertEqual(strings.totalWidth, "Gesamtbreite")
        XCTAssertEqual(strings.machineCaption, "Gerät")
        XCTAssertEqual(strings.untitledMeasurement(number: 3), "Messung 3")
        XCTAssertTrue(strings.percent(20.0).hasPrefix("20,0"), strings.percent(20.0))
    }

    /// The whole point of the boundary: the app's vocabulary moved, the agent's did not.
    func testTheAgentVocabularyIsUnmovedByAnyCatalog() {
        XCTAssertEqual(ExportStrings.englishFixed.totalArea, "Total area")
        XCTAssertEqual(ExportStrings.englishFixed.percent(20.0), "20.0%")
    }

    func testPaletteDisplayNamesTranslateWhileSlugsDoNot() throws {
        let german = try bundle(for: "de")
        XCTAssertEqual(Palette.displayName(forIndex: 1, bundle: german), "Himmelblau")
        XCTAssertEqual(Palette.name(forIndex: 1), "sky blue", "the sidecar contract must never move")
    }

    func testSpokenMeasurementTranslates() throws {
        let german = try bundle(for: "de")
        let measurement = Cubit.Measurement(
            kind: .rectangle,
            rect: CanonicalRect(x: 0, y: 0, width: 500, height: 200),
            colorIndex: 1
        )
        XCTAssertEqual(MeasurementAccessibilityDescription.label(for: measurement, bundle: german), "Rechteck, Himmelblau")

        let value = MeasurementAccessibilityDescription.value(
            for: measurement,
            reference: CanonicalRect(x: 0, y: 0, width: 1000, height: 1000),
            referenceMode: .screen,
            scale: 2,
            locale: Locale(identifier: "de_DE"),
            bundle: german
        )
        XCTAssertEqual(value, "10,0 Prozent der Bildschirm-Fläche, 500 Punkte mal 200 Punkte")
    }
}
