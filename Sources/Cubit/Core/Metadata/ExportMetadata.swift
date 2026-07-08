import CoreGraphics
import Foundation

/// Optional, privacy-sensitive identifying info a user may choose to imprint on an export's
/// footer. Every field here is pure data plus pure formatting — no AppKit, no I/O. Collection
/// (sysctl, NSScreen, NSRunningApplication) lives outside Core in `MetadataCollector`.

struct MachineInfo: Sendable, Equatable {
    /// Friendly model name (already resolved via `MacModelNames`), e.g. "MacBook Pro 14-inch, M3".
    var modelName: String
    var displayPixelsWidth: Int
    var displayPixelsHeight: Int
    var displayPointsWidth: Int
    var displayPointsHeight: Int
    var scale: CGFloat
    /// e.g. "26.1"
    var osVersion: String

    /// Display lines, e.g. ["MacBook Pro 14-inch, M3 · macOS 26.1", "3024×1964 px @2x"].
    var lines: [String] {
        [
            "\(modelName) · macOS \(osVersion)",
            "\(displayPixelsWidth)×\(displayPixelsHeight) px @\(scaleLabel)"
        ]
    }

    private var scaleLabel: String {
        scale == scale.rounded() ? "\(Int(scale))x" : String(format: "%.2gx", scale)
    }
}

/// Omitted entirely unless the export's reference mode is `.windowUnderCursor`.
struct WindowInfoMeta: Sendable, Equatable {
    var title: String?
    var ownerName: String
    var sizePointsWidth: Int
    var sizePointsHeight: Int
    var sizePixelsWidth: Int
    var sizePixelsHeight: Int

    /// Title line is omitted (never an empty-quotes line) when the title is nil or blank.
    var lines: [String] {
        var result: [String] = []
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(title)
        }
        result.append(ownerName)
        result.append("\(sizePointsWidth)×\(sizePointsHeight) pt (\(sizePixelsWidth)×\(sizePixelsHeight) px)")
        return result
    }
}

struct AppInfoMeta: Sendable, Equatable {
    var name: String
    var version: String?

    /// A bundle-less process (version unavailable) shows the name alone.
    var lines: [String] {
        if let version, !version.isEmpty { return ["\(name) \(version)"] }
        return [name]
    }
}

struct ExportMetadata: Sendable, Equatable {
    var machine: MachineInfo?
    var window: WindowInfoMeta?
    var app: AppInfoMeta?

    init(machine: MachineInfo? = nil, window: WindowInfoMeta? = nil, app: AppInfoMeta? = nil) {
        self.machine = machine
        self.window = window
        self.app = app
    }

    var isEmpty: Bool { machine == nil && window == nil && app == nil }
}

/// Maps a raw `hw.model` sysctl identifier (e.g. "Mac15,3") to a friendly marketing name.
/// Unknown identifiers pass through unchanged so the footer never shows a blank machine line.
enum MacModelNames {
    private static let table: [String: String] = [
        "Mac16,1": "MacBook Pro 14-inch, M4",
        "Mac16,6": "MacBook Pro 14-inch, M4 Pro/Max",
        "Mac16,8": "MacBook Pro 16-inch, M4 Pro/Max",
        "Mac16,7": "MacBook Pro 16-inch, M4 Pro",
        "Mac16,5": "MacBook Pro 16-inch, M4 Max",
        "Mac16,2": "iMac, M4",
        "Mac16,3": "iMac, M4",
        "Mac16,10": "Mac mini, M4",
        "Mac16,11": "Mac mini, M4 Pro",
        "Mac16,9": "Mac Studio, M4 Max",
        "Mac16,12": "Mac Studio, M3 Ultra",
        "Mac15,3": "MacBook Pro 14-inch, M3",
        "Mac15,6": "MacBook Pro 14-inch, M3 Pro",
        "Mac15,8": "MacBook Pro 14-inch, M3 Pro",
        "Mac15,7": "MacBook Pro 16-inch, M3 Pro",
        "Mac15,9": "MacBook Pro 16-inch, M3 Max",
        "Mac15,10": "MacBook Pro 16-inch, M3 Max",
        "Mac15,11": "MacBook Pro 14-inch, M3 Max",
        "Mac15,4": "iMac 24-inch, M3",
        "Mac15,5": "iMac 24-inch, M3",
        "Mac15,12": "MacBook Air 13-inch, M3",
        "Mac15,13": "MacBook Air 15-inch, M3",
        "Mac14,2": "MacBook Air, M2",
        "Mac14,15": "MacBook Air 15-inch, M2",
        "Mac14,7": "MacBook Pro 13-inch, M2",
        "Mac14,9": "MacBook Pro 14-inch, M2 Pro",
        "Mac14,10": "MacBook Pro 16-inch, M2 Pro",
        "Mac14,5": "MacBook Pro 14-inch, M2 Max",
        "Mac14,6": "MacBook Pro 16-inch, M2 Max",
        "Mac14,3": "Mac mini, M2",
        "Mac14,12": "Mac mini, M2 Pro",
        "Mac13,1": "Mac Studio, M1 Max",
        "Mac13,2": "Mac Studio, M1 Ultra",
        "MacBookPro18,1": "MacBook Pro 16-inch, M1 Pro",
        "MacBookPro18,2": "MacBook Pro 16-inch, M1 Max",
        "MacBookPro18,3": "MacBook Pro 14-inch, M1 Pro",
        "MacBookPro18,4": "MacBook Pro 14-inch, M1 Max",
        "MacBookPro17,1": "MacBook Pro 13-inch, M1",
        "MacBookAir10,1": "MacBook Air, M1",
        "Macmini9,1": "Mac mini, M1",
        "iMac21,1": "iMac 24-inch, M1",
        "iMac21,2": "iMac 24-inch, M1"
    ]

    static func friendlyName(forIdentifier identifier: String) -> String {
        table[identifier] ?? identifier
    }
}
