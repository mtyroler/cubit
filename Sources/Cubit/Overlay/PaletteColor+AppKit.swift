import AppKit

extension PaletteColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// Legible ink for text drawn on top of this swatch — see `PaletteColor.ink`.
    var nsInkColor: NSColor { ink.nsColor }
}
