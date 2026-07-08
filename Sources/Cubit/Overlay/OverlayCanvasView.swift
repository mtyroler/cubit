import AppKit
import SwiftUI

@MainActor
final class OverlayCanvasView: NSView {
    var converter: CoordinateConverter?
    var display: DisplayDescriptor?
    var session: MeasurementSession?
    var onDismiss: (() -> Void)?
    var onDraftChanged: (() -> Void)?

    private var hudHost: NSHostingView<HUDView>?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func installHUD() {
        guard let session else { return }
        let host = NSHostingView(rootView: HUDView(session: session))
        host.isHidden = true
        addSubview(host)
        hudHost = host
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: CGRect) {
        drawDim()

        guard let session, let converter, let display else { return }

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
        guard let draft = session.draft else {
            hudHost.isHidden = true
            return
        }
        hudHost.isHidden = false
        hudHost.layoutSubtreeIfNeeded()
        let size = hudHost.fittingSize
        hudHost.setFrameSize(size)

        let cursor = converter.displayLocal(draft.current, on: display)
        var x = cursor.x + 16
        var y = cursor.y + 16
        if bounds.width - cursor.x < 80 { x = cursor.x - 16 - size.width }
        if bounds.height - cursor.y < 80 { y = cursor.y - 16 - size.height }
        x = max(8, min(x, bounds.width - size.width - 8))
        y = max(8, min(y, bounds.height - size.height - 8))
        hudHost.setFrameOrigin(CGPoint(x: x, y: y))
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
            if session.draft != nil { session.cancelDraft(); refresh() } else { onDismiss?() }
            return
        case 36, 76: // Return / keypad Enter
            if session.draft != nil { session.commitDraft(); refresh() }
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

    override func mouseDown(with event: NSEvent) {
        guard let session, let converter, let display, let point = canonicalLocation(of: event) else { return }
        session.reference = converter.canonicalFrame(of: display)
        session.referenceScale = display.scale
        session.beginDraft(at: point, constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option))
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session, let point = canonicalLocation(of: event) else { return }
        session.updateDraft(to: point, constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard let session, let point = canonicalLocation(of: event) else { return }
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
