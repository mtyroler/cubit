import SwiftUI

/// Styling constants for native-macOS-window exports, calibrated against a real
/// `screencapture -w` on this OS (window corner radius, shadow margins, and peak shadow
/// opacity were measured from the alpha channel; see the scratch measurement harness).
enum WindowExportStyle {
    /// Continuous ("squircle") corner, matching the system window shape. Native measured
    /// ~24pt as a circular equivalent, which is ≈14pt as a continuous corner.
    static let cornerRadius: CGFloat = 14
    static let borderColor = Color(.sRGB, white: 1, opacity: 0.14)
    static let borderWidth: CGFloat = 1

    /// Transparent margins that hold the soft drop shadow (bottom larger for the downward
    /// offset, matching native).
    static let sideMargin: CGFloat = 44
    static let topMargin: CGFloat = 40
    static let bottomMargin: CGFloat = 56
    static let footerGap: CGFloat = 18

    // Soft, light, downward-offset — matching native's ~0.16 peak alpha and wide spread.
    static let shadowColor = Color(.sRGB, white: 0, opacity: 0.26)
    static let shadowRadius: CGFloat = 22
    static let shadowOffsetY: CGFloat = 12

    static let footerCornerRadius: CGFloat = 12
    static let footerFill = Color(.sRGB, white: 0.14, opacity: 1)
}

/// A window export dressed to look like a native macOS window screenshot: the annotated
/// window rounded, hairline-bordered and drop-shadowed inside the margins, with the
/// metadata footer (when present) as its own floating card below. Annotations stay
/// window-relative — the styling only frames the window, it never shifts the layout.
/// The margins are transparent by default; a non-transparent `background` fills them
/// (era styles add their menu bar as extra top inset and round the "screen" corners).
struct StyledWindowExportView: View {
    let layout: ExportLayout
    let image: CGImage
    var background: ExportBackgroundStyle = .transparent

    var body: some View {
        let barHeight = ExportBackgroundChrome.menuBarHeight(style: background, imageSize: layout.imageSize)
        VStack(spacing: WindowExportStyle.footerGap) {
            windowCard
            // A below-placed legend stacks under the window like the footer card, sized by
            // the same engine measurement the in-image card would have used.
            if layout.legend.placement == .below {
                LegendCard(legend: layout.legend)
                    .frame(width: layout.legend.frame.width, height: layout.legend.frame.height)
            }
            if let footer = layout.footer {
                MetadataFooterCard(footer: footer)
            }
        }
        .padding(EdgeInsets(
            top: WindowExportStyle.topMargin + barHeight,
            leading: WindowExportStyle.sideMargin,
            bottom: WindowExportStyle.bottomMargin,
            trailing: WindowExportStyle.sideMargin
        ))
        .background(ExportBackgroundView(style: background, imageSize: layout.imageSize))
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: ExportBackgroundChrome.cornerRadii(style: background, imageSize: layout.imageSize)
        ))
        .fixedSize()
    }

    private var windowCard: some View {
        let shape = RoundedRectangle(cornerRadius: WindowExportStyle.cornerRadius, style: .continuous)
        return AnnotatedWindowView(layout: layout, image: image)
            .frame(width: layout.imageSize.width, height: layout.imageSize.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(WindowExportStyle.borderColor, lineWidth: WindowExportStyle.borderWidth))
            .background(
                // Shadow cast by the window's rounded silhouette only — not the annotations.
                shape
                    .fill(WindowExportStyle.footerFill)
                    .shadow(
                        color: WindowExportStyle.shadowColor,
                        radius: WindowExportStyle.shadowRadius,
                        x: 0,
                        y: WindowExportStyle.shadowOffsetY
                    )
            )
    }
}

/// The metadata footer as a floating rounded card (styled-window mode), matching the legend
/// card's construction and the footer's own typography.
struct MetadataFooterCard: View {
    let footer: FooterGeometry

    var body: some View {
        HStack(alignment: .top, spacing: AnnotationLayoutEngine.footerColumnGap) {
            ForEach(Array(footer.columns.enumerated()), id: \.offset) { _, col in
                column(col)
            }
            if !footer.wordmark.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                        .font(.system(size: 10, weight: .bold))
                    Text(footer.wordmark)
                        .font(ExportFontRole.wordmark.font)
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            WindowExportStyle.footerFill,
            in: RoundedRectangle(cornerRadius: WindowExportStyle.footerCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WindowExportStyle.footerCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 12, x: 0, y: 6)
        .fixedSize()
    }

    private func column(_ col: MetadataFooterColumnInput) -> some View {
        VStack(alignment: .leading, spacing: AnnotationLayoutEngine.footerCaptionLineGap) {
            Text(col.caption.uppercased())
                .font(ExportFontRole.footerCaption.font)
                .foregroundStyle(.white.opacity(0.45))
            VStack(alignment: .leading, spacing: AnnotationLayoutEngine.footerLineSpacing) {
                ForEach(Array(col.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(ExportFontRole.footerLine.font)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }
}
