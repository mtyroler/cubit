import XCTest
import Carbon.HIToolbox
@testable import Cubit

@MainActor
final class HotkeyManagerTests: XCTestCase {
    private func makeSuite(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    /// `registersLiveHotkey: false` keeps these tests from touching Carbon's global
    /// hotkey registry — only the persistence/state side is under test.
    private func makeManager(defaults: UserDefaults) -> HotkeyManager {
        let controller = OverlayController(settings: SettingsStore(defaults: defaults))
        return HotkeyManager(controller: controller, defaults: defaults, registersLiveHotkey: false)
    }

    func testLoadsShippedDefaultWhenNothingStored() {
        let defaults = makeSuite("com.cubit.tests.hotkey.default")
        let manager = makeManager(defaults: defaults)

        XCTAssertEqual(manager.keyCode, HotkeyManager.defaultKeyCode)
        XCTAssertEqual(manager.carbonModifiers, HotkeyManager.defaultModifiers)
    }

    func testRebindUpdatesStateAndPersists() {
        let defaults = makeSuite("com.cubit.tests.hotkey.rebind")
        let manager = makeManager(defaults: defaults)

        let newKeyCode = UInt32(kVK_ANSI_K)
        let newModifiers = UInt32(controlKey | cmdKey)
        manager.rebind(keyCode: newKeyCode, carbonModifiers: newModifiers)

        XCTAssertEqual(manager.keyCode, newKeyCode)
        XCTAssertEqual(manager.carbonModifiers, newModifiers)

        let stored = defaults.dictionary(forKey: HotkeyManager.defaultsKey)
        XCTAssertEqual(stored?["keyCode"] as? Int, Int(newKeyCode))
        XCTAssertEqual(stored?["carbonModifiers"] as? Int, Int(newModifiers))
    }

    func testRebindPersistsAcrossReinitialization() {
        let defaults = makeSuite("com.cubit.tests.hotkey.reinit")
        let manager = makeManager(defaults: defaults)
        manager.rebind(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey))

        let reloaded = makeManager(defaults: defaults)
        XCTAssertEqual(reloaded.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(reloaded.carbonModifiers, UInt32(cmdKey | optionKey))
    }

    func testResetToDefaultRestoresShippedBinding() {
        let defaults = makeSuite("com.cubit.tests.hotkey.reset")
        let manager = makeManager(defaults: defaults)
        manager.rebind(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey))

        manager.resetToDefault()

        XCTAssertEqual(manager.keyCode, HotkeyManager.defaultKeyCode)
        XCTAssertEqual(manager.carbonModifiers, HotkeyManager.defaultModifiers)

        let stored = defaults.dictionary(forKey: HotkeyManager.defaultsKey)
        XCTAssertEqual(stored?["keyCode"] as? Int, Int(HotkeyManager.defaultKeyCode))
        XCTAssertEqual(stored?["carbonModifiers"] as? Int, Int(HotkeyManager.defaultModifiers))
    }
}
