import AppKit

@MainActor
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var previouslyActiveApp: NSRunningApplication?

    var isPresented: Bool { !windows.isEmpty }

    func toggle() {
        if isPresented {
            dismiss()
        } else {
            present()
        }
    }

    func present() {
        guard !isPresented else { return }

        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return }

        previouslyActiveApp = NSWorkspace.shared.frontmostApplication

        let converter = CoordinateConverter(
            primaryScreenHeight: primaryHeight,
            displays: screens.map(Self.descriptor(for:))
        )

        for screen in screens {
            let window = OverlayWindow(contentRect: screen.frame)
            let canvas = OverlayCanvasView(frame: CGRect(origin: .zero, size: screen.frame.size))
            canvas.converter = converter
            canvas.onDismiss = { [weak self] in self?.dismiss() }
            window.contentView = canvas
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)

        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.contentView)
        }
    }

    func dismiss() {
        guard isPresented else { return }

        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()

        previouslyActiveApp?.activate()
        previouslyActiveApp = nil
    }

    private static func descriptor(for screen: NSScreen) -> DisplayDescriptor {
        let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID ?? 0
        return DisplayDescriptor(
            id: displayID,
            cocoaFrame: screen.frame,
            scale: screen.backingScaleFactor
        )
    }
}
