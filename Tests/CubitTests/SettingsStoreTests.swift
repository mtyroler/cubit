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
    }

    func testPersistsToInjectedSuite() {
        let defaults = makeSuite("com.cubit.tests.settings.persist")
        let settings = SettingsStore(defaults: defaults)

        settings.defaultTool = .horizontal
        settings.defaultReferenceMode = .screen
        settings.dimOpacity = 0.3
        settings.showMenuBarPercent = false
        settings.copyAfterExport = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.defaultTool, .horizontal)
        XCTAssertEqual(reloaded.defaultReferenceMode, .screen)
        XCTAssertEqual(reloaded.dimOpacity, 0.3, accuracy: 0.0001)
        XCTAssertFalse(reloaded.showMenuBarPercent)
        XCTAssertTrue(reloaded.copyAfterExport)
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

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.defaultTool, .rectangle)
        XCTAssertEqual(settings.defaultReferenceMode, .windowUnderCursor)
        XCTAssertEqual(settings.exportFormat, .png)
    }
}
