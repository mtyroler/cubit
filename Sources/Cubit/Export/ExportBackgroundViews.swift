import SwiftUI

/// Sizing for the era backgrounds, derived from the export's own dimensions so the retro
/// chrome scales like the original OS did on its flagship screen. Metrics are
/// pixel-measured from native-resolution era screenshots (GUIdebook) and the archived
/// Platinum/Aqua HIGs:
///   System 7  — menu bar 20px of a 480px screen (4.2–5.8%); Chicago 12 (em = 60% of bar);
///               desktop = 1px 50% checkerboard; screen corners r≈5px of 640.
///   Platinum  — bar 20px: 1px #FFF / flat #DDD / 1px #999 / 1px #000; Charcoal 12
///               (Chicago metrics); OS 8 desktop = periwinkle stipple #849CF7+#9C9CFF.
///   Aqua 10.1 — bar 22px of 768 with 4px-period pinstripes; Lucida Grande 14;
///               top corners r≈3px of 1024.
/// Invariant held by all three eras: menu text em ≈ 60–64% of bar height.
enum ExportBackgroundChrome {
    /// Extra top inset the background's menu bar occupies. Zero for non-era styles.
    static func menuBarHeight(style: ExportBackgroundStyle, imageSize: CGSize) -> CGFloat {
        let contentHeight = imageSize.height + WindowExportStyle.topMargin + WindowExportStyle.bottomMargin
        switch style {
        case .system7: return (contentHeight * 0.044).rounded()
        case .platinum: return (contentHeight * 0.035).rounded()
        case .aqua: return (contentHeight * 0.030).rounded()
        case .transparent, .studio, .aurora: return 0
        }
    }

    /// One era pixel in points: 1px of a 640-wide screen, half-point aligned so the
    /// checkerboard stays crisp at 2× render scale.
    static func checkerPixel(imageSize: CGSize) -> CGFloat {
        let exportWidth = imageSize.width + WindowExportStyle.sideMargin * 2
        return max(1, ((exportWidth / 640) * 2).rounded() / 2)
    }

    /// Era screen-corner rounding: System 7 rounded all four corners (r≈5px of 640),
    /// Platinum and Aqua only the top (Aqua tighter, r≈3px of 1024). The clipped corners
    /// render transparent, like real CRT captures.
    static func cornerRadii(style: ExportBackgroundStyle, imageSize: CGSize) -> RectangleCornerRadii {
        let exportWidth = imageSize.width + WindowExportStyle.sideMargin * 2
        switch style {
        case .system7:
            let r = exportWidth * 5 / 640
            return RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        case .platinum:
            let r = exportWidth * 5 / 640
            return RectangleCornerRadii(topLeading: r, bottomLeading: 0, bottomTrailing: 0, topTrailing: r)
        case .aqua:
            let r = exportWidth * 3 / 1024
            return RectangleCornerRadii(topLeading: r, bottomLeading: 0, bottomTrailing: 0, topTrailing: r)
        case .transparent, .studio, .aurora:
            return RectangleCornerRadii()
        }
    }
}

/// Dispatches a background style to its renderer. Sized by the export's window image so
/// the era chrome scales relative to the export, the way each OS related to its screen.
struct ExportBackgroundView: View {
    let style: ExportBackgroundStyle
    let imageSize: CGSize

    var body: some View {
        switch style {
        case .transparent:
            Color.clear
        case .studio:
            StudioExportBackground()
        case .aurora:
            AuroraExportBackground()
        case .system7:
            SystemSevenExportBackground(
                barHeight: ExportBackgroundChrome.menuBarHeight(style: style, imageSize: imageSize),
                checker: ExportBackgroundChrome.checkerPixel(imageSize: imageSize)
            )
        case .platinum:
            PlatinumExportBackground(
                barHeight: ExportBackgroundChrome.menuBarHeight(style: style, imageSize: imageSize),
                checker: ExportBackgroundChrome.checkerPixel(imageSize: imageSize)
            )
        case .aqua:
            AquaExportBackground(
                barHeight: ExportBackgroundChrome.menuBarHeight(style: style, imageSize: imageSize)
            )
        }
    }
}

private func hex(_ v: UInt32) -> Color {
    Color(
        .sRGB,
        red: Double((v >> 16) & 0xFF) / 255,
        green: Double((v >> 8) & 0xFF) / 255,
        blue: Double(v & 0xFF) / 255,
        opacity: 1
    )
}

// MARK: - Studio

/// Quiet graphite: soft key light above the window, gentle corner vignette.
struct StudioExportBackground: View {
    var body: some View {
        ZStack {
            Color(.sRGB, white: 0.115, opacity: 1)
            RadialGradient(
                colors: [Color(.sRGB, white: 0.20, opacity: 1), .clear],
                center: .init(x: 0.5, y: 0.12),
                startRadius: 0, endRadius: 900
            )
            RadialGradient(
                colors: [.clear, Color(.sRGB, white: 0, opacity: 0.35)],
                center: .center,
                startRadius: 420, endRadius: 1200
            )
        }
    }
}

// MARK: - Aurora

/// Desaturated macOS-wallpaper gradient: dark indigo base with blurred color blobs.
struct AuroraExportBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.10, green: 0.12, blue: 0.22, opacity: 1),
                    Color(.sRGB, red: 0.16, green: 0.10, blue: 0.24, opacity: 1),
                    Color(.sRGB, red: 0.05, green: 0.13, blue: 0.18, opacity: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(.sRGB, red: 0.28, green: 0.20, blue: 0.55, opacity: 0.55))
                .frame(width: 900, height: 900)
                .offset(x: -420, y: -380)
                .blur(radius: 160)
            Circle()
                .fill(Color(.sRGB, red: 0.05, green: 0.42, blue: 0.48, opacity: 0.45))
                .frame(width: 1000, height: 1000)
                .offset(x: 480, y: 420)
                .blur(radius: 180)
            Circle()
                .fill(Color(.sRGB, red: 0.65, green: 0.30, blue: 0.45, opacity: 0.28))
                .frame(width: 700, height: 700)
                .offset(x: 380, y: -420)
                .blur(radius: 170)
        }
        .clipped()
    }
}

// MARK: - Shared retro pieces

/// 1-era-pixel checkerboard of two colors; one era pixel = `px` points.
private struct CheckerDesktop: View {
    let px: CGFloat
    let light: Color
    let dark: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : px
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: px, height: px)), with: .color(dark))
                    x += px * 2
                }
                y += px
                row += 1
            }
        }
    }
}

/// The Cubit mascot as a hand-placed pixel sprite — it stands where the Apple logo lived,
/// so it renders in the same idiom as the era's 1-bit menu bar icons. User-approved
/// export-content artwork derived from the app icon (the SF-Symbols rule governs in-app
/// UI chrome, not exported pixels).
struct ExportPixelMascot: View {
    /// One sprite pixel in points; callers half-point-align for crisp 2× rendering.
    var px: CGFloat
    /// C teal head, D dark cap, K eye/mouth, P cheek, . clear
    private static let map = [
        "..DDDDDDDD..",
        ".DDDDDDDDDD.",
        ".CCCCCCCCCC.",
        ".CCCCCCCCCC.",
        ".CKKCCCCKKC.",
        ".CCCCCCCCCC.",
        ".CPCCKKCCPC.",
        ".CCCCCCCCCC.",
        "..CCCCCCCC..",
    ]

    var body: some View {
        Canvas { ctx, _ in
            for (r, row) in Self.map.enumerated() {
                for (c, ch) in row.enumerated() {
                    let color: Color?
                    switch ch {
                    case "C": color = Color(.sRGB, red: 0.36, green: 0.65, blue: 0.62, opacity: 1)
                    case "D": color = Color(.sRGB, red: 0.22, green: 0.45, blue: 0.43, opacity: 1)
                    case "K": color = Color(.sRGB, white: 0.10, opacity: 1)
                    case "P": color = Color(.sRGB, red: 0.91, green: 0.56, blue: 0.54, opacity: 1)
                    default: color = nil
                    }
                    if let color {
                        ctx.fill(
                            Path(CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px, height: px)),
                            with: .color(color)
                        )
                    }
                }
            }
        }
        .frame(width: px * 12, height: px * CGFloat(Self.map.count))
    }
}

/// Half-point-aligns a mascot pixel size so sprite cells land on device pixels at 2×.
private func mascotPixel(barHeight: CGFloat, fraction: CGFloat) -> CGFloat {
    ((barHeight * fraction / 9) * 2).rounded() / 2
}

// MARK: - System 7

/// Measured System 7: white bar (19 rows + 1px black rule), Chicago via Krungthep (whose
/// Latin glyphs are Chicago), 7.5's right-side order (clock, Guide "?", application menu),
/// and the color-Mac rendering of the 1-bit 50% dither.
struct SystemSevenExportBackground: View {
    let barHeight: CGFloat
    let checker: CGFloat

    var body: some View {
        let fontSize = (barHeight * 0.60).rounded()
        let gap = (fontSize * 1.25).rounded()
        let rule = max(1, (barHeight / 20).rounded())
        let mascot = mascotPixel(barHeight: barHeight, fraction: 0.65)

        return ZStack(alignment: .top) {
            CheckerDesktop(px: checker, light: hex(0xA0A0A0), dark: hex(0x606060))
            VStack(spacing: 0) {
                HStack(spacing: gap) {
                    ExportPixelMascot(px: mascot)
                    Group {
                        Text("File"); Text("Edit"); Text("View"); Text("Label"); Text("Special")
                    }
                    Spacer()
                    Text("9:02 AM")
                    Text("?")
                    ExportPixelMascot(px: mascot * 0.85)
                }
                .font(.custom("Krungthep", size: fontSize))
                .foregroundStyle(.black)
                .padding(.horizontal, barHeight)
                .frame(height: barHeight - rule)
                .background(Color.white)
                Rectangle().fill(Color.black).frame(height: rule)
            }
        }
    }
}

// MARK: - Platinum (Mac OS 8/9)

/// Measured Platinum: bar rows 1px #FFF / flat #DDD / 1px #999 / 1px #000, Charcoal 12
/// stood in by Tahoma Bold (Charcoal is metric-built on Chicago), OS 9's etched divider
/// before the application menu, and the OS 8 "Mac OS Default" periwinkle stipple
/// (#849CF7 + #9C9CFF ≈ 50/50, spatial average #879AE5).
struct PlatinumExportBackground: View {
    let barHeight: CGFloat
    let checker: CGFloat

    var body: some View {
        let fontSize = (barHeight * 0.60).rounded()
        let gap = (fontSize * 1.2).rounded()
        let row = max(1, (barHeight / 20).rounded())
        let mascot = mascotPixel(barHeight: barHeight, fraction: 0.70)

        return ZStack(alignment: .top) {
            CheckerDesktop(px: checker, light: hex(0x9C9CFF), dark: hex(0x849CF7))
            VStack(spacing: 0) {
                Rectangle().fill(Color.white).frame(height: row)
                HStack(spacing: gap) {
                    ExportPixelMascot(px: mascot)
                    Group {
                        Text("File"); Text("Edit"); Text("View"); Text("Special"); Text("Help")
                    }
                    Spacer()
                    Text("8:53 PM")
                    HStack(spacing: 0) {
                        Rectangle().fill(hex(0x999999)).frame(width: row)
                        Rectangle().fill(Color.white).frame(width: row)
                    }
                    .frame(height: barHeight * 0.8)
                    ExportPixelMascot(px: mascot * 0.85)
                    Text("Cubit")
                }
                .font(.custom("Tahoma-Bold", size: fontSize))
                .foregroundStyle(.black)
                .padding(.horizontal, barHeight)
                .frame(height: barHeight - row * 3)
                .background(hex(0xDDDDDD))
                Rectangle().fill(hex(0x999999)).frame(height: row)
                Rectangle().fill(Color.black).frame(height: row)
            }
        }
    }
}

// MARK: - Aqua (Mac OS X 10.1)

/// Measured Aqua: 22px-bar proportions with the 4px-period pinstripe cycle
/// (#E9E9E9/#FAFAFA/#FFFFFF/#FAFAFA) over #D4D4D4 + #757575 bottom rows, Lucida Grande
/// (which still ships) at 14-of-22 with the app name bold, and an "Aqua Blue" wallpaper
/// rebuilt from the measured palette (#19328A arc cores → #466BA8 median → #5A82B3 fields,
/// white crescent crests).
struct AquaExportBackground: View {
    let barHeight: CGFloat

    var body: some View {
        let fontSize = (barHeight * 14 / 22).rounded()
        let gap = (fontSize * 1.5).rounded()
        let row = max(1, (barHeight / 22).rounded())
        let stripe = barHeight * 4 / 22
        let mascot = mascotPixel(barHeight: barHeight, fraction: 0.77)

        return ZStack(alignment: .top) {
            aquaBlueWallpaper
            VStack(spacing: 0) {
                HStack(spacing: gap) {
                    ExportPixelMascot(px: mascot)
                    Text("Cubit").font(.custom("LucidaGrande-Bold", size: fontSize))
                    Group {
                        Text("File"); Text("Edit"); Text("View"); Text("Go"); Text("Window"); Text("Help")
                    }
                    Spacer()
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: fontSize * 0.85))
                    Text("Thu 11:53 AM")
                }
                .font(.custom("LucidaGrande", size: fontSize))
                .foregroundStyle(.black)
                .padding(.horizontal, barHeight * 0.9)
                .frame(height: barHeight - row * 2)
                .background(
                    Canvas { ctx, size in
                        let cycle = [hex(0xE9E9E9), hex(0xFAFAFA), hex(0xFFFFFF), hex(0xFAFAFA)]
                        let h = stripe / 4
                        var y: CGFloat = 0
                        var i = 0
                        while y < size.height {
                            ctx.fill(
                                Path(CGRect(x: 0, y: y, width: size.width, height: h)),
                                with: .color(cycle[i % 4])
                            )
                            y += h
                            i += 1
                        }
                    }
                )
                Rectangle().fill(hex(0xD4D4D4)).frame(height: row)
                Rectangle().fill(hex(0x757575)).frame(height: row)
            }
        }
    }

    /// Aqua Blue's composition: dark royal arc anchoring lower-left, diagonal light bands,
    /// a sharp white crescent entering top right-of-center and a softer swoosh lower-right.
    private var aquaBlueWallpaper: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                hex(0x466BA8)
                RadialGradient(
                    colors: [hex(0x5A82B3), .clear],
                    center: .init(x: 0.30, y: 0.45), startRadius: 0, endRadius: w * 0.65
                )
                Circle()
                    .stroke(hex(0x19328A), lineWidth: w * 0.16)
                    .frame(width: w * 1.05, height: w * 1.05)
                    .offset(x: -w * 0.28, y: h * 0.72)
                    .blur(radius: w * 0.03)
                RadialGradient(
                    colors: [hex(0x1C4396), .clear],
                    center: .init(x: 1.08, y: -0.10), startRadius: 0, endRadius: w * 0.45
                )
                Capsule()
                    .fill(hex(0x778FBB))
                    .frame(width: w * 1.3, height: h * 0.22)
                    .rotationEffect(.degrees(-18))
                    .offset(x: w * 0.10, y: -h * 0.10)
                    .blur(radius: w * 0.05)
                    .opacity(0.7)
                Path { p in
                    p.move(to: .init(x: w * 0.62, y: -h * 0.04))
                    p.addQuadCurve(
                        to: .init(x: w * 1.03, y: h * 0.38),
                        control: .init(x: w * 0.97, y: h * 0.02)
                    )
                }
                .stroke(
                    Color.white.opacity(0.85),
                    style: StrokeStyle(lineWidth: w * 0.008, lineCap: .round)
                )
                .blur(radius: 2)
                Path { p in
                    p.move(to: .init(x: w * 0.35, y: h * 1.05))
                    p.addQuadCurve(
                        to: .init(x: w * 1.05, y: h * 0.55),
                        control: .init(x: w * 0.75, y: h * 0.78)
                    )
                }
                .stroke(
                    Color.white.opacity(0.35),
                    style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round)
                )
                .blur(radius: w * 0.015)
            }
            .clipped()
        }
    }
}
