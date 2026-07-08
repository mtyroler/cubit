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
    var nsFont: NSFont {
        monospacedDigit
            ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: weight.nsWeight)
            : NSFont.systemFont(ofSize: pointSize, weight: weight.nsWeight)
    }

    var font: Font {
        let base = Font.system(size: pointSize, weight: weight.swiftUIWeight)
        return monospacedDigit ? base.monospacedDigit() : base
    }
}

/// The real `TextMeasuring` used at render time. Sizes strings with the same fonts the
/// SwiftUI renderer draws, so the engine's collision geometry matches the pixels.
struct AttributedStringMeasurer: TextMeasuring {
    func size(of string: String, role: ExportFontRole) -> CGSize {
        let measured = NSAttributedString(string: string, attributes: [.font: role.nsFont]).size()
        return CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
    }
}
