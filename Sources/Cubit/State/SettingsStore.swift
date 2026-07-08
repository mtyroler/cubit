import Foundation
import Observation
import ServiceManagement

enum ExportFormat: String, CaseIterable, Sendable {
    case png
}

/// UserDefaults-backed app preferences. Injectable suite so tests never touch the real
/// domain. Metadata-imprint toggles (`export.metadata.*`) are owned by the export/metadata
/// feature — this store reads/writes those raw keys but does not define their semantics.
@MainActor
@Observable
final class SettingsStore {
    enum Keys {
        static let defaultTool = "settings.defaultTool"
        static let defaultReferenceMode = "settings.defaultReferenceMode"
        static let dimOpacity = "settings.dimOpacity"
        static let showMenuBarPercent = "settings.showMenuBarPercent"
        static let exportFormat = "settings.exportFormat"
        static let copyAfterExport = "settings.copyAfterExport"

        static let metadataMachine = "export.metadata.machine"
        static let metadataWindow = "export.metadata.window"
        static let metadataApp = "export.metadata.app"
    }

    static let dimOpacityRange: ClosedRange<Double> = 0.05...0.4
    static let defaultDimOpacity: Double = 0.15

    private let defaults: UserDefaults

    private var _dimOpacity: Double

    var defaultTool: MeasurementKind {
        didSet { defaults.set(defaultTool.rawValue, forKey: Keys.defaultTool) }
    }

    var defaultReferenceMode: ReferenceMode {
        didSet { defaults.set(defaultReferenceMode.rawValue, forKey: Keys.defaultReferenceMode) }
    }

    var dimOpacity: Double {
        get { _dimOpacity }
        set {
            _dimOpacity = newValue.clamped(to: Self.dimOpacityRange)
            defaults.set(_dimOpacity, forKey: Keys.dimOpacity)
        }
    }

    var showMenuBarPercent: Bool {
        didSet { defaults.set(showMenuBarPercent, forKey: Keys.showMenuBarPercent) }
    }

    var exportFormat: ExportFormat {
        didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }

    var copyAfterExport: Bool {
        didSet { defaults.set(copyAfterExport, forKey: Keys.copyAfterExport) }
    }

    /// Metadata imprint toggles, stored under keys owned by the export/metadata feature.
    /// This store only forwards raw Bool reads/writes — it does not interpret them.
    var imprintMachineName: Bool {
        get { defaults.bool(forKey: Keys.metadataMachine) }
        set { defaults.set(newValue, forKey: Keys.metadataMachine) }
    }

    var imprintWindowTitle: Bool {
        get { defaults.bool(forKey: Keys.metadataWindow) }
        set { defaults.set(newValue, forKey: Keys.metadataWindow) }
    }

    var imprintAppName: Bool {
        get { defaults.bool(forKey: Keys.metadataApp) }
        set { defaults.set(newValue, forKey: Keys.metadataApp) }
    }

    /// Reflects (and drives) the system login-item registration via SMAppService. A no-op
    /// under XCTest so tests never register/unregister a real login item.
    var launchAtLogin: Bool {
        get {
            guard !Self.isRunningTests else { return false }
            return SMAppService.mainApp.status == .enabled
        }
        set {
            guard !Self.isRunningTests else { return }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration can legitimately fail (e.g. already in the desired state,
                // or the user declined in System Settings). The getter always reflects
                // whatever SMAppService actually did, so there's nothing to roll back.
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.defaultTool = MeasurementKind(rawValue: defaults.string(forKey: Keys.defaultTool) ?? "") ?? .rectangle
        self.defaultReferenceMode = ReferenceMode(rawValue: defaults.string(forKey: Keys.defaultReferenceMode) ?? "") ?? .windowUnderCursor

        if let stored = defaults.object(forKey: Keys.dimOpacity) as? Double {
            self._dimOpacity = stored.clamped(to: Self.dimOpacityRange)
        } else {
            self._dimOpacity = Self.defaultDimOpacity
        }

        if defaults.object(forKey: Keys.showMenuBarPercent) != nil {
            self.showMenuBarPercent = defaults.bool(forKey: Keys.showMenuBarPercent)
        } else {
            self.showMenuBarPercent = true
        }

        self.exportFormat = ExportFormat(rawValue: defaults.string(forKey: Keys.exportFormat) ?? "") ?? .png
        self.copyAfterExport = defaults.bool(forKey: Keys.copyAfterExport)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
