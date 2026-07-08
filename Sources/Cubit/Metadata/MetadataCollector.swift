import AppKit
import Foundation

/// Gathers the AppKit/sysctl-backed facts behind `ExportMetadata`. Only collects a category
/// whose toggle is on — never reads what won't be imprinted.
@MainActor
enum MetadataCollector {
    static func collect(
        toggles: MetadataToggles,
        reference: ResolvedReference,
        captured: CapturedDisplay
    ) -> ExportMetadata {
        let machine = toggles.machine ? collectMachine(captured: captured) : nil
        let window = (toggles.window && reference.mode == .windowUnderCursor)
            ? reference.window.map { windowMeta(from: $0, scale: captured.scale) }
            : nil
        let app = (toggles.app && reference.mode == .windowUnderCursor)
            ? reference.window.map { collectApp(pid: $0.ownerPID) }
            : nil
        return ExportMetadata(machine: machine, window: window, app: app)
    }

    private static func windowMeta(from window: WindowInfo, scale: CGFloat) -> WindowInfoMeta {
        let bounds = window.canonicalBounds
        return WindowInfoMeta(
            title: window.title,
            ownerName: window.ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Unknown"
                : window.ownerName,
            sizePointsWidth: Int(bounds.width.rounded()),
            sizePointsHeight: Int(bounds.height.rounded()),
            sizePixelsWidth: Int((bounds.width * scale).rounded()),
            sizePixelsHeight: Int((bounds.height * scale).rounded())
        )
    }

    private static func collectMachine(captured: CapturedDisplay) -> MachineInfo {
        let identifier = hardwareModelIdentifier()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return MachineInfo(
            modelName: MacModelNames.friendlyName(forIdentifier: identifier),
            displayPixelsWidth: captured.pixelWidth,
            displayPixelsHeight: captured.pixelHeight,
            displayPointsWidth: Int(captured.canonicalFrame.width.rounded()),
            displayPointsHeight: Int(captured.canonicalFrame.height.rounded()),
            scale: captured.scale,
            osVersion: "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        )
    }

    private static func collectApp(pid: pid_t) -> AppInfoMeta {
        guard let running = NSRunningApplication(processIdentifier: pid) else {
            return AppInfoMeta(name: "Unknown", version: nil)
        }
        let name = running.localizedName ?? "Unknown"
        var version: String?
        if let bundleURL = running.bundleURL, let bundle = Bundle(url: bundleURL) {
            version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        }
        return AppInfoMeta(name: name, version: version)
    }

    private static func hardwareModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
