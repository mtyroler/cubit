import AppKit
import SwiftUI

@MainActor
final class OverlayCanvasView: NSView, NSTextFieldDelegate {
    var converter: CoordinateConverter?
    var display: DisplayDescriptor?
    var session: MeasurementSession?
    var appState: AppState?
    var frozenImage: CGImage? { didSet { needsDisplay = true } }

    /// True when the user has asked the system to reduce motion; every overlay animation
    /// checks this and falls back to an instant change.
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Swaps in a snapshot that lost the capture race, cross-fading rather than popping.
    /// Nothing is drawn over the background yet at this point in a session, so fading the
    /// whole layer is exactly the right visual.
    func setFrozenImage(_ image: CGImage?, animated: Bool) {
        if animated, !Self.prefersReducedMotion, let layer {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.18
            layer.add(fade, forKey: "frozenImageFade")
        }
        frozenImage = image
    }
    /// Height of the menu-bar strip (points) to leave unfrozen at the top of this display.
    var topInset: CGFloat = 0
    /// Height of the Dock strip (points), when docked at the bottom of this display — 0 if
    /// the Dock is hidden or docked to a side. macOS renders the Dock above our maximum-level
    /// overlay, so bottom-anchored UI (the tool pill) needs to sit above it, not behind it.
    var bottomInset: CGFloat = 0 {
        didSet { layoutToolPill() }
    }
    var provider: WindowInfoProviding?
    var screenRects: [CanonicalRect] = []
    var excludedPID: pid_t = 0
    /// Dim fill alpha outside measured/drafted rects — configurable in Settings, defaults to 15%.
    var dimOpacity: CGFloat = CGFloat(SettingsStore.defaultDimOpacity)
    /// Measurement stroke width and rectangle fill alpha — configurable in Settings.
    var measurementBorderWidth: CGFloat = CGFloat(SettingsStore.defaultMeasurementBorderWidth)
    var measurementFillOpacity: CGFloat = CGFloat(SettingsStore.defaultMeasurementFillOpacity)
    var showLabelPills = true
    var labelTextSize: LabelTextSize = .medium
    var onDismiss: (() -> Void)?
    var onDraftChanged: (() -> Void)?
    var onExportSave: (() -> Void)?
    var onExportCopy: (() -> Void)?
    var exportDragProvider: (() -> NSItemProvider?)?
    var currentMetadataToggles: (() -> MetadataToggles)?
    var currentFraming: (() -> ExportFraming)?
    var onMetadataTogglesChanged: ((MetadataToggles, ExportFraming, Bool) -> Void)?

    private struct HandleTarget {
        var xEdge: RectEdge?
        var yEdge: RectEdge?
    }

    private enum HitTarget {
        case handle(UUID, HandleTarget)
        case label(UUID)
        case body(UUID)

        var id: UUID {
            switch self {
            case .handle(let id, _), .label(let id), .body(let id): return id
            }
        }
    }

    private enum DragKind {
        case move(UUID)
        case resize(UUID, HandleTarget)
    }

    private struct ActiveDrag {
        var kind: DragKind
        var edited: Bool
    }

    private var hudHost: NSHostingView<HUDView>?
    private var toolPillHost: NSHostingView<ToolPillView>?
    private var exportMenuHost: NSHostingView<ExportMenuView>?
    private var toastHost: NSHostingView<ToastView>?
    private var toastDismissWork: DispatchWorkItem?
    private var toolFlashHost: NSHostingView<ToolSwitchFlashView>?
    private var toolFlashDismissWork: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?
    private var hovering = false
    private var lastCursor: CanonicalPoint?
    private var activeDrag: ActiveDrag?
    private var lastDragPoint: CanonicalPoint?
    private var editingField: NSTextField?
    private var editingMeasurementID: UUID?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func installHUD() {
        guard let session else { return }
        let host = NSHostingView(rootView: HUDView(session: session))
        host.isHidden = true
        addSubview(host)
        hudHost = host
    }

    func installToolPill() {
        guard let session, let appState else { return }
        let view = ToolPillView(
            session: session,
            appState: appState,
            onSelectTool: { [weak self] kind in self?.selectTool(kind) },
            onCycleMode: { [weak self] in self?.cycleReferenceMode() },
            onBeginCustomFrame: { [weak self] in self?.beginCustomFrame() },
            onCycleColor: { [weak self] in self?.cycleColor() },
            onExport: { [weak self] in self?.toggleExportMenu() },
            onDismiss: { [weak self] in self?.onDismiss?() },
            onUndo: { [weak self] in self?.undo() },
            onRedo: { [weak self] in self?.redo() }
        )
        let host = NSHostingView(rootView: view)
        addSubview(host)
        toolPillHost = host
        layoutToolPill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        resolveReference(at: canonicalMouseLocation())
        layoutToolPill()
        refresh()
    }

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: CGRect) {
        drawFrozenBackground()
        drawDim()

        guard let session, let converter, let display else { return }

        drawReferenceOutline(session: session, converter: converter, display: display)
        drawCustomReference(session: session, converter: converter, display: display)

        for measurement in session.measurements {
            let color = Palette.color(forIndex: measurement.colorIndex).nsColor
            drawMeasurement(kind: measurement.kind, rect: measurement.rect, converter: converter, display: display, color: color)
            if showLabelPills { drawLabelPill(for: measurement, converter: converter, display: display, color: color) }
            if measurement.id == session.selectedID {
                drawHandles(for: measurement, converter: converter, display: display, color: color)
            }
        }
        if let rect = session.draftRect, let draft = session.draft {
            let color = Palette.color(forIndex: draft.colorIndex).nsColor
            drawMeasurement(kind: draft.kind, rect: rect, converter: converter, display: display, color: color)
        }
    }

    private func drawFrozenBackground() {
        guard let frozenImage, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let scale = display?.scale ?? (bounds.width > 0 ? CGFloat(frozenImage.width) / bounds.width : 1)
        let layout = FrozenBackgroundLayout.layout(
            imagePixelWidth: CGFloat(frozenImage.width),
            imagePixelHeight: CGFloat(frozenImage.height),
            scale: scale,
            canvasSize: bounds.size,
            topInsetPoints: topInset
        )
        guard !layout.isEmpty, let cropped = frozenImage.cropping(to: layout.sourcePixelRect) else { return }

        // The view is flipped (top-left origin); a CGImage drawn straight into it comes out
        // upside down. Invert the y-axis over the destination strip so the snapshot fills its
        // region the right way up. The menu-bar strip above `topInset` is left to the dim only,
        // so the live menu bar (always drawn on top) isn't ghosted by a frozen copy.
        let dest = layout.destPointRect
        ctx.saveGState()
        ctx.translateBy(x: 0, y: dest.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cropped, in: CGRect(x: dest.minX, y: 0, width: dest.width, height: dest.height))
        ctx.restoreGState()
    }

    private func drawDim() {
        let dim = NSBezierPath(rect: bounds)
        dim.windingRule = .evenOdd

        if let session, let converter, let display {
            for measurement in session.measurements where measurement.kind == .rectangle {
                dim.append(NSBezierPath(rect: localRect(measurement.rect, converter: converter, display: display)))
            }
            if let rect = session.draftRect, session.draft?.kind == .rectangle {
                dim.append(NSBezierPath(rect: localRect(rect, converter: converter, display: display)))
            }
        }

        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        dim.fill()
    }

    private func drawReferenceOutline(session: MeasurementSession, converter: CoordinateConverter, display: DisplayDescriptor) {
        // Screen-mode reference spans the whole display; outlining it just traces the
        // overlay edge, so only outline window/custom references that sit inside the screen.
        guard session.resolved.mode != .screen else { return }
        let frame = localRect(session.resolved.rect, converter: converter, display: display).insetBy(dx: 0.75, dy: 0.75)
        guard bounds.intersects(frame) else { return }
        let outline = NSBezierPath(rect: frame)
        outline.lineWidth = 1.5
        NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke()
        outline.stroke()
    }

    private func drawCustomReference(session: MeasurementSession, converter: CoordinateConverter, display: DisplayDescriptor) {
        let rect = session.customDraftRect ?? session.customRect
        guard let rect else { return }
        let frame = localRect(rect, converter: converter, display: display)
        guard bounds.intersects(frame) else { return }
        let path = NSBezierPath(rect: frame)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemTeal.setStroke()
        path.stroke()
    }

    private func localRect(_ rect: CanonicalRect, converter: CoordinateConverter, display: DisplayDescriptor) -> CGRect {
        let local = converter.displayLocal(rect, on: display)
        return CGRect(x: local.origin.x, y: local.origin.y, width: local.width, height: local.height)
    }

    private func drawMeasurement(kind: MeasurementKind, rect: CanonicalRect, converter: CoordinateConverter, display: DisplayDescriptor, color: NSColor) {
        let frame = localRect(rect, converter: converter, display: display)

        switch kind {
        case .rectangle:
            color.withAlphaComponent(measurementFillOpacity).setFill()
            NSBezierPath(rect: frame).fill()
            color.setStroke()
            let border = NSBezierPath(rect: frame)
            border.lineWidth = measurementBorderWidth
            border.stroke()
        case .horizontal:
            drawLine(from: CGPoint(x: frame.minX, y: frame.minY), to: CGPoint(x: frame.maxX, y: frame.minY), capAxisVertical: true, color: color)
        case .vertical:
            drawLine(from: CGPoint(x: frame.minX, y: frame.minY), to: CGPoint(x: frame.minX, y: frame.maxY), capAxisVertical: false, color: color)
        }
    }

    private func drawLine(from start: CGPoint, to end: CGPoint, capAxisVertical: Bool, color: NSColor) {
        color.setStroke()
        let line = NSBezierPath()
        line.lineWidth = measurementBorderWidth
        line.move(to: start)
        line.line(to: end)
        line.stroke()

        let half: CGFloat = 6
        for point in [start, end] {
            let cap = NSBezierPath()
            cap.lineWidth = measurementBorderWidth
            if capAxisVertical {
                cap.move(to: CGPoint(x: point.x, y: point.y - half))
                cap.line(to: CGPoint(x: point.x, y: point.y + half))
            } else {
                cap.move(to: CGPoint(x: point.x - half, y: point.y))
                cap.line(to: CGPoint(x: point.x + half, y: point.y))
            }
            cap.stroke()
        }
    }

    // MARK: Selection handles

    private func handlePositions(for measurement: Measurement, frame: CGRect) -> [(HandleTarget, CGPoint)] {
        switch measurement.kind {
        case .rectangle:
            return [
                (HandleTarget(xEdge: .minX, yEdge: .minY), CGPoint(x: frame.minX, y: frame.minY)),
                (HandleTarget(xEdge: .maxX, yEdge: .minY), CGPoint(x: frame.maxX, y: frame.minY)),
                (HandleTarget(xEdge: .maxX, yEdge: .maxY), CGPoint(x: frame.maxX, y: frame.maxY)),
                (HandleTarget(xEdge: .minX, yEdge: .maxY), CGPoint(x: frame.minX, y: frame.maxY))
            ]
        case .horizontal:
            return [
                (HandleTarget(xEdge: .minX, yEdge: nil), CGPoint(x: frame.minX, y: frame.minY)),
                (HandleTarget(xEdge: .maxX, yEdge: nil), CGPoint(x: frame.maxX, y: frame.minY))
            ]
        case .vertical:
            return [
                (HandleTarget(xEdge: nil, yEdge: .minY), CGPoint(x: frame.minX, y: frame.minY)),
                (HandleTarget(xEdge: nil, yEdge: .maxY), CGPoint(x: frame.minX, y: frame.maxY))
            ]
        }
    }

    private func drawHandles(for measurement: Measurement, converter: CoordinateConverter, display: DisplayDescriptor, color: NSColor) {
        let frame = localRect(measurement.rect, converter: converter, display: display)
        let size: CGFloat = 6
        for (_, point) in handlePositions(for: measurement, frame: frame) {
            let handleRect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: handleRect).fill()
            color.setStroke()
            let border = NSBezierPath(rect: handleRect)
            border.lineWidth = 1.5
            border.stroke()
        }
    }

    // MARK: Label pills

    private func labelString(for measurement: Measurement) -> NSAttributedString {
        guard let session else { return NSAttributedString() }
        let text = MeasurementLabel.text(for: measurement, reference: session.reference, scale: session.referenceScale)
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: CGFloat(labelTextSize.pointSize), weight: .semibold),
            .foregroundColor: Palette.color(forIndex: measurement.colorIndex).nsInkColor
        ])
    }

    private func labelPillFrame(for measurement: Measurement, converter: CoordinateConverter, display: DisplayDescriptor) -> CGRect {
        let frame = localRect(measurement.rect, converter: converter, display: display)
        let textSize = labelString(for: measurement).size()
        let padding = CGSize(width: 7, height: 4)
        let pillSize = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        return CGRect(origin: labelOrigin(for: measurement.kind, frame: frame, pillSize: pillSize), size: pillSize)
    }

    private func labelOrigin(for kind: MeasurementKind, frame: CGRect, pillSize: CGSize) -> CGPoint {
        switch kind {
        case .rectangle:
            let inset: CGFloat = 6
            if frame.height >= pillSize.height + inset * 2, frame.width >= pillSize.width + inset * 2 {
                return CGPoint(x: frame.minX + inset, y: frame.minY + inset)
            }
            return CGPoint(x: frame.minX, y: frame.minY - pillSize.height - 6)
        case .horizontal:
            return CGPoint(x: frame.midX - pillSize.width / 2, y: frame.minY - pillSize.height - 8)
        case .vertical:
            return CGPoint(x: frame.minX + 10, y: frame.midY - pillSize.height / 2)
        }
    }

    private func drawLabelPill(for measurement: Measurement, converter: CoordinateConverter, display: DisplayDescriptor, color: NSColor) {
        let pillRect = labelPillFrame(for: measurement, converter: converter, display: display)
        guard bounds.intersects(pillRect) else { return }
        let path = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)
        color.setFill()
        path.fill()
        let padding = CGSize(width: 7, height: 4)
        labelString(for: measurement).draw(at: CGPoint(x: pillRect.minX + padding.width, y: pillRect.minY + padding.height))
    }

    // MARK: Hit testing

    private func hitTest(at point: CanonicalPoint) -> HitTarget? {
        guard let session, let converter, let display else { return nil }
        let local = converter.displayLocal(point, on: display)
        let localPoint = CGPoint(x: local.x, y: local.y)

        if let selectedID = session.selectedID,
           let measurement = session.measurements.first(where: { $0.id == selectedID }) {
            let frame = localRect(measurement.rect, converter: converter, display: display)
            let radius: CGFloat = 7
            for (target, handlePoint) in handlePositions(for: measurement, frame: frame) {
                if abs(localPoint.x - handlePoint.x) <= radius, abs(localPoint.y - handlePoint.y) <= radius {
                    return .handle(measurement.id, target)
                }
            }
        }

        for measurement in session.measurements.reversed() {
            if showLabelPills, labelPillFrame(for: measurement, converter: converter, display: display).contains(localPoint) {
                return .label(measurement.id)
            }
            let bodyFrame = localRect(measurement.rect, converter: converter, display: display).insetBy(dx: -5, dy: -5)
            if bodyFrame.contains(localPoint) {
                return .body(measurement.id)
            }
        }
        return nil
    }

    // MARK: Cursor

    /// The overlay's whole bounds gets one cursor rect reflecting the active tool
    /// (or the custom-reference draw state); AppKit re-invokes this whenever a
    /// subview's own cursor rects don't claim the point, so it composes correctly
    /// with the tool pill/HUD/export menu/label-edit text field sitting on top.
    override func resetCursorRects() {
        super.resetCursorRects()

        // During an active drag, lock the whole view to the drag affordance so the cursor
        // doesn't flip back to the tool cursor as the pointer leaves the grabbed shape.
        if let drag = activeDrag {
            addCursorRect(bounds, cursor: dragCursor(for: drag.kind))
            return
        }

        addCursorRect(bounds, cursor: currentToolCursor())

        // Edit affordances layered over the tool cursor: hovering an existing measurement's
        // body / label / resize handle should read as move / click / resize, not the active
        // draw tool. Later cursor rects win where they overlap, so bodies go down first and
        // the smaller handles on top. Suppressed while placing a new measurement or the custom
        // reference — that's a draw gesture, not an edit.
        guard let session, session.draft == nil, session.customDraft == nil, !session.isDrawingCustom,
              let converter, let display else { return }

        for measurement in session.measurements {
            let body = localRect(measurement.rect, converter: converter, display: display).insetBy(dx: -5, dy: -5)
            addCursorRect(body, cursor: .openHand)
            if showLabelPills {
                addCursorRect(labelPillFrame(for: measurement, converter: converter, display: display), cursor: .pointingHand)
            }
        }

        if let selectedID = session.selectedID,
           let measurement = session.measurements.first(where: { $0.id == selectedID }) {
            let frame = localRect(measurement.rect, converter: converter, display: display)
            let radius: CGFloat = 7
            for (target, point) in handlePositions(for: measurement, frame: frame) {
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                addCursorRect(rect, cursor: resizeCursor(for: target))
            }
        }
    }

    private func currentToolCursor() -> NSCursor {
        guard let session else { return .crosshair }
        let style: CursorStyle = session.isDrawingCustom
            ? .customFrame
            : CursorStyleCatalog.style(forTool: session.tool)
        return ToolCursorFactory.cursor(for: style)
    }

    /// The edit-affordance cursor for the point under the pointer, or nil when it isn't over
    /// an editable region (caller falls back to the tool cursor). Mirrors `resetCursorRects`
    /// but resolves to a single cursor for the immediate `.set()`.
    private func editCursor() -> NSCursor? {
        guard let session else { return nil }
        if let drag = activeDrag { return dragCursor(for: drag.kind) }
        guard session.draft == nil, session.customDraft == nil, !session.isDrawingCustom,
              let lastCursor else { return nil }
        switch hitTest(at: lastCursor) {
        case .handle(_, let target): return resizeCursor(for: target)
        case .label: return .pointingHand
        case .body: return .openHand
        case .none: return nil
        }
    }

    private func dragCursor(for kind: DragKind) -> NSCursor {
        switch kind {
        case .move: return .closedHand
        case .resize(_, let target): return resizeCursor(for: target)
        }
    }

    /// Directional resize cursor for a handle: horizontal for a line endpoint that moves in x,
    /// vertical for one that moves in y, and a diagonal for a rectangle corner (both edges).
    /// The diagonal uses AppKit's private window-resize cursors when available, falling back to
    /// the horizontal resize cursor.
    private func resizeCursor(for target: HandleTarget) -> NSCursor {
        switch (target.xEdge, target.yEdge) {
        case (.some, .some(let yEdge)):
            let nwse = (target.xEdge == .minX) == (yEdge == .minY)
            return Self.diagonalResizeCursor(nwse: nwse) ?? .resizeLeftRight
        case (.some, .none):
            return .resizeLeftRight
        case (.none, .some):
            return .resizeUpDown
        case (.none, .none):
            return .openHand
        }
    }

    private static func diagonalResizeCursor(nwse: Bool) -> NSCursor? {
        let selectorName = nwse
            ? "_windowResizeNorthWestSouthEastCursor"
            : "_windowResizeNorthEastSouthWestCursor"
        let selector = NSSelectorFromString(selectorName)
        let cursorClass = NSCursor.self as AnyObject
        guard cursorClass.responds(to: selector),
              let cursor = cursorClass.perform(selector)?.takeUnretainedValue() as? NSCursor else {
            return nil
        }
        return cursor
    }

    /// Cursor rects only get re-evaluated by AppKit on the next opportunity
    /// (mouse enter, resize, …); invalidate on every state change so a tool/mode
    /// switch is reflected right away, and force it immediately if the pointer is
    /// already inside our bounds rather than waiting for the next mouse event.
    private func updateCursor() {
        window?.invalidateCursorRects(for: self)
        if hovering { (editCursor() ?? currentToolCursor()).set() }
    }

    // MARK: HUD positioning

    private func refresh() {
        needsDisplay = true
        updateHUD()
        updateCursor()
        onDraftChanged?()
    }

    private func updateHUD() {
        guard let hudHost, let session, let converter, let display else { return }

        let anchorPoint: CanonicalPoint?
        if let draft = session.draft {
            anchorPoint = draft.current
        } else if let customDraft = session.customDraft {
            anchorPoint = customDraft.current
        } else if hovering, let lastCursor {
            anchorPoint = lastCursor
        } else {
            anchorPoint = nil
        }

        guard let anchorPoint else {
            hudHost.isHidden = true
            return
        }

        hudHost.isHidden = false
        hudHost.layoutSubtreeIfNeeded()
        let size = hudHost.fittingSize
        hudHost.setFrameSize(size)

        let cursor = converter.displayLocal(anchorPoint, on: display)
        var x = cursor.x + 16
        var y = cursor.y + 16
        if bounds.width - cursor.x < 80 { x = cursor.x - 16 - size.width }
        if bounds.height - cursor.y < 80 { y = cursor.y - 16 - size.height }
        x = max(8, min(x, bounds.width - size.width - 8))
        y = max(8, min(y, bounds.height - bottomInset - size.height - 8))
        hudHost.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func layoutToolPill() {
        guard let toolPillHost else { return }
        toolPillHost.layoutSubtreeIfNeeded()
        let size = toolPillHost.fittingSize
        toolPillHost.setFrameSize(size)
        let x = (bounds.width - size.width) / 2
        // Same 24pt margin as always, measured from the visible (Dock-excluded) bottom edge
        // rather than the raw canvas bottom, so the pill sits above the Dock instead of behind
        // it. bottomInset is 0 when the Dock is hidden or docked to a side, preserving today's
        // placement exactly.
        let y = bounds.height - bottomInset - size.height - 24
        toolPillHost.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: Export menu

    private func toggleExportMenu() {
        if exportMenuHost != nil { hideExportMenu(); return }
        guard appState?.captureAvailable == true else { onExportSave?(); return }

        let view = ExportMenuView(
            onSave: { [weak self] in self?.hideExportMenu(); self?.onExportSave?() },
            onCopy: { [weak self] in self?.hideExportMenu(); self?.onExportCopy?() },
            dragProvider: { [weak self] in self?.exportDragProvider?() },
            initialToggles: currentMetadataToggles?() ?? .allOff,
            initialFraming: currentFraming?() ?? .default,
            onMetadataChange: { [weak self] toggles, framing, remember in
                self?.onMetadataTogglesChanged?(toggles, framing, remember)
            }
        )
        let host = NSHostingView(rootView: view)
        addSubview(host)
        exportMenuHost = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.setFrameSize(size)

        // Above the tool pill, right-aligned to it (the Export button sits on that side).
        let pillFrame = toolPillHost?.frame ?? CGRect(x: bounds.midX, y: bounds.height - 60, width: 0, height: 0)
        var x = pillFrame.maxX - size.width
        x = max(8, min(x, bounds.width - size.width - 8))
        let y = pillFrame.minY - size.height - 8
        host.setFrameOrigin(CGPoint(x: x, y: max(8, y)))
    }

    private func hideExportMenu() {
        exportMenuHost?.removeFromSuperview()
        exportMenuHost = nil
    }

    // MARK: Toast confirmation

    /// Redraw and refresh the edit-affordance cursors after agent-proposed measurements are
    /// injected into the session (the handoff arrives from outside the normal event flow). The
    /// selected injected measurement's handles become live immediately.
    func refreshAfterHandoff() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        if hovering { (editCursor() ?? currentToolCursor()).set() }
    }

    /// Brief confirmation ("Saved to …") near the top of the overlay, auto-dismissed. A handoff
    /// arrival uses a longer hold so the user notices the proposal.
    func showToast(_ message: String, duration: TimeInterval = 2.4) {
        toastDismissWork?.cancel()
        toastHost?.removeFromSuperview()

        let host = NSHostingView(rootView: ToastView(message: message))
        addSubview(host)
        toastHost = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.setFrameSize(size)
        host.setFrameOrigin(CGPoint(x: (bounds.width - size.width) / 2, y: 40))
        host.alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; host.animator().alphaValue = 1 }

        let work = DispatchWorkItem { [weak self, weak host] in
            guard let host else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; host.animator().alphaValue = 0 }) {
                host.removeFromSuperview()
                if self?.toastHost === host { self?.toastHost = nil }
            }
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: Tool switch flash

    /// Brief label near the cursor when the active tool/state changes (key or pill
    /// click) — fades in, holds, fades out after ~700ms. The tool pill alone is too
    /// peripheral to register a switch.
    private func showToolFlash(_ label: String) {
        toolFlashDismissWork?.cancel()
        toolFlashHost?.removeFromSuperview()

        let host = NSHostingView(rootView: ToolSwitchFlashView(label: label))
        addSubview(host)
        toolFlashHost = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.setFrameSize(size)
        host.setFrameOrigin(flashOrigin(for: size))

        host.alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; host.animator().alphaValue = 1 }

        let work = DispatchWorkItem { [weak self, weak host] in
            guard let host else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; host.animator().alphaValue = 0 }) {
                host.removeFromSuperview()
                if self?.toolFlashHost === host { self?.toolFlashHost = nil }
            }
        }
        toolFlashDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func flashOrigin(for size: CGSize) -> CGPoint {
        let anchor: CGPoint
        if hovering, let lastCursor, let converter, let display {
            let local = converter.displayLocal(lastCursor, on: display)
            anchor = CGPoint(x: local.x, y: local.y)
        } else {
            anchor = CGPoint(x: bounds.midX, y: bounds.midY)
        }

        let x = max(8, min(anchor.x + 20, bounds.width - size.width - 8))
        let y = max(8, min(anchor.y + 20, bounds.height - bottomInset - size.height - 8))
        return CGPoint(x: x, y: y)
    }

    // MARK: Tool pill actions

    private func selectTool(_ kind: MeasurementKind) {
        guard let session else { return }
        let changed = session.tool != kind || session.isDrawingCustom
        session.tool = kind
        if changed { showToolFlash(CursorStyleCatalog.flashLabel(for: CursorStyleCatalog.style(forTool: kind))) }
        refresh()
    }

    private func cycleReferenceMode() {
        guard let session else { return }
        session.cycleMode()
        resolveReference(at: hovering ? lastCursor : canonicalMouseLocation())
        refresh()
    }

    private func beginCustomFrame() {
        guard let session else { return }
        let changed = !session.isDrawingCustom
        session.beginCustomDraw()
        if changed { showToolFlash(CursorStyleCatalog.flashLabel(for: .customFrame)) }
        refresh()
    }

    /// Cycles the color of the active draft, else the selected measurement — the shape
    /// recolors live, which is its own feedback, so no flash here (unlike tool switches).
    private func cycleColor(forward: Bool = true) {
        session?.cycleColor(forward: forward)
        refresh()
    }

    private func setColor(index: Int) {
        session?.setColor(index: index)
        refresh()
    }

    // MARK: History

    /// Undo/redo can restore a different reference mode or custom rect, so the resolved
    /// reference has to be recomputed before the redraw — otherwise the HUD and every label
    /// percentage keep quoting the reference the user just undid.
    private func undo() {
        session?.undo()
        resolveReference(at: hovering ? lastCursor : canonicalMouseLocation())
        refresh()
    }

    private func redo() {
        session?.redo()
        resolveReference(at: hovering ? lastCursor : canonicalMouseLocation())
        refresh()
    }

    private func duplicateSelected() {
        guard session?.duplicateSelected() != nil else { return }
        refresh()
    }

    private func clearAll() {
        guard session?.clearAll() == true else { return }
        refresh()
    }

    private func editSelectedLabel() {
        guard let session, let measurement = session.selectedMeasurement,
              let converter, let display else { return }
        beginEditingLabel(for: measurement, converter: converter, display: display)
        refresh()
    }

    // MARK: Contextual menu

    /// Right-click is the Mac's discovery mechanism: every capability reachable by key —
    /// delete, duplicate, label, color, undo — has to be reachable here too.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let session, editingField == nil else { return nil }
        hideExportMenu()
        guard let point = canonicalLocation(of: event) else { return nil }
        lastCursor = point

        if let hit = hitTest(at: point) {
            session.select(hit.id)
            refresh()
            return measurementMenu(for: hit.id, session: session)
        }

        session.select(nil)
        refresh()
        return canvasMenu(session: session)
    }

    private func measurementMenu(for id: UUID, session: MeasurementSession) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Edit Label…", #selector(menuEditLabel)))
        menu.addItem(item("Duplicate", #selector(menuDuplicate), key: "d", modifiers: .command))
        menu.addItem(item("Delete", #selector(menuDelete), key: "\u{8}", modifiers: []))
        menu.addItem(.separator())

        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu(selectedIndex: session.selectedMeasurement?.colorIndex)
        menu.addItem(colorItem)

        menu.addItem(.separator())
        addHistoryItems(to: menu, session: session)
        return menu
    }

    private func canvasMenu(session: MeasurementSession) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addHistoryItems(to: menu, session: session)
        menu.addItem(.separator())

        for kind in [MeasurementKind.rectangle, .horizontal, .vertical] {
            let toolItem = item(toolMenuTitle(kind), #selector(menuSelectTool), key: toolMenuKey(kind), modifiers: [])
            toolItem.tag = toolMenuTag(kind)
            toolItem.state = session.tool == kind && !session.isDrawingCustom ? .on : .off
            menu.addItem(toolItem)
        }
        menu.addItem(item("Custom Reference Frame", #selector(menuBeginCustomFrame), key: "c", modifiers: []))

        menu.addItem(.separator())
        let clear = item("Clear All Measurements", #selector(menuClearAll))
        clear.isEnabled = !session.measurements.isEmpty
        menu.addItem(clear)
        menu.addItem(item("Done", #selector(menuDismiss), key: "\u{1b}", modifiers: []))
        return menu
    }

    private func addHistoryItems(to menu: NSMenu, session: MeasurementSession) {
        let undoItem = item(undoTitle("Undo", session.undoActionName), #selector(menuUndo), key: "z", modifiers: .command)
        undoItem.isEnabled = session.canUndo
        menu.addItem(undoItem)

        let redoItem = item(undoTitle("Redo", session.redoActionName), #selector(menuRedo), key: "z", modifiers: [.command, .shift])
        redoItem.isEnabled = session.canRedo
        menu.addItem(redoItem)
    }

    /// "Undo Move Measurement" when the manager knows the action, plain "Undo" when it doesn't.
    private func undoTitle(_ verb: String, _ actionName: String) -> String {
        actionName.isEmpty ? verb : "\(verb) \(actionName)"
    }

    private func colorMenu(selectedIndex: Int?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for index in Palette.colors.indices {
            let entry = item(Palette.name(forIndex: index).capitalized, #selector(menuSetColor), key: "\(index + 1)", modifiers: [])
            entry.tag = index
            entry.state = index == selectedIndex ? .on : .off
            entry.image = swatchImage(for: index)
            menu.addItem(entry)
        }
        return menu
    }

    /// SF Symbol swatch, tinted with the palette color — custom artwork is reserved for the
    /// app icon, so the menu draws `circle.fill` rather than a hand-rolled color chip.
    private func swatchImage(for index: Int) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [Palette.color(forIndex: index).nsColor]))
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: Palette.name(forIndex: index))?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }

    private func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        entry.target = self
        return entry
    }

    private func toolMenuTitle(_ kind: MeasurementKind) -> String {
        switch kind {
        case .rectangle: return "Rectangle Tool"
        case .horizontal: return "Horizontal Tool"
        case .vertical: return "Vertical Tool"
        }
    }

    private func toolMenuKey(_ kind: MeasurementKind) -> String {
        switch kind {
        case .rectangle: return "r"
        case .horizontal: return "h"
        case .vertical: return "v"
        }
    }

    private func toolMenuTag(_ kind: MeasurementKind) -> Int {
        switch kind {
        case .rectangle: return 0
        case .horizontal: return 1
        case .vertical: return 2
        }
    }

    private func toolForTag(_ tag: Int) -> MeasurementKind {
        switch tag {
        case 1: return .horizontal
        case 2: return .vertical
        default: return .rectangle
        }
    }

    @objc private func menuUndo() { undo() }
    @objc private func menuRedo() { redo() }
    @objc private func menuDuplicate() { duplicateSelected() }
    @objc private func menuClearAll() { clearAll() }
    @objc private func menuEditLabel() { editSelectedLabel() }
    @objc private func menuDismiss() { onDismiss?() }
    @objc private func menuBeginCustomFrame() { beginCustomFrame() }
    @objc private func menuSelectTool(_ sender: NSMenuItem) { selectTool(toolForTag(sender.tag)) }
    @objc private func menuSetColor(_ sender: NSMenuItem) { setColor(index: sender.tag) }

    @objc private func menuDelete() {
        guard let session, session.selectedID != nil else { return }
        session.deleteSelected()
        refresh()
    }

    // MARK: Reference resolution

    private func resolveReference(at cursor: CanonicalPoint?) {
        guard let session, let provider, let cursor else { return }
        session.resolveReference(cursor: cursor, screens: screenRects, provider: provider, excludedPID: excludedPID)
    }

    private func canonicalMouseLocation() -> CanonicalPoint? {
        guard let converter else { return nil }
        return converter.canonical(fromCocoa: NSEvent.mouseLocation)
    }

    // MARK: Label editing

    private func beginEditingLabel(for measurement: Measurement, converter: CoordinateConverter, display: DisplayDescriptor) {
        let pillFrame = labelPillFrame(for: measurement, converter: converter, display: display)
        let field = NSTextField(frame: pillFrame.insetBy(dx: -4, dy: -3))
        field.stringValue = measurement.label
        field.placeholderString = "Label"
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.bezelStyle = .roundedBezel
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        editingField = field
        editingMeasurementID = measurement.id
    }

    private func commitLabelEdit() {
        guard let session, let id = editingMeasurementID, let field = editingField else { return }
        session.setLabel(field.stringValue, for: id)
        endLabelEdit()
    }

    private func cancelLabelEdit() {
        endLabelEdit()
    }

    private func endLabelEdit() {
        editingField?.removeFromSuperview()
        editingField = nil
        editingMeasurementID = nil
        window?.makeFirstResponder(self)
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitLabelEdit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelLabelEdit()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard editingField != nil else { return }
        commitLabelEdit()
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let session else { super.keyDown(with: event); return }
        let modifiers = event.modifierFlags
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers.contains(.command) {
            switch characters {
            case "z": modifiers.contains(.shift) ? redo() : undo()
            case "d": duplicateSelected()
            case "s": hideExportMenu(); onExportSave?()
            case "c": hideExportMenu(); onExportCopy?()
            case "e": toggleExportMenu()
            default: break
            }
            return
        }

        switch event.keyCode {
        case 53: // Esc
            if exportMenuHost != nil { hideExportMenu() }
            else if session.selectedID != nil { session.select(nil); refresh() }
            else if session.isDrawingCustom { session.isDrawingCustom = false; session.customDraft = nil; refresh() }
            else if session.draft != nil { session.cancelDraft(); refresh() }
            else { onDismiss?() }
            return
        case 36, 76: // Return / keypad Enter
            if session.draft != nil { session.commitDraft(); refresh() }
            return
        case 48: // Tab — cycle reference mode
            cycleReferenceMode()
            return
        case 51, 117: // Delete / forward delete
            if session.selectedID != nil { session.deleteSelected(); refresh() }
            return
        case 123, 124, 125, 126: // arrows
            handleArrow(keyCode: event.keyCode, resize: modifiers.contains(.option), large: modifiers.contains(.shift))
            return
        default:
            break
        }

        switch characters {
        case "r": selectTool(.rectangle)
        case "h": selectTool(.horizontal)
        case "v": selectTool(.vertical)
        case "c": beginCustomFrame()
        case "x": cycleColor(forward: !modifiers.contains(.shift))
        case "1", "2", "3", "4", "5", "6", "7", "8":
            if let digit = characters.flatMap(Int.init) { setColor(index: digit - 1) }
        default: super.keyDown(with: event)
        }
    }

    private func handleArrow(keyCode: UInt16, resize: Bool, large: Bool) {
        guard let session, session.draft == nil, session.selectedID != nil else { return }
        let step: CGFloat = large ? 10 : 1

        if resize {
            switch keyCode {
            case 123: session.resizeSelected(edge: .maxX, by: -step)
            case 124: session.resizeSelected(edge: .maxX, by: step)
            case 126: session.resizeSelected(edge: .maxY, by: -step)
            case 125: session.resizeSelected(edge: .maxY, by: step)
            default: break
            }
        } else {
            switch keyCode {
            case 123: session.nudgeSelected(dx: -step, dy: 0)
            case 124: session.nudgeSelected(dx: step, dy: 0)
            case 126: session.nudgeSelected(dx: 0, dy: -step)
            case 125: session.nudgeSelected(dx: 0, dy: step)
            default: break
            }
        }

        refresh()
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        guard let session, let point = canonicalLocation(of: event) else { return }
        hovering = true
        lastCursor = point
        if session.draft == nil && session.customDraft == nil {
            resolveReference(at: point)
        }
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        guard let session, let point = canonicalLocation(of: event) else { return }
        lastCursor = point

        // A click outside the open export menu dismisses it and is otherwise swallowed.
        if let menu = exportMenuHost {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if !menu.frame.contains(viewPoint) { hideExportMenu() }
            return
        }

        if editingField != nil { commitLabelEdit() }

        if session.isDrawingCustom {
            session.beginCustomDraft(at: point)
            refresh()
            return
        }

        if let hit = hitTest(at: point) {
            switch hit {
            case .handle(let id, let target):
                session.select(id)
                activeDrag = ActiveDrag(kind: .resize(id, target), edited: false)
                lastDragPoint = point
                refresh()
                return
            case .label(let id):
                session.select(id)
                if event.clickCount >= 2,
                   let measurement = session.measurements.first(where: { $0.id == id }),
                   let converter, let display {
                    beginEditingLabel(for: measurement, converter: converter, display: display)
                    refresh()
                    return
                }
                activeDrag = ActiveDrag(kind: .move(id), edited: false)
                lastDragPoint = point
                refresh()
                return
            case .body(let id):
                session.select(id)
                activeDrag = ActiveDrag(kind: .move(id), edited: false)
                lastDragPoint = point
                refresh()
                return
            }
        }

        session.select(nil)

        // Pin the reference for the whole draft — resolve once, here.
        resolveReference(at: point)
        session.referenceScale = display?.scale ?? session.referenceScale
        session.beginDraft(at: point, constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option))
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session, let point = canonicalLocation(of: event) else { return }
        lastCursor = point

        if let drag = activeDrag {
            if !drag.edited {
                session.beginTransientEdit(actionName: Self.actionName(for: drag.kind))
                activeDrag?.edited = true
            }
            applyDrag(drag.kind, to: point, session: session)
            lastDragPoint = point
            refresh()
            return
        }

        if session.customDraft != nil {
            session.updateCustomDraft(to: point)
            refresh()
            return
        }

        session.updateDraft(to: point, constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard let session, let point = canonicalLocation(of: event) else { return }
        lastCursor = point

        if activeDrag != nil {
            activeDrag = nil
            lastDragPoint = nil
            refresh()
            return
        }

        if session.customDraft != nil {
            session.updateCustomDraft(to: point)
            session.commitCustomDraft()
            resolveReference(at: point)
            refresh()
            return
        }

        session.updateDraft(to: point, constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option))
        session.commitDraft()
        refresh()
    }

    private static func actionName(for kind: DragKind) -> String {
        switch kind {
        case .move: return "Move Measurement"
        case .resize: return "Resize Measurement"
        }
    }

    private func applyDrag(_ kind: DragKind, to point: CanonicalPoint, session: MeasurementSession) {
        guard let lastDragPoint else { return }
        let dx = point.x - lastDragPoint.x
        let dy = point.y - lastDragPoint.y

        switch kind {
        case .move(let id):
            guard let measurement = session.measurements.first(where: { $0.id == id }) else { return }
            session.updateSelectedRect(MeasurementEngine.moved(measurement.rect, dx: dx, dy: dy))
        case .resize(let id, let target):
            guard var rect = session.measurements.first(where: { $0.id == id })?.rect else { return }
            if let xEdge = target.xEdge { rect = MeasurementEngine.resized(rect, edge: xEdge, by: dx) }
            if let yEdge = target.yEdge { rect = MeasurementEngine.resized(rect, edge: yEdge, by: dy) }
            session.updateSelectedRect(rect)
        }
    }

    private func canonicalLocation(of event: NSEvent) -> CanonicalPoint? {
        guard let window, let converter else { return nil }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        return converter.canonical(fromCocoa: screenPoint)
    }
}
