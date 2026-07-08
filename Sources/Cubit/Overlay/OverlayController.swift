import AppKit

@MainActor
final class OverlayController {
    let appState = AppState()

    private let permissions = PermissionsManager()
    private let captureService = ScreenCaptureService()
    private var onboarding: OnboardingWindow?

    private var windows: [OverlayWindow] = []
    private var session: MeasurementSession?
    private var previouslyActiveApp: NSRunningApplication?
    private var presenting = false
    private var continuedWithout = false

    /// Snapshots captured at overlay entry, held until dismiss. M6's exporter consumes these.
    private(set) var capturedDisplays: [CapturedDisplay] = []

    var isPresented: Bool { !windows.isEmpty }

    func toggle() {
        if isPresented {
            dismiss()
        } else {
            present()
        }
    }

    func present() {
        guard !isPresented, !presenting else { return }

        switch permissions.entryDecision(hasContinuedWithout: continuedWithout) {
        case .showOnboarding:
            showOnboarding()
        case .presentOverlay:
            presenting = true
            Task { await presentOverlay() }
        }
    }

    private func showOnboarding() {
        let onboarding = self.onboarding ?? OnboardingWindow(permissions: permissions)
        onboarding.onGranted = { [weak self] in self?.present() }
        onboarding.onContinueWithout = { [weak self] in
            self?.continuedWithout = true
            self?.present()
        }
        self.onboarding = onboarding
        onboarding.show()
    }

    private func presentOverlay() async {
        defer { presenting = false }

        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return }

        previouslyActiveApp = NSWorkspace.shared.frontmostApplication

        let descriptors = screens.map(Self.descriptor(for:))
        let converter = CoordinateConverter(
            primaryScreenHeight: primaryHeight,
            displays: descriptors
        )

        let primaryDescriptor = descriptors[0]
        let session = MeasurementSession(
            screenReference: converter.canonicalFrame(of: primaryDescriptor),
            scale: primaryDescriptor.scale
        )
        self.session = session
        appState.draftPercent = nil

        // Kick capture before ordering windows front. Our own windows are excluded from
        // the content filter, so a snapshot that lands after presentation is still clean.
        let requests = descriptors.map {
            CaptureRequest(
                displayID: $0.id,
                canonicalFrame: converter.canonicalFrame(of: $0),
                scale: $0.scale
            )
        }
        let service = captureService
        let captureTask = Task { await service.captureAll(requests) }

        // Race the capture against a short timeout so a fast snapshot freezes the scene
        // immediately, while a slow one never delays the overlay appearing.
        let early = await Self.raceValue(of: captureTask, timeoutMillis: 300)
        let earlyDisplays = Self.displays(from: early)
        capturedDisplays = earlyDisplays
        appState.captureAvailable = !earlyDisplays.isEmpty

        buildWindows(
            screens: screens,
            descriptors: descriptors,
            converter: converter,
            session: session,
            captured: earlyDisplays
        )
        orderWindowsFront()

        // Capture didn't beat the timeout — swap the frozen background in when it lands.
        if early == nil {
            Task { @MainActor in
                let outcome = await captureTask.value
                self.applyCaptured(outcome)
            }
        }
    }

    private func buildWindows(
        screens: [NSScreen],
        descriptors: [DisplayDescriptor],
        converter: CoordinateConverter,
        session: MeasurementSession,
        captured: [CapturedDisplay]
    ) {
        let screenRects = descriptors.map(converter.canonicalFrame(of:))
        let provider = CGWindowInfoProvider()
        let excludedPID = getpid()

        for (screen, descriptor) in zip(screens, descriptors) {
            let window = OverlayWindow(contentRect: screen.frame)
            window.acceptsMouseMovedEvents = true
            let canvas = OverlayCanvasView(frame: CGRect(origin: .zero, size: screen.frame.size))
            canvas.converter = converter
            canvas.display = descriptor
            canvas.session = session
            canvas.provider = provider
            canvas.screenRects = screenRects
            canvas.excludedPID = excludedPID
            canvas.frozenImage = captured.first(where: { $0.displayID == descriptor.id })?.cgImage
            canvas.appState = appState
            canvas.onDismiss = { [weak self] in self?.dismiss() }
            canvas.onDraftChanged = { [weak self] in self?.updateAppState() }
            canvas.onExportSave = { [weak self] in self?.exportSave() }
            canvas.onExportCopy = { [weak self] in self?.exportCopy() }
            canvas.exportDragProvider = { [weak self] in self?.exportDragProvider() }
            canvas.installHUD()
            canvas.installToolPill()
            window.contentView = canvas
            window.setFrame(screen.frame, display: true)
            windows.append(window)
        }
    }

    private func orderWindowsFront() {
        for window in windows {
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.contentView)
        }
    }

    private func applyCaptured(_ outcome: CaptureOutcome) {
        guard isPresented else { return }
        let displays = Self.displays(from: outcome)
        guard !displays.isEmpty else { return }
        capturedDisplays = displays
        appState.captureAvailable = true
        for window in windows {
            guard let canvas = window.contentView as? OverlayCanvasView,
                  let id = canvas.display?.id,
                  let match = displays.first(where: { $0.displayID == id }) else { continue }
            canvas.frozenImage = match.cgImage
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
        capturedDisplays = []
        appState.draftPercent = nil
        appState.captureAvailable = false

        previouslyActiveApp?.activate()
        previouslyActiveApp = nil
    }

    // MARK: Export

    private var canExport: Bool { !capturedDisplays.isEmpty }

    private var frontCanvas: OverlayCanvasView? {
        (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.contentView as? OverlayCanvasView
    }

    private func currentExportPNG() -> Data? {
        guard let session,
              let captured = ExportRenderer.captured(for: session.resolved, in: capturedDisplays) else { return nil }
        return ExportRenderer.renderPNG(
            measurements: session.measurements,
            reference: session.resolved,
            captured: captured
        )
    }

    func exportSave() {
        guard canExport else { showOnboarding(); return }
        guard let data = currentExportPNG() else { return }
        if let url = Exporter.saveToFile(data, above: windows as [NSWindow]) {
            frontCanvas?.showToast("Saved to \(Exporter.abbreviatedPath(url))")
        }
    }

    func exportCopy() {
        guard canExport else { showOnboarding(); return }
        guard let data = currentExportPNG() else { return }
        Exporter.copyToPasteboard(data)
        frontCanvas?.showToast("Copied to clipboard")
    }

    private func exportDragProvider() -> NSItemProvider? {
        guard canExport, let data = currentExportPNG() else { return nil }
        return Exporter.dragItemProvider(data)
    }

    private func updateAppState() {
        guard let percent = session?.currentPrimaryPercent else {
            appState.draftPercent = nil
            return
        }
        appState.draftPercent = String(format: "%.1f%%", percent)
    }

    /// Returns the outcome if the capture finishes before the timeout, otherwise nil.
    /// The capture task is left running either way.
    private static func raceValue(
        of task: Task<CaptureOutcome, Never>,
        timeoutMillis: UInt64
    ) async -> CaptureOutcome? {
        await withTaskGroup(of: CaptureOutcome?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutMillis * 1_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func displays(from outcome: CaptureOutcome?) -> [CapturedDisplay] {
        if case .captured(let displays)? = outcome { return displays }
        return []
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
