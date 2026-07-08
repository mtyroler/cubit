import AppKit
import SwiftUI

@MainActor
final class OverlayCanvasView: NSView, NSTextFieldDelegate {
    var converter: CoordinateConverter?
    var display: DisplayDescriptor?
    var session: MeasurementSession?
    var appState: AppState?
    var frozenImage: CGImage? { didSet { needsDisplay = true } }
    var provider: WindowInfoProviding?
    var screenRects: [CanonicalRect] = []
    var excludedPID: pid_t = 0
    var onDismiss: (() -> Void)?
    var onDraftChanged: (() -> Void)?
    var onExportSave: (() -> Void)?
    var onExportCopy: (() -> Void)?
    var exportDragProvider: (() -> NSItemProvider?)?

    private struct HandleTarget {
        var xEdge: RectEdge?
        var yEdge: RectEdge?
    }

    private enum HitTarget {
        case handle(UUID, HandleTarget)
        case label(UUID)
        case body(UUID)
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
            onExport: { [weak self] in self?.toggleExportMenu() },
            onDismiss: { [weak self] in self?.onDismiss?() }
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
            drawLabelPill(for: measurement, converter: converter, display: display, color: color)
            if measurement.id == session.selectedID {
                drawHandles(for: measurement, converter: converter, display: display, color: color)
            }
        }
        if let rect = session.draftRect, let draft = session.draft {
            drawMeasurement(kind: draft.kind, rect: rect, converter: converter, display: display, color: .controlAccentColor)
        }
    }

    private func drawFrozenBackground() {
        guard let frozenImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        // The view is flipped (top-left origin); a CGImage drawn straight into it comes out
        // upside down. Invert the y-axis over the view's own bounds before drawing so the
        // snapshot fills this display's canvas the right way up.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(frozenImage, in: CGRect(origin: .zero, size: bounds.size))
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

        NSColor.black.withAlphaComponent(0.15).setFill()
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
            color.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: frame).fill()
            color.setStroke()
            let border = NSBezierPath(rect: frame)
            border.lineWidth = 2
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
        line.lineWidth = 2
        line.move(to: start)
        line.line(to: end)
        line.stroke()

        let half: CGFloat = 6
        for point in [start, end] {
            let cap = NSBezierPath()
            cap.lineWidth = 2
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
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
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
            if labelPillFrame(for: measurement, converter: converter, display: display).contains(localPoint) {
                return .label(measurement.id)
            }
            let bodyFrame = localRect(measurement.rect, converter: converter, display: display).insetBy(dx: -5, dy: -5)
            if bodyFrame.contains(localPoint) {
                return .body(measurement.id)
            }
        }
        return nil
    }

    // MARK: HUD positioning

    private func refresh() {
        needsDisplay = true
        updateHUD()
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
        y = max(8, min(y, bounds.height - size.height - 8))
        hudHost.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func layoutToolPill() {
        guard let toolPillHost else { return }
        toolPillHost.layoutSubtreeIfNeeded()
        let size = toolPillHost.fittingSize
        toolPillHost.setFrameSize(size)
        let x = (bounds.width - size.width) / 2
        let y = bounds.height - size.height - 24
        toolPillHost.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: Export menu

    private func toggleExportMenu() {
        if exportMenuHost != nil { hideExportMenu(); return }
        guard appState?.captureAvailable == true else { onExportSave?(); return }

        let view = ExportMenuView(
            onSave: { [weak self] in self?.hideExportMenu(); self?.onExportSave?() },
            onCopy: { [weak self] in self?.hideExportMenu(); self?.onExportCopy?() },
            dragProvider: { [weak self] in self?.exportDragProvider?() }
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

    /// Brief confirmation ("Saved to …") near the top of the overlay, auto-dismissed.
    func showToast(_ message: String) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    // MARK: Tool pill actions

    private func selectTool(_ kind: MeasurementKind) {
        session?.tool = kind
        refresh()
    }

    private func cycleReferenceMode() {
        guard let session else { return }
        session.cycleMode()
        resolveReference(at: hovering ? lastCursor : canonicalMouseLocation())
        refresh()
    }

    private func beginCustomFrame() {
        session?.beginCustomDraw()
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
            case "z": session.undo(); refresh()
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
            if !drag.edited { session.beginTransientEdit(); activeDrag?.edited = true }
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
