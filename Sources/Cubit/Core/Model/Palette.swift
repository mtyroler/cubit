import CoreGraphics

/// Colorblind-aware measurement colors, derived from the Okabe-Ito palette
/// (minus black and white, which don't read well as measurement fills/borders
/// over the overlay's dim). Pure RGBA components — no AppKit/SwiftUI — mapped
/// to NSColor/Color at the UI edge.
struct PaletteColor: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
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

    static func color(forIndex index: Int) -> PaletteColor {
        colors[index % colors.count]
    }
}
