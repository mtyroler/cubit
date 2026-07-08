import Foundation
import Observation
import ServiceManagement

enum ExportFormat: String, CaseIterable, Sendable {
    case png
}

/// Overlay label-pill text size. Point sizes live here (not in the overlay) so Settings
/// and the canvas agree on a single source of truth without either owning the other.
enum LabelTextSize: String, CaseIterable, Sendable {
    case small, medium, large

    var pointSize: Double {
        switch self {
        case .small: return 10
        case .medium: return 11
        case .large: return 13
        }
    }

    var displayName: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }
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
        static let measurementBorderWidth = "settings.measurementBorderWidth"
        static let measurementFillOpacity = "settings.measurementFillOpacity"
        static let showLabelPills = "settings.showLabelPills"
        static let labelTextSize = "settings.labelTextSize"
        static let defaultExportFolderPath = "settings.defaultExportFolderPath"

        static let metadataMachine = "export.metadata.machine"
        static let metadataWindow = "export.metadata.window"
        static let metadataApp = "export.metadata.app"
    }

    static let dimOpacityRange: ClosedRange<Double> = 0.05...0.4
    static let defaultDimOpacity: Double = 0.15

    static let measurementBorderWidthRange: ClosedRange<Double> = 1...4
    static let defaultMeasurementBorderWidth: Double = 2

    static let measurementFillOpacityRange: ClosedRange<Double> = 0.05...0.30
    static let defaultMeasurementFillOpacity: Double = 0.12

    private let defaults: UserDefaults

    private var _dimOpacity: Double
    private var _measurementBorderWidth: Double
    private var _measurementFillOpacity: Double

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

    var measurementBorderWidth: Double {
        get { _measurementBorderWidth }
        set {
            _measurementBorderWidth = newValue.clamped(to: Self.measurementBorderWidthRange)
            defaults.set(_measurementBorderWidth, forKey: Keys.measurementBorderWidth)
        }
    }

    var measurementFillOpacity: Double {
        get { _measurementFillOpacity }
        set {
            _measurementFillOpacity = newValue.clamped(to: Self.measurementFillOpacityRange)
            defaults.set(_measurementFillOpacity, forKey: Keys.measurementFillOpacity)
        }
    }

    var showLabelPills: Bool {
        didSet { defaults.set(showLabelPills, forKey: Keys.showLabelPills) }
    }

    var labelTextSize: LabelTextSize {
        didSet { defaults.set(labelTextSize.rawValue, forKey: Keys.labelTextSize) }
    }

    /// Absolute path to the folder pre-selected in the export save panel, or nil to fall
    /// back to the system default (last-used location). This is a runtime-only
    /// preference picked live via a folder picker and persisted to UserDefaults — never a
    /// path baked into source.
    var defaultExportFolderPath: String? {
        didSet { defaults.set(defaultExportFolderPath, forKey: Keys.defaultExportFolderPath) }
    }

    /// `defaultExportFolderPath` contracted to "~/…" for display, so the Settings UI never
    /// shows a raw absolute path.
    var defaultExportFolderDisplayPath: String? {
        defaultExportFolderPath.map { ($0 as NSString).abbreviatingWithTildeInPath }
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

        if let stored = defaults.object(forKey: Keys.measurementBorderWidth) as? Double {
            self._measurementBorderWidth = stored.clamped(to: Self.measurementBorderWidthRange)
        } else {
            self._measurementBorderWidth = Self.defaultMeasurementBorderWidth
        }

        if let stored = defaults.object(forKey: Keys.measurementFillOpacity) as? Double {
            self._measurementFillOpacity = stored.clamped(to: Self.measurementFillOpacityRange)
        } else {
            self._measurementFillOpacity = Self.defaultMeasurementFillOpacity
        }

        if defaults.object(forKey: Keys.showLabelPills) != nil {
            self.showLabelPills = defaults.bool(forKey: Keys.showLabelPills)
        } else {
            self.showLabelPills = true
        }

        self.labelTextSize = LabelTextSize(rawValue: defaults.string(forKey: Keys.labelTextSize) ?? "") ?? .medium
        self.defaultExportFolderPath = defaults.string(forKey: Keys.defaultExportFolderPath)
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
