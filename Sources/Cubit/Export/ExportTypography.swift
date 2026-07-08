import AppKit
import SwiftUI

extension ExportFontWeight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

extension ExportFontRole {
    var nsFont: NSFont { nsFont(pointSize: pointSize) }

    /// Explicit-size variant for roles whose size flows from user settings (callout text at
    /// `MarkupStyle.calloutLabelPointSize` etc.) — must match whatever size measured the text.
    func nsFont(pointSize: CGFloat) -> NSFont {
        monospacedDigit
            ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: weight.nsWeight)
            : NSFont.systemFont(ofSize: pointSize, weight: weight.nsWeight)
    }

    var font: Font { font(pointSize: pointSize) }

    func font(pointSize: CGFloat) -> Font {
        let base = Font.system(size: pointSize, weight: weight.swiftUIWeight)
        return monospacedDigit ? base.monospacedDigit() : base
    }
}

/// The real `TextMeasuring` used at render time. Sizes strings with the same fonts the
/// SwiftUI renderer draws, so the engine's collision geometry matches the pixels.
struct AttributedStringMeasurer: TextMeasuring {
    func size(of string: String, role: ExportFontRole, pointSize: CGFloat) -> CGSize {
        let measured = NSAttributedString(string: string, attributes: [.font: role.nsFont(pointSize: pointSize)]).size()
        return CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
    }
}
