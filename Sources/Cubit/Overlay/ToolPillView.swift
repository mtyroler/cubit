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

    var body: some View {
        HStack(spacing: 10) {
            toolButton("rectangle.dashed", hint: "R", kind: .rectangle)
            toolButton("arrow.left.and.right", hint: "H", kind: .horizontal)
            toolButton("arrow.up.and.down", hint: "V", kind: .vertical)
            colorSwatchButton

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

            pillButton(action: onBeginCustomFrame) {
                HStack(spacing: 5) {
                    Image(systemName: "crop")
                        .font(.system(size: 12, weight: .medium))
                    hintTag("C")
                }
            }

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

            divider

            pillButton(action: onDismiss) {
                HStack(spacing: 5) {
                    Text("Done")
                        .font(.system(size: 11, weight: .medium))
                    hintTag("esc")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }

    private var divider: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(width: 1, height: 20)
    }

    private func toolButton(_ symbol: String, hint: String, kind: MeasurementKind) -> some View {
        let active = session.tool == kind
        return pillButton(action: { onSelectTool(kind) }) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                hintTag(hint)
            }
        }
        .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        .background(active ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
