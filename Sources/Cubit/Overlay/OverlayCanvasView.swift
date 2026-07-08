import AppKit
import SwiftUI

@MainActor
final class OverlayCanvasView: NSView {
    var converter: CoordinateConverter?
    var display: DisplayDescriptor?
    var session: MeasurementSession?
    var provider: WindowInfoProviding?
    var screenRects: [CanonicalRect] = []
    var excludedPID: pid_t = 0
    var onDismiss: (() -> Void)?
    var onDraftChanged: (() -> Void)?

    private var hudHost: NSHostingView<HUDView>?
    private var trackingArea: NSTrackingArea?
    private var hovering = false
    private var lastCursor: CanonicalPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func installHUD() {
        guard let session else { return }
        let host = NSHostingView(rootView: HUDView(session: session))
        host.isHidden = true
        addSubview(host)
        hudHost = host
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        resolveReference(at: canonicalMouseLocation())
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
        drawDim()

        guard let session, let converter, let display else { return }

        drawReferenceOutline(session: session, converter: converter, display: display)
        drawCustomReference(session: session, converter: converter, display: display)

        for measurement in session.measurements {
            drawMeasurement(kind: measurement.kind, rect: measurement.rect, converter: converter, display: display, active: false)
        }
        if let rect = session.draftRect, let draft = session.draft {
            drawMeasurement(kind: draft.kind, rect: rect, converter: converter, display: display, active: true)
        }
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

    private func drawMeasurement(kind: MeasurementKind, rect: CanonicalRect, converter: CoordinateConverter, display: DisplayDescriptor, active: Bool) {
        let frame = localRect(rect, converter: converter, display: display)
        let color = NSColor.controlAccentColor

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

    // MARK: Reference resolution

    private func resolveReference(at cursor: CanonicalPoint?) {
        guard let session, let provider, let cursor else { return }
        session.resolveReference(cursor: cursor, screens: screenRects, provider: provider, excludedPID: excludedPID)
    }

    private func canonicalMouseLocation() -> CanonicalPoint? {
        guard let converter else { return nil }
        return converter.canonical(fromCocoa: NSEvent.mouseLocation)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let session else { super.keyDown(with: event); return }
        let modifiers = event.modifierFlags
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers.contains(.command) {
            if characters == "z" { session.undo(); refresh() }
            return
        }

        switch event.keyCode {
        case 53: // Esc
            if session.isDrawingCustom { session.isDrawingCustom = false; session.customDraft = nil; refresh() }
            else if session.draft != nil { session.cancelDraft(); refresh() }
            else { onDismiss?() }
            return
        case 36, 76: // Return / keypad Enter
            if session.draft != nil { session.commitDraft(); refresh() }
            return
        case 48: // Tab — cycle reference mode
            session.cycleMode()
            resolveReference(at: hovering ? lastCursor : canonicalMouseLocation())
            refresh()
            return
        case 123, 124, 125, 126: // arrows
            handleArrow(keyCode: event.keyCode, resize: modifiers.contains(.option), large: modifiers.contains(.shift))
            return
        default:
            break
        }

        switch characters {
        case "r": session.tool = .rectangle; refresh()
        case "h": session.tool = .horizontal; refresh()
        case "v": session.tool = .vertical; refresh()
        case "c": session.beginCustomDraw(); refresh()
        default: super.keyDown(with: event)
        }
    }

    private func handleArrow(keyCode: UInt16, resize: Bool, large: Bool) {
        guard let session, session.draft == nil, !session.measurements.isEmpty else { return }
        let step: CGFloat = large ? 10 : 1
        let index = session.measurements.count - 1
        var measurement = session.measurements[index]

        if resize {
            switch keyCode {
            case 123: measurement.rect = MeasurementEngine.resized(measurement.rect, edge: .maxX, by: -step)
            case 124: measurement.rect = MeasurementEngine.resized(measurement.rect, edge: .maxX, by: step)
            case 126: measurement.rect = MeasurementEngine.resized(measurement.rect, edge: .maxY, by: -step)
            case 125: measurement.rect = MeasurementEngine.resized(measurement.rect, edge: .maxY, by: step)
            default: break
            }
        } else {
            switch keyCode {
            case 123: measurement.rect = MeasurementEngine.moved(measurement.rect, dx: -step, dy: 0)
            case 124: measurement.rect = MeasurementEngine.moved(measurement.rect, dx: step, dy: 0)
            case 126: measurement.rect = MeasurementEngine.moved(measurement.rect, dx: 0, dy: -step)
            case 125: measurement.rect = MeasurementEngine.moved(measurement.rect, dx: 0, dy: step)
            default: break
            }
        }

        session.measurements[index] = measurement
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

        if session.isDrawingCustom {
            session.beginCustomDraft(at: point)
            refresh()
            return
        }

        // Pin the reference for the whole draft — resolve once, here.
        resolveReference(at: point)
        session.referenceScale = display?.scale ?? session.referenceScale
        session.beginDraft(at: point, constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option))
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session, let point = canonicalLocation(of: event) else { return }
        lastCursor = point

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

    private func canonicalLocation(of event: NSEvent) -> CanonicalPoint? {
        guard let window, let converter else { return nil }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        return converter.canonical(fromCocoa: screenPoint)
    }
}
