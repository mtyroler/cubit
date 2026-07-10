import SwiftUI

struct ToolPillView: View {
    let session: MeasurementSession
    let appState: AppState
    var onSelectTool: (MeasurementKind) -> Void
    var onCycleMode: () -> Void
    var onBeginCustomFrame: () -> Void
    var onCycleColor: () -> Void
    var onExport: () -> Void
    var onDismiss: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            toolButton("rectangle.dashed", hint: "R", kind: .rectangle)
            toolButton("arrow.left.and.right", hint: "H", kind: .horizontal)
            toolButton("arrow.up.and.down", hint: "V", kind: .vertical)
            colorSwatchButton

            divider

            historyButton(
                "arrow.uturn.backward",
                hint: "⌘Z",
                enabled: session.canUndo,
                title: title("Undo", session.undoActionName),
                action: onUndo
            )
            historyButton(
                "arrow.uturn.forward",
                hint: "⇧⌘Z",
                enabled: session.canRedo,
                title: title("Redo", session.redoActionName),
                action: onRedo
            )

            divider

            pillButton(action: onCycleMode) {
                HStack(spacing: 5) {
                    Image(systemName: modeSymbol)
                        .font(.system(size: 12, weight: .medium))
                    Text(modeName)
                        .font(.system(size: 11, weight: .medium))
                    hintTag("⇥")
                }
            }
            .help("Reference: \(modeName) — Tab to cycle")
            .accessibilityLabel("Reference frame")
            .accessibilityValue(modeName)
            .accessibilityHint("Cycles between window, screen, and custom")

            pillButton(action: onBeginCustomFrame) {
                HStack(spacing: 5) {
                    Image(systemName: "crop")
                        .font(.system(size: 12, weight: .medium))
                    hintTag("C")
                }
            }
            .help("Draw a custom reference frame — C")
            .accessibilityLabel("Draw custom reference frame")

            divider

            pillButton(action: onExport) {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                    hintTag("⌘E")
                }
            }
            .disabled(!appState.captureAvailable)
            .opacity(appState.captureAvailable ? 1 : 0.4)
            .help(appState.captureAvailable ? "Export annotated screenshot" : "Screen Recording required")
            .accessibilityLabel("Export annotated screenshot")
            .accessibilityHint(appState.captureAvailable ? "" : "Unavailable until Screen Recording is granted")

            divider

            pillButton(action: onDismiss) {
                HStack(spacing: 5) {
                    Text("Done")
                        .font(.system(size: 11, weight: .medium))
                    // Spelled out, not "⎋": at this caption size the glyph reads as a circular
                    // "reset" arrow. The contextual menu's Done item uses the real key
                    // equivalent, which AppKit draws at menu size where the glyph is legible.
                    hintTag("esc")
                }
            }
            .help("Done — esc")
            .accessibilityLabel("Done")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }

    /// "Undo Move Measurement" when the manager knows what the step was, plain "Undo" otherwise.
    private func title(_ verb: String, _ actionName: String) -> String {
        actionName.isEmpty ? verb : "\(verb) \(actionName)"
    }

    /// Undo and redo were reachable only by ⌘Z. Every overlay capability needs a visible,
    /// clickable affordance — and the tooltip names the step it will unwind.
    private func historyButton(
        _ symbol: String,
        hint: String,
        enabled: Bool,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        pillButton(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                hintTag(hint)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(title)
        .accessibilityLabel(title)
    }

    private var divider: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(width: 1, height: 20)
            .accessibilityHidden(true)
    }

    private func toolButton(_ symbol: String, hint: String, kind: MeasurementKind) -> some View {
        let active = session.tool == kind
        let name = toolName(kind)
        return pillButton(action: { onSelectTool(kind) }) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                hintTag(hint)
            }
        }
        .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        .background(active ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("\(name) — \(hint)")
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private func toolName(_ kind: MeasurementKind) -> String {
        switch kind {
        case .rectangle: return "Rectangle"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }

    /// Shows the color of the active draft/selection; empty (disabled) when there's no
    /// target, matching the export button's disabled treatment. Click cycles forward, same
    /// as X — the only visible affordance for an otherwise keyboard-only feature.
    private var colorSwatchButton: some View {
        let colorIndex = session.currentColorIndex
        let swatchColor = colorIndex.map { Palette.color(forIndex: $0).color }
        return pillButton(action: onCycleColor) {
            VStack(spacing: 2) {
                Circle()
                    .fill(swatchColor ?? Color.clear)
                    .overlay(Circle().strokeBorder(.white.opacity(swatchColor == nil ? 0.15 : 0.6), lineWidth: 1))
                    .frame(width: 14, height: 14)
                hintTag("X")
            }
        }
        .disabled(colorIndex == nil)
        .opacity(colorIndex == nil ? 0.35 : 1)
        .help("Color — X / 1–8")
        .accessibilityLabel("Color")
        .accessibilityValue(colorIndex.map { Palette.name(forIndex: $0).capitalized } ?? "None")
        .accessibilityHint("Cycles the color of the selected measurement")
    }

    private func pillButton<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hintTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private var modeSymbol: String {
        switch session.mode {
        case .windowUnderCursor: return "macwindow"
        case .screen: return "display"
        case .custom: return "rectangle.dashed"
        }
    }

    private var modeName: String {
        switch session.mode {
        case .windowUnderCursor: return "Window"
        case .screen: return "Screen"
        case .custom: return "Custom"
        }
    }
}
