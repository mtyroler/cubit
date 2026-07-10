import AppKit

/// One VoiceOver element per measurement. The overlay canvas draws its shapes rather than
/// building subviews, so without these the whole canvas is a single opaque rectangle to
/// assistive technology — a drawing on top of the Mac rather than part of it.
///
/// Modelled as `.layoutItem` inside the canvas's `.layoutArea`, which is AppKit's vocabulary for
/// "user-positionable graphic in a drawing surface" (the same roles Keynote's canvas uses).
/// That gives VoiceOver move/resize semantics for free: it drives `setAccessibilityFrame`, and
/// it announces the shape as something that can be repositioned rather than as static text.
@MainActor
final class MeasurementAccessibilityElement: NSAccessibilityElement {
    let measurementID: UUID
    private weak var canvas: OverlayCanvasView?

    /// True while the canvas is publishing geometry *to* this element, as opposed to VoiceOver
    /// writing geometry *into* it. Same setter, opposite directions.
    private var isPublishingFrame = false

    init(measurementID: UUID, canvas: OverlayCanvasView) {
        self.measurementID = measurementID
        self.canvas = canvas
        super.init()
        setAccessibilityParent(canvas)
        setAccessibilityRole(.layoutItem)
    }

    private var measurement: Measurement? {
        canvas?.session?.measurements.first { $0.id == measurementID }
    }

    override func accessibilityLabel() -> String? {
        measurement.map(MeasurementAccessibilityDescription.label(for:))
    }

    override func accessibilityValue() -> Any? {
        guard let measurement, let session = canvas?.session else { return nil }
        return MeasurementAccessibilityDescription.value(
            for: measurement,
            reference: session.reference,
            referenceMode: session.resolved.mode,
            scale: session.referenceScale
        )
    }

    override func accessibilityHelp() -> String? {
        "Press to select. Arrow keys move, Option-arrow resizes, Delete removes."
    }

    override func isAccessibilityElement() -> Bool { true }
    override func isAccessibilityEnabled() -> Bool { true }

    // MARK: Selection

    override func isAccessibilitySelected() -> Bool {
        canvas?.session?.selectedID == measurementID
    }

    override func setAccessibilitySelected(_ selected: Bool) {
        guard let canvas, let session = canvas.session else { return }
        session.select(selected ? measurementID : nil)
        canvas.refreshFromAccessibility()
    }

    override func accessibilityPerformPress() -> Bool {
        setAccessibilitySelected(true)
        return true
    }

    override func accessibilityPerformDelete() -> Bool {
        guard let canvas, let session = canvas.session else { return false }
        session.select(measurementID)
        session.deleteSelected()
        canvas.refreshFromAccessibility()
        return true
    }

    // MARK: Geometry

    /// The canvas pushing this element's current geometry down. Never treated as a move.
    func publishFrame(_ frame: NSRect) {
        isPublishingFrame = true
        setAccessibilityFrame(frame)
        isPublishingFrame = false
    }

    /// VoiceOver repositions a layout item by writing its frame (in screen coordinates). Route
    /// that back through the same undo-registering move the mouse and arrow keys use, so a
    /// VoiceOver drag is a first-class, undoable edit rather than a silent mutation.
    ///
    /// `super` runs either way: the stored frame is what VoiceOver draws its cursor around and
    /// hit-tests against, and an element that never stores one is invisible to it.
    override func setAccessibilityFrame(_ frame: NSRect) {
        super.setAccessibilityFrame(frame)
        guard !isPublishingFrame, let canvas else { return }
        canvas.moveMeasurementFromAccessibility(id: measurementID, toScreenFrame: frame)
    }
}
