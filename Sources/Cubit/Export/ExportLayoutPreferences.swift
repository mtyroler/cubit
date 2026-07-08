import Foundation

/// Persisted "remembered" export-framing preference. Off by default: a fresh UserDefaults
/// suite reports window/custom exports as window-only. The key is the contract with the
/// Settings Export tab (owned separately) — this type never surfaces UI itself.
struct ExportLayoutPreferences: @unchecked Sendable {
    static let includeContextKey = "export.includeContext"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var includeContext: Bool {
        get { defaults.bool(forKey: Self.includeContextKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.includeContextKey) }
    }
}
