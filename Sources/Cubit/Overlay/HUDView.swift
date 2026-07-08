import SwiftUI

struct HUDView: View {
    let session: MeasurementSession

    var body: some View {
        if let draft = session.draft, let rect = session.draftRect {
            fullCard(draft: draft, rect: rect)
        } else {
            referenceChip(faded: true)
        }
    }

    private func fullCard(draft: MeasurementSession.Draft, rect: CanonicalRect) -> some View {
        let metrics = MeasurementEngine.metrics(
            kind: draft.kind,
            rect: rect,
            reference: session.reference,
            scale: session.referenceScale
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(primaryLine(kind: draft.kind, rect: rect, metrics: metrics))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
            referenceLine()
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
    }

    private func referenceChip(faded: Bool) -> some View {
        referenceLine()
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .opacity(faded ? 0.85 : 1)
            .fixedSize()
    }

    private func primaryLine(kind: MeasurementKind, rect: CanonicalRect, metrics: Metrics) -> String {
        switch kind {
        case .rectangle:
            return "\(pt(rect.width)) × \(pt(rect.height)) pt · area \(pct(metrics.areaPercent)) · w \(pct(metrics.widthPercent)) · h \(pct(metrics.heightPercent))"
        case .horizontal:
            return "\(pt(rect.width)) pt · \(pct(metrics.widthPercent)) of width"
        case .vertical:
            return "\(pt(rect.height)) pt · \(pct(metrics.heightPercent)) of height"
        }
    }

    private func referenceLine() -> some View {
        HStack(spacing: 5) {
            Image(systemName: modeSymbol(session.resolved.mode))
                .font(.system(size: 10, weight: .medium))
            Text(session.resolved.descriptor)
        }
    }

    private func modeSymbol(_ mode: ReferenceMode) -> String {
        switch mode {
        case .windowUnderCursor: return "macwindow"
        case .screen: return "display"
        case .custom: return "rectangle.dashed"
        }
    }

    private func pt(_ value: CGFloat) -> Int {
        Int(value.rounded())
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

/// Brief label shown near the cursor when the active tool/state changes (key or
/// pill click) — the tool pill alone is too peripheral to notice a switch.
struct ToolSwitchFlashView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            .fixedSize()
    }
}
