import SwiftUI

/// The small ⌘E export panel shown above the tool pill: save, copy, drag-out, and reserved
/// M6b toggles. Rendering happens in the controller; these are just triggers.
struct ExportMenuView: View {
    var onSave: () -> Void
    var onCopy: () -> Void
    var dragProvider: () -> NSItemProvider?

    @State private var includeMetadata = false

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

            Toggle(isOn: $includeMetadata) {
                Text("Include capture metadata")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .disabled(true)
            .help("Coming soon")
        }
        .padding(10)
        .frame(width: 208)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
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
