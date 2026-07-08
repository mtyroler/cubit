import SwiftUI

/// Full-width strip drawn below the screenshot content: a hairline separator, up to three
/// left-to-right column groups (MACHINE · WINDOW · APP), and the Cubit wordmark at the
/// trailing edge — the one copy that would otherwise live in the legend card.
struct MetadataFooterView: View {
    let footer: FooterGeometry

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: AnnotationLayoutEngine.footerHairlineHeight)

            HStack(alignment: .top, spacing: AnnotationLayoutEngine.footerColumnGap) {
                if footer.columns.count == 1 {
                    Spacer(minLength: 0)
                    column(footer.columns[0])
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(footer.columns.enumerated()), id: \.offset) { _, col in
                        column(col)
                    }
                    Spacer(minLength: 0)
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
            .padding(AnnotationLayoutEngine.footerPadding)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: footer.frame.width, height: footer.frame.height, alignment: .top)
        // A solid fill, not `.regularMaterial`: the footer sits below the screenshot on an
        // otherwise-transparent canvas, so a translucent material has nothing dark to blur
        // and would render as a mismatched light band instead of matching the legend card.
        .background(Color(.sRGB, white: 0.13, opacity: 1))
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
