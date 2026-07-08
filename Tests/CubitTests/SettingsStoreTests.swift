import XCTest
@testable import Cubit

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeSuite(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    func testDefaultsAreDocumentedValues() {
        let defaults = makeSuite("com.cubit.tests.settings.defaults")
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.defaultTool, .rectangle)
        XCTAssertEqual(settings.defaultReferenceMode, .windowUnderCursor)
        XCTAssertEqual(settings.dimOpacity, 0.15, accuracy: 0.0001)
        XCTAssertTrue(settings.showMenuBarPercent)
        XCTAssertEqual(settings.exportFormat, .png)
        XCTAssertFalse(settings.copyAfterExport)
        XCTAssertFalse(settings.imprintMachineName)
        XCTAssertFalse(settings.imprintWindowTitle)
        XCTAssertFalse(settings.imprintAppName)
        XCTAssertEqual(settings.measurementBorderWidth, 2, accuracy: 0.0001)
        XCTAssertEqual(settings.measurementFillOpacity, 0.12, accuracy: 0.0001)
        XCTAssertTrue(settings.showLabelPills)
        XCTAssertEqual(settings.labelTextSize, .medium)
        XCTAssertNil(settings.defaultExportFolderPath)
        XCTAssertNil(settings.defaultExportFolderDisplayPath)
    }

    func testPersistsToInjectedSuite() {
        let defaults = makeSuite("com.cubit.tests.settings.persist")
        let settings = SettingsStore(defaults: defaults)

        settings.defaultTool = .horizontal
        settings.defaultReferenceMode = .screen
        settings.dimOpacity = 0.3
        settings.showMenuBarPercent = false
        settings.copyAfterExport = true
        settings.measurementBorderWidth = 3
        settings.measurementFillOpacity = 0.2
        settings.showLabelPills = false
        settings.labelTextSize = .large
        let examplePath = NSTemporaryDirectory() + "example-export-folder"
        settings.defaultExportFolderPath = examplePath

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.defaultTool, .horizontal)
        XCTAssertEqual(reloaded.defaultReferenceMode, .screen)
        XCTAssertEqual(reloaded.dimOpacity, 0.3, accuracy: 0.0001)
        XCTAssertFalse(reloaded.showMenuBarPercent)
        XCTAssertTrue(reloaded.copyAfterExport)
        XCTAssertEqual(reloaded.measurementBorderWidth, 3, accuracy: 0.0001)
        XCTAssertEqual(reloaded.measurementFillOpacity, 0.2, accuracy: 0.0001)
        XCTAssertFalse(reloaded.showLabelPills)
        XCTAssertEqual(reloaded.labelTextSize, .large)
        XCTAssertEqual(reloaded.defaultExportFolderPath, examplePath)
    }

    func testDimOpacityClampsToDocumentedRange() {
        let defaults = makeSuite("com.cubit.tests.settings.clamp")
        let settings = SettingsStore(defaults: defaults)

        settings.dimOpacity = 10
        XCTAssertEqual(settings.dimOpacity, SettingsStore.dimOpacityRange.upperBound, accuracy: 0.0001)

        settings.dimOpacity = -5
        XCTAssertEqual(settings.dimOpacity, SettingsStore.dimOpacityRange.lowerBound, accuracy: 0.0001)
    }

    func testStoredOutOfRangeDimOpacityIsClampedOnLoad() {
        let defaults = makeSuite("com.cubit.tests.settings.clamp-load")
        defaults.set(0.9, forKey: SettingsStore.Keys.dimOpacity)

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.dimOpacity, SettingsStore.dimOpacityRange.upperBound, accuracy: 0.0001)
    }

    func testMeasurementBorderWidthClampsToDocumentedRange() {
        let defaults = makeSuite("com.cubit.tests.settings.borderwidth-clamp")
        let settings = SettingsStore(defaults: defaults)

        settings.measurementBorderWidth = 10
        XCTAssertEqual(settings.measurementBorderWidth, SettingsStore.measurementBorderWidthRange.upperBound, accuracy: 0.0001)

        settings.measurementBorderWidth = -1
        XCTAssertEqual(settings.measurementBorderWidth, SettingsStore.measurementBorderWidthRange.lowerBound, accuracy: 0.0001)
    }

    func testStoredOutOfRangeMeasurementBorderWidthIsClampedOnLoad() {
        let defaults = makeSuite("com.cubit.tests.settings.borderwidth-clamp-load")
        defaults.set(99.0, forKey: SettingsStore.Keys.measurementBorderWidth)

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.measurementBorderWidth, SettingsStore.measurementBorderWidthRange.upperBound, accuracy: 0.0001)
    }

    func testMeasurementFillOpacityClampsToDocumentedRange() {
        let defaults = makeSuite("com.cubit.tests.settings.fillopacity-clamp")
        let settings = SettingsStore(defaults: defaults)

        settings.measurementFillOpacity = 5
        XCTAssertEqual(settings.measurementFillOpacity, SettingsStore.measurementFillOpacityRange.upperBound, accuracy: 0.0001)

        settings.measurementFillOpacity = -1
        XCTAssertEqual(settings.measurementFillOpacity, SettingsStore.measurementFillOpacityRange.lowerBound, accuracy: 0.0001)
    }

    func testStoredOutOfRangeMeasurementFillOpacityIsClampedOnLoad() {
        let defaults = makeSuite("com.cubit.tests.settings.fillopacity-clamp-load")
        defaults.set(0.99, forKey: SettingsStore.Keys.measurementFillOpacity)

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.measurementFillOpacity, SettingsStore.measurementFillOpacityRange.upperBound, accuracy: 0.0001)
    }

    func testLabelTextSizePointSizesAreOrdered() {
        XCTAssertLessThan(LabelTextSize.small.pointSize, LabelTextSize.medium.pointSize)
        XCTAssertLessThan(LabelTextSize.medium.pointSize, LabelTextSize.large.pointSize)
    }

    func testDefaultExportFolderPathAbbreviatesWithTilde() {
        let defaults = makeSuite("com.cubit.tests.settings.export-folder")
        let settings = SettingsStore(defaults: defaults)

        settings.defaultExportFolderPath = NSHomeDirectory() + "/Desktop"
        XCTAssertEqual(settings.defaultExportFolderDisplayPath, "~/Desktop")
    }

    func testMetadataTogglesReadWriteSharedRawKeys() {
        let defaults = makeSuite("com.cubit.tests.settings.metadata")
        let settings = SettingsStore(defaults: defaults)

        settings.imprintMachineName = true
        settings.imprintWindowTitle = true

        XCTAssertTrue(defaults.bool(forKey: "export.metadata.machine"))
        XCTAssertTrue(defaults.bool(forKey: "export.metadata.window"))
        XCTAssertFalse(defaults.bool(forKey: "export.metadata.app"))
    }

    func testLaunchAtLoginIsNoOpUnderTests() {
        let defaults = makeSuite("com.cubit.tests.settings.launch")
        let settings = SettingsStore(defaults: defaults)

        // Under XCTest this must never touch the real SMAppService login item.
        settings.launchAtLogin = true
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testUnrecognizedStoredRawValuesFallBackToDefaults() {
        let defaults = makeSuite("com.cubit.tests.settings.garbage")
        defaults.set("not-a-real-tool", forKey: SettingsStore.Keys.defaultTool)
        defaults.set("not-a-real-mode", forKey: SettingsStore.Keys.defaultReferenceMode)
        defaults.set("not-a-real-format", forKey: SettingsStore.Keys.exportFormat)
        defaults.set("not-a-real-size", forKey: SettingsStore.Keys.labelTextSize)

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.defaultTool, .rectangle)
        XCTAssertEqual(settings.defaultReferenceMode, .windowUnderCursor)
        XCTAssertEqual(settings.exportFormat, .png)
        XCTAssertEqual(settings.labelTextSize, .medium)
    }
}
