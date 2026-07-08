import Foundation

/// Export framing options that live outside the annotation layout: whether to include the
/// desktop context around a window, and whether to style window exports like a native macOS
/// window screenshot (rounded corners + shadow). Window shadow defaults ON — it is the look
/// users expect from ⇧⌘4; context defaults OFF (window-only).
struct ExportFraming: Sendable, Equatable {
    var includeContext: Bool
    var windowShadow: Bool
    /// Add a summed total per measurement kind to the legend (rectangle area, horizontal
    /// width, vertical height). Off by default.
    var showTotals: Bool

    init(includeContext: Bool, windowShadow: Bool, showTotals: Bool = false) {
        self.includeContext = includeContext
        self.windowShadow = windowShadow
        self.showTotals = showTotals
    }

    static let `default` = ExportFraming(includeContext: false, windowShadow: true)
}

/// Reads/writes the persisted ("Remembered") export framing. The keys are the contract with
/// the Settings Export tab (owned separately) — this type never surfaces UI itself.
struct ExportLayoutPreferences: @unchecked Sendable {
    static let includeContextKey = "export.includeContext"
    static let windowShadowKey = "export.windowShadow"
    static let showTotalsKey = "export.showTotals"
    /// When true, a file export also writes a `<basename>.json` sidecar describing the
    /// measurements for machine parsing. Off by default; not part of `ExportFraming` since it
    /// changes what is written to disk, not how the image is composed.
    static let jsonSidecarKey = "export.jsonSidecar"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Defaults to false when unset.
    var writeJSONSidecar: Bool {
        get { defaults.bool(forKey: Self.jsonSidecarKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.jsonSidecarKey) }
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

    /// Defaults to false when unset.
    var showTotals: Bool {
        get { defaults.bool(forKey: Self.showTotalsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.showTotalsKey) }
    }

    var framing: ExportFraming {
        ExportFraming(includeContext: includeContext, windowShadow: windowShadow, showTotals: showTotals)
    }

    func save(_ framing: ExportFraming) {
        includeContext = framing.includeContext
        windowShadow = framing.windowShadow
        showTotals = framing.showTotals
    }
}
