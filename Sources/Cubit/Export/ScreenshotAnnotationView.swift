import SwiftUI

private extension PaletteColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    /// Legible ink for text/marks drawn on top of this swatch color.
    var inkColor: Color {
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.62 ? Color(.sRGB, white: 0.12, opacity: 1) : .white
    }
}

/// Renders the composed export image: frozen screenshot + measurement marks, callout pills,
/// leader lines, and the legend card. Pure presentation — every position comes from the
/// engine's `ExportLayout`; every string is pre-composed. Drawn by `ImageRenderer`.
/// This is the unstyled path (screen/custom/context): window + full-bleed footer, opaque.
struct ScreenshotAnnotationView: View {
    let layout: ExportLayout
    let image: CGImage

    var body: some View {
        VStack(spacing: 0) {
            AnnotatedWindowView(layout: layout, image: image)

            if let footer = layout.footer {
                MetadataFooterView(footer: footer)
                    .frame(width: footer.frame.width, height: footer.frame.height)
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
    }
}

/// The window itself: frozen screenshot + measurement marks, callout pills, leaders, and the
/// legend card, sized to the window crop. Reused unstyled (stacked with a full-bleed footer)
/// and styled (rounded/shadowed with a floating footer card).
struct AnnotatedWindowView: View {
    let layout: ExportLayout
    let image: CGImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .frame(width: layout.imageSize.width, height: layout.imageSize.height)

            Canvas { context, _ in
                drawReferenceOutline(in: context)
                for shape in layout.shapes { drawShape(shape, in: context) }
                for callout in layout.callouts { drawLeader(callout, in: context) }
            }
            .frame(width: layout.imageSize.width, height: layout.imageSize.height)

            ForEach(layout.callouts) { callout in
                CalloutPill(callout: callout, markup: layout.markup)
                    .position(x: callout.frame.midX, y: callout.frame.midY)
            }

            LegendCard(legend: layout.legend)
                .frame(width: layout.legend.frame.width, height: layout.legend.frame.height)
                .position(x: layout.legend.frame.midX, y: layout.legend.frame.midY)
        }
        .frame(width: layout.imageSize.width, height: layout.imageSize.height)
    }

    // MARK: Canvas marks

    private func drawReferenceOutline(in context: GraphicsContext) {
        guard let outline = layout.referenceOutline else { return }
        let path = Path(roundedRect: outline, cornerRadius: 3)
        context.stroke(
            path,
            with: .color(Color(.sRGB, white: 1, opacity: 0.85)),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )
        context.stroke(path, with: .color(Color(.sRGB, white: 0, opacity: 0.35)), lineWidth: 1.5)
    }

    private func drawShape(_ shape: ShapeGeometry, in context: GraphicsContext) {
        let palette = Palette.color(forIndex: shape.colorIndex)
        let color = palette.swiftUIColor
        let r = shape.rect

        switch shape.kind {
        case .rectangle:
            let box = Path(roundedRect: r, cornerRadius: 2)
            context.fill(box, with: .color(color.opacity(layout.markup.fillOpacity)))
            context.stroke(box, with: .color(color), lineWidth: layout.markup.borderWidth)
            drawEdgeTicks(r, color: color, in: context)
        case .horizontal:
            let a = CGPoint(x: r.minX, y: r.minY), b = CGPoint(x: r.maxX, y: r.minY)
            drawLine(a, b, color: color, capVertical: true, in: context)
        case .vertical:
            let a = CGPoint(x: r.minX, y: r.minY), b = CGPoint(x: r.minX, y: r.maxY)
            drawLine(a, b, color: color, capVertical: false, in: context)
        }
    }

    private func drawEdgeTicks(_ r: CGRect, color: Color, in context: GraphicsContext) {
        let len: CGFloat = 5
        var path = Path()
        // Short ruler ticks at each edge midpoint.
        path.move(to: CGPoint(x: r.midX, y: r.minY)); path.addLine(to: CGPoint(x: r.midX, y: r.minY + len))
        path.move(to: CGPoint(x: r.midX, y: r.maxY)); path.addLine(to: CGPoint(x: r.midX, y: r.maxY - len))
        path.move(to: CGPoint(x: r.minX, y: r.midY)); path.addLine(to: CGPoint(x: r.minX + len, y: r.midY))
        path.move(to: CGPoint(x: r.maxX, y: r.midY)); path.addLine(to: CGPoint(x: r.maxX - len, y: r.midY))
        context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1.5)
    }

    private func drawLine(_ a: CGPoint, _ b: CGPoint, color: Color, capVertical: Bool, in context: GraphicsContext) {
        let width = layout.markup.borderWidth
        var line = Path()
        line.move(to: a); line.addLine(to: b)
        context.stroke(line, with: .color(color), lineWidth: width)

        let half: CGFloat = 6
        var caps = Path()
        for p in [a, b] {
            if capVertical {
                caps.move(to: CGPoint(x: p.x, y: p.y - half)); caps.addLine(to: CGPoint(x: p.x, y: p.y + half))
            } else {
                caps.move(to: CGPoint(x: p.x - half, y: p.y)); caps.addLine(to: CGPoint(x: p.x + half, y: p.y))
            }
        }
        context.stroke(caps, with: .color(color), lineWidth: width)
    }

    private func drawLeader(_ callout: PlacedCallout, in context: GraphicsContext) {
        guard let leader = callout.leader else { return }
        let color = Palette.color(forIndex: callout.colorIndex).swiftUIColor
        var line = Path()
        line.move(to: leader.start); line.addLine(to: leader.end)
        context.stroke(line, with: .color(color.opacity(0.85)), lineWidth: 1.5)
        let dot = CGRect(x: leader.end.x - 3, y: leader.end.y - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: dot), with: .color(color))
    }
}

private struct CalloutPill: View {
    let callout: PlacedCallout
    let markup: MarkupStyle

    var body: some View {
        let palette = Palette.color(forIndex: callout.colorIndex)
        VStack(alignment: .leading, spacing: AnnotationLayoutEngine.pillLineSpacing) {
            if let label = callout.labelText, !label.isEmpty {
                Text(label)
                    .font(ExportFontRole.calloutLabel.font(pointSize: markup.calloutLabelPointSize))
                    .foregroundStyle(palette.inkColor.opacity(0.9))
            }
            Text(callout.primaryText)
                .font(ExportFontRole.calloutPrimary.font(pointSize: markup.calloutPrimaryPointSize))
                .foregroundStyle(palette.inkColor)
            if !callout.detailText.isEmpty {
                Text(callout.detailText)
                    .font(ExportFontRole.calloutDetail.font(pointSize: markup.calloutDetailPointSize))
                    .foregroundStyle(palette.inkColor.opacity(0.85))
            }
        }
        .padding(.horizontal, AnnotationLayoutEngine.pillPaddingH)
        .padding(.vertical, AnnotationLayoutEngine.pillPaddingV)
        .frame(width: callout.frame.width, height: callout.frame.height, alignment: .leading)
        .background(palette.swiftUIColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1)
    }
}

private struct LegendCard: View {
    let legend: LegendGeometry

    var body: some View {
        VStack(alignment: .leading, spacing: AnnotationLayoutEngine.legendRowSpacing) {
            Text(legend.headerText)
                .font(ExportFontRole.legendHeader.font)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ForEach(Array(legend.rows.enumerated()), id: \.offset) { _, row in
                // Spacing 0 with explicit gaps so the rendered width matches the engine's
                // row model exactly (swatch + gap + label + ≥gap + value).
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Palette.color(forIndex: row.colorIndex).swiftUIColor)
                        .frame(width: AnnotationLayoutEngine.legendSwatch, height: AnnotationLayoutEngine.legendSwatch)
                    Text(row.labelText)
                        .font(ExportFontRole.legendLabel.font)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, AnnotationLayoutEngine.legendSwatchGap)
                    Spacer(minLength: AnnotationLayoutEngine.legendLabelValueGap)
                    Text(row.valueText)
                        .font(ExportFontRole.legendValue.font)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            if !legend.wordmark.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                        .font(.system(size: 10, weight: .bold))
                    Text(legend.wordmark)
                        .font(ExportFontRole.wordmark.font)
                }
                .foregroundStyle(.tertiary)
            }

            if legend.metadataHeight > 0 {
                Color.clear.frame(height: legend.metadataHeight)
            }
        }
        .padding(AnnotationLayoutEngine.legendPadding)
        .frame(
            width: legend.frame.width,
            height: legend.frame.height,
            alignment: .topLeading
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 2)
    }
}
