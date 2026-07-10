import AppKit

@MainActor
final class OverlayController {
    let appState = AppState()

    private let settings: SettingsStore
    private let permissions = PermissionsManager()
    private let captureService = ScreenCaptureService()
    private var onboarding: OnboardingWindow?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private var windows: [OverlayWindow] = []
    private var session: MeasurementSession?
    private var previouslyActiveApp: NSRunningApplication?
    private var presenting = false
    private var continuedWithout = false

    /// Canonical frames of the screens the current overlay spans; used to clamp an incoming
    /// handoff into reachable bounds. Set when the overlay presents, cleared on dismiss.
    private var canonicalScreenRects: [CanonicalRect] = []
    /// A handoff that arrived while the overlay wasn't presented yet — injected once
    /// `presentOverlay()` has built the session and windows, and only while it's still fresh.
    /// Discarded when the user dismisses the permission gate. See `PendingHandoff`.
    private var pendingHandoff: PendingHandoff?

    /// Snapshots captured at overlay entry, held until dismiss. M6's exporter consumes these.
    private(set) var capturedDisplays: [CapturedDisplay] = []

    /// Persisted ("Remembered") metadata toggles — off by default. M6b.
    private let metadataPreferences = MetadataPreferences()
    /// Persisted ("Remembered") export framing — window-only, shadow on, by default.
    private let layoutPreferences = ExportLayoutPreferences()
    /// One-shot overrides from the current export panel session; cleared after each export
    /// so the following export reverts to the persisted defaults.
    private var pendingMetadataToggles: MetadataToggles?
    private var pendingFraming: ExportFraming?

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
        // Closing the gate is a refusal, not a deferral: drop any queued agent proposal so it can
        // never surface later over unrelated content.
        onboarding.onDismiss = { [weak self] in self?.pendingHandoff = nil }
        // Tell the user WHY the gate appeared when an agent, not the hotkey, triggered it.
        onboarding.pendingHandoffCount = pendingHandoff?.measurements.count
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
        canonicalScreenRects = descriptors.map(converter.canonicalFrame(of:))

        let primaryDescriptor = descriptors[0]
        let session = MeasurementSession(
            screenReference: converter.canonicalFrame(of: primaryDescriptor),
            scale: primaryDescriptor.scale,
            mode: settings.defaultReferenceMode
        )
        session.tool = settings.defaultTool
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

        // A handoff queued before the overlay existed injects now that the session and windows do —
        // but only if the agent asked recently. This overlay may have been opened by the user's
        // hotkey long afterwards, over unrelated content, with no agent involved.
        if let pending = pendingHandoff {
            pendingHandoff = nil
            if pending.isFresh(now: Date()) {
                injectHandoff(pending.measurements, note: pending.note)
            } else {
                FileHandle.standardError.write(Data(
                    "Cubit: discarding a stale agent handoff (older than \(Int(PendingHandoff.maxAge))s)\n".utf8
                ))
            }
        }

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
            canvas.dimOpacity = CGFloat(settings.dimOpacity)
            canvas.measurementBorderWidth = CGFloat(settings.measurementBorderWidth)
            canvas.measurementFillOpacity = CGFloat(settings.measurementFillOpacity)
            canvas.showLabelPills = settings.showLabelPills
            canvas.labelTextSize = settings.labelTextSize
            canvas.frozenImage = captured.first(where: { $0.displayID == descriptor.id })?.cgImage
            // Top inset = this screen's menu-bar height; excluded from the frozen draw so the
            // live menu bar (rendered above the overlay) isn't ghosted by a frozen copy.
            canvas.topInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            // Bottom inset = this screen's Dock height when docked at the bottom (0 if hidden
            // or docked to a side) — macOS renders the Dock above our maximum-level overlay,
            // so bottom-anchored UI (the tool pill) needs to sit above it, not behind it.
            canvas.bottomInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
            canvas.appState = appState
            canvas.onDismiss = { [weak self] in self?.dismiss() }
            canvas.onDraftChanged = { [weak self] in self?.updateAppState() }
            canvas.onExportSave = { [weak self] in self?.exportSave() }
            canvas.onExportCopy = { [weak self] in self?.exportCopy() }
            canvas.exportDragProvider = { [weak self] in self?.exportDragProvider() }
            canvas.currentMetadataToggles = { [weak self] in self?.effectiveMetadataToggles ?? .allOff }
            canvas.currentFraming = { [weak self] in self?.effectiveFraming ?? .default }
            canvas.onMetadataTogglesChanged = { [weak self] toggles, framing, remember in
                guard let self else { return }
                self.pendingMetadataToggles = toggles
                self.pendingFraming = framing
                if remember {
                    self.metadataPreferences.save(toggles)
                    self.layoutPreferences.save(framing)
                }
            }
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
        canonicalScreenRects = []
        appState.draftPercent = nil
        appState.captureAvailable = false

        previouslyActiveApp?.activate()
        previouslyActiveApp = nil
    }

    // MARK: Handoff (live-overlay, M4)

    /// Entry point for an agent's live-overlay handoff. The measurements are already validated +
    /// mapped from the `cubit://` document by Core (`HandoffMapper`); this presents the overlay if
    /// needed and injects them as editable shapes. If the overlay is already open, they're injected
    /// into the current session rather than tearing it down. `note` is an optional agent message
    /// surfaced in the arrival toast.
    func handleHandoff(_ proposed: [Measurement], note: String?) {
        guard !proposed.isEmpty else { return }
        if isPresented {
            injectHandoff(proposed, note: note)
        } else {
            pendingHandoff = PendingHandoff(measurements: proposed, note: note, queuedAt: Date())
            present()
        }
    }

    private func injectHandoff(_ proposed: [Measurement], note: String?) {
        guard let session else { return }
        // Clamp into the live screen bounds so an off-screen or oversized proposal stays reachable.
        let bounds = canonicalScreenRects.isEmpty ? [session.reference] : canonicalScreenRects
        let clamped = HandoffMapper.clamped(proposed, to: bounds)
        guard session.injectProposed(clamped) else { return }

        // The session is shared across every screen's canvas — redraw them all (a measurement may
        // land on any display), and surface the arrival toast on the front one.
        for window in windows {
            (window.contentView as? OverlayCanvasView)?.refreshAfterHandoff()
        }
        frontCanvas?.showToast(Self.handoffMessage(count: clamped.count, note: note), duration: 4.5)
        updateAppState()
    }

    private static func handoffMessage(count: Int, note: String?) -> String {
        let plural = count == 1 ? "" : "s"
        if let note, !note.isEmpty {
            return "\(note) — \(count) proposed, adjust or ⌘E to export"
        }
        return "Agent proposed \(count) measurement\(plural) — adjust or ⌘E to export"
    }

    // MARK: Export

    private var canExport: Bool { !capturedDisplays.isEmpty }

    private var frontCanvas: OverlayCanvasView? {
        (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.contentView as? OverlayCanvasView
    }

    /// The toggles that would apply to an export started right now: a pending panel
    /// selection if one exists, otherwise the persisted ("Remembered") defaults.
    private var effectiveMetadataToggles: MetadataToggles {
        pendingMetadataToggles ?? metadataPreferences.toggles
    }

    /// The framing that would apply to an export started right now: a pending panel
    /// selection if one exists, otherwise the persisted ("Remembered") default.
    private var effectiveFraming: ExportFraming {
        pendingFraming ?? layoutPreferences.framing
    }

    private func currentExport() async -> ExportRenderer.RenderedExport? {
        guard let session,
              let captured = ExportRenderer.captured(for: session.resolved, in: capturedDisplays) else { return nil }
        let reference = session.resolved
        let toggles = effectiveMetadataToggles
        let framing = effectiveFraming
        // One-shot: the next export reverts to the persisted defaults unless this
        // selection was "Remembered", in which case that's now the persisted default too.
        pendingMetadataToggles = nil
        pendingFraming = nil

        // Exact-window export: capture the window's own occlusion-free pixels so a window
        // stacked on top of the target doesn't bleed into the crop. Falls back (nil) to the
        // display-snapshot crop if the capture fails. Context/screen/custom keep the snapshot.
        var windowImage: CGImage?
        if reference.mode == .windowUnderCursor,
           !framing.includeContext,
           let windowID = reference.window?.windowID {
            windowImage = await captureService.captureWindow(windowID: CGWindowID(windowID))
        }

        let metadata = MetadataCollector.collect(toggles: toggles, reference: reference, captured: captured)
        let markup = MarkupStyle(
            borderWidth: CGFloat(settings.measurementBorderWidth),
            fillOpacity: CGFloat(settings.measurementFillOpacity),
            labelPointSize: CGFloat(settings.labelTextSize.pointSize)
        )
        return ExportRenderer.renderExport(
            measurements: session.measurements,
            reference: reference,
            captured: captured,
            includeContext: framing.includeContext,
            windowShadow: framing.windowShadow,
            metadata: metadata,
            markup: markup,
            windowImage: windowImage,
            showTotals: framing.showTotals,
            background: framing.background
        )
    }

    func exportSave() {
        guard canExport else { showOnboarding(); return }
        Task { @MainActor in
            guard let export = await currentExport() else { return }
            let directoryURL = Exporter.resolvedSaveDirectory(forPath: settings.defaultExportFolderPath)
            if let url = Exporter.saveToFile(export.png, above: windows as [NSWindow], directoryURL: directoryURL) {
                // The sidecar rides alongside a file save only, and never blocks the image:
                // a failure to write it is swallowed inside `writeSidecar`.
                if settings.writeJSONSidecar {
                    Exporter.writeSidecar(export.sidecar, besideImageAt: url)
                }
                frontCanvas?.showToast("Saved to \(Exporter.abbreviatedPath(url))")
            }
        }
    }

    func exportCopy() {
        guard canExport else { showOnboarding(); return }
        Task { @MainActor in
            guard let export = await currentExport() else { return }
            Exporter.copyToPasteboard(export.png)
            frontCanvas?.showToast("Copied to clipboard")
        }
    }

    private func exportDragProvider() -> NSItemProvider? {
        guard canExport else { return nil }
        return Exporter.dragItemProvider { [weak self] in
            await self?.currentExport()?.png
        }
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
