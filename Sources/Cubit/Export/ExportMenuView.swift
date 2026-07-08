import SwiftUI

/// The small ⌘E export panel shown above the tool pill: save, copy, drag-out, and reserved
/// M6b toggles. Rendering happens in the controller; these are just triggers.
struct ExportMenuView: View {
    var onSave: () -> Void
    var onCopy: () -> Void
    var dragProvider: () -> NSItemProvider?
    /// Toggle state saved from a prior "Remember" — off by default for every fresh user.
    var initialToggles: MetadataToggles
    /// Framing (window-only vs. context, and native window styling), saved from a prior
    /// "Remember" — window-only + shadow-on by default.
    var initialFraming: ExportFraming
    /// Fired on every toggle/remember flip so the caller can track the pending (possibly
    /// one-shot) selection and, when `remember` is true, persist it.
    var onMetadataChange: (MetadataToggles, _ framing: ExportFraming, _ remember: Bool) -> Void

    @State private var machine: Bool
    @State private var window: Bool
    @State private var app: Bool
    @State private var includeContext: Bool
    @State private var windowShadow: Bool
    @State private var showTotals: Bool
    @State private var remember = false

    init(
        onSave: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        dragProvider: @escaping () -> NSItemProvider?,
        initialToggles: MetadataToggles = .allOff,
        initialFraming: ExportFraming = .default,
        onMetadataChange: @escaping (MetadataToggles, ExportFraming, Bool) -> Void = { _, _, _ in }
    ) {
        self.onSave = onSave
        self.onCopy = onCopy
        self.dragProvider = dragProvider
        self.initialToggles = initialToggles
        self.initialFraming = initialFraming
        self.onMetadataChange = onMetadataChange
        _machine = State(initialValue: initialToggles.machine)
        _window = State(initialValue: initialToggles.window)
        _app = State(initialValue: initialToggles.app)
        _includeContext = State(initialValue: initialFraming.includeContext)
        _windowShadow = State(initialValue: initialFraming.windowShadow)
        _showTotals = State(initialValue: initialFraming.showTotals)
    }

    private var currentToggles: MetadataToggles {
        MetadataToggles(machine: machine, window: window, app: app)
    }

    private var currentFraming: ExportFraming {
        ExportFraming(includeContext: includeContext, windowShadow: windowShadow, showTotals: showTotals)
    }

    private func notifyChange() {
        onMetadataChange(currentToggles, currentFraming, remember)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXPORT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)

            row(action: onSave, symbol: "square.and.arrow.down", title: "Save…", hint: "⌘S")
            row(action: onCopy, symbol: "doc.on.doc", title: "Copy", hint: "⌘C")

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text("Drag out")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onDrag { dragProvider() ?? NSItemProvider() }

            Divider().padding(.vertical, 2)

            Text("LAYOUT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .padding(.bottom, 2)

            Toggle(isOn: $windowShadow) {
                Text("Window shadow")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .help("Style window exports like a native macOS screenshot: rounded corners and a drop shadow")

            Toggle(isOn: $includeContext) {
                Text("Include surrounding context")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .help("Export the area around the window instead of the window alone")

            Toggle(isOn: $showTotals) {
                Text("Sum measurement totals")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .help("Add a summed total per kind to the legend: rectangle area, horizontal width, vertical height")

            Divider().padding(.vertical, 2)

            Text("METADATA")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .padding(.bottom, 2)

            metadataToggle("Machine", isOn: $machine)
            metadataToggle("Window", isOn: $window)
            metadataToggle("App", isOn: $app)

            Divider().padding(.vertical, 2)

            Toggle(isOn: $remember) {
                Text("Remember for next time")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .onChange(of: remember) { _, _ in notifyChange() }
        }
        .onChange(of: machine) { _, _ in notifyChange() }
        .onChange(of: window) { _, _ in notifyChange() }
        .onChange(of: app) { _, _ in notifyChange() }
        .onChange(of: includeContext) { _, _ in notifyChange() }
        .onChange(of: windowShadow) { _, _ in notifyChange() }
        .onChange(of: showTotals) { _, _ in notifyChange() }
        .padding(10)
        .frame(width: 208)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func metadataToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 11))
        }
        .toggleStyle(.checkbox)
    }

    private func row(action: @escaping () -> Void, symbol: String, title: String, hint: String) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Transient confirmation ("Saved to …", "Copied") shown briefly after an export.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .fixedSize()
    }
}
