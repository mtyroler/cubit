import SwiftUI

struct HUDView: View {
    let session: MeasurementSession

    var body: some View {
        if let draft = session.draft, let rect = session.draftRect {
            let metrics = MeasurementEngine.metrics(
                kind: draft.kind,
                rect: rect,
                reference: session.reference,
                scale: session.referenceScale
            )
            VStack(alignment: .leading, spacing: 4) {
                toolGlyphs(active: draft.kind)
                Text(primaryLine(kind: draft.kind, rect: rect, metrics: metrics))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                Text(referenceLine())
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .fixedSize()
        }
    }

    private func toolGlyphs(active: MeasurementKind) -> some View {
        HStack(spacing: 8) {
            glyph("rectangle.dashed", kind: .rectangle, active: active)
            glyph("arrow.left.and.right", kind: .horizontal, active: active)
            glyph("arrow.up.and.down", kind: .vertical, active: active)
        }
    }

    private func glyph(_ name: String, kind: MeasurementKind, active: MeasurementKind) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: kind == active ? .semibold : .regular))
            .foregroundStyle(kind == active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
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

    private func referenceLine() -> String {
        "Screen — \(pt(session.reference.width))×\(pt(session.reference.height))"
    }

    private func pt(_ value: CGFloat) -> Int {
        Int(value.rounded())
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}
