import SwiftUI

// Lives under Export/, not Overlay/, because the SwiftPM library target (which the `cubit` and
// `cubit-mcp` binaries share) compiles Export but excludes Overlay — and the export renderer
// needs `inkColor`. The AppKit bridge stays in Overlay/: nothing outside the app uses `nsColor`.
extension PaletteColor {
    var color: Color {
        Color(.sRGB, red: Double(red), green: Double(green), blue: Double(blue), opacity: 1)
    }

    /// Legible ink for text and marks drawn on top of this swatch — see `PaletteColor.ink`.
    var inkColor: Color { ink.color }
}
