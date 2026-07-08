import AppKit

@MainActor
final class OverlayCanvasView: NSView {
    var converter: CoordinateConverter?
    var onDismiss: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: CGRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        dirtyRect.fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        _ = canonicalLocation(of: event)
    }

    override func mouseDragged(with event: NSEvent) {
        _ = canonicalLocation(of: event)
    }

    override func mouseUp(with event: NSEvent) {
        _ = canonicalLocation(of: event)
    }

    private func canonicalLocation(of event: NSEvent) -> CanonicalPoint? {
        guard let window, let converter else { return nil }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        return converter.canonical(fromCocoa: screenPoint)
    }
}
