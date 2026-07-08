import Foundation

/// Which metadata categories are currently active for an export. The three toggles map
/// 1:1 to `MetadataPreferences`' UserDefaults keys, which are the contract with the
/// Settings window (owned separately) — this type never surfaces UI itself.
struct MetadataToggles: Sendable, Equatable {
    var machine: Bool
    var window: Bool
    var app: Bool

    static let allOff = MetadataToggles(machine: false, window: false, app: false)
}

/// Reads/writes the persisted "remembered" metadata toggles. Off by default: a fresh
/// UserDefaults suite reports every category disabled, so a user who never opts in gets
/// zero identifying content in exports.
struct MetadataPreferences: @unchecked Sendable {
    private enum Keys {
        static let machine = "export.metadata.machine"
        static let window = "export.metadata.window"
        static let app = "export.metadata.app"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var machineEnabled: Bool {
        get { defaults.bool(forKey: Keys.machine) }
        nonmutating set { defaults.set(newValue, forKey: Keys.machine) }
    }

    var windowEnabled: Bool {
        get { defaults.bool(forKey: Keys.window) }
        nonmutating set { defaults.set(newValue, forKey: Keys.window) }
    }

    var appEnabled: Bool {
        get { defaults.bool(forKey: Keys.app) }
        nonmutating set { defaults.set(newValue, forKey: Keys.app) }
    }

    var toggles: MetadataToggles {
        MetadataToggles(machine: machineEnabled, window: windowEnabled, app: appEnabled)
    }

    func save(_ toggles: MetadataToggles) {
        machineEnabled = toggles.machine
        windowEnabled = toggles.window
        appEnabled = toggles.app
    }
}
