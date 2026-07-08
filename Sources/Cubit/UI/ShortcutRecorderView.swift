import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A hand-rolled shortcut recorder (zero third-party deps): click to arm, type the next
/// combo, Esc to cancel. Requires at least one of ⌘/⌥/⌃ so a binding never collides with
/// plain typing.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var carbonModifiers: UInt32
    var onRecorded: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let view = ShortcutRecorderControl()
        view.keyCode = keyCode
        view.carbonModifiers = carbonModifiers
        view.onRecorded = { newKeyCode, newModifiers in
            keyCode = newKeyCode
            carbonModifiers = newModifiers
            onRecorded(newKeyCode, newModifiers)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.keyCode = keyCode
        nsView.carbonModifiers = carbonModifiers
    }
}

@MainActor
final class ShortcutRecorderControl: NSView {
    var onRecorded: ((UInt32, UInt32) -> Void)?

    var keyCode: UInt32 = HotkeyManager.defaultKeyCode { didSet { needsDisplay = true } }
    var carbonModifiers: UInt32 = HotkeyManager.defaultModifiers { didSet { needsDisplay = true } }

    private var isArmed = false { didSet { needsDisplay = true } }
    private var showsInvalidHint = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 24) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isArmed {
            disarm()
        } else {
            arm()
        }
    }

    override func resignFirstResponder() -> Bool {
        disarm()
        return super.resignFirstResponder()
    }

    private func arm() {
        guard !isArmed else { return }
        isArmed = true
        showsInvalidHint = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func disarm() {
        isArmed = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            disarm()
            return
        }

        let carbon = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard ShortcutFormatter.hasRequiredModifier(carbonModifiers: carbon) else {
            NSSound.beep()
            flashInvalidHint()
            return
        }

        let code = UInt32(event.keyCode)
        keyCode = code
        carbonModifiers = carbon
        onRecorded?(code, carbon)
        disarm()
    }

    private func flashInvalidHint() {
        showsInvalidHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showsInvalidHint = false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isArmed ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()

        (showsInvalidHint ? NSColor.systemRed : NSColor.separatorColor).setStroke()
        path.lineWidth = showsInvalidHint ? 2 : 1
        path.stroke()

        let text = isArmed ? "Type shortcut…" : ShortcutFormatter.string(keyCode: keyCode, carbonModifiers: carbonModifiers)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isArmed ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        text.draw(at: point, withAttributes: attributes)
    }
}
