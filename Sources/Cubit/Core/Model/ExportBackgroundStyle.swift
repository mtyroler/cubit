import Foundation

/// Decorative background rendered behind a styled window export's margins. `transparent`
/// preserves the original alpha-margin behavior and stays the factory default. Raw values
/// are the UserDefaults contract (`export.background`) — never rename a case.
enum ExportBackgroundStyle: String, CaseIterable, Sendable {
    /// Alpha margins only — the export composites onto whatever it lands on.
    case transparent
    /// Quiet graphite with a soft key light and corner vignette.
    case studio
    /// Desaturated macOS-wallpaper-style gradient blobs.
    case aurora
    /// System 7 desktop: 50% dither, white Chicago menu bar.
    case system7
    /// Mac OS 8/9 Platinum: periwinkle stipple, dimensional gray menu bar.
    case platinum
    /// Mac OS X 10.1 Aqua: pinstriped menu bar over the Aqua Blue wallpaper.
    case aqua

    var displayName: String {
        switch self {
        case .transparent: return "Transparent"
        case .studio: return "Studio"
        case .aurora: return "Aurora"
        case .system7: return "System 7"
        case .platinum: return "Platinum"
        case .aqua: return "Aqua"
        }
    }
}
