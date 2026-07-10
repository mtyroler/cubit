import CoreGraphics
import Foundation

/// Colorblind-aware measurement colors, derived from the Okabe-Ito palette
/// (minus black and white, which don't read well as measurement fills/borders
/// over the overlay's dim). Pure RGBA components — no AppKit/SwiftUI — mapped
/// to NSColor/Color at the UI edge.
struct PaletteColor: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    /// Grayscale convenience — the two ink tones below are the only achromatic colors here.
    init(white: CGFloat) {
        self.init(red: white, green: white, blue: white)
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// WCAG 2.x relative luminance: gamma-expand each sRGB component, then weight.
    /// Not the 0.299/0.587/0.114 luma approximation — that overstates the brightness of
    /// saturated mid-tones and puts white ink on swatches it can't survive.
    var relativeLuminance: CGFloat {
        func expand(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * expand(red) + 0.7152 * expand(green) + 0.0722 * expand(blue)
    }

    /// WCAG contrast ratio between this color and `other`, in [1, 21].
    func contrastRatio(against other: PaletteColor) -> CGFloat {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Ink for text and marks drawn on top of this swatch: whichever of the two tones
    /// contrasts more. Every palette entry clears WCAG AA for normal text this way —
    /// white-on-yellow, the old unconditional choice, sat at 1.3:1.
    var ink: PaletteColor {
        contrastRatio(against: .lightInk) >= contrastRatio(against: .darkInk) ? .lightInk : .darkInk
    }

    /// Contrast the chosen `ink` actually achieves on this swatch. Asserted in tests.
    var inkContrastRatio: CGFloat { contrastRatio(against: ink) }

    static let lightInk = PaletteColor(white: 1.0)
    /// Near-black rather than pure black: softer against a saturated fill, and still clears
    /// 4.5:1 on every swatch that selects it.
    static let darkInk = PaletteColor(white: 0.08)
}

enum Palette {
    static let colors: [PaletteColor] = [
        PaletteColor(red: 0.902, green: 0.624, blue: 0.000), // orange
        PaletteColor(red: 0.337, green: 0.706, blue: 0.914), // sky blue
        PaletteColor(red: 0.000, green: 0.620, blue: 0.451), // bluish green
        PaletteColor(red: 0.941, green: 0.894, blue: 0.259), // yellow
        PaletteColor(red: 0.000, green: 0.447, blue: 0.698), // blue
        PaletteColor(red: 0.835, green: 0.369, blue: 0.000), // vermillion
        PaletteColor(red: 0.800, green: 0.475, blue: 0.655), // reddish purple
        PaletteColor(red: 0.600, green: 0.600, blue: 0.600)  // neutral gray
    ]

    /// Stable, human-readable names paralleling `colors` (Okabe-Ito). Used by the JSON
    /// sidecar so an agent can refer to a measurement's color by name, not just index.
    static let colorNames: [String] = [
        "orange",
        "sky blue",
        "bluish green",
        "yellow",
        "blue",
        "vermillion",
        "reddish purple",
        "gray"
    ]

    static func color(forIndex index: Int) -> PaletteColor {
        colors[index % colors.count]
    }

    static func name(forIndex index: Int) -> String {
        colorNames[((index % colorNames.count) + colorNames.count) % colorNames.count]
    }

    /// Wraps `index` one step forward or backward through the palette (index 0 follows the
    /// last color going backward, and vice versa going forward).
    static func cycledIndex(_ index: Int, forward: Bool) -> Int {
        let count = colors.count
        let normalized = ((index % count) + count) % count
        return forward ? (normalized + 1) % count : (normalized - 1 + count) % count
    }
}
