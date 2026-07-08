import AppKit

@MainActor
final class OverlayController {
    let appState = AppState()

    private var windows: [OverlayWindow] = []
    private var session: MeasurementSession?
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

        let primaryDescriptor = Self.descriptor(for: screens[0])
        let session = MeasurementSession(
            reference: converter.canonicalFrame(of: primaryDescriptor),
            scale: primaryDescriptor.scale
        )
        self.session = session
        appState.draftPercent = nil

        for screen in screens {
            let descriptor = Self.descriptor(for: screen)
            let window = OverlayWindow(contentRect: screen.frame)
            let canvas = OverlayCanvasView(frame: CGRect(origin: .zero, size: screen.frame.size))
            canvas.converter = converter
            canvas.display = descriptor
            canvas.session = session
            canvas.onDismiss = { [weak self] in self?.dismiss() }
            canvas.onDraftChanged = { [weak self] in self?.updateAppState() }
            canvas.installHUD()
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
        session = nil
        appState.draftPercent = nil

        previouslyActiveApp?.activate()
        previouslyActiveApp = nil
    }

    private func updateAppState() {
        guard let percent = session?.currentPrimaryPercent else {
            appState.draftPercent = nil
            return
        }
        appState.draftPercent = String(format: "%.1f%%", percent)
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
