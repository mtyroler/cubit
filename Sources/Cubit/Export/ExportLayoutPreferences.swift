import Foundation

/// Export framing options that live outside the annotation layout: whether to include the
/// desktop context around a window, and whether to style window exports like a native macOS
/// window screenshot (rounded corners + shadow). Window shadow defaults ON — it is the look
/// users expect from ⇧⌘4; context defaults OFF (window-only).
struct ExportFraming: Sendable, Equatable {
    var includeContext: Bool
    var windowShadow: Bool

    static let `default` = ExportFraming(includeContext: false, windowShadow: true)
}

/// Reads/writes the persisted ("Remembered") export framing. The keys are the contract with
/// the Settings Export tab (owned separately) — this type never surfaces UI itself.
struct ExportLayoutPreferences: @unchecked Sendable {
    static let includeContextKey = "export.includeContext"
    static let windowShadowKey = "export.windowShadow"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var includeContext: Bool {
        get { defaults.bool(forKey: Self.includeContextKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.includeContextKey) }
    }

    /// Defaults to true when unset (a fresh install styles window exports).
    var windowShadow: Bool {
        get { defaults.object(forKey: Self.windowShadowKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.windowShadowKey) }
    }

    var framing: ExportFraming {
        ExportFraming(includeContext: includeContext, windowShadow: windowShadow)
    }

    func save(_ framing: ExportFraming) {
        includeContext = framing.includeContext
        windowShadow = framing.windowShadow
    }
}
