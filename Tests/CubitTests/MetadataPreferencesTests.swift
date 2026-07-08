import XCTest
@testable import Cubit

final class MetadataPreferencesTests: XCTestCase {
    private func freshSuite() -> UserDefaults {
        let name = "com.cubit.tests.metadata.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAllTogglesDefaultFalseOnFreshSuite() {
        let preferences = MetadataPreferences(defaults: freshSuite())
        XCTAssertFalse(preferences.machineEnabled)
        XCTAssertFalse(preferences.windowEnabled)
        XCTAssertFalse(preferences.appEnabled)
        XCTAssertEqual(preferences.toggles, .allOff)
    }

    func testSaveRoundTripsAllThreeToggles() {
        let preferences = MetadataPreferences(defaults: freshSuite())
        preferences.save(MetadataToggles(machine: true, window: false, app: true))
        XCTAssertTrue(preferences.machineEnabled)
        XCTAssertFalse(preferences.windowEnabled)
        XCTAssertTrue(preferences.appEnabled)
    }

    func testIndividualToggleWritesIndependently() {
        let preferences = MetadataPreferences(defaults: freshSuite())
        preferences.windowEnabled = true
        XCTAssertEqual(preferences.toggles, MetadataToggles(machine: false, window: true, app: false))
    }
}
