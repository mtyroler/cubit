import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMeasure = Self("toggleMeasure", default: .init(.m, modifiers: [.option, .command]))
}

@MainActor
final class HotkeyManager {
    private let controller: OverlayController

    init(controller: OverlayController) {
        self.controller = controller
        KeyboardShortcuts.onKeyDown(for: .toggleMeasure) { [weak controller] in
            controller?.toggle()
        }
    }
}
