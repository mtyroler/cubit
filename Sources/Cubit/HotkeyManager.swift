import Foundation
import Carbon.HIToolbox

private func cubitHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

@MainActor
final class HotkeyManager {
    static let defaultsKey = "hotkey.toggleMeasure"

    private static let signature: OSType = 0x43424954 // 'CBIT'
    static let defaultKeyCode = UInt32(kVK_ANSI_M)
    static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)

    private let controller: OverlayController
    private let defaults: UserDefaults
    private let hotKeyID = EventHotKeyID(signature: signature, id: 1)
    /// Whether to actually touch Carbon's global hotkey registry — tests inject a fake
    /// controller and a scratch UserDefaults suite but should never register a live
    /// system-wide shortcut.
    private let registersLiveHotkey: Bool

    private(set) var keyCode: UInt32
    private(set) var carbonModifiers: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(controller: OverlayController, defaults: UserDefaults = .standard, registersLiveHotkey: Bool = true) {
        self.controller = controller
        self.defaults = defaults
        self.registersLiveHotkey = registersLiveHotkey
        let stored = Self.storedBinding(defaults: defaults)
        self.keyCode = stored?.keyCode ?? Self.defaultKeyCode
        self.carbonModifiers = stored?.modifiers ?? Self.defaultModifiers
        guard registersLiveHotkey else { return }
        installEventHandler()
        register()
    }

    func rebind(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        persistBinding()
        guard registersLiveHotkey else { return }
        register()
    }

    /// Restores the shipped default (⌃⌥⌘M).
    func resetToDefault() {
        rebind(keyCode: Self.defaultKeyCode, carbonModifiers: Self.defaultModifiers)
    }

    func handleHotKey(id: UInt32) {
        guard id == hotKeyID.id else { return }
        controller.toggle()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            cubitHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func register() {
        unregister()
        RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func persistBinding() {
        defaults.set(
            ["keyCode": Int(keyCode), "carbonModifiers": Int(carbonModifiers)],
            forKey: Self.defaultsKey
        )
    }

    private static func storedBinding(defaults: UserDefaults) -> (keyCode: UInt32, modifiers: UInt32)? {
        guard let dict = defaults.dictionary(forKey: defaultsKey),
              let keyCode = dict["keyCode"] as? Int,
              let modifiers = dict["carbonModifiers"] as? Int else {
            return nil
        }
        return (UInt32(keyCode), UInt32(modifiers))
    }
}
